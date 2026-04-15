#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE33_OUTPUT_DIR:-$repo_root/build/release_confidence/phase33}"
objc_log="$output_dir/phase33_objc.log"

mkdir -p "$output_dir"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" arlen >/dev/null
make -C "$repo_root" build-tests >/dev/null

set +e
make -C "$repo_root" test-unit-filter TEST=Phase33EHTests >"$objc_log" 2>&1
objc_status=$?
set -e
printf '%s\n' "$objc_status" >"$output_dir/phase33_objc.exit"

ARLEN_PHASE28_TS_GENERATED_OUTPUT_DIR="$output_dir/ts_generated" \
  bash "$repo_root/tools/ci/run_phase28_ts_generated.sh"
ARLEN_PHASE28_TS_UNIT_OUTPUT_DIR="$output_dir/ts_unit" \
  bash "$repo_root/tools/ci/run_phase28_ts_unit.sh"

python3 "$repo_root/tools/ci/generate_phase33_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --objc-log "$objc_log" \
  --ts-generated-manifest "$output_dir/ts_generated/manifest.json" \
  --ts-unit-manifest "$output_dir/ts_unit/manifest.json"

echo "ci: phase33 confidence gate complete"
