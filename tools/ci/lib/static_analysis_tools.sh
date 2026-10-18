#!/usr/bin/env bash
# Source-only helper shared by the static-analysis gate lanes.

# Prints the path of an LLVM tool. Order: the explicit override (if non-empty),
# the unversioned name on PATH, then the name suffixed with the major version
# of the `clang` on PATH (Debian/Ubuntu ship e.g. scan-build-19 and
# intercept-build-19 in clang-tools-19). Returns 1 when nothing is found.
aln_static_resolve_llvm_tool() {
  local name="$1"
  local override="${2:-}"
  local major

  if [[ -n "$override" ]]; then
    command -v "$override" 2>/dev/null || return 1
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  major="$(clang -dumpversion 2>/dev/null | cut -d. -f1)"
  if [[ -n "$major" ]] && command -v "$name-$major" >/dev/null 2>&1; then
    command -v "$name-$major"
    return 0
  fi
  return 1
}

# The lanes analyze every first-party translation unit, so they always start
# from an empty build/ directory.
aln_static_clean_build_dir() {
  local repo_root="$1"
  rm -rf "$repo_root/build"
}
