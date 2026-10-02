#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
source tools/source_gnustep_env.sh
export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
pg_bin="$(bash tools/ci/resolve_postgres_test_bin.sh)"
regression_tmp="$(mktemp -d /tmp/arlen-postgres-regressions.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$regression_tmp/data" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$regression_tmp"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$regression_tmp/data" --no-locale --encoding=UTF8 --auth=trust --username=arlen_regression >"$regression_tmp/init.log"
mkdir "$regression_tmp/socket"
"$pg_bin/pg_ctl" -D "$regression_tmp/data" -l "$regression_tmp/server.log" \
  -o "-k $regression_tmp/socket -c listen_addresses=''" -w start
# URI form also supports older test commands that pass the DSN as a shell argument.
export ARLEN_PG_TEST_DSN="postgresql://arlen_regression@/postgres?host=$regression_tmp/socket"

# Exercise explicit non-default GNUSTEP_SH propagation into nested build scripts.
printf 'source %q\n' "$GNUSTEP_SH" > "$regression_tmp/GNUstep.sh"
export GNUSTEP_SH="$regression_tmp/GNUstep.sh"
mkdir -p build/release_confidence/postgres_regressions
for test_class in GNUstepResolutionTests TestSupportTests Phase27SearchTests; do
  make test-unit-filter TEST="$test_class" 2>&1 | tee "build/release_confidence/postgres_regressions/$test_class.log"
done
for test_class in PostgresIntegrationTests Phase13ModulePostgresIntegrationTests Phase13AuthAdminIntegrationTests; do
  make test-integration-filter TEST="$test_class" 2>&1 | tee "build/release_confidence/postgres_regressions/$test_class.log"
done
# A second auth run detects accumulation of child servers and their DB sessions.
make test-integration-filter TEST=Phase13AuthAdminIntegrationTests 2>&1 | tee build/release_confidence/postgres_regressions/auth-repeat.log
# Inspect only servers belonging to this cluster; unrelated developer apps are untouched.
python3 - <<'CHECK_PROCESSES'
import os
from pathlib import Path
marker = b"ARLEN_PG_TEST_DSN=" + os.environ["ARLEN_PG_TEST_DSN"].encode()
leaked = []
for entry in Path("/proc").iterdir():
    if not entry.name.isdigit():
        continue
    try:
        if entry.joinpath("comm").read_text().strip() != "boomhauer-app":
            continue
        if marker in entry.joinpath("environ").read_bytes().split(b"\0"):
            leaked.append(entry.name)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        continue
if leaked:
    raise SystemExit("postgres-regressions: leaked server PIDs: " + ", ".join(leaked))
CHECK_PROCESSES
remaining_sessions="$("$pg_bin/psql" "$ARLEN_PG_TEST_DSN" -Atc "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid()")"
if [[ "$remaining_sessions" != 0 ]]; then
  echo "postgres-regressions: leaked $remaining_sessions database sessions" >&2
  exit 1
fi
# dropdb without FORCE proves that the test database has no remaining users.
"$pg_bin/dropdb" --host="$regression_tmp/socket" --username=arlen_regression postgres
