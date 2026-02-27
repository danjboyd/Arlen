#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_PROTOCOL_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/protocol_adversarial}"
fixture="${ARLEN_PHASE10M_PROTOCOL_FIXTURE:-tests/fixtures/protocol/phase10m_protocol_adversarial_cases.json}"
backends="${ARLEN_PHASE10M_PROTOCOL_BACKENDS:-llhttp,legacy}"
allow_fail="${ARLEN_PHASE10M_PROTOCOL_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

make boomhauer

args=(
  --repo-root "$repo_root"
  --binary build/boomhauer
  --fixture "$fixture"
  --output-dir "$output_dir"
  --backends "$backends"
)
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/protocol_adversarial_probe.py "${args[@]}"

echo "ci: phase10m protocol adversarial gate complete"
