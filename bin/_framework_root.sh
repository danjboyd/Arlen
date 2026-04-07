#!/usr/bin/env bash

arlen_runtime_has_compiled_binary() {
  local candidate="$1"
  [[ -x "$candidate" ]] || [[ "$candidate" != *.exe && -x "$candidate.exe" ]]
}

arlen_framework_root_is_checkout() {
  local root="$1"
  [[ -f "$root/GNUmakefile" ]] &&
    [[ -f "$root/tools/eocc.m" ]] &&
    [[ -d "$root/src/Arlen" ]] &&
    [[ -d "$root/src/MojoObjc" ]]
}

arlen_framework_root_is_packaged_release() {
  local root="$1"
  arlen_runtime_has_compiled_binary "$root/build/eocc" &&
    arlen_runtime_has_compiled_binary "$root/build/arlen" &&
    arlen_runtime_has_compiled_binary "$root/build/boomhauer" &&
    [[ -f "$root/build/lib/libArlenFramework.a" ]] &&
    [[ -d "$root/src/Arlen" ]] &&
    [[ -d "$root/src/MojoObjc" ]]
}

arlen_framework_root_mode() {
  local root="$1"
  if arlen_framework_root_is_checkout "$root"; then
    printf 'checkout\n'
    return 0
  fi
  if arlen_framework_root_is_packaged_release "$root"; then
    printf 'packaged\n'
    return 0
  fi
  return 1
}

arlen_validate_framework_root() {
  local tool_name="$1"
  local root="$2"
  local mode=""
  if ! mode="$(arlen_framework_root_mode "$root")"; then
    echo "$tool_name: invalid framework root: $root" >&2
    echo "$tool_name: expected an Arlen checkout or packaged release framework payload" >&2
    return 1
  fi
  printf '%s\n' "$mode"
}
