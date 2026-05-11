#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE28_OUTPUT_DIR:-$repo_root/build/release_confidence/phase28}"
docs_log="$output_dir/phase28_docs.log"

mkdir -p "$output_dir"

source "$repo_root/tools/ci/phase28_common.sh"
phase28_source_gnustep "$repo_root"

ARLEN_PHASE28_TS_UNIT_OUTPUT_DIR="$output_dir/ts_unit" \
  bash "$repo_root/tools/ci/run_phase28_ts_unit.sh"
ARLEN_PHASE28_TS_GENERATED_OUTPUT_DIR="$output_dir/generated" \
  bash "$repo_root/tools/ci/run_phase28_ts_generated.sh"
ARLEN_PHASE28_TS_INTEGRATION_OUTPUT_DIR="$output_dir/integration" \
  bash "$repo_root/tools/ci/run_phase28_ts_integration.sh"
ARLEN_PHASE28_REACT_REFERENCE_OUTPUT_DIR="$output_dir/react_reference" \
  bash "$repo_root/tools/ci/run_react_typescript_reference.sh"

make -C "$repo_root" docs-api 2>&1 | tee "$docs_log"
bash "$repo_root/tools/ci/run_docs_quality.sh" 2>&1 | tee -a "$docs_log"

python3 "$repo_root/tools/ci/generate_phase28_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --unit-manifest "$output_dir/ts_unit/manifest.json" \
  --generated-manifest "$output_dir/generated/manifest.json" \
  --integration-manifest "$output_dir/integration/manifest.json" \
  --react-reference-manifest "$output_dir/react_reference/manifest.json" \
  --generated-metrics "$output_dir/generated/generated_metrics.json" \
  --docs-log "$docs_log"

echo "ci: phase28 confidence gate complete"
