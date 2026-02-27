#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10L_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10l}"
thresholds_path="${ARLEN_PHASE10L_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10l_route_match_thresholds.json}"
route_count="${ARLEN_PHASE10L_ROUTE_COUNT:-12000}"
iterations="${ARLEN_PHASE10L_ITERATIONS:-15000}"
warmup="${ARLEN_PHASE10L_WARMUP:-1500}"
rounds="${ARLEN_PHASE10L_ROUNDS:-3}"
capture_flamegraph="${ARLEN_PHASE10L_CAPTURE_FLAMEGRAPH:-0}"
flamegraph_frequency="${ARLEN_PHASE10L_FLAMEGRAPH_FREQUENCY:-99}"
flamegraph_iterations="${ARLEN_PHASE10L_FLAMEGRAPH_ITERATIONS:-15000}"
flamegraph_warmup="${ARLEN_PHASE10L_FLAMEGRAPH_WARMUP:-1500}"
allow_fail="${ARLEN_PHASE10L_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
make route-match-perf-bench

generator_args=(
  "--repo-root" "$repo_root"
  "--benchmark-binary" "$repo_root/build/route-match-perf-bench"
  "--thresholds" "$thresholds_path"
  "--output-dir" "$output_dir"
  "--route-count" "$route_count"
  "--iterations" "$iterations"
  "--warmup" "$warmup"
  "--rounds" "$rounds"
  "--flamegraph-frequency" "$flamegraph_frequency"
  "--flamegraph-iterations" "$flamegraph_iterations"
  "--flamegraph-warmup" "$flamegraph_warmup"
)

if [[ "$capture_flamegraph" == "1" ]]; then
  generator_args+=("--capture-flamegraph")
fi
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=("--allow-fail")
fi

python3 ./tools/ci/generate_phase10l_route_match_artifacts.py "${generator_args[@]}"

echo "ci: phase10l route matcher investigation gate complete"
