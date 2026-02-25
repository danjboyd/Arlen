#!/usr/bin/env bash

PROFILE_NAME="fastapi_comparison_http"
MAKE_TARGETS=(boomhauer)
SERVER_BINARY="${ARLEN_FASTAPI_PYTHON:-python3}"
SERVER_ARGS=(
  -m uvicorn app:app
  --app-dir "tests/performance/fastapi_reference"
  --host "127.0.0.1"
  --port "{port}"
  --workers "1"
  --log-level "warning"
)
SERVER_ENV=()
READINESS_PATH="/healthz"
CONCURRENCY=16
SCENARIOS=(
  "healthz:/healthz"
  "api_status:/api/status"
  "root:/"
)
