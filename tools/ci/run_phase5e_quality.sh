#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export ARLEN_PHASE5E_SOAK_ITERS="${ARLEN_PHASE5E_SOAK_ITERS:-240}"

python3 ./tools/ci/check_runtime_json_abstraction.py --repo-root "$repo_root"
bash ./tools/ci/run_phase5a_quality.sh
bash ./tools/ci/run_runtime_concurrency_gate.sh
bash ./tools/ci/run_phase9i_fault_injection.sh
bash ./tools/ci/run_phase10e_json_performance.sh
bash ./tools/ci/run_phase10g_dispatch_performance.sh
bash ./tools/ci/run_phase10h_http_parse_performance.sh
bash ./tools/ci/run_phase10m_blob_throughput.sh
python3 ./tools/ci/generate_phase5e_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$repo_root/build/release_confidence/phase5e"

echo "ci: phase5e quality gate complete"
