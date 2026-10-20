#!/usr/bin/env bash
# Exercise the actual propane FD-probe functions with a deterministic lsof
# failure, including on Linux hosts where propane normally selects /proc.
set -euo pipefail
propane="$1"
fd_probe=lsof
eval "$(sed -n '/^is_uint() {/,/^}/p;/^worker_fd_count() {/,/^}/p;/^worker_fd_soft_limit() {/,/^}/p;/^worker_fd_targets() {/,/^}/p;/^worker_fd_top_targets() {/,/^}/p;/^remove_worker_pid() {/,/^}/p;/^check_worker_fd_pressure() {/,/^}/p;/^note_worker_exit() {/,/^}/p' "$propane")"

probe_mode=fail
lsof() {
  if [[ "$probe_mode" == fail ]]; then
    return 1
  fi
  case " $* " in
    *" -F n "*) printf 'p%s\nn/dev/null\n' "$$" ;;
    *) printf 'p%s\nf1\nf2\nf3\n' "$$" ;;
  esac
}

events=()
emit_lifecycle_event() { events+=("$*"); }
terminate_pid_list() { :; }
workers=("$$")
no_respawn=1
once_mode=0
shutting_down=0
respawn_delay_ms=50
respawn_backoff_max_ms=200
startup_failure_limit=3
startup_failure_give_up=0
http_startup_streak=0
http_startup_same=0
http_startup_last=""
worker_fd_warn_percent=0
worker_fd_critical_percent=0
worker_fd_retire_percent=0
worker_fd_retire_count=0

[[ "$(worker_fd_count "$$")" == -1 ]] || exit 1
check_worker_fd_pressure
[[ ${#events[@]} -eq 0 && ${#workers[@]} -eq 1 ]] || exit 1
for attempt in 1 2 3; do
  note_worker_exit http "module broken" "$respawn_delay_ms"
done
[[ "$startup_failure_give_up" -eq 1 ]] || exit 1
[[ "$http_startup_streak" -eq 3 ]] || exit 1
[[ "$next_respawn_delay_ms" -eq 200 ]] || exit 1
[[ ${#events[@]} -eq 3 ]] || exit 1
case "${events[2]}" in
  *"consecutive_failures=3"*"next_respawn_delay_ms=200"*) ;;
  *) exit 1 ;;
esac
echo 'unavailable sample preserved startup limit and backoff'

probe_mode=valid
events=()
workers=("$$")
worker_fd_retire_count=3
[[ "$(worker_fd_count "$$")" == 3 ]] || exit 1
expected_limit="$(ulimit -n)"
check_worker_fd_pressure
[[ ${#events[@]} -eq 1 ]] || exit 1
case "${events[0]}" in
  *"worker_fd_pressure_retire_requested"*"fd_count=3"*"fd_soft_limit=$expected_limit"*"top_fd_targets="*"_/dev/null"*) ;;
  *) exit 1 ;;
esac
echo 'valid sample preserved count, limit and retirement event'
