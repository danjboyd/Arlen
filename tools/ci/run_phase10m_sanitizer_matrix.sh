#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE10M_SANITIZER_OUTPUT_DIR:-$repo_root/build/release_confidence/phase10m/sanitizers}"
include_thread_nightly="${ARLEN_PHASE10M_INCLUDE_THREAD_NIGHTLY:-0}"
allow_fail="${ARLEN_PHASE10M_SANITIZER_ALLOW_FAIL:-0}"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

asan_so="$(clang -print-file-name=libasan.so)"
ubsan_so="$(clang -print-file-name=libubsan.so)"
if [[ -z "$asan_so" || ! -f "$asan_so" ]]; then
  echo "phase10m sanitizer matrix: unable to locate libasan.so"
  exit 1
fi
if [[ -z "$ubsan_so" || ! -f "$ubsan_so" ]]; then
  echo "phase10m sanitizer matrix: unable to locate libubsan.so"
  exit 1
fi

export EXTRA_OBJC_FLAGS="${EXTRA_OBJC_FLAGS:--fsanitize=address,undefined -fno-omit-frame-pointer}"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1:strict_string_checks=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"
export XCTEST_LD_PRELOAD="$asan_so:$ubsan_so"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
lane_tsv="$tmp_dir/lane_results.tsv"
: > "$lane_tsv"

record_lane() {
  local lane_id="$1"
  local blocking="$2"
  local status="$3"
  local rc="$4"
  local evidence="$5"
  printf '%s|%s|%s|%s|%s\n' "$lane_id" "$blocking" "$status" "$rc" "$evidence" >> "$lane_tsv"
}

run_lane() {
  local lane_id="$1"
  local blocking="$2"
  local evidence="$3"
  shift 3
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    record_lane "$lane_id" "$blocking" "pass" "0" "$evidence"
  else
    record_lane "$lane_id" "$blocking" "fail" "$rc" "$evidence"
  fi
  return 0
}

python3 ./tools/ci/check_sanitizer_suppressions.py

run_lane \
  "asan_ubsan_unit" \
  "true" \
  "make test-unit" \
  make test-unit

run_lane \
  "asan_ubsan_runtime_probe" \
  "true" \
  "runtime_concurrency_probe" \
  bash -lc "make boomhauer && python3 ./tools/ci/runtime_concurrency_probe.py --binary ./build/boomhauer --iterations \"${ARLEN_SANITIZER_RUNTIME_ITERS:-1}\""

run_lane \
  "asan_ubsan_backend_parity" \
  "true" \
  "run_phase10m_backend_parity_matrix.sh" \
  bash ./tools/ci/run_phase10m_backend_parity_matrix.sh

run_lane \
  "asan_ubsan_protocol_adversarial" \
  "true" \
  "run_phase10m_protocol_adversarial.sh" \
  bash ./tools/ci/run_phase10m_protocol_adversarial.sh

run_lane \
  "asan_ubsan_syscall_fault_injection" \
  "true" \
  "run_phase10m_syscall_fault_injection.sh" \
  bash ./tools/ci/run_phase10m_syscall_fault_injection.sh

run_lane \
  "asan_ubsan_allocation_fault_injection" \
  "true" \
  "run_phase10m_allocation_fault_injection.sh" \
  bash ./tools/ci/run_phase10m_allocation_fault_injection.sh

run_lane \
  "asan_ubsan_long_run_soak" \
  "true" \
  "run_phase10m_soak.sh" \
  bash ./tools/ci/run_phase10m_soak.sh

run_lane \
  "asan_ubsan_chaos_restart" \
  "true" \
  "run_phase10m_chaos_restart.sh" \
  bash ./tools/ci/run_phase10m_chaos_restart.sh

run_lane \
  "asan_ubsan_static_analysis" \
  "true" \
  "run_phase10m_static_analysis.sh" \
  bash ./tools/ci/run_phase10m_static_analysis.sh

if [[ "$include_thread_nightly" == "1" ]]; then
  run_lane \
    "thread_race_nightly" \
    "false" \
    "run_phase10m_thread_race_nightly.sh" \
    bash ./tools/ci/run_phase10m_thread_race_nightly.sh
else
  record_lane "thread_race_nightly" "false" "skipped" "0" "not_requested"
fi

lane_json="$tmp_dir/lane_results.json"
python3 - "$lane_tsv" "$lane_json" <<'PY'
import json
import sys
from datetime import datetime, timezone

source_path, output_path = sys.argv[1:]
rows = []
with open(source_path, 'r', encoding='utf-8') as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        lane_id, blocking, status, rc, evidence = line.split('|', 4)
        rows.append({
            'id': lane_id,
            'blocking': blocking == 'true',
            'status': status,
            'return_code': int(rc),
            'evidence': evidence,
        })
payload = {
    'version': 'phase10m-sanitizer-matrix-v1',
    'generated_at': datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
    'lane_results': rows,
}
with open(output_path, 'w', encoding='utf-8') as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write('\n')
PY

generator_args=(
  --repo-root "$repo_root"
  --lane-results "$lane_json"
  --output-dir "$output_dir"
)
if [[ "$allow_fail" == "1" ]]; then
  generator_args+=(--allow-fail)
fi

python3 ./tools/ci/generate_phase10m_sanitizer_matrix_artifacts.py "${generator_args[@]}"

echo "ci: phase10m sanitizer matrix gate complete"
