#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

artifact_dir="${ARLEN_PHASE10M_THREAD_ARTIFACT_DIR:-$repo_root/build/sanitizers/phase10m_thread_race}"
mkdir -p "$artifact_dir"
summary_path="$artifact_dir/summary.json"
log_path="$artifact_dir/thread_race.log"
staging_dir="$(mktemp -d)"
staged_summary_path="$staging_dir/summary.json"
staged_log_path="$staging_dir/thread_race.log"

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
  local engine="$2"
  local exit_code="$3"
  local reason="$4"
  python3 - "$staged_summary_path" "$status" "$engine" "$exit_code" "$reason" "$log_path" <<'PY'
import json
import sys
from datetime import datetime, timezone

summary_path, status, engine, exit_code, reason, log_path = sys.argv[1:]
payload = {
    "version": "phase10m-thread-race-nightly-v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": status,
    "engine": engine,
    "exit_code": int(exit_code),
    "reason": reason,
    "log_path": log_path,
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

if [[ -f "$repo_root/tools/source_gnustep_env.sh" ]]; then
  set +u
  source "$repo_root/tools/source_gnustep_env.sh"
  set -u
fi
make boomhauer

tsan_so="$(clang -print-file-name=libtsan.so)"
if [[ -n "$tsan_so" && -f "$tsan_so" ]]; then
  {
    echo "phase10m-thread-race: engine=tsan"
  } | tee -a "$staged_log_path"
  if ARLEN_TSAN_ARTIFACT_DIR="$artifact_dir/tsan" bash ./tools/ci/run_phase5e_tsan_experimental.sh >>"$staged_log_path" 2>&1; then
    write_summary "pass" "tsan" "0" ""
    echo "ci: phase10m thread-race nightly complete (tsan)" | tee -a "$staged_log_path"
    exit 0
  else
    rc=$?
    write_summary "fail" "tsan" "$rc" "tsan_lane_failure"
    echo "ci: phase10m thread-race nightly failed (tsan)" | tee -a "$staged_log_path"
    exit "$rc"
  fi
fi

if command -v valgrind >/dev/null 2>&1; then
  engine="helgrind"
  port="${ARLEN_PHASE10M_HELGRIND_PORT:-39127}"
  {
    echo "phase10m-thread-race: engine=helgrind"
  } | tee -a "$staged_log_path"
  set +e
  valgrind --tool=helgrind --error-exitcode=66 ./build/boomhauer --port "$port" --once >"$artifact_dir/helgrind.out" 2>"$artifact_dir/helgrind.err" &
  server_pid=$!
  curl_rc=1
  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
      curl_rc=0
      break
    fi
    sleep 0.1
  done
  wait "$server_pid"
  server_rc=$?
  set -e
  if [[ "$curl_rc" -eq 0 && "$server_rc" -eq 0 ]]; then
    write_summary "pass" "$engine" "0" ""
    echo "ci: phase10m thread-race nightly complete (helgrind)" | tee -a "$staged_log_path"
    exit 0
  fi
  rc="$server_rc"
  if [[ "$rc" -eq 0 ]]; then
    rc="$curl_rc"
  fi
  write_summary "fail" "$engine" "$rc" "helgrind_lane_failure"
  echo "ci: phase10m thread-race nightly failed (helgrind)" | tee -a "$staged_log_path"
  exit "$rc"
fi

write_summary "skipped" "none" "0" "no_tsan_or_valgrind"
echo "ci: phase10m thread-race nightly skipped (no tsan/helgrind)" | tee -a "$staged_log_path"
