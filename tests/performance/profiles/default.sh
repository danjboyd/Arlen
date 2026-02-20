#!/usr/bin/env bash

PROFILE_NAME="default"
MAKE_TARGETS=(boomhauer)
SERVER_BINARY="./build/boomhauer"
SERVER_ARGS=(--port "{port}")
SERVER_ENV=()
READINESS_PATH="/healthz"
SCENARIOS=(
  "healthz:/healthz"
  "api_status:/api/status"
  "root:/"
  "openapi_json:/openapi.json"
  "openapi_docs:/openapi"
)
