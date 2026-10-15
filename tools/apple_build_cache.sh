#!/usr/bin/env bash
# Incremental-build helpers shared by the Apple build scripts.
#
# Objects are compiled with `-MMD -MF <obj>.d`. An object is current when no
# file in its depfile (the source and its non-system headers) is newer or
# missing. A link output is current when no input is newer and the input list
# matches the last link.
#
# Must stay compatible with macOS /bin/bash 3.2.

# aln_apple_sdk_path
# Physical path of the macOS SDK. xcrun reports MacOSX.sdk or a versioned
# alias such as MacOSX26.4.sdk (a symlink to it), depending on the environment
# (xctest sets SDKROOT to the alias). The SDK path is part of the build
# fingerprint, so an unresolved path rebuilds everything when builds alternate
# between a terminal and a test run.
aln_apple_sdk_path() {
  local sdk
  sdk="$(xcrun --show-sdk-path)" || return
  (cd "$sdk" && pwd -P)
}

# aln_apple_any_newer <ref> <path...>
# True when any path is missing or has a later mtime than ref. Uses BSD find,
# which compares full-resolution mtimes; bash 3.2's -nt only compares seconds.
aln_apple_any_newer() {
  local ref="$1"
  shift
  [[ $# -gt 0 ]] || return 1
  local newer
  newer="$(find "$@" -prune -newer "$ref" 2>/dev/null)" || return 0
  [[ -n "$newer" ]]
}

# aln_apple_reset_on_flag_change <obj_root> <fingerprint-input...>
# Wipes obj_root when the compiler, flags, or other fingerprint inputs change.
aln_apple_reset_on_flag_change() {
  local obj_root="$1"
  shift
  local stamp_file="$obj_root/.build-fingerprint"
  local fingerprint
  fingerprint="$(printf '%s\n' "$@" | shasum -a 256 | awk '{print $1}')"
  if [[ -f "$stamp_file" && "$(cat "$stamp_file")" == "$fingerprint" ]]; then
    return 0
  fi
  rm -rf "$obj_root"
  mkdir -p "$obj_root"
  printf '%s\n' "$fingerprint" >"$stamp_file"
}

# aln_apple_object_is_current <src> <obj>
aln_apple_object_is_current() {
  local src="$1"
  local obj="$2"
  local depfile="${obj%.o}.d"
  [[ -f "$obj" && -f "$depfile" ]] || return 1
  [[ "$src" -nt "$obj" ]] && return 1

  # Print one dependency per line: join continuation lines, drop the target,
  # and unescape "\ " in paths.
  local deps=()
  local dep
  while IFS= read -r dep; do
    deps+=("$dep")
  done < <(awk '
    { sub(/\\$/, ""); text = text " " $0 }
    END {
      sub(/^[^:]*: /, "", text)
      gsub(/\\ /, "\001", text)
      n = split(text, parts, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (parts[i] == "") continue
        gsub(/\001/, " ", parts[i])
        print parts[i]
      }
    }' "$depfile")
  [[ ${#deps[@]} -gt 0 ]] || return 1
  ! aln_apple_any_newer "$obj" "${deps[@]}"
}

# aln_apple_link_is_current <manifest> <output> <input...>
aln_apple_link_is_current() {
  local manifest="$1"
  local output="$2"
  shift 2
  [[ -e "$output" && -f "$manifest" ]] || return 1
  [[ "$(cat "$manifest")" == "$(printf '%s\n' "$@")" ]] || return 1
  ! aln_apple_any_newer "$output" "$@"
}

# aln_apple_record_link_inputs <manifest> <input...>
aln_apple_record_link_inputs() {
  local manifest="$1"
  shift
  mkdir -p "$(dirname "$manifest")"
  printf '%s\n' "$@" >"$manifest"
}

# aln_apple_reset_generated_if_stale <gen_dir> <eocc_bin> <manifest>
# eocc reuses outputs whose template hash is unchanged. Clear them when eocc
# itself was rebuilt, since a transpiler change can change every output.
aln_apple_reset_generated_if_stale() {
  local gen_dir="$1"
  local eocc_bin="$2"
  local manifest="$3"
  if [[ -f "$manifest" ]] && ! aln_apple_any_newer "$manifest" "$eocc_bin"; then
    return 0
  fi
  rm -rf "$gen_dir"
  mkdir -p "$gen_dir"
}
