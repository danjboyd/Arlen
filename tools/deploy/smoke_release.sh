#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: smoke_release.sh [options]

Validate release build/activate/health-readiness operability/rollback runbook end-to-end.

Options:
  --app-root <path>        App root to package (default: cwd)
  --framework-root <path>  Framework root (default: script ../..)
  --work-dir <path>        Working directory for temporary release artifacts
  --port <n>               Base probe port (default: 3901)
  --release-a <id>         First release id (default: smoke-a)
  --release-b <id>         Second release id (default: smoke-b)
  --json                   Emit machine-readable result payload
  --help                   Show this help
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
framework_root="$(cd "$script_dir/../.." && pwd)"
app_root="$PWD"
work_dir=""
port=3901
release_a="smoke-a"
release_b="smoke-b"
output_json=0

json_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

emit_json() {
  local status="$1"
  local current_release="$2"
  local server_log_a="$3"
  local server_log_b="$4"
  local smoke_output="$5"
  printf '{'
  printf '"workflow":"deploy.smoke_release",'
  printf '"status":"%s",' "$(json_escape "$status")"
  printf '"framework_root":"%s",' "$(json_escape "$framework_root")"
  printf '"app_root":"%s",' "$(json_escape "$app_root")"
  printf '"releases_dir":"%s",' "$(json_escape "$releases_dir")"
  printf '"release_a":"%s",' "$(json_escape "$release_a")"
  printf '"release_b":"%s",' "$(json_escape "$release_b")"
  printf '"current_release":"%s",' "$(json_escape "$current_release")"
  printf '"server_log_release_b":"%s",' "$(json_escape "$server_log_b")"
  printf '"server_log_release_a":"%s",' "$(json_escape "$server_log_a")"
  printf '"smoke_output":"%s"' "$(json_escape "$smoke_output")"
  printf '}\n'
}

resolve_directory_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (
      cd "$path"
      pwd -P
    )
    return 0
  fi
  return 1
}

resolve_operability_helper() {
  local release_dir="$1"
  local manifest_path="$release_dir/metadata/manifest.json"
  local helper_path=""
  if [[ -f "$manifest_path" ]] && command -v python3 >/dev/null 2>&1; then
    helper_path="$(python3 - "$manifest_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
helper = ""
if isinstance(payload, dict):
    paths = payload.get("paths")
    if isinstance(paths, dict):
        value = paths.get("operability_probe_helper")
        if isinstance(value, str):
            helper = value
print(helper)
PY
)"
    if [[ -n "$helper_path" ]]; then
      if [[ "$helper_path" = /* ]] || [[ "$helper_path" =~ ^[A-Za-z]:[\\/] ]] || [[ "$helper_path" =~ ^\\\\ ]]; then
        printf '%s\n' "$helper_path"
      else
        printf '%s\n' "$release_dir/$helper_path"
      fi
      return 0
    fi
  fi
  printf '%s\n' "$release_dir/framework/tools/deploy/validate_operability.sh"
}

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
    --json)
      output_json=1
      shift
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

run_release_health_check() {
  local release_dir="$1"
  local probe_port="$2"
  local server_log="$3"
  local helper_path="$4"

  ARLEN_APP_ROOT="$release_dir/app" \
    ARLEN_FRAMEWORK_ROOT="$release_dir/framework" \
    "$release_dir/framework/bin/propane" --port "$probe_port" --pid-file "$release_dir/app/tmp/propane-smoke.pid" \
    >"$server_log" 2>&1 &
  local server_pid=$!

  local success=0
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${probe_port}/healthz" >/dev/null 2>&1; then
      success=1
      break
    fi
    sleep 0.05
  done

  if [[ "$success" != "1" ]]; then
    kill -TERM "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" || true
    local message="health probe failed for $release_dir"
    if [[ "$output_json" == "1" ]]; then
      emit_json "error" "$release_dir" "" "" "$message"
    else
      echo "smoke_release.sh: $message"
      echo "smoke_release.sh: server log follows"
      cat "$server_log"
    fi
    return 1
  fi

  if ! "$helper_path" \
      --base-url "http://127.0.0.1:${probe_port}" >/dev/null; then
    kill -TERM "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" || true
    local message="operability validation failed for $release_dir"
    if [[ "$output_json" == "1" ]]; then
      emit_json "error" "$release_dir" "" "" "$message"
    else
      echo "smoke_release.sh: $message"
      echo "smoke_release.sh: server log follows"
      cat "$server_log"
    fi
    return 1
  fi

  kill -TERM "$server_pid" >/dev/null 2>&1 || true
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

current_release="$(readlink -f "$releases_dir/current")"
if [[ -z "$current_release" ]]; then
  current_release="$(resolve_directory_path "$releases_dir/current" || true)"
fi
if [[ ! -f "$current_release/metadata/release.env" ]]; then
  echo "smoke_release.sh: missing release metadata in active release"
  exit 1
fi
release_b_server_log="$work_dir/server_${release_b}.log"
release_b_helper="$(resolve_operability_helper "$current_release")"
run_release_health_check "$current_release" "$port" "$release_b_server_log" "$release_b_helper"

"$framework_root/tools/deploy/rollback_release.sh" \
  --releases-dir "$releases_dir" \
  --release-id "$release_a" >/dev/null

current_release="$(readlink -f "$releases_dir/current")"
if [[ -z "$current_release" ]]; then
  current_release="$(resolve_directory_path "$releases_dir/current" || true)"
fi
if [[ "$current_release" != "$releases_dir/$release_a" ]]; then
  echo "smoke_release.sh: rollback failed to activate $release_a"
  exit 1
fi
release_a_server_log="$work_dir/server_${release_a}.log"
release_a_helper="$(resolve_operability_helper "$current_release")"
run_release_health_check "$current_release" "$((port + 1))" "$release_a_server_log" "$release_a_helper"

success_message="release smoke passed: releases_dir=$releases_dir active=$current_release"
if [[ "$output_json" == "1" ]]; then
  emit_json "ok" "$current_release" "$release_a_server_log" "$release_b_server_log" "$success_message"
else
  echo "$success_message"
fi
