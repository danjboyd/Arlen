#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_SOAK_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/soak}"
thresholds="${ARLEN_PHASE10M_SOAK_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10m_soak_thresholds.json}"
allow_fail="${ARLEN_PHASE10M_SOAK_ALLOW_FAIL:-0}"
perf_cooldown_seconds="${ARLEN_PERF_COOLDOWN_SECONDS:-15}"
perf_retry_count="${ARLEN_PERF_RETRY_COUNT:-2}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

run_soak_gate() {
  local attempt=1
  local status=0
  local generator_args=(
    --repo-root "$repo_root"
    --binary "$repo_root/build/boomhauer"
    --thresholds "$thresholds"
    --output-dir "$output_dir"
  )
  if [[ "$allow_fail" == "1" ]]; then
    generator_args+=(--allow-fail)
  fi

  while (( attempt <= perf_retry_count )); do
    if make boomhauer >/dev/null &&
      python3 ./tools/ci/generate_phase10m_soak_artifacts.py "${generator_args[@]}"; then
      return 0
    else
      status=$?
    fi
    if (( attempt < perf_retry_count )); then
      echo "ci: phase10m long-run soak failed on attempt ${attempt}; retrying after cooldown"
      sleep "$perf_cooldown_seconds"
    fi
    attempt=$((attempt + 1))
  done

  return "$status"
}

run_soak_gate

echo "ci: phase10m long-run soak gate complete"
