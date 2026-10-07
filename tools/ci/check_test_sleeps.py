#!/usr/bin/env python3
"""Keep new sleep-and-poll waits out of the tests.

A test that sleeps for a guessed interval is slow when the guess is generous
and flaky when it is tight. Tests should wait for a real signal instead, with
the helpers in tests/shared/ALNTestWait.h (built on XCTestExpectation and
XCTWaiter).

Checks Objective-C and C sources under tests/ (not tests/fixtures/) for
`usleep(`, `sleep(`, `nanosleep(`, `sleepForTimeInterval:`, `sleepUntilDate:`
and `runUntilDate:` outside string literals and comments. A call is allowed
when its line, or the line before it, carries `sleep-ok: <reason>`: use that
for a delay that is the point of the test, such as letting a TTL expire.

Calls that predate this check are listed per file in the baseline. A file may
not have more unannotated sleeps than its baseline count, and the baseline must
come down as sleeps are converted, so the total only ever shrinks. After
converting some, run with --update-baseline; it refuses to raise any count.
"""
import argparse
import json
import re
import sys
from pathlib import Path

BASELINE = "tests/fixtures/testing/test_sleep_baseline.json"
SOURCE_SUFFIXES = {".m", ".mm", ".h", ".c"}
EXCLUDED_DIRS = ("tests/fixtures/",)

SLEEP_CALL = re.compile(
    r"\b(?:usleep|sleep|nanosleep)\s*\(|\b(?:sleepForTimeInterval|sleepUntilDate|runUntilDate)\s*:"
)
STRING_LITERAL = re.compile(r'"(?:\\.|[^"\\])*"')
ANNOTATION = re.compile(r"sleep-ok:\s*\S")


def code_part(line: str) -> str:
    """The line with string literals blanked and any // comment removed."""
    without_strings = STRING_LITERAL.sub('""', line)
    return without_strings.split("//", 1)[0]


def unannotated_sleeps(path: Path) -> list[int]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    found = []
    for index, line in enumerate(lines):
        if not SLEEP_CALL.search(code_part(line)):
            continue
        # The line above counts only when it is a comment of its own, so one
        # annotated call doesn't cover the call after it.
        previous = lines[index - 1].strip() if index > 0 else ""
        previous_is_comment = previous.startswith(("//", "/*", "*"))
        if ANNOTATION.search(line) or (previous_is_comment and ANNOTATION.search(previous)):
            continue
        found.append(index + 1)
    return found


def scan(repo_root: Path) -> dict[str, list[int]]:
    results = {}
    for path in sorted((repo_root / "tests").rglob("*")):
        if not path.is_file() or path.suffix not in SOURCE_SUFFIXES:
            continue
        relative = path.relative_to(repo_root).as_posix()
        if relative.startswith(EXCLUDED_DIRS):
            continue
        hits = unannotated_sleeps(path)
        if hits:
            results[relative] = hits
    return results


def load_baseline(repo_root: Path) -> dict[str, int]:
    path = repo_root / BASELINE
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    files = payload.get("files", {})
    if not isinstance(files, dict):
        raise SystemExit(f"{BASELINE}: `files` must be an object")
    return {name: int(count) for name, count in files.items()}


def write_baseline(repo_root: Path, counts: dict[str, int]) -> None:
    payload = {
        "description": (
            "Unannotated sleeps in tests that predate tools/ci/check_test_sleeps.py. "
            "Counts may only go down; see docs/TESTING_WORKFLOW.md."
        ),
        "files": dict(sorted(counts.items())),
    }
    path = repo_root / BASELINE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Reject new sleep-based waits in tests.")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="lower the baseline to the current counts (never raises one)",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    current = scan(repo_root)
    counts = {name: len(lines) for name, lines in current.items()}
    baseline = load_baseline(repo_root)

    increases = []
    for name, lines in current.items():
        allowed = baseline.get(name, 0)
        if len(lines) > allowed:
            where = ", ".join(str(line) for line in lines)
            increases.append(
                f"{name}: {len(lines)} unannotated sleep(s) (baseline {allowed}) at line(s) {where}"
            )

    if args.update_baseline:
        if increases:
            print("test-sleeps: refusing to raise the baseline:", file=sys.stderr)
            for message in increases:
                print(f"  {message}", file=sys.stderr)
            return 1
        write_baseline(repo_root, counts)
        print(f"test-sleeps: baseline updated ({sum(counts.values())} remaining)")
        return 0

    stale = sorted(
        f"{name}: baseline {allowed}, found {counts.get(name, 0)}"
        for name, allowed in baseline.items()
        if counts.get(name, 0) < allowed
    )

    if increases or stale:
        if increases:
            print(
                "test-sleeps: new sleep-based waits in tests. Wait for a real signal with "
                "tests/shared/ALNTestWait.h, or mark a deliberate delay with "
                "`// sleep-ok: <reason>`:",
                file=sys.stderr,
            )
            for message in increases:
                print(f"  {message}", file=sys.stderr)
        if stale:
            print(
                "test-sleeps: the baseline is higher than the code; lower it with "
                "`python3 tools/ci/check_test_sleeps.py --repo-root . --update-baseline`:",
                file=sys.stderr,
            )
            for message in stale:
                print(f"  {message}", file=sys.stderr)
        return 1

    print(f"test-sleeps: no new sleeps in tests ({sum(counts.values())} in the baseline)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
