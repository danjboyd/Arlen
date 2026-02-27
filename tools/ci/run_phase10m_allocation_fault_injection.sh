#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_ALLOC_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/allocation_faults}"
seed="${ARLEN_PHASE10M_ALLOC_SEED:-11041}"
iterations="${ARLEN_PHASE10M_ALLOC_ITERS:-1}"
modes="${ARLEN_PHASE10M_ALLOC_MODES:-concurrent,serialized}"
fixture="${ARLEN_PHASE10M_ALLOC_FIXTURE:-tests/fixtures/fault_injection/phase10m_allocation_fault_scenarios.json}"
scenarios="${ARLEN_PHASE10M_ALLOC_SCENARIOS:-}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

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
  --scenario-fixture "$fixture"
)
if [[ -n "$scenarios" ]]; then
  command+=(--scenarios "$scenarios")
fi

"${command[@]}"

echo "ci: phase10m allocation fault-injection gate complete"
