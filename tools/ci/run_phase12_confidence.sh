#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE12_OUTPUT_DIR:-$repo_root/build/release_confidence/phase12}"
xctest_runner="${ARLEN_XCTEST:-xctest}"
xctest_ld_library_path="${ARLEN_XCTEST_LD_LIBRARY_PATH:-}"
unit_bundle="${ARLEN_PHASE12_UNIT_BUNDLE:-$repo_root/build/tests/ArlenUnitTests.xctest}"
fixture_path="${ARLEN_PHASE12_FIXTURE:-$repo_root/tests/fixtures/auth/phase12_oidc_cases.json}"
server_binary="${ARLEN_PHASE12_SERVER_BINARY:-$repo_root/build/auth-primitives-server}"
unit_log="$output_dir/phase12_unit.log"
server_log="$output_dir/auth_primitives_server.log"
login_flow_json="$output_dir/phase12_auth_primitives_login_flow.json"
step_up_flow_json="$output_dir/phase12_auth_primitives_step_up_flow.json"

mkdir -p "$output_dir" "${HOME}/GNUstep/Defaults/.lck"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

run_xctest() {
  if [[ -n "$xctest_ld_library_path" ]]; then
    LD_LIBRARY_PATH="$xctest_ld_library_path${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$xctest_runner" "$@"
  else
    "$xctest_runner" "$@"
  fi
}

make build-tests auth-primitives-server

run_xctest "$unit_bundle" >"$unit_log" 2>&1
cp "$fixture_path" "$output_dir/phase12_oidc_cases.json"

port="$(
  python3 - <<'PY'
import socket

s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ARLEN_APP_ROOT=examples/auth_primitives "$server_binary" --port "$port" >"$server_log" 2>&1 &
server_pid="$!"

ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != "1" ]]; then
  echo "phase12-confidence: auth-primitives server failed to become ready" >&2
  exit 1
fi

python3 - "$port" <<'PY' >"$login_flow_json"
import http.cookiejar
import json
import sys
import urllib.request

port = int(sys.argv[1])
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
login = json.loads(
    opener.open(f"http://127.0.0.1:{port}/auth/provider/stub/login", timeout=5)
    .read()
    .decode("utf-8")
)
session = json.loads(
    opener.open(f"http://127.0.0.1:{port}/auth/session", timeout=5).read().decode("utf-8")
)
print(json.dumps({"login": login, "session": session}, sort_keys=True))
PY

python3 - "$port" <<'PY' >"$step_up_flow_json"
import base64
import hashlib
import hmac
import http.cookiejar
import json
import struct
import sys
import time
import urllib.error
import urllib.request

port = int(sys.argv[1])
secret = "JBSWY3DPEHPK3PXP"
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def request_json(url: str):
    try:
        response = opener.open(url, timeout=5)
        return response.getcode(), json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def totp(secret_value: str) -> str:
    key = base64.b32decode(secret_value, casefold=True)
    counter = int(time.time() // 30)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = ((digest[offset] & 0x7F) << 24) | ((digest[offset + 1] & 0xFF) << 16)
    value |= (digest[offset + 2] & 0xFF) << 8
    value |= digest[offset + 3] & 0xFF
    return f"{value % 1000000:06d}"


login_status, login = request_json(f"http://127.0.0.1:{port}/auth/provider/stub/login")
if login_status != 200:
    raise SystemExit(json.dumps({"status": login_status, "body": login}, sort_keys=True))

secure_before_status, secure_before = request_json(f"http://127.0.0.1:{port}/auth/provider/secure")
step_up_status, step_up = request_json(
    f"http://127.0.0.1:{port}/auth/local/totp/verify?code={totp(secret)}"
)
secure_after_status, secure_after = request_json(f"http://127.0.0.1:{port}/auth/provider/secure")

payload = {
    "login": {"status": login_status, "body": login},
    "secure_before": {"status": secure_before_status, "body": secure_before},
    "step_up": {"status": step_up_status, "body": step_up},
    "secure_after": {"status": secure_after_status, "body": secure_after},
}
print(json.dumps(payload, sort_keys=True))
PY

python3 ./tools/ci/generate_phase12_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$output_dir" \
  --unit-log "$unit_log" \
  --fixture "$output_dir/phase12_oidc_cases.json" \
  --login-flow "$login_flow_json" \
  --step-up-flow "$step_up_flow_json"

echo "ci: phase12 confidence gate complete"
