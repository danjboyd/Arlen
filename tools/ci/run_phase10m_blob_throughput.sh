#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_BLOB_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/blob_throughput}"
thresholds_path="${ARLEN_PHASE10M_BLOB_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10m_blob_throughput_thresholds.json}"
profile="${ARLEN_PHASE10M_BLOB_PROFILE:-phase10m_blob_large}"
concurrency="${ARLEN_PHASE10M_BLOB_CONCURRENCY:-32}"
repeats="${ARLEN_PHASE10M_BLOB_REPEATS:-3}"
requests="${ARLEN_PHASE10M_BLOB_REQUESTS:-120}"
fast_mode="${ARLEN_PHASE10M_BLOB_FAST:-0}"
allow_fail="${ARLEN_PHASE10M_BLOB_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

ARLEN_PERF_PROFILE="$profile" \
ARLEN_PERF_CONCURRENCY="$concurrency" \
ARLEN_PERF_REPEATS="$repeats" \
ARLEN_PERF_REQUESTS="$requests" \
ARLEN_PERF_FAST="$fast_mode" \
ARLEN_PERF_SKIP_GATE=1 \
ARLEN_PERF_SKIP_BUILD=0 \
bash ./tests/performance/run_perf.sh

generator_args=(
  "--repo-root" "$repo_root"
  "--report" "$repo_root/build/perf/latest.json"
  "--runs-csv" "$repo_root/build/perf/latest_runs.csv"
  "--summary-csv" "$repo_root/build/perf/latest.csv"
  "--thresholds" "$thresholds_path"
  "--output-dir" "$output_dir"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=("--allow-fail")
fi

python3 ./tools/ci/generate_phase10m_blob_throughput_artifacts.py "${generator_args[@]}"

echo "ci: phase10m blob throughput gate complete"
