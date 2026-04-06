#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/run_clang64.sh" bash ./tools/ci/run_phase24_windows_parity.sh
