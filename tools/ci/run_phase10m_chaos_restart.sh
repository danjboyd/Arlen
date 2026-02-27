#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_CHAOS_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/chaos_restart}"
thresholds="${ARLEN_PHASE10M_CHAOS_THRESHOLDS:-$repo_root/tests/fixtures/runtime/phase10m_chaos_restart_thresholds.json}"
allow_fail="${ARLEN_PHASE10M_CHAOS_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
make boomhauer

generator_args=(
  --repo-root "$repo_root"
  --output-dir "$output_dir"
  --thresholds "$thresholds"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=(--allow-fail)
fi

python3 ./tools/ci/generate_phase10m_chaos_restart_artifacts.py "${generator_args[@]}"

echo "ci: phase10m chaos restart gate complete"
