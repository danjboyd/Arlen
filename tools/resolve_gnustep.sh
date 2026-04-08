#!/usr/bin/env bash
set -euo pipefail

default_gnustep_sh="/usr/GNUstep/System/Library/Makefiles/GNUstep.sh"
clang64_gnustep_sh="/clang64/share/GNUstep/Makefiles/GNUstep.sh"

print_path() {
  printf '%s\n' "$1"
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

print_path "$default_gnustep_sh"
if [[ -f "$default_gnustep_sh" ]]; then
  exit 0
fi

exit 1
