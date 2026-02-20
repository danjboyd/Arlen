#!/usr/bin/env bash

PROFILE_NAME="middleware_heavy"
MAKE_TARGETS=(boomhauer)
SERVER_BINARY="./build/boomhauer"
SERVER_ARGS=(--port "{port}")
SERVER_ENV=(
  "ARLEN_SESSION_ENABLED=1"
  "ARLEN_SESSION_SECRET=phase3c-session-secret"
  "ARLEN_CSRF_ENABLED=1"
  "ARLEN_RATE_LIMIT_ENABLED=1"
  "ARLEN_RATE_LIMIT_REQUESTS=100000"
  "ARLEN_RATE_LIMIT_WINDOW_SECONDS=60"
  "ARLEN_SECURITY_HEADERS_ENABLED=1"
)
READINESS_PATH="/healthz"
SCENARIOS=(
  "healthz:/healthz"
  "api_status:/api/status"
  "api_echo:/api/echo/hank"
  "root:/"
)
