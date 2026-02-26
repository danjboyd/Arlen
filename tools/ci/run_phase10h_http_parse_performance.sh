#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10H_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10h}"
fixtures_dir="${ARLEN_PHASE10H_FIXTURES_DIR:-$repo_root/tests/fixtures/performance/http_parse}"
thresholds_path="${ARLEN_PHASE10H_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10h_http_parse_perf_thresholds.json}"
iterations="${ARLEN_PHASE10H_ITERATIONS:-1500}"
warmup="${ARLEN_PHASE10H_WARMUP:-200}"
allow_fail="${ARLEN_PHASE10H_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
make http-parse-perf-bench

generator_args=(
  "--repo-root" "$repo_root"
  "--benchmark-binary" "$repo_root/build/http-parse-perf-bench"
  "--fixtures-dir" "$fixtures_dir"
  "--thresholds" "$thresholds_path"
  "--output-dir" "$output_dir"
  "--iterations" "$iterations"
  "--warmup" "$warmup"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=("--allow-fail")
fi

python3 ./tools/ci/generate_phase10h_http_parse_perf_artifacts.py "${generator_args[@]}"

echo "ci: phase10h http parser performance gate complete"
