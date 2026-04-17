#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE35_OUTPUT_DIR:-$repo_root/build/release_confidence/phase35}"

mkdir -p "$output_dir"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" build-tests >"$output_dir/build-tests.log" 2>&1
make -C "$repo_root" test-unit-filter TEST=MiddlewareTests >"$output_dir/middleware-tests.log" 2>&1
make -C "$repo_root" test-unit-filter TEST=RouterTests >"$output_dir/router-tests.log" 2>&1
make -C "$repo_root" test-unit-filter TEST=Phase16FTests >"$output_dir/admin-ui-policy-tests.log" 2>&1

cat >"$output_dir/manifest.json" <<EOF
{
  "version": "phase35-confidence-v1",
  "status": "pass",
  "artifacts": [
    "build-tests.log",
    "middleware-tests.log",
    "router-tests.log",
    "admin-ui-policy-tests.log"
  ],
  "coverage": [
    "route policy config validation",
    "IPv4 and IPv6 source IP allowlist decisions",
    "trusted proxy Forwarded and X-Forwarded-For handling",
    "spoofed and malformed forwarded-header regressions",
    "route-side policy metadata",
    "admin-ui policy attachment"
  ]
}
EOF

echo "ci: phase35 confidence gate complete"
