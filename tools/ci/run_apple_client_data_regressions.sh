#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo 'Apple runtime required' >&2; exit 1; }
export ARLEN_TEST_PG_BIN="${ARLEN_TEST_PG_BIN:-$(brew --prefix postgresql@17)/bin}"
export ARLEN_LIBPQ_PREFIX="${ARLEN_LIBPQ_PREFIX:-$(brew --prefix libpq)}"
pg_bin="$(bash tools/ci/resolve_postgres_test_bin.sh)"
client_pg_tmp="$(mktemp -d /tmp/arlen-client-pg.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$client_pg_tmp/data" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$client_pg_tmp"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$client_pg_tmp/data" --no-locale --encoding=UTF8 --auth=trust --username=arlen_client_test >"$client_pg_tmp/init.log"
mkdir "$client_pg_tmp/socket"
"$pg_bin/pg_ctl" -D "$client_pg_tmp/data" -l "$client_pg_tmp/server.log" \
  -o "-k $client_pg_tmp/socket -c listen_addresses=''" -w start
export ARLEN_PG_TEST_DSN="host=$client_pg_tmp/socket dbname=postgres user=arlen_client_test"
bundle_path="$(tools/build_apple_xctest.sh --suite unit --print-bundle-path)"
for filter in HTTPCompatTests DataverseRegressionTests PgTests/testPostgresTimestampMicrosecondRoundTrips; do
  xcrun xctest -XCTest "$filter" "$bundle_path"
done
