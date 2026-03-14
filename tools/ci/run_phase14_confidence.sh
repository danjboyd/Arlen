#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE14_OUTPUT_DIR:-$repo_root/build/release_confidence/phase14}"
xctest_runner="${ARLEN_XCTEST:-xctest}"
xctest_ld_library_path="${ARLEN_XCTEST_LD_LIBRARY_PATH:-}"
unit_bundle="${ARLEN_PHASE14_UNIT_BUNDLE:-$repo_root/build/tests/ArlenUnitTests.xctest}"
example_root="${ARLEN_PHASE14_EXAMPLE_ROOT:-$repo_root/examples/phase14_modules_demo}"
unit_log="$output_dir/phase14_unit.log"
module_list_json="$output_dir/phase14_module_list.json"
doctor_json="$output_dir/phase14_module_doctor.json"
migrate_json="$output_dir/phase14_module_migrate.json"
assets_json="$output_dir/phase14_module_assets.json"
assets_dir="$output_dir/module_assets"
flow_json="$output_dir/phase14_sample_flow.json"
server_log="$output_dir/phase14_modules_demo_server.log"

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

make build-tests arlen boomhauer
run_xctest "$unit_bundle" >"$unit_log" 2>&1

if [[ -z "${ARLEN_PG_TEST_DSN:-}" ]]; then
  python3 ./tools/ci/generate_phase14_confidence_artifacts.py \
    --repo-root "$repo_root" \
    --output-dir "$output_dir" \
    --unit-log "$unit_log" \
    --mode skipped \
    --reason "ARLEN_PG_TEST_DSN is unset; Phase 14 sample app flow was skipped"
  echo "ci: phase14 confidence gate skipped sample app flow because ARLEN_PG_TEST_DSN is unset"
  exit 0
fi

temp_app="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase14-confidence-XXXXXX")"
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
cleanup_user "$demo_email"

server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  cleanup_user "$demo_email"
  rm -rf "$temp_app"
}
trap cleanup EXIT

for module in auth admin-ui jobs notifications storage ops search; do
  (cd "$temp_app" && ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" module add "$module" --json >/dev/null)
done

(cd "$temp_app" && "$repo_root/build/arlen" module list --json >"$module_list_json")
(cd "$temp_app" && "$repo_root/build/arlen" module migrate --env development --json >"$migrate_json")
(cd "$temp_app" && "$repo_root/build/arlen" module doctor --env development --json >"$doctor_json")
(cd "$temp_app" && "$repo_root/build/arlen" module assets --output-dir "$assets_dir" --json >"$assets_json")

port="$(
  python3 - <<'PY'
import socket

s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

(cd "$temp_app" && ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/bin/boomhauer" --no-watch --port "$port" >"$server_log" 2>&1) &
server_pid="$!"

ready=0
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${port}/auth/api/session" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != "1" ]]; then
  echo "phase14-confidence: sample app server failed to become ready" >&2
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
import urllib.parse
import urllib.request

port = int(sys.argv[1])
dsn = sys.argv[2]
output_path = sys.argv[3]
email = "demo-admin@example.test"
password = "phase14-demo-password-ok"

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def request(path: str, method: str = "GET", payload: dict | None = None, headers: dict | None = None, body: bytes | None = None):
    raw_headers = {"Accept": "application/json"}
    if headers:
        raw_headers.update(headers)
    data = body
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        raw_headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, headers=raw_headers, method=method)
    with opener.open(req, timeout=10) as response:
        payload_bytes = response.read()
        content_type = response.headers.get("Content-Type", "")
        parsed_body: object
        if "application/json" in content_type:
            parsed_body = json.loads(payload_bytes.decode("utf-8"))
        else:
            parsed_body = payload_bytes.decode("utf-8")
        return {
            "status": response.getcode(),
            "headers": dict(response.headers.items()),
            "body": parsed_body,
        }


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


def csrf_token_from_session() -> str:
    session = request("/auth/api/session")
    body = session["body"] if isinstance(session["body"], dict) else {}
    return body.get("csrf_token", "")


def json_data(response: dict) -> dict:
    body = response.get("body")
    return body if isinstance(body, dict) else {}


auth_session = request("/auth/api/session")
csrf = json_data(auth_session).get("csrf_token", "")
register = request(
    "/auth/api/register",
    method="POST",
    payload={
        "email": email,
        "display_name": "Demo Admin",
        "password": password,
        "csrf_token": csrf,
    },
)
csrf = csrf_token_from_session()
request("/auth/api/mfa/totp")
secret = sql_scalar(
    "SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
    "WHERE lower(u.email) = lower('demo-admin@example.test') ORDER BY m.id DESC LIMIT 1;"
)
step_up = request(
    "/auth/api/mfa/totp/verify",
    method="POST",
    payload={"code": totp(secret), "csrf_token": csrf},
)
post_step_up_session = request("/auth/api/session")
csrf = json_data(post_step_up_session).get("csrf_token", "")
csrf_headers = {"X-CSRF-Token": csrf}

manual_enqueue = request(
    "/jobs/api/enqueue",
    method="POST",
    payload={"job": "phase14demo.recorded", "payload": {"value": "manual-job"}},
    headers=csrf_headers,
)
manual_worker = request(
    "/jobs/api/run-worker",
    method="POST",
    payload={"limit": 5},
    headers=csrf_headers,
)
after_manual_executions = request("/demo/api/executions")

scheduler = request(
    "/jobs/api/run-scheduler",
    method="POST",
    payload={},
    headers=csrf_headers,
)
scheduler_worker = request(
    "/jobs/api/run-worker",
    method="POST",
    payload={"limit": 5},
    headers=csrf_headers,
)
after_scheduler_executions = request("/demo/api/executions")

notifications_preview = request(
    "/notifications/api/preview",
    method="POST",
    payload={
        "notification": "phase14demo.notification",
        "payload": {
            "recipient": "demo-admin",
            "email": "demo-admin@example.test",
            "name": "Admin",
        },
    },
    headers=csrf_headers,
)
notifications_test_send = request(
    "/notifications/api/test-send",
    method="POST",
    payload={
        "notification": "phase14demo.notification",
        "payload": {
            "recipient": "demo-admin",
            "email": "demo-admin@example.test",
            "name": "Admin",
        },
    },
    headers=csrf_headers,
)

upload_session = request(
    "/storage/api/upload-sessions",
    method="POST",
    payload={
        "collection": "media",
        "name": "avatar.png",
        "contentType": "image/png",
        "sizeBytes": 4,
        "metadata": {"kind": "avatar"},
        "expiresIn": 120,
    },
    headers=csrf_headers,
)
upload_session_body = json_data(upload_session).get("data", {})
session_id = upload_session_body.get("sessionID", "")
upload_token = upload_session_body.get("token", "")
upload = request(
    f"/storage/api/upload-sessions/{urllib.parse.quote(session_id)}/upload",
    method="POST",
    body=b"png!",
    headers={
        **csrf_headers,
        "Accept": "application/json",
        "Content-Type": "image/png",
        "X-Upload-Token": upload_token,
    },
)
upload_body = json_data(upload).get("data", {})
object_id = upload_body.get("object", {}).get("objectID", "")
variant_worker = request(
    "/jobs/api/run-worker",
    method="POST",
    payload={"limit": 10},
    headers=csrf_headers,
)
detail = request(f"/storage/api/collections/media/objects/{urllib.parse.quote(object_id)}")
download_token = request(
    f"/storage/api/collections/media/objects/{urllib.parse.quote(object_id)}/download-token",
    method="POST",
    payload={"expiresIn": 120},
    headers=csrf_headers,
)
download_token_body = json_data(download_token).get("data", {})
download = request(f"/storage/api/download/{urllib.parse.quote(download_token_body.get('token', ''))}", headers={"Accept": "*/*"})

search_reindex = request(
    "/search/api/resources/orders/reindex",
    method="POST",
    payload={},
    headers=csrf_headers,
)
search_worker = request(
    "/jobs/api/run-worker",
    method="POST",
    payload={"limit": 10},
    headers=csrf_headers,
)
search_query = request("/search/api/resources/orders/query?q=pending")
admin_indexes = request("/admin/api/resources/search_indexes/items")

ops_summary = request("/ops/api/summary")
ops_openapi = request("/ops/api/openapi")

payload = {
    "auth": {
        "session": auth_session,
        "register": register,
        "step_up": step_up,
        "post_step_up_session": post_step_up_session,
    },
    "jobs": {
        "manual_enqueue": manual_enqueue,
        "manual_worker": manual_worker,
        "after_manual_executions": after_manual_executions,
        "scheduler": scheduler,
        "scheduler_worker": scheduler_worker,
        "after_scheduler_executions": after_scheduler_executions,
    },
    "notifications": {
        "preview": notifications_preview,
        "test_send": notifications_test_send,
    },
    "storage": {
        "upload_session": upload_session,
        "upload": upload,
        "variant_worker": variant_worker,
        "detail": detail,
        "download_token": download_token,
        "download": download,
    },
    "search": {
        "reindex": search_reindex,
        "worker": search_worker,
        "query": search_query,
        "admin_indexes": admin_indexes,
    },
    "ops": {
        "summary": ops_summary,
        "openapi": ops_openapi,
    },
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

python3 ./tools/ci/generate_phase14_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$output_dir" \
  --unit-log "$unit_log" \
  --module-list "$module_list_json" \
  --doctor "$doctor_json" \
  --migrate "$migrate_json" \
  --assets "$assets_json" \
  --flow "$flow_json"

echo "ci: phase14 confidence gate complete"
