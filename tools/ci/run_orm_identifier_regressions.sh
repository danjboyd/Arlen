#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
source tools/source_gnustep_env.sh

# An isolated cluster makes live persistence mandatory without application credentials.
pg_bin="$(bash "$repo_root/tools/ci/resolve_postgres_test_bin.sh")"
echo "ci: PostgreSQL server tools: $pg_bin"
orm_pg_tmp="$(mktemp -d /tmp/arlen-orm-pg.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$orm_pg_tmp/data" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$orm_pg_tmp"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$orm_pg_tmp/data" --no-locale --encoding=UTF8 --auth=trust --username=arlen_orm_test >"$orm_pg_tmp/init.log"
mkdir "$orm_pg_tmp/socket"
"$pg_bin/pg_ctl" -D "$orm_pg_tmp/data" -l "$orm_pg_tmp/server.log" \
  -o "-k $orm_pg_tmp/socket -c listen_addresses=''" -w start
export ARLEN_PG_TEST_DSN="host=$orm_pg_tmp/socket dbname=postgres user=arlen_orm_test"
make phase26-orm-generated phase26-orm-unit phase20-sql-builder-tests
