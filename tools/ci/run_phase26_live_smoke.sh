#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE26_LIVE_OUTPUT_DIR:-$repo_root/build/release_confidence/phase26/live}"
manifest_path="${ARLEN_PHASE26_LIVE_MANIFEST:-$output_dir/manifest.json}"
log_path="${ARLEN_PHASE26_LIVE_LOG:-$output_dir/live.log}"
generated_dir="$output_dir/generated"
dataverse_manifest="$output_dir/dataverse.json"

mkdir -p "$output_dir"

dataverse_env_for_target() {
  local base_name="$1"
  local target_name="${2:-default}"
  local normalized_target
  normalized_target="$(printf '%s' "$target_name" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$normalized_target" && "$normalized_target" != "default" ]]; then
    local targeted_name="${base_name}_$(printf '%s' "$normalized_target" | tr '[:lower:]' '[:upper:]')"
    local targeted_value="${!targeted_name:-}"
    if [[ -n "$targeted_value" ]]; then
      printf '%s\n' "$targeted_value"
      return 0
    fi
  fi
  printf '%s\n' "${!base_name:-}"
}

write_manifest() {
  local status="$1"
  local reason="${2:-}"
  cat >"$manifest_path" <<EOF
{
  "status": "$status",
  "reason": "$reason",
  "artifacts": [
    "live.log"
  ]
}
EOF
}

have_live_credentials() {
  local live_target="${ARLEN_PHASE26_DATAVERSE_TARGET:-default}"
  local service_root
  service_root="$(dataverse_env_for_target ARLEN_DATAVERSE_URL "$live_target")"
  if [[ -z "$service_root" ]]; then
    service_root="$(dataverse_env_for_target ARLEN_DATAVERSE_SERVICE_ROOT "$live_target")"
  fi
  local tenant_id
  tenant_id="$(dataverse_env_for_target ARLEN_DATAVERSE_TENANT_ID "$live_target")"
  local client_id
  client_id="$(dataverse_env_for_target ARLEN_DATAVERSE_CLIENT_ID "$live_target")"
  local client_secret
  client_secret="$(dataverse_env_for_target ARLEN_DATAVERSE_CLIENT_SECRET "$live_target")"
  [[ -n "$service_root" &&
     -n "$tenant_id" &&
     -n "$client_id" &&
     -n "$client_secret" ]]
}

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

if ! have_live_credentials; then
  printf '%s\n' "phase26-live: skipped because ARLEN_DATAVERSE_* live credentials are not fully set" | tee "$log_path"
  write_manifest skipped missing_credentials
  exit 0
fi

live_target="${ARLEN_PHASE26_DATAVERSE_TARGET:-default}"
rm -rf "$generated_dir"
mkdir -p "$generated_dir"

set +e
"$repo_root/build/arlen" dataverse-codegen \
  --target "$live_target" \
  --output-dir "$generated_dir" \
  --manifest "$dataverse_manifest" \
  --prefix ALNPhase26Live \
  --force 2>&1 | tee "$log_path"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  write_manifest pass ""
else
  write_manifest fail live_codegen_failed
fi

exit "$status"
