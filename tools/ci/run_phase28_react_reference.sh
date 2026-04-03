#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE28_REACT_REFERENCE_OUTPUT_DIR:-$repo_root/build/release_confidence/phase28/react_reference}"
log_path="$output_dir/phase28_react_reference.log"
server_log="$output_dir/phase28_reference_server.log"
live_openapi="$output_dir/live_openapi.json"
merged_openapi="$output_dir/merged_openapi.json"
comparison_path="$output_dir/openapi_comparison.json"
dist_listing="$output_dir/react_reference_dist.txt"
manifest_path="$output_dir/manifest.json"

mkdir -p "$output_dir"

source "$repo_root/tools/ci/phase28_common.sh"
phase28_require_command curl
phase28_require_command npm
phase28_require_command node
phase28_source_gnustep "$repo_root"

make -C "$repo_root" arlen phase28-reference-server >/dev/null
phase28_ensure_npm_deps "$repo_root/examples/phase28_react_reference" "vite"

port="$(phase28_pick_port)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

ARLEN_APP_ROOT=examples/phase28_reference "$repo_root/build/phase28-reference-server" \
  --host 127.0.0.1 \
  --port "$port" \
  >"$server_log" 2>&1 &
server_pid=$!

phase28_wait_for_server "$port"
curl -fsS "http://127.0.0.1:${port}/openapi.json" >"$live_openapi"
python3 "$repo_root/tools/ci/merge_phase28_openapi.py" \
  --live-openapi "$live_openapi" \
  --metadata-openapi "$repo_root/tests/fixtures/phase28/openapi_contract.json" \
  --merged-output "$merged_openapi" \
  --comparison-output "$comparison_path"

set +e
{
  cd "$repo_root/examples/phase28_react_reference"
  ARLEN_PHASE28_OPENAPI_INPUT="$merged_openapi" npm run generate:arlen
  ARLEN_PHASE28_BASE_URL="http://127.0.0.1:${port}" npm run typecheck
  ARLEN_PHASE28_BASE_URL="http://127.0.0.1:${port}" npm run build
} 2>&1 | tee "$log_path"
status=$?
set -e

find "$repo_root/examples/phase28_react_reference/dist" -type f 2>/dev/null | sort >"$dist_listing" || true

cat >"$manifest_path" <<EOF
{
  "status": "$([[ $status -eq 0 ]] && echo pass || echo fail)",
  "artifacts": [
    "phase28_react_reference.log",
    "phase28_reference_server.log",
    "live_openapi.json",
    "merged_openapi.json",
    "openapi_comparison.json",
    "react_reference_dist.txt"
  ]
}
EOF

exit "$status"
