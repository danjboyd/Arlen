#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

mkdir -p build/perf/ci

capture_perf_artifacts() {
  local profile="$1"
  cp build/perf/latest.json "build/perf/ci/${profile}_report.json"
  cp build/perf/latest.csv "build/perf/ci/${profile}_summary.csv"
  cp build/perf/latest_runs.csv "build/perf/ci/${profile}_runs.csv"
  cp build/perf/latest_trend.json "build/perf/ci/${profile}_trend.json"
  cp build/perf/latest_trend.md "build/perf/ci/${profile}_trend.md"
}

run_perf_profile() {
  local profile="$1"
  ARLEN_PERF_PROFILE="$profile" make perf
  capture_perf_artifacts "$profile"
}

make test-unit
make test-integration
run_perf_profile default
run_perf_profile middleware_heavy
run_perf_profile template_heavy
run_perf_profile api_reference
run_perf_profile migration_sample

echo "ci: phase3c quality gate complete"
