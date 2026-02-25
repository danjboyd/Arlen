#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export ARLEN_PHASE5E_SOAK_ITERS="${ARLEN_PHASE5E_SOAK_ITERS:-240}"

bash ./tools/ci/run_phase5a_quality.sh
bash ./tools/ci/run_runtime_concurrency_gate.sh
python3 ./tools/ci/generate_phase5e_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$repo_root/build/release_confidence/phase5e"

echo "ci: phase5e quality gate complete"
