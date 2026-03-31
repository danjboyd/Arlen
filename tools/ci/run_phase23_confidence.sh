#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE23_OUTPUT_DIR:-$repo_root/build/release_confidence/phase23}"
dataverse_log="$output_dir/phase23_dataverse_tests.log"
live_output_dir="$output_dir/live"
live_log="$output_dir/phase23_live_codegen.log"
live_manifest="$live_output_dir/manifest.json"

mkdir -p "$output_dir" "$live_output_dir"

write_live_manifest() {
  local status="$1"
  local reason="${2:-}"

  case "$status" in
    pass)
      cat >"$live_manifest" <<EOF
{
  "status": "pass",
  "reason": "",
  "artifacts": [
    "generated/ALNDVLiveDataverseSchema.h",
    "generated/ALNDVLiveDataverseSchema.m",
    "dataverse.json",
    "../phase23_live_codegen.log"
  ]
}
EOF
      ;;
    fail)
      cat >"$live_manifest" <<EOF
{
  "status": "fail",
  "reason": "${reason:-codegen_failed}",
  "artifacts": [
    "../phase23_live_codegen.log"
  ]
}
EOF
      ;;
    *)
      cat >"$live_manifest" <<EOF
{
  "status": "skipped",
  "reason": "${reason:-missing_credentials}",
  "artifacts": [
    "../phase23_live_codegen.log"
  ]
}
EOF
      ;;
  esac
}

have_live_credentials() {
  local service_root="${ARLEN_DATAVERSE_URL:-${ARLEN_DATAVERSE_SERVICE_ROOT:-}}"
  [[ -n "$service_root" &&
     -n "${ARLEN_DATAVERSE_TENANT_ID:-}" &&
     -n "${ARLEN_DATAVERSE_CLIENT_ID:-}" &&
     -n "${ARLEN_DATAVERSE_CLIENT_SECRET:-}" ]]
}

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

make -C "$repo_root" phase23-dataverse-tests 2>&1 | tee "$dataverse_log"

if have_live_credentials; then
  live_target="${ARLEN_PHASE23_DATAVERSE_TARGET:-default}"
  rm -rf "$live_output_dir/generated"
  mkdir -p "$live_output_dir/generated"

  live_args=(
    "$repo_root/build/arlen"
    dataverse-codegen
    --target "$live_target"
    --output-dir "$live_output_dir/generated"
    --manifest "$live_output_dir/dataverse.json"
    --prefix ALNDVLive
    --force
  )

  if [[ -n "${ARLEN_PHASE23_DATAVERSE_ENTITIES:-}" ]]; then
    IFS=',' read -r -a live_entities <<<"${ARLEN_PHASE23_DATAVERSE_ENTITIES}"
    for entity in "${live_entities[@]}"; do
      entity="$(printf '%s' "$entity" | xargs)"
      if [[ -n "$entity" ]]; then
        live_args+=(--entity "$entity")
      fi
    done
  fi

  set +e
  "${live_args[@]}" 2>&1 | tee "$live_log"
  live_status=$?
  set -e

  if [[ $live_status -eq 0 ]]; then
    write_live_manifest pass
  else
    write_live_manifest fail codegen_failed
  fi
else
  printf '%s\n' "phase23-confidence: live Dataverse codegen skipped because ARLEN_DATAVERSE_* credentials are not fully set" | tee "$live_log"
  write_live_manifest skipped missing_credentials
fi

python3 "$repo_root/tools/ci/generate_phase23_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --dataverse-log "$dataverse_log" \
  --live-manifest "$live_manifest" \
  --live-log "$live_log"

echo "ci: phase23 confidence gate complete"
