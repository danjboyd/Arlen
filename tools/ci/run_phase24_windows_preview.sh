#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
SMOKE_ROOT="$REPO_ROOT/build/phase24/windows-preview-smoke"
APP_ROOT="$SMOKE_ROOT/SmokeApp"

make -C "$REPO_ROOT" clean
rm -rf "$SMOKE_ROOT"
mkdir -p "$SMOKE_ROOT"

make -C "$REPO_ROOT" all
make -C "$REPO_ROOT" phase24-windows-tests
make -C "$REPO_ROOT" phase24-windows-db-smoke

"$REPO_ROOT/build/arlen" doctor --json >"$SMOKE_ROOT/doctor.json"
"$REPO_ROOT/build/arlen" new "$APP_ROOT" --force

(
  cd "$APP_ROOT"
  ARLEN_FRAMEWORK_ROOT="$REPO_ROOT" "$REPO_ROOT/build/arlen" boomhauer --no-watch --prepare-only
  ARLEN_FRAMEWORK_ROOT="$REPO_ROOT" "$REPO_ROOT/build/arlen" routes >"$SMOKE_ROOT/routes.txt"
)
