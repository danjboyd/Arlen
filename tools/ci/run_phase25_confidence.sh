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
    "tech_demo_live_orders.json"
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

  grep -q '/arlen/live.js' "$page_artifact"
  grep -q 'data-arlen-live-src="/tech-demo/live/pulse"' "$page_artifact"
  grep -q 'data-arlen-live-stream="/ws/channel/tech_demo.live"' "$page_artifact"
  grep -q 'window.ArlenLive' "$runtime_artifact"
  grep -q '"version":"arlen-live-v1"' "$orders_artifact"
  grep -q '"op":"update"' "$orders_artifact"
  grep -q 'ORD-410' "$orders_artifact"
  echo "phase25-confidence: smoke checks passed"
} 2>&1 | tee "$smoke_log"

echo "ci: phase25 confidence gate complete"
