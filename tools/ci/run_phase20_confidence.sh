#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE20_OUTPUT_DIR:-$repo_root/build/release_confidence/phase20}"
dsn="${ARLEN_PHASE20_DSN:-${ARLEN_PG_TEST_DSN:-}}"

rm -rf "$output_dir"
mkdir -p "$output_dir"

args=(
  python3
  "$repo_root/tools/ci/generate_phase20_confidence_artifacts.py"
  --repo-root "$repo_root"
  --output-dir "$output_dir"
)

if [[ -n "$dsn" ]]; then
  args+=(--dsn "$dsn")
fi

"${args[@]}"
