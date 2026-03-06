#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE11_LIVE_OUTPUT_DIR:-$repo_root/build/release_confidence/phase11/live_adversarial}"
modes="${ARLEN_PHASE11_LIVE_MODES:-serialized,concurrent}"
rounds="${ARLEN_PHASE11_LIVE_ROUNDS:-2}"
allow_fail="${ARLEN_PHASE11_LIVE_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

export ARLEN_WEBSOCKET_ALLOWED_ORIGINS="${ARLEN_WEBSOCKET_ALLOWED_ORIGINS:-https://allowed.example}"
export ARLEN_WEBSOCKET_READ_TIMEOUT_MS="${ARLEN_WEBSOCKET_READ_TIMEOUT_MS:-250}"

make boomhauer

args=(
  --repo-root "$repo_root"
  --binary build/boomhauer
  --output-dir "$output_dir"
  --modes "$modes"
  --rounds "$rounds"
)
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/phase11_live_adversarial_probe.py "${args[@]}"

echo "ci: phase11 live adversarial gate complete"
