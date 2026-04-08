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

work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-apple-smoke.XXXXXX")"
server_pid=""
server_log=""
cleanup_handlers=()

register_cleanup() {
  cleanup_handlers+=("$1")
}

cleanup_server() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  server_pid=""
}

cleanup_work_root() {
  rm -rf "$work_root"
}

cleanup() {
  cleanup_server
  for handler in "${cleanup_handlers[@]}"; do
    "$handler"
  done
}

register_cleanup cleanup_work_root
trap cleanup EXIT

next_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

json_assert() {
  local json="$1"
  local expression="$2"
  local failure_message="$3"
  JSON_INPUT="$json" ASSERT_EXPR="$expression" ASSERT_MESSAGE="$failure_message" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_INPUT"])
if not eval(os.environ["ASSERT_EXPR"], {"payload": payload}):
    print(os.environ["ASSERT_MESSAGE"], file=sys.stderr)
    sys.exit(1)
PY
}

totp_code() {
  python3 - <<'PY'
import base64
import hashlib
import hmac
import struct
import time

secret = "JBSWY3DPEHPK3PXP"
key = base64.b32decode(secret, casefold=True)
counter = int(time.time() // 30)
msg = struct.pack(">Q", counter)
digest = hmac.new(key, msg, hashlib.sha1).digest()
offset = digest[-1] & 0x0F
value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
print(f"{value % 1000000:06d}")
PY
}

wait_for_health() {
  local port="$1"
  local label="$2"
  local ready=0
  for _ in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.5
  done

  if [[ $ready -ne 1 ]]; then
    echo "test-apple: $label failed to start" >&2
    if [[ -n "$server_log" && -f "$server_log" ]]; then
      cat "$server_log" >&2 || true
    fi
    exit 1
  fi
}

start_server() {
  local app_root="$1"
  local binary="$2"
  local port="$3"
  local label="$4"
  server_log="$work_root/${label}.log"
  (
    cd "$app_root"
    "$binary" --port "$port" >"$server_log" 2>&1
  ) &
  server_pid=$!
  wait_for_health "$port" "$label"
}

run_scaffold_smoke() {
  local app_root="$work_root/AppleSmokeApp"
  echo "test-apple: scaffolding AppleSmokeApp"
  (
    cd "$work_root"
    "$repo_root/build/apple/arlen" new AppleSmokeApp >/dev/null
  )

  echo "test-apple: preparing scaffold app"
  local app_binary
  app_binary="$(
    cd "$app_root"
    ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/tools/build_apple_app.sh" \
      --framework-root "$repo_root" \
      --prepare-only \
      --print-path
  )"

  local port
  port="$(next_port)"
  echo "test-apple: starting scaffold app on port $port"
  start_server "$app_root" "$app_binary" "$port" "scaffold-app"

  local home_response
  local health_response
  local openapi_response
  home_response="$(curl -fsS "http://127.0.0.1:$port/")"
  health_response="$(curl -fsS "http://127.0.0.1:$port/healthz")"
  openapi_response="$(curl -fsS "http://127.0.0.1:$port/openapi")"

  if [[ "$home_response" != *"Arlen"* ]]; then
    echo "test-apple: scaffold home response did not contain expected content" >&2
    exit 1
  fi

  if [[ "$health_response" != *"ok"* && "$health_response" != *"OK"* ]]; then
    echo "test-apple: scaffold healthz response did not contain expected health content" >&2
    exit 1
  fi

  if [[ "$openapi_response" != *"openapi"* ]]; then
    echo "test-apple: scaffold openapi response did not contain an OpenAPI document" >&2
    exit 1
  fi

  cleanup_server
}

run_auth_primitives_validation() {
  local app_root="$repo_root/examples/auth_primitives"
  echo "test-apple: preparing auth_primitives example"
  local app_binary
  app_binary="$(
    cd "$app_root"
    ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/tools/build_apple_app.sh" \
      --app-root "$app_root" \
      --framework-root "$repo_root" \
      --prepare-only \
      --print-path
  )"

  local port
  port="$(next_port)"
  echo "test-apple: starting auth_primitives example on port $port"
  start_server "$app_root" "$app_binary" "$port" "auth-primitives"

  local root_response
  root_response="$(curl -fsS "http://127.0.0.1:$port/")"
  json_assert "$root_response" "'/auth/provider/secure' in payload.get('routes', [])" \
    "test-apple: auth_primitives root payload did not expose the expected route set"

  local local_cookie_jar="$work_root/auth-local.cookies"
  local local_login_response
  local local_provisioning_response
  local local_totp_response
  local local_session_response
  local totp

  local_login_response="$(curl -fsS -c "$local_cookie_jar" -b "$local_cookie_jar" \
    "http://127.0.0.1:$port/auth/local/login")"
  json_assert "$local_login_response" "payload.get('session', {}).get('provider') == 'local'" \
    "test-apple: local login did not establish a local provider session"

  local_provisioning_response="$(curl -fsS -c "$local_cookie_jar" -b "$local_cookie_jar" \
    "http://127.0.0.1:$port/auth/local/totp/provisioning")"
  json_assert "$local_provisioning_response" \
    "payload.get('otpauth_uri', '').startswith('otpauth://totp/')" \
    "test-apple: local TOTP provisioning did not return an otpauth URI"

  totp="$(totp_code)"
  local_totp_response="$(curl -fsS -c "$local_cookie_jar" -b "$local_cookie_jar" \
    "http://127.0.0.1:$port/auth/local/totp/verify?code=$totp")"
  json_assert "$local_totp_response" "payload.get('session', {}).get('aal') == 2" \
    "test-apple: local TOTP verification did not elevate the session to AAL2"
  json_assert "$local_totp_response" "payload.get('session', {}).get('mfa') in (True, 1)" \
    "test-apple: local TOTP verification did not mark the session as MFA authenticated"

  local_session_response="$(curl -fsS -c "$local_cookie_jar" -b "$local_cookie_jar" \
    "http://127.0.0.1:$port/auth/session")"
  json_assert "$local_session_response" "payload.get('aal') == 2 and payload.get('mfa') in (True, 1)" \
    "test-apple: local session state did not preserve AAL2 MFA state"

  local provider_cookie_jar="$work_root/auth-provider.cookies"
  local provider_login_response
  local provider_session_response
  provider_login_response="$(curl -fsS -L -c "$provider_cookie_jar" -b "$provider_cookie_jar" \
    "http://127.0.0.1:$port/auth/provider/stub/login")"
  json_assert "$provider_login_response" "'session' in payload" \
    "test-apple: provider login did not complete the callback flow"

  provider_session_response="$(curl -fsS -c "$provider_cookie_jar" -b "$provider_cookie_jar" \
    "http://127.0.0.1:$port/auth/session")"
  json_assert "$provider_session_response" \
    "payload.get('provider') == 'stub_oidc' and payload.get('aal') == 1 and payload.get('mfa') in (False, 0)" \
    "test-apple: provider login session state did not match the expected OIDC primary-auth result"

  cleanup_server
}

echo "test-apple: running doctor"
"$repo_root/bin/arlen" doctor >/dev/null

xctest_smoke_available=0
if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  if command -v xcrun >/dev/null 2>&1 && xcrun --find xctest >/dev/null 2>&1; then
    xctest_smoke_available=1
  else
    echo "test-apple: full Xcode is active, but xctest is unavailable via xcrun" >&2
  fi
else
  echo "test-apple: xcodebuild not found; Apple XCTest execution is unavailable in this environment" >&2
fi

if [[ $xctest_smoke_available -eq 1 ]]; then
  if [[ $smoke_only -eq 1 ]]; then
    echo "test-apple: running Apple XCTest smoke"
    "$repo_root/tools/apple_xctest_smoke.sh" >/dev/null
  else
    echo "test-apple: running Apple XCTest unit suite"
    "$repo_root/tools/test_apple_xctest.sh" --suite unit >/dev/null
  fi
fi

echo "test-apple: building framework and Apple verification artifacts"
"$repo_root/bin/build-apple" --with-boomhauer >/dev/null

echo "test-apple: running Apple auth/security audit"
"$repo_root/build/apple/apple-auth-audit" >/dev/null

run_scaffold_smoke
run_auth_primitives_validation

if [[ $smoke_only -eq 0 && $xctest_smoke_available -ne 1 ]]; then
  echo "test-apple: Apple XCTest unit suite was skipped because full Xcode is not active" >&2
fi

echo "test-apple: Apple runtime verification passed"
