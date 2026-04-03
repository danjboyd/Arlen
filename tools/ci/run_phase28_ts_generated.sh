#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE28_TS_GENERATED_OUTPUT_DIR:-$repo_root/build/release_confidence/phase28/generated}"
log_path="$output_dir/phase28_ts_generated.log"
metrics_path="$output_dir/generated_metrics.json"
manifest_path="$output_dir/manifest.json"

mkdir -p "$output_dir"

source "$repo_root/tools/ci/phase28_common.sh"
phase28_require_command npm
phase28_require_command node
phase28_source_gnustep "$repo_root"

make -C "$repo_root" arlen >/dev/null
phase28_ensure_npm_deps "$repo_root/tests/typescript" "tsc"

start_ms="$(phase28_now_ms)"
set +e
{
  cd "$repo_root/tests/typescript"
  npm run generate:arlen
  npm run test:generated
} 2>&1 | tee "$log_path"
status=$?
set -e
end_ms="$(phase28_now_ms)"

package_dir="$repo_root/tests/typescript/generated/arlen"
manifest_file="$repo_root/tests/typescript/generated/arlen.manifest.json"
cat >"$metrics_path" <<EOF
{
  "codegen_duration_ms": $((end_ms - start_ms)),
  "manifest_bytes": $(phase28_file_size_bytes "$manifest_file"),
  "package_bytes": $(phase28_directory_size_bytes "$package_dir"),
  "client_bytes": $(phase28_file_size_bytes "$package_dir/src/client.ts"),
  "react_bytes": $(phase28_file_size_bytes "$package_dir/src/react.ts")
}
EOF

cat >"$manifest_path" <<EOF
{
  "status": "$([[ $status -eq 0 ]] && echo pass || echo fail)",
  "artifacts": [
    "phase28_ts_generated.log",
    "generated_metrics.json"
  ]
}
EOF

exit "$status"
