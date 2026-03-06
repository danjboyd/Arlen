#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE11_PROTOCOL_OUTPUT_DIR:-$repo_root/build/release_confidence/phase11/protocol_adversarial}"
fixture="${ARLEN_PHASE11_PROTOCOL_FIXTURE:-tests/fixtures/protocol/phase11_protocol_adversarial_cases.json}"
backends="${ARLEN_PHASE11_PROTOCOL_BACKENDS:-llhttp,legacy}"
allow_fail="${ARLEN_PHASE11_PROTOCOL_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

export ARLEN_WEBSOCKET_ALLOWED_ORIGINS="${ARLEN_WEBSOCKET_ALLOWED_ORIGINS:-https://allowed.example}"

make boomhauer

args=(
  --repo-root "$repo_root"
  --binary build/boomhauer
  --fixture "$fixture"
  --output-dir "$output_dir"
  --backends "$backends"
  --version-label "phase11-protocol-adversarial-v1"
  --markdown-title "Phase 11 Protocol Adversarial Probe"
  --markdown-filename "phase11_protocol_adversarial.md"
  --print-label "phase11-protocol-adversarial"
)
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/protocol_adversarial_probe.py "${args[@]}"

echo "ci: phase11 protocol adversarial gate complete"
