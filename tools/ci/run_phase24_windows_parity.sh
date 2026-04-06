#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/_gnustep_env.sh"
. "$SCRIPT_DIR/_phase24_windows_env.sh"
arlen_ci_source_gnustep
arlen_phase24_windows_configure_defaults
arlen_phase24_windows_validate_env

: "${ARLEN_PHASE10M_INCLUDE_THREAD_NIGHTLY:=0}"
: "${ARLEN_PHASE11_INCLUDE_THREAD:=0}"
: "${ARLEN_PERF_RETRY_COUNT:=3}"

export ARLEN_PHASE10M_INCLUDE_THREAD_NIGHTLY
export ARLEN_PHASE11_INCLUDE_THREAD
export ARLEN_PERF_RETRY_COUNT

make -C "$REPO_ROOT" all
make -C "$REPO_ROOT" test-unit
make -C "$REPO_ROOT" test-integration
make -C "$REPO_ROOT" phase20-postgres-live-tests
make -C "$REPO_ROOT" phase20-mssql-live-tests

bash "$REPO_ROOT/tools/ci/run_phase10e_json_performance.sh"
bash "$REPO_ROOT/tools/ci/run_phase10g_dispatch_performance.sh"
bash "$REPO_ROOT/tools/ci/run_phase10h_http_parse_performance.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_blob_throughput.sh"
bash "$REPO_ROOT/tools/ci/run_phase9i_fault_injection.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_backend_parity_matrix.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_protocol_adversarial.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_syscall_fault_injection.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_allocation_fault_injection.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_soak.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_chaos_restart.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_static_analysis.sh"
bash "$REPO_ROOT/tools/ci/run_phase10m_sanitizer_matrix.sh"
bash "$REPO_ROOT/tools/ci/run_phase11_confidence.sh"
