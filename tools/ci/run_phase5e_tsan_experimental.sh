#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

artifact_dir="${ARLEN_TSAN_ARTIFACT_DIR:-$repo_root/build/sanitizers/tsan}"
mkdir -p "$artifact_dir"
log_path="$artifact_dir/tsan.log"
summary_path="$artifact_dir/summary.json"
rm -f "$log_path"
touch "$log_path"

write_summary() {
  local status="$1"
  local exit_code="$2"
  local reason="${3:-}"
  python3 - "$summary_path" "$status" "$exit_code" "$reason" "$log_path" <<'PY'
import json
import sys
from datetime import datetime, timezone

summary_path, status, exit_code, reason, log_path = sys.argv[1:]
payload = {
    "version": "phase9h-tsan-run-v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": status,
    "exit_code": int(exit_code),
    "reason": reason,
    "log_path": log_path,
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

export GNUSTEP_USER_ROOT="${GNUSTEP_USER_ROOT:-$repo_root/.gnustep}"
mkdir -p "$GNUSTEP_USER_ROOT"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

tsan_so="$(clang -print-file-name=libtsan.so)"
if [[ -z "$tsan_so" || ! -f "$tsan_so" ]]; then
  echo "ci: tsan experimental skipped (libtsan.so unavailable)" | tee -a "$log_path"
  write_summary "skipped" "0" "libtsan_unavailable"
  exit 0
fi

export EXTRA_OBJC_FLAGS="${EXTRA_OBJC_FLAGS:--fsanitize=thread -fno-omit-frame-pointer}"
export TSAN_OPTIONS="${TSAN_OPTIONS:-halt_on_error=1:history_size=7}"
export XCTEST_LD_PRELOAD="$tsan_so"

set +e
{
  echo "ci: tsan log path $log_path"
  echo "ci: tsan iterations ${ARLEN_TSAN_RUNTIME_ITERS:-1}"
  make boomhauer
  make test-unit
  python3 ./tools/ci/runtime_concurrency_probe.py \
    --binary ./build/boomhauer \
    --iterations "${ARLEN_TSAN_RUNTIME_ITERS:-1}"
} 2>&1 | tee -a "$log_path"
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
