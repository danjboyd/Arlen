#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"

if ! aln_platform_is_macos; then
  echo "test-apple: this helper only supports macOS" >&2
  exit 1
fi

smoke_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke-only)
      smoke_only=1
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: test_apple.sh [--smoke-only]

Runs the current Apple-runtime verification lane.
USAGE
      exit 0
      ;;
    *)
      echo "test-apple: unknown option $1" >&2
      exit 2
      ;;
  esac
done

echo "test-apple: running doctor"
"$repo_root/bin/arlen" doctor >/dev/null

if command -v xcodebuild >/dev/null 2>&1; then
  if xcodebuild -version >/dev/null 2>&1; then
    echo "test-apple: full Xcode detected, but Apple XCTest build integration is not yet implemented" >&2
    echo "test-apple: continuing with smoke verification only" >&2
  else
    echo "test-apple: full Xcode is not active; Apple XCTest execution is unavailable in this environment" >&2
  fi
else
  echo "test-apple: xcodebuild not found; Apple XCTest execution is unavailable in this environment" >&2
fi

echo "test-apple: building framework and repo-root boomhauer"
"$repo_root/bin/build-apple" --with-boomhauer >/dev/null

work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-apple-smoke.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT

app_root="$work_root/AppleSmokeApp"
echo "test-apple: scaffolding AppleSmokeApp"
(
  cd "$work_root"
  "$repo_root/build/apple/arlen" new AppleSmokeApp >/dev/null
)

echo "test-apple: preparing scaffold app"
app_binary="$(
  cd "$app_root"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/tools/build_apple_app.sh" \
    --framework-root "$repo_root" \
    --prepare-only \
    --print-path
)"

port="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

echo "test-apple: starting scaffold app on port $port"
(
  cd "$app_root"
  "$app_binary" --port "$port" >"$work_root/server.log" 2>&1
) &
server_pid=$!

cleanup_server() {
  if kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap 'cleanup_server; rm -rf "$work_root"' EXIT

ready=0
for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done

if [[ $ready -ne 1 ]]; then
  echo "test-apple: scaffold app failed to start" >&2
  cat "$work_root/server.log" >&2 || true
  exit 1
fi

home_response="$(curl -fsS "http://127.0.0.1:$port/")"
health_response="$(curl -fsS "http://127.0.0.1:$port/healthz")"

if [[ "$home_response" != *"Arlen"* ]]; then
  echo "test-apple: home response did not contain expected scaffold content" >&2
  exit 1
fi

if [[ "$health_response" != *"ok"* && "$health_response" != *"OK"* ]]; then
  echo "test-apple: healthz response did not contain expected health content" >&2
  exit 1
fi

cleanup_server

if [[ $smoke_only -eq 0 ]]; then
  echo "test-apple: Apple XCTest remains deferred until full Xcode-backed integration lands"
fi

echo "test-apple: smoke verification passed"
