#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE21_OUTPUT_DIR:-$repo_root/build/release_confidence/phase21}"
template_log="$output_dir/phase21_template_tests.log"
protocol_output_dir="$output_dir/protocol"
generated_apps_output_dir="$output_dir/generated_apps"

mkdir -p "$output_dir"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

make -C "$repo_root" phase21-template-tests 2>&1 | tee "$template_log"
ARLEN_PHASE21_PROTOCOL_OUTPUT_DIR="$protocol_output_dir" bash "$repo_root/tools/ci/run_phase21_protocol_corpus.sh"
ARLEN_PHASE21_MATRIX_OUTPUT_DIR="$generated_apps_output_dir" bash "$repo_root/tools/ci/run_phase21_generated_app_matrix.sh"

python3 "$repo_root/tools/ci/generate_phase21_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --template-log "$template_log" \
  --protocol-manifest "$protocol_output_dir/manifest.json" \
  --generated-app-manifest "$generated_apps_output_dir/manifest.json"

echo "ci: phase21 confidence gate complete"
