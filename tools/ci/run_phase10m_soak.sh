#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_SOAK_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/soak}"
thresholds="${ARLEN_PHASE10M_SOAK_THRESHOLDS:-$repo_root/tests/fixtures/performance/phase10m_soak_thresholds.json}"
allow_fail="${ARLEN_PHASE10M_SOAK_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
make boomhauer

generator_args=(
  --repo-root "$repo_root"
  --binary "$repo_root/build/boomhauer"
  --thresholds "$thresholds"
  --output-dir "$output_dir"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=(--allow-fail)
fi

python3 ./tools/ci/generate_phase10m_soak_artifacts.py "${generator_args[@]}"

echo "ci: phase10m long-run soak gate complete"
