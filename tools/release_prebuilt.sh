#!/usr/bin/env bash
# Prebuilt-release helpers for the make (GNU) build path: Windows CLANG64
# release archives (tools/release/package_framework.sh --kind windows-x64).
#
# The archive ships build/arlen.exe, build/boomhauer.exe, build/eocc.exe and
# build/lib/libArlenFramework.a without build/obj, plus build/.release-prebuilt.
# Without objects and depfiles, `make -q` would call the framework stale and
# rebuild it on the user's first command. So, as tools/apple_build_cache.sh
# does for build/apple, the prebuilt outputs are trusted while the build
# inputs, the build flags and the toolchain still match the manifest. Any
# mismatch removes the manifest, and the normal make checks take over from then
# on. The check fails closed: anything it cannot determine counts as stale.
#
# Manifest (build/.release-prebuilt), one key=value per line:
#   source_digest=      SHA-256 over every build input (aln_release_source_digest)
#   build_flags=        the flag environment the GNUmakefile's build-flags
#                       sentinel tracks (aln_release_build_flags)
#   toolchain=          gnustep-cli toolchain_version (state/cli-state.json)
#   toolchain_sha256=   gnustep-cli toolchain_artifact_sha256
# A source_digest=, build_flags= or toolchain= mismatch is stale, as is an empty
# source_digest= or toolchain=. A toolchain_sha256= mismatch alone is only
# reported (a republished toolchain can keep its version).
#
# Must stay compatible with macOS /bin/bash 3.2.

# aln_release_source_digest <repo_root>
# SHA-256 over the per-file hashes (and paths) of every input to the framework
# tools and library. Prints nothing and fails when no SHA-256 tool is found.
aln_release_source_digest() {
  local hasher
  if command -v sha256sum >/dev/null 2>&1; then
    hasher="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    hasher="shasum -a 256"
  else
    return 1
  fi
  (
    cd "$1" &&
      find src modules templates \
        tools/eocc.m tools/arlen.m tools/boomhauer.m tools/ALNWindowsWatchChild.h \
        tools/resolve_gnustep.sh tools/release_prebuilt.sh \
        GNUmakefile bin/arlen bin/boomhauer \
        -type f 2>/dev/null |
      LC_ALL=C sort | tr '\n' '\0' | xargs -0 $hasher -- 2>/dev/null |
      $hasher | awk '{print $1}'
  )
}

# aln_release_build_flags
# The environment overrides the GNUmakefile feeds into BUILD_FLAGS_SENTINEL_INPUT
# (GNUSTEP_SH is covered by toolchain=). boomhauer compiles apps with the same
# variables, so an app built with ARLEN_ENABLE_LLHTTP=1 must not link a library
# built without it.
aln_release_build_flags() {
  printf 'yyjson=%s|llhttp=%s|extra=%s\n' \
    "${ARLEN_ENABLE_YYJSON:-}" "${ARLEN_ENABLE_LLHTTP:-}" "${EXTRA_OBJC_FLAGS:-}"
}

# aln_release_toolchain_state_file
# The gnustep-cli managed root's state file, when this shell runs in one
# (the managed root is the MSYS2 root, so it is /state/cli-state.json).
aln_release_toolchain_state_file() {
  local candidate="${ARLEN_TOOLCHAIN_STATE_FILE:-/state/cli-state.json}"
  [[ -f "$candidate" ]] && printf '%s\n' "$candidate"
}

# aln_release_toolchain_value <key>
# A top-level string from cli-state.json (toolchain_version,
# toolchain_artifact_sha256); empty when unknown. No python or jq: the CLANG64
# python prints CRLF and is slow to start.
aln_release_toolchain_value() {
  local state
  state="$(aln_release_toolchain_state_file)" || return 0
  tr -d '\r' <"$state" |
    sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

# aln_release_manifest_value <manifest> <key>
aln_release_manifest_value() {
  awk -F= -v key="$2" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$1"
}

# aln_release_write_manifest <repo_root>
# Writes <repo_root>/build/.release-prebuilt for the current tree, flags and
# toolchain. Fails (writing nothing) when the source digest or the toolchain
# version cannot be determined, since such a manifest could never be trusted.
aln_release_write_manifest() {
  local root="$1"
  local digest toolchain
  digest="$(aln_release_source_digest "$root")" || digest=""
  toolchain="$(aln_release_toolchain_value toolchain_version)"
  if [[ -z "$digest" ]]; then
    echo "aln_release_write_manifest: no SHA-256 tool (sha256sum or shasum) to digest $root" >&2
    return 1
  fi
  if [[ -z "$toolchain" ]]; then
    echo "aln_release_write_manifest: no gnustep-cli toolchain_version (state/cli-state.json)" >&2
    return 1
  fi
  mkdir -p "$root/build"
  {
    printf 'source_digest=%s\n' "$digest"
    printf 'build_flags=%s\n' "$(aln_release_build_flags)"
    printf 'toolchain=%s\n' "$toolchain"
    printf 'toolchain_sha256=%s\n' "$(aln_release_toolchain_value toolchain_artifact_sha256)"
  } >"$root/build/.release-prebuilt"
}

# aln_release_prebuilt_is_current <repo_root> <output...>
# True when <repo_root>/build/.release-prebuilt matches the tree, the build
# flags and the toolchain and every output exists. A stale manifest is removed.
aln_release_prebuilt_is_current() {
  local root="$1"
  shift
  local manifest="$root/build/.release-prebuilt"
  [[ -f "$manifest" ]] || return 1
  local output
  for output in "$@"; do
    [[ -f "$output" ]] || { rm -f "$manifest"; return 1; }
  done
  local recorded_digest current_digest recorded_toolchain current_toolchain
  recorded_digest="$(aln_release_manifest_value "$manifest" source_digest)"
  current_digest="$(aln_release_source_digest "$root")" || current_digest=""
  recorded_toolchain="$(aln_release_manifest_value "$manifest" toolchain)"
  current_toolchain="$(aln_release_toolchain_value toolchain_version)"
  if [[ -z "$recorded_digest" || -z "$current_digest" || "$recorded_digest" != "$current_digest" ||
        -z "$recorded_toolchain" || -z "$current_toolchain" || "$recorded_toolchain" != "$current_toolchain" ||
        "$(aln_release_manifest_value "$manifest" build_flags)" != "$(aln_release_build_flags)" ]]; then
    rm -f "$manifest"
    return 1
  fi
  local recorded_sha current_sha
  recorded_sha="$(aln_release_manifest_value "$manifest" toolchain_sha256)"
  current_sha="$(aln_release_toolchain_value toolchain_artifact_sha256)"
  if [[ -n "$recorded_sha" && -n "$current_sha" && "$recorded_sha" != "$current_sha" ]]; then
    echo "arlen: prebuilt framework was built with toolchain artifact $recorded_sha; this toolchain is $current_sha (same version, using the prebuilt build)" >&2
  fi
  return 0
}
