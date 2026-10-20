#!/usr/bin/env python3
"""Maintain the integration tests that the nightly ASAN+UBSan lane skips.

An integration test can't run against a sanitizer-instrumented framework when
it (directly or through a helper in the same file) builds an app root through
bin/boomhauer or bin/arlen, runs `make`, propane or a tools/ci script. Those
paths refuse the instrumented libArlenFramework.a, or `make clean` it, which
wipes build/ under the running suite (issue 271).

The skip list lives in tests/fixtures/sanitizers/integration_nightly_skips.txt.
Its generated section is this classifier's output; its manual section holds
tests skipped for other reasons, each with a comment. One entry per line:
`Class` or `Class/testMethod`.

Usage:
  classify_sanitizer_integration_skips.py --check   # exit 1 if the generated section is stale
  classify_sanitizer_integration_skips.py --write   # rewrite the generated section
  classify_sanitizer_integration_skips.py --print-args  # print -skip-testing arguments
"""
import argparse
import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TESTS_DIR = os.path.join(REPO_ROOT, "tests", "integration")
SKIP_FILE = os.path.join(REPO_ROOT, "tests", "fixtures", "sanitizers", "integration_nightly_skips.txt")
BUNDLE = "ArlenIntegrationTests"
GENERATED_BEGIN = "# BEGIN GENERATED"
GENERATED_END = "# END GENERATED"

MARK = re.compile(
    r'tools/ci|\.sh\b|\bclean\b|bin/boomhauer|bin/arlen|build/arlen|prepare-only|"new"|\bmake\b|propane|ARLEN_FRAMEWORK_ROOT'
)


def classify(tests_dir):
    entries = []
    for name in sorted(os.listdir(tests_dir)):
        if not name.endswith(".m"):
            continue
        with open(os.path.join(tests_dir, name), encoding="utf-8", errors="replace") as handle:
            source = handle.read()
        # Comments may discuss make/cleanup without executing either. Preserve
        # quoted literals (including URLs) while removing actual C comments.
        source = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/',
                        lambda m: re.sub(r"[^\n]", " ", m.group(0)) if m.group(0).startswith(("//", "/*")) else m.group(0),
                        source, flags=re.DOTALL)
        match = re.search(r"@implementation\s+(\w+)", source)
        if not match:
            continue
        cls = match.group(1)
        # Split into methods and static functions; a test is unsafe when its
        # body, or any helper it calls in this file, matches MARK.
        parts = re.split(r"\n(?=[-+] \(|static [\w\s\*]+\(|@end)", source)
        bodies = {}
        for part in parts:
            m = re.match(r"[-+] \([^)]*\)\s*(\w+)", part) or re.match(r"static [\w\s\*]+?(\w+)\(", part)
            if m:
                bodies[m.group(1)] = part
        dirty = {n for n, body in bodies.items() if MARK.search(body)}
        changed = True
        while changed:
            changed = False
            for n, body in bodies.items():
                if n in dirty:
                    continue
                if any(re.search(r"\b" + re.escape(helper) + r"\b", body) for helper in dirty):
                    dirty.add(n)
                    changed = True
        tests = [n for n in bodies if n.startswith("test")]
        unsafe = [t for t in tests if t in dirty]
        if not tests:
            continue
        if "setUp" in dirty or "setUpClass" in dirty or len(unsafe) == len(tests):
            entries.append(cls)
        else:
            entries.extend(f"{cls}/{t}" for t in unsafe)
    return entries


def read_skip_file():
    with open(SKIP_FILE, encoding="utf-8") as handle:
        return handle.read().split("\n")


def generated_section(lines):
    begin = lines.index(GENERATED_BEGIN)
    end = lines.index(GENERATED_END)
    return begin, end, [l for l in lines[begin + 1:end] if l and not l.startswith("#")]


def all_entries(lines):
    return [l.strip() for l in lines if l.strip() and not l.strip().startswith("#")]


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--print-args", action="store_true")
    args = parser.parse_args()

    lines = read_skip_file()
    if args.print_args:
        for entry in all_entries(lines):
            print(f"-skip-testing:{BUNDLE}/{entry}")
        return 0

    current = classify(TESTS_DIR)
    begin, end, recorded = generated_section(lines)
    if args.write:
        lines[begin + 1:end] = current
        with open(SKIP_FILE, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines))
        print(f"wrote {len(current)} generated entries to {os.path.relpath(SKIP_FILE, REPO_ROOT)}")
        return 0

    if recorded != current:
        missing = sorted(set(current) - set(recorded))
        stale = sorted(set(recorded) - set(current))
        for entry in missing:
            print(f"sanitizer integration skips: not listed but builds an app root: {entry}", file=sys.stderr)
        for entry in stale:
            print(f"sanitizer integration skips: listed but no longer builds an app root: {entry}", file=sys.stderr)
        print("sanitizer integration skips: run `python3 tools/ci/classify_sanitizer_integration_skips.py --write`",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
