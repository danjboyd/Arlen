#!/usr/bin/env bash

PROFILE_NAME="comparison_http"
MAKE_TARGETS=(boomhauer)
SERVER_BINARY="./build/boomhauer"
SERVER_ARGS=(--env "production" --port "{port}")
SERVER_ENV=(
  "ARLEN_PERFORMANCE_LOGGING=0"
  "ARLEN_LOG_LEVEL=warn"
)
READINESS_PATH="/healthz"
CONCURRENCY=16
SCENARIOS=(
  "healthz:/healthz"
  "api_status:/api/status"
  "root:/"
)
