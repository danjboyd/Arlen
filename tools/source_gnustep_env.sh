#!/usr/bin/env bash

_aln_source_gnustep_env_main() {
  local script_path="${BASH_SOURCE[0]}"
  local script_dir
  local resolved_gnustep_sh
  local restore_nounset=0

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "source_gnustep_env.sh must be sourced, not executed" >&2
    exit 1
  fi

  if resolved="$(readlink -f "$script_path" 2>/dev/null)"; then
    script_path="$resolved"
  fi
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"

  resolved_gnustep_sh="$(bash "$script_dir/resolve_gnustep.sh" 2>/dev/null || true)"
  if [[ -z "$resolved_gnustep_sh" ]]; then
    resolved_gnustep_sh="${GNUSTEP_SH:-/usr/GNUstep/System/Library/Makefiles/GNUstep.sh}"
  fi

  if [[ ! -f "$resolved_gnustep_sh" ]]; then
    echo "Arlen: GNUstep.sh not found at $resolved_gnustep_sh" >&2
    echo "Arlen: set GNUSTEP_SH, export GNUSTEP_MAKEFILES, or source your toolchain env script first" >&2
    return 1
  fi

  export GNUSTEP_SH="$resolved_gnustep_sh"

  case $- in
    *u*) restore_nounset=1 ;;
  esac

  set +u
  # shellcheck disable=SC1090
  source "$resolved_gnustep_sh"
  if [[ $restore_nounset -eq 1 ]]; then
    set -u
  fi
}

_aln_source_gnustep_env_main "$@"
unset -f _aln_source_gnustep_env_main
