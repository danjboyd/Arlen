#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE37_ACCEPTANCE_OUTPUT_DIR:-$repo_root/build/release_confidence/phase37/acceptance}"
include_service_backed="${ARLEN_PHASE37_INCLUDE_SERVICE_BACKED:-0}"

args=(
  --repo-root "$repo_root"
  --output-dir "$output_dir"
)
if [[ "$include_service_backed" == "1" ]]; then
  args+=(--include-service-backed)
fi

python3 "$repo_root/tools/ci/phase37_acceptance_harness.py" "${args[@]}"

echo "ci: phase37 acceptance gate complete"
