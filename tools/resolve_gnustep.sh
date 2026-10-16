#!/usr/bin/env bash
set -euo pipefail

default_gnustep_sh="/usr/GNUstep/System/Library/Makefiles/GNUstep.sh"
clang64_gnustep_sh="/clang64/share/GNUstep/Makefiles/GNUstep.sh"

print_path() {
  local path="$1"
  # MSYS2 rewrites path-like variables (GNUSTEP_MAKEFILES) to C:/... when a
  # native Windows process (xctest, an app) starts a shell. Print one spelling
  # so callers that hash this path (the framework build-flags sentinel) agree;
  # otherwise each spelling deletes the other's sentinel and rebuilds everything.
  if [[ "$path" =~ ^[A-Za-z]:[\\/] ]]; then
    # /usr/bin/cygpath too: callers may run this with a PATH that omits it.
    local cygpath_bin
    cygpath_bin="$(command -v cygpath 2>/dev/null || true)"
    [[ -z "$cygpath_bin" && -x /usr/bin/cygpath ]] && cygpath_bin=/usr/bin/cygpath
    if [[ -n "$cygpath_bin" ]]; then
      path="$("$cygpath_bin" -u "$path")"
    fi
  fi
  printf '%s\n' "$path"
}

candidate_from_makefiles() {
  local makefiles_path="${1:-}"
  if [[ -z "$makefiles_path" ]]; then
    return 1
  fi
  print_path "${makefiles_path%/}/GNUstep.sh"
}

if [[ -n "${GNUSTEP_SH:-}" ]]; then
  if [[ -f "$GNUSTEP_SH" ]]; then
    print_path "$GNUSTEP_SH"
    exit 0
  fi
fi

if [[ -n "${GNUSTEP_MAKEFILES:-}" ]]; then
  candidate="$(candidate_from_makefiles "$GNUSTEP_MAKEFILES")"
  if [[ -f "$candidate" ]]; then
    print_path "$candidate"
    exit 0
  fi
fi

if command -v gnustep-config >/dev/null 2>&1; then
  makefiles_path="$(gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null || true)"
  makefiles_path="${makefiles_path//$'\r'/}"
  while [[ "$makefiles_path" == *$'\n' ]]; do
    makefiles_path="${makefiles_path%$'\n'}"
  done
  if [[ -n "$makefiles_path" ]]; then
    candidate="$(candidate_from_makefiles "$makefiles_path")"
    if [[ -f "$candidate" ]]; then
      print_path "$candidate"
      exit 0
    fi
  fi
fi

if [[ -f "$clang64_gnustep_sh" ]]; then
  print_path "$clang64_gnustep_sh"
  exit 0
fi

if [[ -f "$default_gnustep_sh" ]]; then
  print_path "$default_gnustep_sh"
  exit 0
fi

# Managed toolchains installed by gnustep-cli (`gnustep setup --user` or
# `--system`), used when there is no /usr/GNUstep toolchain.
for managed_root in "${HOME:-}/.local/share/gnustep-cli" /opt/gnustep-cli; do
  candidate="$managed_root/System/Library/Makefiles/GNUstep.sh"
  if [[ -n "$managed_root" && -f "$candidate" ]]; then
    print_path "$candidate"
    exit 0
  fi
done

print_path "$default_gnustep_sh"

exit 1
