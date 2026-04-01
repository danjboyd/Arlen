#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE25_OUTPUT_DIR:-$repo_root/build/release_confidence/phase25}"
live_test_log="$output_dir/phase25_live_tests.log"
smoke_log="$output_dir/phase25_live_smoke.log"
server_log="$output_dir/tech_demo_live_server.log"
manifest="$output_dir/manifest.json"
page_artifact="$output_dir/tech_demo_live.html"
runtime_artifact="$output_dir/live_runtime.js"
orders_artifact="$output_dir/tech_demo_live_orders.json"
stream_push_artifact="$output_dir/tech_demo_live_stream_push.json"
backpressure_headers_artifact="$output_dir/tech_demo_live_backpressure.headers"

mkdir -p "$output_dir"

server_pid=""
failure_reason="phase25_confidence_failed"

write_manifest() {
  local status="$1"
  local reason="${2:-}"
  cat >"$manifest" <<EOF
{
  "status": "$status",
  "reason": "$reason",
  "artifacts": [
    "phase25_live_tests.log",
    "phase25_live_smoke.log",
    "tech_demo_live_server.log",
    "tech_demo_live.html",
    "live_runtime.js",
    "tech_demo_live_orders.json",
    "tech_demo_live_stream_push.json",
    "tech_demo_live_backpressure.headers"
  ]
}
EOF
}

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}

trap 'status=$?; cleanup; if [[ $status -eq 0 ]]; then write_manifest pass ""; else write_manifest fail "$failure_reason"; fi; exit $status' EXIT

set +u
source "$repo_root/tools/source_gnustep_env.sh"
set -u

make -C "$repo_root" phase25-live-tests 2>&1 | tee "$live_test_log"
make -C "$repo_root" tech-demo-server >/dev/null

port="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

failure_reason="phase25_server_failed_to_start"
ARLEN_APP_ROOT=examples/tech_demo "$repo_root/build/tech-demo-server" --host 127.0.0.1 --port "$port" \
  >"$server_log" 2>&1 &
server_pid=$!

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null

failure_reason="phase25_live_smoke_failed"
{
  echo "phase25-confidence: fetching /tech-demo/live"
  curl -fsS "http://127.0.0.1:$port/tech-demo/live" >"$page_artifact"
  echo "phase25-confidence: fetching /arlen/live.js"
  curl -fsS "http://127.0.0.1:$port/arlen/live.js" >"$runtime_artifact"
  echo "phase25-confidence: fetching live fragment payload"
  curl -fsS \
    -H 'X-Arlen-Live: true' \
    -H 'X-Arlen-Live-Target: #live-orders' \
    -H 'X-Arlen-Live-Swap: update' \
    "http://127.0.0.1:$port/tech-demo/live/orders?owner=Pat&status=Live" \
    >"$orders_artifact"
  echo "phase25-confidence: capturing websocket push artifact"
  PORT="$port" STREAM_PUSH_ARTIFACT="$stream_push_artifact" python3 - <<'PY'
import base64
import os
import socket
import struct
import time
import urllib.request

port = int(os.environ["PORT"])
artifact_path = os.environ["STREAM_PUSH_ARTIFACT"]

def recv_exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("connection closed")
        data += chunk
    return data

def recv_text(sock):
    b1, b2 = recv_exact(sock, 2)
    opcode = b1 & 0x0F
    length = b2 & 0x7F
    masked = (b2 & 0x80) != 0
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask_key = recv_exact(sock, 4) if masked else b""
    payload = recv_exact(sock, length)
    if masked:
        payload = bytes(payload[i] ^ mask_key[i % 4] for i in range(length))
    if opcode != 0x1:
        raise RuntimeError(f"unexpected opcode {opcode}")
    return payload.decode("utf-8")

key = base64.b64encode(os.urandom(16)).decode("ascii")
request = (
    "GET /ws/channel/tech_demo.live HTTP/1.1\r\n"
    f"Host: 127.0.0.1:{port}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
).encode("utf-8")

sock = socket.create_connection(("127.0.0.1", port), timeout=5)
sock.sendall(request)
headers = sock.recv(4096).decode("utf-8", "replace")
if "101 Switching Protocols" not in headers:
    raise RuntimeError(headers)
time.sleep(0.2)
urllib.request.urlopen(
    f"http://127.0.0.1:{port}/tech-demo/live/feed/publish?key=row-confidence&label=Confidence",
    timeout=5,
).read()
message = recv_text(sock)
with open(artifact_path, "w", encoding="utf-8") as handle:
    handle.write(message)
sock.close()
PY
  echo "phase25-confidence: capturing negative live artifact"
  curl -sS -D "$backpressure_headers_artifact" -o /dev/null \
    -H 'X-Arlen-Live: true' \
    -H 'X-Arlen-Live-Target: #live-orders' \
    "http://127.0.0.1:$port/tech-demo/live/orders?simulate=backpressure"

  grep -q '/arlen/live.js' "$page_artifact"
  grep -q 'data-arlen-live-src="/tech-demo/live/pulse"' "$page_artifact"
  grep -q 'data-arlen-live-stream="/ws/channel/tech_demo.live"' "$page_artifact"
  grep -q 'window.ArlenLive' "$runtime_artifact"
  grep -q '"version":"arlen-live-v1"' "$orders_artifact"
  grep -q '"op":"update"' "$orders_artifact"
  grep -q 'ORD-410' "$orders_artifact"
  grep -q '"op":"upsert"' "$stream_push_artifact"
  grep -q 'row-confidence' "$stream_push_artifact"
  grep -q '429 Too Many Requests' "$backpressure_headers_artifact"
  grep -q 'Retry-After: 3' "$backpressure_headers_artifact"
  echo "phase25-confidence: smoke checks passed"
} 2>&1 | tee "$smoke_log"

echo "ci: phase25 confidence gate complete"
