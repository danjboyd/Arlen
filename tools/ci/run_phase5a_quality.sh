#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

bash ./tools/ci/run_phase4_quality.sh
python3 ./tools/ci/check_phase5a_contracts.py

echo "ci: phase5a quality gate complete"
