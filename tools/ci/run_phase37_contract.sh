#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE37_OUTPUT_DIR:-$repo_root/build/release_confidence/phase37}"
mkdir -p "$output_dir"

python3 "$repo_root/tools/ci/check_phase37_contract.py" \
  --repo-root "$repo_root" \
  --output "$output_dir/contract_summary.json"

echo "ci: phase37 contract gate complete"
