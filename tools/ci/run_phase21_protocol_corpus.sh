#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE21_PROTOCOL_OUTPUT_DIR:-$repo_root/build/release_confidence/phase21/protocol}"
fixture="${ARLEN_PHASE21_PROTOCOL_FIXTURE:-tests/fixtures/protocol/phase21_protocol_corpus.json}"
backends="${ARLEN_PHASE21_PROTOCOL_BACKENDS:-llhttp,legacy}"
case_filter="${ARLEN_PHASE21_PROTOCOL_CASES:-}"
allow_fail="${ARLEN_PHASE21_PROTOCOL_ALLOW_FAIL:-0}"

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
)
if [[ -n "$case_filter" ]]; then
  args+=(--case "$case_filter")
fi
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/phase21_protocol_replay.py "${args[@]}"

echo "ci: phase21 protocol corpus gate complete"
