#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE28_TS_UNIT_OUTPUT_DIR:-$repo_root/build/release_confidence/phase28/ts_unit}"
log_path="$output_dir/phase28_ts_unit.log"
manifest_path="$output_dir/manifest.json"

mkdir -p "$output_dir"

source "$repo_root/tools/ci/phase28_common.sh"
phase28_require_command npm
phase28_require_command node
phase28_source_gnustep "$repo_root"

make -C "$repo_root" arlen >/dev/null
phase28_ensure_npm_deps "$repo_root/tests/typescript" "tsx"

set +e
{
  cd "$repo_root/tests/typescript"
  npm run generate:arlen
  npm run test:unit
} 2>&1 | tee "$log_path"
status=$?
set -e

cat >"$manifest_path" <<EOF
{
  "status": "$([[ $status -eq 0 ]] && echo pass || echo fail)",
  "artifacts": [
    "phase28_ts_unit.log"
  ]
}
EOF

exit "$status"
