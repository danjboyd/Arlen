#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE21_MATRIX_OUTPUT_DIR:-$repo_root/build/release_confidence/phase21/generated_apps}"
fixture="${ARLEN_PHASE21_MATRIX_FIXTURE:-tests/fixtures/phase21/generated_app_matrix.json}"
allow_fail="${ARLEN_PHASE21_MATRIX_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

make arlen boomhauer

args=(
  --repo-root "$repo_root"
  --fixture "$fixture"
  --output-dir "$output_dir"
)
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/phase21_generated_app_matrix.py "${args[@]}"

echo "ci: phase21 generated-app matrix complete"
