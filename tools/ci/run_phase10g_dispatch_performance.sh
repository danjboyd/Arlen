#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10G_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10g}"
thresholds_path="${ARLEN_PHASE10G_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10g_dispatch_perf_thresholds.json}"
iterations="${ARLEN_PHASE10G_ITERATIONS:-50000}"
warmup="${ARLEN_PHASE10G_WARMUP:-5000}"
rounds="${ARLEN_PHASE10G_ROUNDS:-3}"
allow_fail="${ARLEN_PHASE10G_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
make dispatch-perf-bench

generator_args=(
  "--repo-root" "$repo_root"
  "--benchmark-binary" "$repo_root/build/dispatch-perf-bench"
  "--thresholds" "$thresholds_path"
  "--output-dir" "$output_dir"
  "--iterations" "$iterations"
  "--warmup" "$warmup"
  "--rounds" "$rounds"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=("--allow-fail")
fi

python3 ./tools/ci/generate_phase10g_dispatch_perf_artifacts.py "${generator_args[@]}"

echo "ci: phase10g dispatch performance gate complete"
