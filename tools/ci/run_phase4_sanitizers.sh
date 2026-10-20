#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

source "$repo_root/tools/ci/source_clang_sanitizers.sh"
python3 ./tools/ci/test_clang_sanitizer_runtime.py

make clean
make test-unit
if [[ "${ARLEN_SANITIZER_INCLUDE_INTEGRATION:-0}" == "1" ]]; then
  make test-integration
fi
python3 ./tools/ci/test_runtime_concurrency_probe.py
make boomhauer runtime-concurrency-fixture
python3 ./tools/ci/runtime_concurrency_probe.py \
  --binary ./build/runtime-concurrency-fixture \
  --iterations "${ARLEN_SANITIZER_RUNTIME_ITERS:-1}"
make test-data-layer

echo "ci: phase4 sanitizer gate complete"
