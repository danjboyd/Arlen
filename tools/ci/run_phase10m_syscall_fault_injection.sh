#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_SYSCALL_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/syscall_faults}"
seed="${ARLEN_PHASE10M_SYSCALL_SEED:-10041}"
iterations="${ARLEN_PHASE10M_SYSCALL_ITERS:-1}"
modes="${ARLEN_PHASE10M_SYSCALL_MODES:-concurrent,serialized}"
fixture="${ARLEN_PHASE10M_SYSCALL_FIXTURE:-tests/fixtures/fault_injection/phase10m_syscall_fault_scenarios.json}"
scenarios="${ARLEN_PHASE10M_SYSCALL_SCENARIOS:-}"

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

echo "ci: phase10m syscall fault-injection gate complete"
