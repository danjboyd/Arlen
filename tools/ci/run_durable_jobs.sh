#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
source tools/source_gnustep_env.sh

# An isolated cluster makes live persistence mandatory without application credentials.
pg_bin="$(bash "$repo_root/tools/ci/resolve_postgres_test_bin.sh")"
echo "ci: PostgreSQL server tools: $pg_bin"
jobs_pg_tmp="$(mktemp -d /tmp/arlen-jobs-pg.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$jobs_pg_tmp/data" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$jobs_pg_tmp"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$jobs_pg_tmp/data" --no-locale --encoding=UTF8 --auth=trust --username=arlen_jobs_test >"$jobs_pg_tmp/init.log"
mkdir "$jobs_pg_tmp/socket"
"$pg_bin/pg_ctl" -D "$jobs_pg_tmp/data" -l "$jobs_pg_tmp/server.log" \
  -o "-k $jobs_pg_tmp/socket -c listen_addresses=''" -w start
export ARLEN_PG_TEST_DSN="host=$jobs_pg_tmp/socket dbname=postgres user=arlen_jobs_test connect_timeout=2"
export ARLEN_JOBS_TEST_PG_DATA="$jobs_pg_tmp/data"
export ARLEN_JOBS_TEST_PG_BIN="$pg_bin"
mkdir -p build/release_confidence
if ! make durable-jobs-tests 2>&1 | tee build/release_confidence/durable_jobs.log; then
  cat "$jobs_pg_tmp/server.log" >&2
  exit 1
fi
