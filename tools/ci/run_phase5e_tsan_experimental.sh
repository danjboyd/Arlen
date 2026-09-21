#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

artifact_dir="${ARLEN_TSAN_ARTIFACT_DIR:-$repo_root/build/sanitizers/tsan}"
log_path="$artifact_dir/tsan.log"
summary_path="$artifact_dir/summary.json"
staging_dir="$(mktemp -d)"
staged_log_path="$staging_dir/tsan.log"
staged_summary_path="$staging_dir/summary.json"
bootstrap_dir="$staging_dir/bootstrap"
bootstrap_eocc="$bootstrap_dir/eocc"

finalize_artifacts() {
  mkdir -p "$artifact_dir"
  if [[ -f "$staged_log_path" ]]; then
    cp "$staged_log_path" "$log_path"
  fi
  if [[ -f "$staged_summary_path" ]]; then
    cp "$staged_summary_path" "$summary_path"
  fi
}

cleanup() {
  finalize_artifacts
  rm -rf "$staging_dir"
}

trap cleanup EXIT

rm -f "$staged_log_path"
touch "$staged_log_path"

write_summary() {
  local status="$1"
  local exit_code="$2"
  local reason="${3:-}"
  python3 - "$staged_summary_path" "$status" "$exit_code" "$reason" "$log_path" <<'PY'
import json
import sys
import re
from pathlib import Path
from datetime import datetime, timezone

summary_path, status, exit_code, reason, log_path = sys.argv[1:]
started = warnings = assertion_failures = 0
runtime_probe_completed = False
with Path(summary_path).with_name("tsan.log").open(errors="replace") as log:
    for line in log:
        started += len(re.findall(r"XCTest:\s+(test\w+)\.\.\.", line))
        warnings += line.count("WARNING: ThreadSanitizer")
        assertion_failures += line.count("Assertion FAILED")
        runtime_probe_completed |= "ci: tsan runtime probe complete" in line
payload = {
    "version": "phase9h-tsan-run-v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": status,
    "exit_code": int(exit_code),
    "reason": reason,
    "log_path": log_path,
    "unit_methods_started": started,
    "sanitizer_warnings": warnings,
    "unit_assertion_failures": assertion_failures,
    "tsan_excluded_tests": [],
    "runtime_probe_completed": runtime_probe_completed,
    "coverage_note": "Method starts are reported; other service-dependent opt-in tests may return early.",
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
mkdir -p "$bootstrap_dir"
if [[ -f "$repo_root/tools/source_gnustep_env.sh" ]]; then
  set +u
  source "$repo_root/tools/source_gnustep_env.sh"
  set -u
fi

tsan_so="$(clang -print-file-name=libtsan.so)"
if [[ -z "$tsan_so" || ! -f "$tsan_so" ]]; then
  echo "ci: tsan experimental unavailable (libtsan.so missing)" | tee -a "$staged_log_path"
  write_summary "unavailable" "77" "libtsan_unavailable"
  exit 77
fi

tsan_objc_flags="${EXTRA_OBJC_FLAGS:--fsanitize=thread -fno-omit-frame-pointer}"
tsan_suppressions_file="${ARLEN_TSAN_SUPPRESSIONS_FILE:-$repo_root/tests/fixtures/sanitizers/phase9h_tsan.supp}"
tsan_options="${TSAN_OPTIONS:-halt_on_error=1:history_size=7:second_deadlock_stack=1}"
using_default_tsan_suppressions=0
if [[ -n "$tsan_suppressions_file" && -f "$tsan_suppressions_file" && "$tsan_options" != *"suppressions="* ]]; then
  tsan_options="${tsan_options}:suppressions=$tsan_suppressions_file"
  using_default_tsan_suppressions=1
fi
export TSAN_OPTIONS="$tsan_options"
export XCTEST_LD_PRELOAD="$tsan_so"

set +e
{
  echo "ci: tsan log path $log_path"
  echo "ci: tsan bootstrap eocc $bootstrap_eocc"
  if [[ "$using_default_tsan_suppressions" -eq 1 ]]; then
    echo "ci: tsan suppressions $tsan_suppressions_file"
  fi
  echo "ci: tsan iterations ${ARLEN_TSAN_RUNTIME_ITERS:-1}"
  make clean || exit $?
  make EXTRA_OBJC_FLAGS= EOC_TOOL="$bootstrap_eocc" eocc transpile module-transpile || exit $?
  make EXTRA_OBJC_FLAGS="$tsan_objc_flags" EOC_TOOL="$bootstrap_eocc" -o "$bootstrap_eocc" boomhauer arlen || exit $?
  make EXTRA_OBJC_FLAGS="$tsan_objc_flags" EOC_TOOL="$bootstrap_eocc" -o "$bootstrap_eocc" test-unit || exit $?
  python3 ./tools/ci/runtime_concurrency_probe.py \
    --binary ./build/boomhauer \
    --iterations "${ARLEN_TSAN_RUNTIME_ITERS:-1}" || exit $?
  echo "ci: tsan runtime probe complete"
} 2>&1 | tee -a "$staged_log_path"
tsan_rc=${PIPESTATUS[0]}
set -e

if [[ "$tsan_rc" -eq 0 ]]; then
  write_summary "pass" "0"
  echo "ci: phase5e tsan experimental run complete"
  exit 0
fi

write_summary "fail" "$tsan_rc" "tsan_lane_failure"
echo "ci: phase5e tsan experimental run failed"
exit "$tsan_rc"
