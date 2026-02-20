#!/usr/bin/env bash

PROFILE_NAME="migration_sample"
MAKE_TARGETS=(migration-sample-server)
SERVER_BINARY="./build/migration-sample-server"
SERVER_ARGS=(--port "{port}")
SERVER_ENV=(
  "ARLEN_APP_ROOT=examples/gsweb_migration"
)
READINESS_PATH="/healthz"
SCENARIOS=(
  "legacy_user:/legacy/users/42"
  "arlen_user:/arlen/users/42"
  "openapi_docs:/openapi"
)
