#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

export EXTRA_OBJC_FLAGS="${EXTRA_OBJC_FLAGS:--fsanitize=address,undefined -fno-omit-frame-pointer}"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1:strict_string_checks=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"

asan_so="$(clang -print-file-name=libasan.so)"
ubsan_so="$(clang -print-file-name=libubsan.so)"
if [[ -z "$asan_so" || ! -f "$asan_so" ]]; then
  echo "sanitizer gate: unable to locate libasan.so via clang"
  exit 1
fi
if [[ -z "$ubsan_so" || ! -f "$ubsan_so" ]]; then
  echo "sanitizer gate: unable to locate libubsan.so via clang"
  exit 1
fi
export XCTEST_LD_PRELOAD="$asan_so:$ubsan_so"

make test-unit
if [[ "${ARLEN_SANITIZER_INCLUDE_INTEGRATION:-0}" == "1" ]]; then
  make test-integration
fi
make boomhauer
python3 ./tools/ci/runtime_concurrency_probe.py \
  --binary ./build/boomhauer \
  --iterations "${ARLEN_SANITIZER_RUNTIME_ITERS:-1}"
make test-data-layer

echo "ci: phase4 sanitizer gate complete"
