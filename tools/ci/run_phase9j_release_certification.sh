#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

phase9j_output_dir="${ARLEN_PHASE9J_OUTPUT_DIR:-$repo_root/build/release_confidence/phase9j}"
phase9j_release_id="${ARLEN_PHASE9J_RELEASE_ID:-rc-$(date -u +%Y%m%dT%H%M%SZ)}"
phase9j_skip_gates="${ARLEN_PHASE9J_SKIP_GATES:-0}"
phase9j_allow_incomplete="${ARLEN_PHASE9J_ALLOW_INCOMPLETE:-0}"

if [[ "$phase9j_skip_gates" != "1" ]]; then
  bash ./tools/ci/run_phase5e_quality.sh
  bash ./tools/ci/run_phase5e_sanitizers.sh
  bash ./tools/deploy/smoke_release.sh \
    --app-root "$repo_root/examples/tech_demo" \
    --framework-root "$repo_root" \
    --release-a phase9j-smoke-a \
    --release-b phase9j-smoke-b
  bash ./tools/build_docs_html.sh
fi

generator_args=(
  "--repo-root" "$repo_root"
  "--output-dir" "$phase9j_output_dir"
  "--release-id" "$phase9j_release_id"
)
if [[ "$phase9j_allow_incomplete" == "1" ]]; then
  generator_args+=("--allow-incomplete")
fi

python3 ./tools/ci/generate_phase9j_release_certification_pack.py "${generator_args[@]}"

echo "ci: phase9j release certification complete"
