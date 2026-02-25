#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

bash ./tools/ci/run_phase4_sanitizers.sh

if [[ "${ARLEN_SANITIZER_INCLUDE_TSAN:-0}" == "1" ]]; then
  if ! bash ./tools/ci/run_phase5e_tsan_experimental.sh; then
    echo "ci: tsan experimental run failed (non-blocking)"
  fi
fi

echo "ci: phase5e sanitizer gate complete"
