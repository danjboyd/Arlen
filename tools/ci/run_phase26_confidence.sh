#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE26_OUTPUT_DIR:-$repo_root/build/release_confidence/phase26}"
unit_log="$output_dir/phase26_orm_unit.log"
generated_log="$output_dir/phase26_orm_generated.log"
integration_log="$output_dir/phase26_orm_integration.log"
backend_log="$output_dir/phase26_orm_backend_parity.log"
perf_log="$output_dir/phase26_orm_perf.log"
reference_log="$output_dir/phase26_orm_reference.log"
docs_log="$output_dir/phase26_docs.log"
live_manifest="$output_dir/live/manifest.json"
perf_json="$output_dir/perf/perf_smoke.json"

mkdir -p "$output_dir"

write_live_manifest() {
  local status="$1"
  local reason="${2:-}"
  mkdir -p "$(dirname "$live_manifest")"
  cat >"$live_manifest" <<EOF
{
  "status": "$status",
  "reason": "$reason",
  "artifacts": [
    "live.log"
  ]
}
EOF
}

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

make -C "$repo_root" phase26-orm-unit 2>&1 | tee "$unit_log"
make -C "$repo_root" phase26-orm-generated 2>&1 | tee "$generated_log"
make -C "$repo_root" phase26-orm-integration 2>&1 | tee "$integration_log"
make -C "$repo_root" phase26-orm-backend-parity 2>&1 | tee "$backend_log"
ARLEN_PHASE26_PERF_OUTPUT="$perf_json" make -C "$repo_root" phase26-orm-perf 2>&1 | tee "$perf_log"
make -C "$repo_root" arlen-orm-reference 2>&1 | tee "$reference_log"
make -C "$repo_root" docs-api 2>&1 | tee "$docs_log"
bash "$repo_root/tools/ci/run_docs_quality.sh" 2>&1 | tee -a "$docs_log"
set +e
ARLEN_PHASE26_LIVE_OUTPUT_DIR="$output_dir/live" \
ARLEN_PHASE26_LIVE_MANIFEST="$live_manifest" \
ARLEN_PHASE26_LIVE_LOG="$output_dir/live/live.log" \
  make -C "$repo_root" phase26-orm-live
live_status=$?
set -e

if [[ ! -f "$live_manifest" ]]; then
  if [[ $live_status -eq 0 ]]; then
    write_live_manifest pass ""
  else
    write_live_manifest fail live_target_failed
  fi
fi

python3 "$repo_root/tools/ci/generate_phase26_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --unit-log "$unit_log" \
  --generated-log "$generated_log" \
  --integration-log "$integration_log" \
  --backend-log "$backend_log" \
  --perf-log "$perf_log" \
  --reference-log "$reference_log" \
  --docs-log "$docs_log" \
  --perf-json "$perf_json" \
  --live-manifest "$live_manifest"

echo "ci: phase26 confidence gate complete"
