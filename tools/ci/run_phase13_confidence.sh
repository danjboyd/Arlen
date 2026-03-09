#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE13_OUTPUT_DIR:-$repo_root/build/release_confidence/phase13}"
unit_bundle="${ARLEN_PHASE13_UNIT_BUNDLE:-$repo_root/build/tests/ArlenUnitTests.xctest}"
example_root="${ARLEN_PHASE13_EXAMPLE_ROOT:-$repo_root/examples/auth_admin_demo}"
unit_log="$output_dir/phase13_unit.log"
flow_json="$output_dir/phase13_sample_flow.json"
server_log="$output_dir/auth_admin_demo_server.log"

mkdir -p "$output_dir" "${HOME}/GNUstep/Defaults/.lck"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

make build-tests arlen boomhauer
xctest "$unit_bundle" >"$unit_log" 2>&1

if [[ -z "${ARLEN_PG_TEST_DSN:-}" ]]; then
  python3 ./tools/ci/generate_phase13_confidence_artifacts.py \
    --repo-root "$repo_root" \
    --output-dir "$output_dir" \
    --unit-log "$unit_log" \
    --mode skipped \
    --reason "ARLEN_PG_TEST_DSN is unset; sample app flow was skipped"
  echo "ci: phase13 confidence gate skipped sample app flow because ARLEN_PG_TEST_DSN is unset"
  exit 0
fi

temp_app="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase13-confidence-XXXXXX")"
cp -R "$example_root"/. "$temp_app"/

python3 - "$temp_app/config/app.plist" "${ARLEN_PG_TEST_DSN}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
dsn = sys.argv[2]
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("__ARLEN_PG_DSN__", dsn.replace("\\", "\\\\").replace('"', '\\"')), encoding="utf-8")
PY

cleanup_user() {
  local email="$1"
  psql "${ARLEN_PG_TEST_DSN}" -c "DELETE FROM auth_users WHERE lower(email) = lower('${email//\'/\'\'}');" >/dev/null 2>&1 || true
}

demo_email="demo-admin@example.test"
provider_email="provider-admin@example.test"
cleanup_user "$demo_email"
cleanup_user "$provider_email"

(cd "$temp_app" && ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" module add auth --json >/dev/null)
(cd "$temp_app" && ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" module add admin-ui --json >/dev/null)
(cd "$temp_app" && "$repo_root/build/arlen" module migrate --env development --json >/dev/null)

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
  cleanup_user "$demo_email"
  cleanup_user "$provider_email"
  rm -rf "$temp_app"
}
trap cleanup EXIT

(cd "$temp_app" && ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/bin/boomhauer" --no-watch --port "$port" >"$server_log" 2>&1) &
server_pid="$!"

ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${port}/auth/api/session" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != "1" ]]; then
  echo "phase13-confidence: sample app server failed to become ready" >&2
  exit 1
fi

python3 - "$port" "${ARLEN_PG_TEST_DSN}" "$flow_json" <<'PY'
import base64
import hashlib
import hmac
import http.cookiejar
import json
import struct
import subprocess
import sys
import time
import urllib.request

port = int(sys.argv[1])
dsn = sys.argv[2]
output_path = sys.argv[3]
email = "demo-admin@example.test"
password = "module-password-ok"

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def request_json(path: str, method: str = "GET", payload: dict | None = None):
    body = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=body, headers=headers, method=method)
    response = opener.open(request, timeout=5)
    return response.getcode(), json.loads(response.read().decode("utf-8"))


def sql_scalar(sql: str) -> str:
    output = subprocess.check_output(["psql", dsn, "-Atc", sql], text=True)
    return output.strip()


def totp(secret: str) -> str:
    key = base64.b32decode(secret, casefold=True)
    counter = int(time.time() // 30)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = ((digest[offset] & 0x7F) << 24) | ((digest[offset + 1] & 0xFF) << 16)
    value |= (digest[offset + 2] & 0xFF) << 8
    value |= digest[offset + 3] & 0xFF
    return f"{value % 1000000:06d}"


_, session = request_json("/auth/api/session")
register_status, register = request_json(
    "/auth/api/register",
    "POST",
    {"email": email, "display_name": "Demo Admin", "password": password, "csrf_token": session.get("csrf_token", "")},
)
_, session = request_json("/auth/api/session")
request_json("/auth/api/mfa/totp")
secret = sql_scalar(
    "SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
    "WHERE lower(u.email) = lower('demo-admin@example.test') ORDER BY m.id DESC LIMIT 1;"
)
step_up_status, step_up = request_json(
    "/auth/api/mfa/totp/verify",
    "POST",
    {"code": totp(secret), "csrf_token": session.get("csrf_token", "")},
)
resources_status, resources = request_json("/admin/api/resources")
action_status, action = request_json(
    "/admin/api/resources/orders/items/ord-100/actions/mark_reviewed",
    "POST",
    {"csrf_token": step_up.get("csrf_token", session.get("csrf_token", ""))},
)

payload = {
    "register": {"status": register_status, "body": register},
    "step_up": {"status": step_up_status, "body": step_up},
    "admin_resources": {
        "status": resources_status,
        "identifiers": [entry.get("identifier", "") for entry in resources.get("resources", [])],
        "body": resources,
    },
    "orders_action": {"status": action_status, "body": action},
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

python3 ./tools/ci/generate_phase13_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$output_dir" \
  --unit-log "$unit_log" \
  --flow "$flow_json"

echo "ci: phase13 confidence gate complete"
