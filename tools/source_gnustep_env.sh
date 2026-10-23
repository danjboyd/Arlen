#!/usr/bin/env bash

_aln_source_gnustep_env_main() {
  local script_path="${BASH_SOURCE[0]}"
  local script_dir
  local resolved_gnustep_sh
  local restore_nounset=0
  local resolved runtime_prefix runtime_variable

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "source_gnustep_env.sh must be sourced, not executed" >&2
    exit 1
  fi

  if resolved="$(readlink -f "$script_path" 2>/dev/null)"; then
    script_path="$resolved"
  fi
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"

  runtime_prefix=""
  if [[ "${OSTYPE:-}" == linux* && -f "$script_dir/setup_runtime.py" ]]; then
    runtime_prefix="$(python3 "$script_dir/setup_runtime.py" selected)" || return 1
    if [[ -n "$runtime_prefix" ]]; then
      runtime_prefix="$(python3 "$script_dir/setup_runtime.py" check --prefix "$runtime_prefix")" || return 1
      # Remove stale GNUstep domain/host variables before sourcing another
      # prefix. A private config is explicit and must retain the prefix domains.
      for runtime_variable in ${!GNUSTEP_@}; do unset "$runtime_variable"; done
      export ARLEN_RUNTIME_PREFIX="$runtime_prefix"
      export GNUSTEP_MAKEFILES="$runtime_prefix/System/Library/Makefiles"
      export GNUSTEP_CONFIG_FILE="${ARLEN_GNUSTEP_CONFIG_FILE:-$runtime_prefix/etc/GNUstep/GNUstep.conf}"
      export PATH="$runtime_prefix/System/Tools:$runtime_prefix/Local/Tools:$runtime_prefix/bin:$PATH"
    elif [[ -f "$script_dir/../.arlen-dist" ]]; then
      echo "Arlen: this Linux release requires its patched runtime. Run python3 $script_dir/setup_runtime.py build, or select --prefix /final/patched/prefix." >&2
      return 1
    fi
  fi

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
  if ! source "$resolved_gnustep_sh"; then
    [[ $restore_nounset -eq 0 ]] || set -u
    return 1
  fi

  # gnustep-cli managed toolchains keep libdispatch and other non-GNUstep
  # libraries in <root>/lib, which GNUstep.sh does not add to the search path.
  local managed_root
  managed_root="$(cd "$(dirname "$resolved_gnustep_sh")/../../.." 2>/dev/null && pwd)"
  if [[ -n "$managed_root" && -f "$managed_root/toolchain-manifest.json" && -d "$managed_root/lib" ]]; then
    case ":${LD_LIBRARY_PATH:-}:" in
      *":$managed_root/lib:"*) ;;
      *) export LD_LIBRARY_PATH="$managed_root/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
    esac
  fi

  if [[ -n "$runtime_prefix" ]]; then
    # Put all selected runtime libraries ahead of ambient/user library domains.
    export LD_LIBRARY_PATH="$runtime_prefix/lib:$runtime_prefix/Local/Library/Libraries:$runtime_prefix/System/Library/Libraries${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi

  if [[ $restore_nounset -eq 1 ]]; then
    set -u
  fi
}

_aln_source_gnustep_env_main "$@" || {
  unset -f _aln_source_gnustep_env_main
  return 1
}
unset -f _aln_source_gnustep_env_main
