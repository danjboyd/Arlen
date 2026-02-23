#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: validate_operability.sh [options]

Validate Arlen operability probe contracts against a running server.

Options:
  --base-url <url>  Base URL for probe requests (default: http://127.0.0.1:3000)
  --help            Show this help
USAGE
}

base_url="http://127.0.0.1:3000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      [[ $# -ge 2 ]] || { echo "validate_operability.sh: --base-url requires a value" >&2; exit 2; }
      base_url="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "validate_operability.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

trimmed_base="${base_url%/}"

health_text="$(curl -fsS "${trimmed_base}/healthz")"
health_text="$(printf '%s' "$health_text" | tr -d '\r\n')"
if [[ "$health_text" != "ok" ]]; then
  echo "validate_operability.sh: /healthz text contract failed (expected 'ok', got '$health_text')" >&2
  exit 1
fi

ready_text="$(curl -fsS "${trimmed_base}/readyz")"
ready_text="$(printf '%s' "$ready_text" | tr -d '\r\n')"
if [[ "$ready_text" != "ready" ]]; then
  echo "validate_operability.sh: /readyz text contract failed (expected 'ready', got '$ready_text')" >&2
  exit 1
fi

validate_json_signal() {
  local endpoint="$1"
  local expected_signal="$2"
  local expected_status="$3"
  local expected_ready="$4"
  local payload
  payload="$(curl -fsS -H 'Accept: application/json' "${trimmed_base}/${endpoint}")"

  if ! PAYLOAD_JSON="$payload" python3 - "$expected_signal" "$expected_status" "$expected_ready" <<'PY'; then
import json
import os
import sys

expected_signal = sys.argv[1]
expected_status = sys.argv[2]
expected_ready = sys.argv[3].lower() == "true"

try:
    payload = json.loads(os.environ.get("PAYLOAD_JSON", ""))
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid JSON payload: {exc}")

if payload.get("signal") != expected_signal:
    raise SystemExit(f"signal mismatch: expected {expected_signal!r}, got {payload.get('signal')!r}")
if payload.get("status") != expected_status:
    raise SystemExit(f"status mismatch: expected {expected_status!r}, got {payload.get('status')!r}")

checks = payload.get("checks")
if not isinstance(checks, dict):
    raise SystemExit("checks object missing")
for key in ("request_dispatch", "metrics_registry", "active_requests", "startup"):
    if key not in checks:
        raise SystemExit(f"checks.{key} missing")

if expected_signal == "ready":
    if bool(payload.get("ready")) != expected_ready:
        raise SystemExit(
            f"ready mismatch: expected {expected_ready!r}, got {payload.get('ready')!r}"
        )

if not isinstance(payload.get("uptime_seconds"), int):
    raise SystemExit("uptime_seconds must be an integer")
if not isinstance(payload.get("timestamp_utc"), str) or not payload.get("timestamp_utc"):
    raise SystemExit("timestamp_utc missing")
PY
    echo "validate_operability.sh: ${endpoint} JSON contract validation failed" >&2
    exit 1
  fi
}

validate_json_signal "healthz" "health" "ok" "true"
validate_json_signal "readyz" "ready" "ready" "true"

metrics_text="$(curl -fsS "${trimmed_base}/metrics")"
if ! printf '%s' "$metrics_text" | grep -q "aln_http_requests_total"; then
  echo "validate_operability.sh: /metrics missing aln_http_requests_total" >&2
  exit 1
fi

echo "operability validation passed: ${trimmed_base}"
