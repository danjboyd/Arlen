#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE37_OUTPUT_DIR:-$repo_root/build/release_confidence/phase37}"

mkdir -p "$output_dir"

ARLEN_PHASE37_OUTPUT_DIR="$output_dir" bash "$repo_root/tools/ci/run_phase37_contract.sh"
python3 "$repo_root/tools/ci/check_phase37_intake.py" \
  --repo-root "$repo_root" \
  --output "$output_dir/intake_summary.json"
ARLEN_PHASE37_OUTPUT_DIR="$output_dir" bash "$repo_root/tools/ci/run_phase37_packaged_deploy_proof.sh"
python3 "$repo_root/tools/ci/test_phase37_acceptance_assertions.py" \
  >"$output_dir/acceptance_assertion_selftest.log"
ARLEN_PHASE37_ACCEPTANCE_MODE="${ARLEN_PHASE37_ACCEPTANCE_MODE:-fast}" \
  ARLEN_PHASE37_ACCEPTANCE_OUTPUT_DIR="$output_dir/acceptance" \
  bash "$repo_root/tools/ci/run_phase37_acceptance.sh"

python3 "$repo_root/tools/ci/generate_phase37_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --contract-summary "$output_dir/contract_summary.json" \
  --eoc-golden-summary "$output_dir/eoc_golden_summary.json" \
  --acceptance-manifest "$output_dir/acceptance/manifest.json" \
  --intake-summary "$output_dir/intake_summary.json" \
  --packaged-deploy-proof "$output_dir/packaged_deploy_proof.json"

echo "ci: phase37 confidence gate complete"
