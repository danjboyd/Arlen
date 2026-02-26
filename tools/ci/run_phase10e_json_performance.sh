#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10E_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10e}"
fixtures_dir="${ARLEN_PHASE10E_FIXTURES_DIR:-$repo_root/tests/fixtures/performance/json}"
thresholds_path="${ARLEN_PHASE10E_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10e_json_perf_thresholds.json}"
iterations="${ARLEN_PHASE10E_ITERATIONS:-1500}"
warmup="${ARLEN_PHASE10E_WARMUP:-200}"
allow_fail="${ARLEN_PHASE10E_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
make json-perf-bench

generator_args=(
  "--repo-root" "$repo_root"
  "--benchmark-binary" "$repo_root/build/json-perf-bench"
  "--fixtures-dir" "$fixtures_dir"
  "--thresholds" "$thresholds_path"
  "--output-dir" "$output_dir"
  "--iterations" "$iterations"
  "--warmup" "$warmup"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=("--allow-fail")
fi

python3 ./tools/ci/generate_phase10e_json_perf_artifacts.py "${generator_args[@]}"

echo "ci: phase10e JSON performance gate complete"
