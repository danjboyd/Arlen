#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

tsan_so="$(clang -print-file-name=libtsan.so)"
if [[ -z "$tsan_so" || ! -f "$tsan_so" ]]; then
  echo "ci: tsan experimental skipped (libtsan.so unavailable)"
  exit 0
fi

export EXTRA_OBJC_FLAGS="${EXTRA_OBJC_FLAGS:--fsanitize=thread -fno-omit-frame-pointer}"
export TSAN_OPTIONS="${TSAN_OPTIONS:-halt_on_error=1:history_size=7}"
export XCTEST_LD_PRELOAD="$tsan_so"

make boomhauer
make test-unit
python3 ./tools/ci/runtime_concurrency_probe.py \
  --binary ./build/boomhauer \
  --iterations "${ARLEN_TSAN_RUNTIME_ITERS:-1}"

echo "ci: phase5e tsan experimental run complete"
