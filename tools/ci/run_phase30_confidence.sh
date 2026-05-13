#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/run_lane_compat.sh"
aln_lane_compat_exec "run_apple_baseline_confidence.sh" "$@"
