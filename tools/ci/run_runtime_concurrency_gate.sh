#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

make boomhauer
python3 ./tools/ci/runtime_concurrency_probe.py \
  --binary ./build/boomhauer \
  --iterations "${ARLEN_RUNTIME_CONCURRENCY_ITERS:-2}"

echo "ci: runtime concurrency gate complete"
