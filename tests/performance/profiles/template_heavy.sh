#!/usr/bin/env bash

PROFILE_NAME="template_heavy"
MAKE_TARGETS=(tech-demo-server)
SERVER_BINARY="./build/tech-demo-server"
SERVER_ARGS=(--port "{port}")
SERVER_ENV=(
  "ARLEN_APP_ROOT=examples/tech_demo"
)
READINESS_PATH="/healthz"
SCENARIOS=(
  "landing:/tech-demo"
  "dashboard:/tech-demo/dashboard?tab=overview"
  "user_show:/tech-demo/users/peggy?flag=admin"
  "catalog_json:/tech-demo/api/catalog"
)
