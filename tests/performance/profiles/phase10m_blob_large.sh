#!/usr/bin/env bash

PROFILE_NAME="phase10m_blob_large"
MAKE_TARGETS=(boomhauer)
SERVER_BINARY="./build/boomhauer"
SERVER_ARGS=(--env "production" --port "{port}")
SERVER_ENV=(
  "ARLEN_PERFORMANCE_LOGGING=0"
  "ARLEN_LOG_LEVEL=warn"
)
READINESS_PATH="/healthz"
CONCURRENCY=32
SCENARIOS=(
  "blob_legacy_string_e2e:/api/blob?size=262144&impl=legacy-string"
  "blob_binary_e2e:/api/blob?size=262144"
  "blob_binary_sendfile:/api/blob?size=262144&mode=sendfile"
)
