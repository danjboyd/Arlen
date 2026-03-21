#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

output_dir="${ARLEN_PERF_SMOKE_OUTPUT_DIR:-$repo_root/build/perf/ci_smoke}"
profiles_csv="${ARLEN_PERF_SMOKE_PROFILES:-default,template_heavy}"
requests="${ARLEN_PERF_SMOKE_REQUESTS:-120}"
repeats="${ARLEN_PERF_SMOKE_REPEATS:-3}"
skip_build="${ARLEN_PERF_SMOKE_SKIP_BUILD:-0}"

mkdir -p "$output_dir"

capture_perf_artifacts() {
  local profile="$1"
  local profile_dir="$output_dir/$profile"
  mkdir -p "$profile_dir"
  cp "$repo_root/build/perf/latest.json" "$profile_dir/report.json"
  cp "$repo_root/build/perf/latest.csv" "$profile_dir/summary.csv"
  cp "$repo_root/build/perf/latest_runs.csv" "$profile_dir/runs.csv"
  cp "$repo_root/build/perf/latest_trend.json" "$profile_dir/trend.json"
  cp "$repo_root/build/perf/latest_trend.md" "$profile_dir/trend.md"
  if [[ -f "$repo_root/build/perf/server_${profile}.log" ]]; then
    cp "$repo_root/build/perf/server_${profile}.log" "$profile_dir/server.log"
  fi
}

run_profile() {
  local profile="$1"
  ARLEN_PERF_PROFILE="$profile" \
  ARLEN_PERF_REQUESTS="$requests" \
  ARLEN_PERF_REPEATS="$repeats" \
  ARLEN_PERF_SKIP_BUILD="$skip_build" \
  make perf
  capture_perf_artifacts "$profile"
}

IFS=',' read -r -a profiles <<<"$profiles_csv"
for profile in "${profiles[@]}"; do
  trimmed_profile="$(printf '%s' "$profile" | xargs)"
  if [[ -z "$trimmed_profile" ]]; then
    continue
  fi
  run_profile "$trimmed_profile"
done

echo "ci: perf smoke complete profiles=$profiles_csv output_dir=$output_dir"
