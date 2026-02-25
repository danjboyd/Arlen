#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

phase9h_output_dir="${ARLEN_PHASE9H_OUTPUT_DIR:-$repo_root/build/release_confidence/phase9h}"
export ARLEN_SANITIZER_INCLUDE_INTEGRATION="${ARLEN_SANITIZER_INCLUDE_INTEGRATION:-0}"

python3 ./tools/ci/check_sanitizer_suppressions.py

blocking_status="pass"
set +e
bash ./tools/ci/run_phase4_sanitizers.sh
blocking_rc=$?
set -e
if [[ "$blocking_rc" -ne 0 ]]; then
  blocking_status="fail"
fi

tsan_status="skipped"
if [[ "${ARLEN_SANITIZER_INCLUDE_TSAN:-0}" == "1" ]]; then
  if bash ./tools/ci/run_phase5e_tsan_experimental.sh; then
    tsan_status="pass"
  else
    tsan_status="fail"
    echo "ci: tsan experimental run failed (non-blocking)"
  fi
fi

python3 ./tools/ci/generate_phase9h_sanitizer_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$phase9h_output_dir" \
  --blocking-status "$blocking_status" \
  --tsan-status "$tsan_status"

if [[ "$blocking_rc" -ne 0 ]]; then
  echo "ci: phase5e sanitizer gate failed (blocking sanitizer lane)"
  exit "$blocking_rc"
fi

echo "ci: phase5e sanitizer gate complete"
