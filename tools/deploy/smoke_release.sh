#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: smoke_release.sh [options]

Validate release build/activate/propane-operability/reload/rollback runbook end-to-end.

Options:
  --app-root <path>        App root to package (default: cwd)
  --framework-root <path>  Framework root (default: script ../..)
  --work-dir <path>        Working directory for temporary release artifacts
  --port <n>               Base probe port (default: 3901)
  --release-a <id>         First release id (default: smoke-a)
  --release-b <id>         Second release id (default: smoke-b)
  --help                   Show this help
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
framework_root="$(cd "$script_dir/../.." && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_release_pointer.sh"
app_root="$PWD"
work_dir=""
port=3901
release_a="smoke-a"
release_b="smoke-b"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      [[ $# -ge 2 ]] || { echo "smoke_release.sh: --app-root requires a value" >&2; exit 2; }
      app_root="$2"
      shift 2
      ;;
    --framework-root)
      [[ $# -ge 2 ]] || { echo "smoke_release.sh: --framework-root requires a value" >&2; exit 2; }
      framework_root="$2"
      shift 2
      ;;
    --work-dir)
      [[ $# -ge 2 ]] || { echo "smoke_release.sh: --work-dir requires a value" >&2; exit 2; }
      work_dir="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || { echo "smoke_release.sh: --port requires a value" >&2; exit 2; }
      port="$2"
      shift 2
      ;;
    --release-a)
      [[ $# -ge 2 ]] || { echo "smoke_release.sh: --release-a requires a value" >&2; exit 2; }
      release_a="$2"
      shift 2
      ;;
    --release-b)
      [[ $# -ge 2 ]] || { echo "smoke_release.sh: --release-b requires a value" >&2; exit 2; }
      release_b="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "smoke_release.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

app_root="$(cd "$app_root" && pwd)"
framework_root="$(cd "$framework_root" && pwd)"
if [[ -z "$work_dir" ]]; then
  work_dir="$(mktemp -d)"
  own_work_dir=1
else
  mkdir -p "$work_dir"
  own_work_dir=0
fi
work_dir="$(cd "$work_dir" && pwd)"
releases_dir="$work_dir/releases"

cleanup() {
  if [[ "${own_work_dir}" == "1" ]]; then
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT

terminate_server_pid() {
  local server_pid="$1"
  local control_file="${2:-}"
  local probe_port="${3:-}"
  if [[ -z "$server_pid" ]]; then
    return 0
  fi

  if [[ -n "$control_file" ]]; then
    mkdir -p "$(dirname "$control_file")"
    printf 'term\n' >"$control_file" 2>/dev/null || true
    for _ in $(seq 1 40); do
      if ! kill -0 "$server_pid" >/dev/null 2>&1; then
        return 0
      fi
      sleep 0.1
    done
  fi

  if arlen_deploy_is_windows_host; then
    if [[ -n "$probe_port" ]]; then
      ARLEN_DEPLOY_PROBE_PORT="$probe_port" \
        powershell -NoProfile -Command \
          '$port = [int]$env:ARLEN_DEPLOY_PROBE_PORT; Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }' \
        >/dev/null 2>&1 || true
    fi
    cmd.exe /d /c "taskkill /PID $server_pid /T /F >NUL 2>NUL" >/dev/null 2>&1 || true
    return 0
  fi

  kill -TERM "$server_pid" >/dev/null 2>&1 || true
}

request_release_control() {
  local control_file="$1"
  local action="$2"
  mkdir -p "$(dirname "$control_file")"
  printf '%s\n' "$action" >"$control_file"
}

wait_for_release_health() {
  local probe_port="$1"
  for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:${probe_port}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_release_control_consumption() {
  local control_file="$1"
  for _ in $(seq 1 50); do
    if [[ ! -e "$control_file" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

run_release_health_check() {
  local release_dir="$1"
  local probe_port="$2"
  local server_log="$3"
  local pid_file="$release_dir/app/tmp/propane.pid"
  local control_file="$release_dir/app/tmp/propane.control"

  mkdir -p "$release_dir/app/tmp"
  rm -f "$pid_file" "$control_file"

  ARLEN_APP_ROOT="$release_dir/app" \
    ARLEN_FRAMEWORK_ROOT="$release_dir/framework" \
    ARLEN_PROPANE_CONTROL_FILE="$control_file" \
    "$release_dir/framework/bin/propane" --env production --port "$probe_port" --pid-file "$pid_file" >"$server_log" 2>&1 &
  local server_pid=$!

  if ! wait_for_release_health "$probe_port"; then
    terminate_server_pid "$server_pid" "$control_file" "$probe_port"
    wait "$server_pid" || true
    echo "smoke_release.sh: health probe failed for $release_dir"
    echo "smoke_release.sh: server log follows"
    cat "$server_log"
    return 1
  fi

  if ! "$framework_root/tools/deploy/validate_operability.sh" \
      --base-url "http://127.0.0.1:${probe_port}" >/dev/null; then
    terminate_server_pid "$server_pid" "$control_file" "$probe_port"
    wait "$server_pid" || true
    echo "smoke_release.sh: operability validation failed for $release_dir"
    echo "smoke_release.sh: server log follows"
    cat "$server_log"
    return 1
  fi

  request_release_control "$control_file" "reload"
  wait_for_release_control_consumption "$control_file" || true
  if ! wait_for_release_health "$probe_port"; then
    terminate_server_pid "$server_pid" "$control_file" "$probe_port"
    wait "$server_pid" || true
    echo "smoke_release.sh: reload probe failed for $release_dir"
    echo "smoke_release.sh: server log follows"
    cat "$server_log"
    return 1
  fi

  terminate_server_pid "$server_pid" "$control_file" "$probe_port"
  wait "$server_pid" || true
  return 0
}

"$framework_root/tools/deploy/build_release.sh" \
  --app-root "$app_root" \
  --framework-root "$framework_root" \
  --releases-dir "$releases_dir" \
  --release-id "$release_a" \
  --allow-missing-certification >/dev/null

"$framework_root/tools/deploy/build_release.sh" \
  --app-root "$app_root" \
  --framework-root "$framework_root" \
  --releases-dir "$releases_dir" \
  --release-id "$release_b" \
  --allow-missing-certification >/dev/null

"$framework_root/tools/deploy/activate_release.sh" \
  --releases-dir "$releases_dir" \
  --release-id "$release_b" >/dev/null

current_release="$(arlen_deploy_resolved_release_path "$releases_dir" "$releases_dir/current")"
if [[ ! -f "$current_release/metadata/release.env" ]]; then
  echo "smoke_release.sh: missing release metadata in active release"
  exit 1
fi
run_release_health_check "$current_release" "$port" "$work_dir/server_${release_b}.log"

"$framework_root/tools/deploy/rollback_release.sh" \
  --releases-dir "$releases_dir" \
  --release-id "$release_a" >/dev/null

current_release="$(arlen_deploy_resolved_release_path "$releases_dir" "$releases_dir/current")"
if [[ "$current_release" != "$releases_dir/$release_a" ]]; then
  echo "smoke_release.sh: rollback failed to activate $release_a"
  exit 1
fi
run_release_health_check "$current_release" "$((port + 1))" "$work_dir/server_${release_a}.log"

echo "release smoke passed: releases_dir=$releases_dir active=$current_release"
