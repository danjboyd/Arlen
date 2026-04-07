#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" arlen
make -C "$repo_root" phase24-windows-db-smoke

echo "ci: phase24 windows preview db smoke complete"
