#!/usr/bin/env bash
# Source-only helper. Implements a deprecated-name compat wrapper for CI lane
# scripts that have been renamed from phase-numbered to capability-named.
#
# Usage from a wrapper script (one example):
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$script_dir/lib/run_lane_compat.sh"
#   aln_lane_compat_exec "run_apple_baseline_confidence.sh" "$@"

aln_lane_compat_exec() {
  local target="$1"
  shift
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  local self_name
  self_name="$(basename "${BASH_SOURCE[1]}")"
  echo "[ci-compat] $self_name is deprecated; invoke $target instead" >&2
  exec bash "$script_dir/$target" "$@"
}
