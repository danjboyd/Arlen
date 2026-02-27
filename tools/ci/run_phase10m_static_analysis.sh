#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_STATIC_ANALYSIS_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/static_analysis}"
policy="${ARLEN_PHASE10M_STATIC_ANALYSIS_POLICY:-$repo_root/tests/fixtures/static_analysis/phase10m_static_analysis_policy.json}"
allow_fail="${ARLEN_PHASE10M_STATIC_ANALYSIS_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

args=(
  --repo-root "$repo_root"
  --policy "$policy"
  --output-dir "$output_dir"
)
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/generate_phase10m_static_analysis_artifacts.py "${args[@]}"

echo "ci: phase10m static analysis gate complete"
