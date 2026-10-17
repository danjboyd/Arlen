#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$repo_root/tools/source_gnustep_env.sh"

# A test stopped by its xctest time allowance never reaches its @finally, and
# Windows does not end a process's children with it: the servers the phase24
# tests start (all rooted under build/phase24-temp) would keep their ports.
stop_phase24_orphans() {
  powershell.exe -NoProfile -Command \
    "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*phase24-temp*' } | ForEach-Object { try { Stop-Process -Id \$_.ProcessId -Force -ErrorAction Stop } catch {} }" \
    >/dev/null 2>&1 || true
}
trap stop_phase24_orphans EXIT

make -C "$repo_root" arlen
make -C "$repo_root" phase24-windows-confidence

echo "ci: phase24 windows preview confidence complete"
