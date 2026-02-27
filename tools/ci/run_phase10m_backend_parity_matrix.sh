#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_PARITY_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/backend_parity}"
combos="${ARLEN_PHASE10M_MATRIX_COMBOS:-1:1,1:0,0:1,0:0}"
http_fixtures_dir="${ARLEN_PHASE10M_HTTP_FIXTURES_DIR:-tests/fixtures/performance/http_parse}"
json_fixtures_dir="${ARLEN_PHASE10M_JSON_FIXTURES_DIR:-tests/fixtures/performance/json}"
allow_fail="${ARLEN_PHASE10M_PARITY_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

args=(
  --repo-root "$repo_root"
  --output-dir "$output_dir"
  --combos "$combos"
  --http-fixtures-dir "$http_fixtures_dir"
  --json-fixtures-dir "$json_fixtures_dir"
)
if [[ "$allow_fail" == "1" ]]; then
  args+=(--allow-fail)
fi

python3 ./tools/ci/generate_phase10m_backend_parity_artifacts.py "${args[@]}"

echo "ci: phase10m backend parity matrix gate complete"
