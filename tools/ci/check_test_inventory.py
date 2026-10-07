#!/usr/bin/env python3
"""Compare the tests xctest discovers against the committed test inventory.

`make test-inventory` writes each bundle's `xctest -list-tests` output to
`<results dir>/inventory/<Bundle>.tests.txt`. This script compares those
listings with the baseline in tests/fixtures/test_inventory/:

- A baseline test missing from a listing fails the check. Tests can disappear
  without anything failing: a file drops out of a bundle's sources, a method's
  signature changes so discovery skips it, or a class stops linking.
- A listed test missing from the baseline also fails, so the baseline always
  matches what runs; a test that never makes it into the baseline would not be
  protected against disappearing later.

When a change is intended, `make update-test-inventory` (this script with
--update) rewrites the baseline from the listings.
"""
import argparse
import re
import sys
from pathlib import Path

BASELINE_DIR = "tests/fixtures/test_inventory"
LISTING_SUFFIX = ".tests.txt"
TEST_ID = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$")
UPDATE_HINT = "if this is intended, run `make update-test-inventory` and commit the result"


def read_tests(path: Path) -> list:
    """Return the sorted, de-duplicated test identifiers in a listing.

    Lines that are not `Target/Class/method` identifiers (log output from
    loading the bundle, blank lines) are ignored.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    return sorted({line.strip() for line in lines if TEST_ID.match(line.strip())})


def listings(directory: Path) -> dict:
    if not directory.is_dir():
        return {}
    return {
        path.name[: -len(LISTING_SUFFIX)]: path
        for path in sorted(directory.glob(f"*{LISTING_SUFFIX}"))
    }


def update(listing_dir: Path, baseline_dir: Path, bundles) -> int:
    current = listings(listing_dir)
    missing = [bundle for bundle in bundles if bundle not in current]
    if missing:
        for bundle in missing:
            print(f"test-inventory: no listing for {bundle} in {listing_dir}", file=sys.stderr)
        return 1
    baseline_dir.mkdir(parents=True, exist_ok=True)
    for bundle, stale in listings(baseline_dir).items():
        if bundle not in bundles:
            stale.unlink()
            print(f"test-inventory: removed the baseline for {bundle}")
    for bundle in bundles:
        tests = read_tests(current[bundle])
        if not tests:
            print(f"test-inventory: {bundle} listed no tests; refusing to record an empty baseline",
                  file=sys.stderr)
            return 1
        (baseline_dir / f"{bundle}{LISTING_SUFFIX}").write_text(
            "".join(f"{test}\n" for test in tests), encoding="utf-8")
        print(f"test-inventory: recorded {len(tests)} tests for {bundle}")
    return 0


def check(listing_dir: Path, baseline_dir: Path) -> int:
    baseline = listings(baseline_dir)
    current = listings(listing_dir)
    if not baseline:
        print(f"test-inventory: no baseline found in {baseline_dir}", file=sys.stderr)
        return 1

    errors = []
    total = 0
    for bundle, baseline_path in baseline.items():
        if bundle not in current:
            errors.append(f"{bundle}: no listing in {listing_dir} (did the bundle build?)")
            continue
        expected = set(read_tests(baseline_path))
        found = set(read_tests(current[bundle]))
        total += len(found)
        removed = sorted(expected - found)
        added = sorted(found - expected)
        if removed:
            errors.append(f"{bundle}: {len(removed)} test(s) in the baseline were not discovered:")
            errors.extend(f"  - {test}" for test in removed)
        if added:
            errors.append(f"{bundle}: {len(added)} discovered test(s) are not in the baseline:")
            errors.extend(f"  + {test}" for test in added)

    if errors:
        for error in errors:
            print(f"test-inventory: {error}", file=sys.stderr)
        print(f"test-inventory: {UPDATE_HINT}", file=sys.stderr)
        return 1

    print(f"test-inventory: {total} tests across {len(baseline)} bundle(s) match the baseline")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Check discovered tests against the committed inventory.")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--listing-dir", required=True,
                        help="directory holding <Bundle>.tests.txt files from xctest -list-tests")
    parser.add_argument("--baseline-dir", help=f"defaults to <repo root>/{BASELINE_DIR}")
    parser.add_argument("--update", nargs="+", metavar="BUNDLE",
                        help="rewrite the baseline for these bundles from the listings")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    listing_dir = Path(args.listing_dir).resolve()
    baseline_dir = Path(args.baseline_dir).resolve() if args.baseline_dir else repo_root / BASELINE_DIR

    if args.update:
        return update(listing_dir, baseline_dir, args.update)
    return check(listing_dir, baseline_dir)


if __name__ == "__main__":
    sys.exit(main())
