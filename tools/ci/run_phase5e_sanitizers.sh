#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

bash ./tools/ci/run_phase4_sanitizers.sh

echo "ci: phase5e sanitizer gate complete"
