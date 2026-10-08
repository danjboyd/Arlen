#!/usr/bin/env bash
# Run the full Apple XCTest unit bundle against a private PostgreSQL, then check
# that Apple discovered exactly the tests in the shared unit inventory.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo 'apple-unit: Apple runtime required' >&2; exit 1; }

output_dir="${ARLEN_APPLE_UNIT_OUTPUT_DIR:-$repo_root/build/release_confidence/apple_unit}"
mkdir -p "$output_dir"
xctest_log="$output_dir/xctest.log"

export ARLEN_TEST_PG_BIN="${ARLEN_TEST_PG_BIN:-$(brew --prefix postgresql@17)/bin}"
export ARLEN_LIBPQ_PREFIX="${ARLEN_LIBPQ_PREFIX:-$(brew --prefix libpq)}"
pg_bin="$(bash tools/ci/resolve_postgres_test_bin.sh)"
# Keep the socket path short: macOS limits Unix socket paths to 104 bytes.
pg_tmp="$(mktemp -d /tmp/arlen-apple-pg.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$pg_tmp/data" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$pg_tmp"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$pg_tmp/data" --no-locale --encoding=UTF8 --auth=trust \
  --username=arlen_unit_test >"$output_dir/initdb.log"
mkdir "$pg_tmp/socket"
"$pg_bin/pg_ctl" -D "$pg_tmp/data" -l "$output_dir/postgres.log" \
  -o "-k $pg_tmp/socket -c listen_addresses=''" -w start >/dev/null
export ARLEN_PG_TEST_DSN="host=$pg_tmp/socket dbname=postgres user=arlen_unit_test"

build_log="$output_dir/build_xctest.log"
if ! bundle_path="$(tools/build_apple_xctest.sh --suite unit --print-bundle-path 2>"$build_log")"; then
  tail -50 "$build_log" >&2
  echo "apple-unit: XCTest bundle build failed; see $build_log" >&2
  exit 1
fi

set +e
xcrun xctest "$bundle_path" >"$xctest_log" 2>&1
xctest_status=$?
set -e
grep -E "^Test Case '.*' (failed|skipped)" "$xctest_log" || true
grep -E "^[[:space:]]+Executed [0-9]+ tests?," "$xctest_log" | tail -1 || true

# Apple's xctest has no -list-tests; every discovered test logs a "started" line.
listing_dir="$output_dir/inventory"
baseline_dir="$output_dir/baseline"
rm -rf "$listing_dir" "$baseline_dir"
mkdir -p "$listing_dir" "$baseline_dir"
sed -nE "s/^Test Case '-\[([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' started\.?$/ArlenUnitTests\/\1\/\2/p" "$xctest_log" |
  sort -u >"$listing_dir/ArlenUnitTests.tests.txt"
cp tests/fixtures/test_inventory/ArlenUnitTests.tests.txt "$baseline_dir/"
set +e
python3 tools/ci/check_test_inventory.py --repo-root "$repo_root" \
  --listing-dir "$listing_dir" --baseline-dir "$baseline_dir"
inventory_status=$?
set -e

if [[ $xctest_status -ne 0 ]]; then
  echo "apple-unit: XCTest failed (exit $xctest_status); see $xctest_log" >&2
  exit "$xctest_status"
fi
exit "$inventory_status"
