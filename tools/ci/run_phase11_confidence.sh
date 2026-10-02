#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

bash ./tools/ci/run_phase11_protocol_adversarial.sh
bash ./tools/ci/run_phase11_protocol_fuzz.sh
bash ./tools/ci/run_phase11_live_adversarial.sh
bash ./tools/ci/run_phase11_sanitizer_matrix.sh

echo "ci: phase11 confidence gate complete"
