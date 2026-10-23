#!/usr/bin/env bash
set -euo pipefail
root="${1:?source}" harness="${2:?harness}" out="${3:?evidence}"
mkdir -p "$out"
cd "$root"
[[ "$(git rev-parse HEAD)" == "$SOURCE_REF" && -z "$(git status --porcelain)" ]]
source tools/source_gnustep_env.sh
unset TEST SKIP_TEST ITERATIONS UNTIL_FAILURE MAKEFLAGS MFLAGS GNUMAKEFLAGS
export ARLEN_TEST_JUNIT=1 ARLEN_USE_VENDORED_XCTEST=1 ARLEN_TEST_RESULTS_DIR="$out/xctest-results"
export TMPDIR="$RUNNER_TEMP/normal-test-temp" TEMP="$RUNNER_TEMP/normal-test-temp" TMP="$RUNNER_TEMP/normal-test-temp"
mkdir -m 700 "$TMPDIR"
cp "$ARLEN_RUNTIME_PREFIX/gnustep-toolchain-provenance.json" "$out/normal-provenance.json"
{ uname -a; cat /etc/os-release; ps -p 1 -o comm=; lscpu; } > "$out/host.txt"
pg_bin="$(bash tools/ci/resolve_postgres_test_bin.sh)"
pg_root="$RUNNER_TEMP/v032-normal-private-pg"
mkdir -m 700 "$pg_root"
trap '"$pg_bin/pg_ctl" -D "$pg_root/data" -m immediate -w stop >/dev/null 2>&1 || true' EXIT
"$pg_bin/initdb" -D "$pg_root/data" --no-locale --encoding=UTF8 --auth=trust --username=arlen_v032 > "$out/pg-init.log"
mkdir "$pg_root/socket"
"$pg_bin/pg_ctl" -D "$pg_root/data" -l "$out/pg-server.log" -o "-k $pg_root/socket -c listen_addresses=''" -w start
export ARLEN_PG_TEST_DSN="host=$pg_root/socket dbname=postgres user=arlen_v032"
make -j4 test-unit > "$out/unit.log" 2>&1
make -j4 test-integration > "$out/integration.log" 2>&1
bash tools/ci/run_runtime_concurrency_gate.sh > "$out/http-concurrency.log" 2>&1
python3 "$harness/verify_native_normal.py" "$root" "$harness" "$out"
