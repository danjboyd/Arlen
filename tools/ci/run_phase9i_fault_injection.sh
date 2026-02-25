#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

output_dir="${ARLEN_PHASE9I_OUTPUT_DIR:-$repo_root/build/release_confidence/phase9i}"
seed="${ARLEN_PHASE9I_SEED:-9011}"
iterations="${ARLEN_PHASE9I_ITERS:-1}"
modes="${ARLEN_PHASE9I_MODES:-concurrent,serialized}"
scenarios="${ARLEN_PHASE9I_SCENARIOS:-}"

make boomhauer

command=(
  python3
  ./tools/ci/runtime_fault_injection.py
  --repo-root "$repo_root"
  --binary ./build/boomhauer
  --output-dir "$output_dir"
  --seed "$seed"
  --iterations "$iterations"
  --modes "$modes"
)
if [[ -n "$scenarios" ]]; then
  command+=(--scenarios "$scenarios")
fi

"${command[@]}"

echo "ci: phase9i fault-injection gate complete"
