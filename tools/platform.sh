#!/usr/bin/env bash

aln_platform_realpath() {
  local target="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$target" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MCwd=realpath -e 'print realpath($ARGV[0]), "\n"' "$target"
    return $?
  fi
  (
    cd "$(dirname "$target")" >/dev/null 2>&1 && pwd -P
  ) | awk -v base="$(basename "$target")" '{ print $0 "/" base }'
}

aln_platform_is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

aln_platform_sha256() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | awk '{print $1}'
    return $?
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha256sum | awk '{print $1}'
    return $?
  fi
  return 1
}

aln_platform_brew_prefix() {
  local formula="$1"
  if ! command -v brew >/dev/null 2>&1; then
    return 1
  fi
  brew --prefix "$formula" 2>/dev/null
}

aln_platform_first_brew_prefix() {
  local formula
  for formula in "$@"; do
    if [[ -z "$formula" ]]; then
      continue
    fi
    if prefix="$(aln_platform_brew_prefix "$formula")" && [[ -n "$prefix" ]]; then
      printf '%s\n' "$prefix"
      return 0
    fi
  done
  return 1
}
