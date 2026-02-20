#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: smoke_release.sh [options]

Validate release build/activate/health/rollback runbook end-to-end.

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

run_release_health_check() {
  local release_dir="$1"
  local probe_port="$2"
  local server_log="$3"

  ARLEN_APP_ROOT="$release_dir/app" \
    ARLEN_FRAMEWORK_ROOT="$release_dir/framework" \
    "$release_dir/framework/build/boomhauer" --port "$probe_port" --once >"$server_log" 2>&1 &
  local server_pid=$!

  local success=0
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${probe_port}/healthz" >/dev/null 2>&1; then
      success=1
      break
    fi
    sleep 0.05
  done

  wait "$server_pid" || true
  if [[ "$success" != "1" ]]; then
    echo "smoke_release.sh: health probe failed for $release_dir"
    echo "smoke_release.sh: server log follows"
    cat "$server_log"
    return 1
  fi
  return 0
}

"$framework_root/tools/deploy/build_release.sh" \
  --app-root "$app_root" \
  --framework-root "$framework_root" \
  --releases-dir "$releases_dir" \
  --release-id "$release_a" >/dev/null

"$framework_root/tools/deploy/build_release.sh" \
  --app-root "$app_root" \
  --framework-root "$framework_root" \
  --releases-dir "$releases_dir" \
  --release-id "$release_b" >/dev/null

"$framework_root/tools/deploy/activate_release.sh" \
  --releases-dir "$releases_dir" \
  --release-id "$release_b" >/dev/null

current_release="$(readlink -f "$releases_dir/current")"
if [[ ! -f "$current_release/metadata/release.env" ]]; then
  echo "smoke_release.sh: missing release metadata in active release"
  exit 1
fi
run_release_health_check "$current_release" "$port" "$work_dir/server_${release_b}.log"

"$framework_root/tools/deploy/rollback_release.sh" \
  --releases-dir "$releases_dir" \
  --release-id "$release_a" >/dev/null

current_release="$(readlink -f "$releases_dir/current")"
if [[ "$current_release" != "$releases_dir/$release_a" ]]; then
  echo "smoke_release.sh: rollback failed to activate $release_a"
  exit 1
fi
run_release_health_check "$current_release" "$((port + 1))" "$work_dir/server_${release_a}.log"

echo "release smoke passed: releases_dir=$releases_dir active=$current_release"
