#!/usr/bin/env bash

PROFILE_NAME="api_reference"
MAKE_TARGETS=(api-reference-server)
SERVER_BINARY="./build/api-reference-server"
SERVER_ARGS=(--port "{port}")
SERVER_ENV=(
  "ARLEN_APP_ROOT=examples/api_reference"
)
READINESS_PATH="/healthz"
SCENARIOS=(
  "status:/api/reference/status"
  "openapi_json:/openapi.json"
  "openapi_docs:/openapi"
)
