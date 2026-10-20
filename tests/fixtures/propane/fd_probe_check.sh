#!/usr/bin/env bash
# Issue 222: runs bin/propane's FD-pressure functions against a process holding
# 300 descriptors. Prints the count check and how often the per-target
# breakdown was built for a healthy worker and for one past the warn threshold.
#   tests/fixtures/propane/fd_probe_check.sh <path to bin/propane>
set -euo pipefail
propane="$1"
coproc HOLDER { ulimit -n 1024; exec python3 -c "import os,sys,time; fds=[os.open('/dev/null',os.O_RDONLY) for _ in range(300)]; print('ready', flush=True); time.sleep(30)"; }
holder=$HOLDER_PID
trap 'kill $holder 2>/dev/null || true' EXIT
read -r _ <&"${HOLDER[0]}"
fd_probe=proc
eval "$(sed -n '/^is_uint() {/,/^}/p;/^worker_fd_count() {/,/^}/p;/^worker_fd_soft_limit() {/,/^}/p;/^worker_fd_targets() {/,/^}/p;/^worker_fd_top_targets() {/,/^}/p;/^remove_worker_pid() {/,/^}/p;/^check_worker_fd_pressure() {/,/^}/p' "$propane")"
expected=$(ls /proc/$holder/fd | wc -l)
echo "count=$(worker_fd_count $holder) expected=$expected"
counter="$(mktemp)"
trap 'kill $holder 2>/dev/null || true; rm -f "$counter"' EXIT
eval "original_$(declare -f worker_fd_top_targets)"
worker_fd_top_targets() { echo x >> "$counter"; original_worker_fd_top_targets "$@"; }
events=()
emit_lifecycle_event() { events+=("$*"); }
terminate_pid_list() { :; }
workers=("$holder"); no_respawn=1; once_mode=0; shutting_down=0
worker_fd_warn_percent=0; worker_fd_critical_percent=0; worker_fd_retire_count=0; worker_fd_retire_percent=0
check_worker_fd_pressure
echo "healthy top_calls=$(wc -l < "$counter" | tr -d ' ') events=${#events[@]}"
worker_fd_retire_count=100000; worker_fd_warn_percent=1
check_worker_fd_pressure
echo "warn top_calls=$(wc -l < "$counter" | tr -d ' ') events=${#events[@]}"
case "${events[0]}" in *"top_fd_targets="*"_/dev/null"*) echo "targets ok";; *) echo "targets bad: ${events[0]}";; esac

# Simulate a worker exiting after the readability check but before awk opens
# /proc/<pid>/limits. Capture assignment exactly as the manager does under -e.
awk() { return 2; }
limit="$(worker_fd_soft_limit "$holder")"
[[ "$limit" == 0 ]]
events=()
check_worker_fd_pressure
[[ ${#events[@]} == 0 ]]
echo "unavailable limits sample preserved manager loop"
unset -f awk
