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
perf_cooldown_seconds="${ARLEN_PERF_COOLDOWN_SECONDS:-15}"
perf_retry_count="${ARLEN_PERF_RETRY_COUNT:-2}"

capture_perf_artifacts() {
  local profile="$1"
  mkdir -p build/perf/ci
  cp build/perf/latest.json "build/perf/ci/${profile}_report.json"
  cp build/perf/latest.csv "build/perf/ci/${profile}_summary.csv"
  cp build/perf/latest_runs.csv "build/perf/ci/${profile}_runs.csv"
  cp build/perf/latest_trend.json "build/perf/ci/${profile}_trend.json"
  cp build/perf/latest_trend.md "build/perf/ci/${profile}_trend.md"
}

run_perf_profile() {
  local profile="$1"
  local attempt=1
  local status=0
  while (( attempt <= perf_retry_count )); do
    if ARLEN_PERF_PROFILE="$profile" make perf; then
      capture_perf_artifacts "$profile"
      return 0
    else
      status=$?
    fi
    if (( attempt < perf_retry_count )); then
      echo "ci: perf profile ${profile} failed on attempt ${attempt}; retrying after cooldown"
      sleep "$perf_cooldown_seconds"
    fi
    attempt=$((attempt + 1))
  done
  return "$status"
}

make test-unit
make test-integration
make test-data-layer
sleep "$perf_cooldown_seconds"
run_perf_profile default
run_perf_profile middleware_heavy
run_perf_profile template_heavy
run_perf_profile api_reference
run_perf_profile migration_sample

echo "ci: phase4 quality gate complete"
