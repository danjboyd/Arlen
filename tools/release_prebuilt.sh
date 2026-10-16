#!/usr/bin/env bash
# Prebuilt-release helpers for the make (GNU) build path: Windows CLANG64
# release archives (tools/release/package_framework.sh --kind windows-x64).
#
# The archive ships build/arlen.exe, build/boomhauer.exe, build/eocc.exe and
# build/lib/libArlenFramework.a without build/obj, plus build/.release-prebuilt.
# Without objects and depfiles, `make -q` would call the framework stale and
# rebuild it on the user's first command. So, as tools/apple_build_cache.sh
# does for build/apple, the prebuilt outputs are trusted while the build
# inputs and the toolchain still match the manifest. Any mismatch removes the
# manifest, and the normal make checks take over from then on.
#
# Manifest (build/.release-prebuilt), one key=value per line:
#   source_digest=      SHA-256 over every build input (aln_release_source_digest)
#   toolchain=          gnustep-cli toolchain_version (state/cli-state.json)
#   toolchain_sha256=   gnustep-cli toolchain_artifact_sha256
# A toolchain= mismatch is stale. A toolchain_sha256= mismatch alone is only
# reported (a republished toolchain can keep its version).
#
# Must stay compatible with macOS /bin/bash 3.2.

# aln_release_source_digest <repo_root>
# SHA-256 over the per-file hashes (and paths) of every input to the framework
# tools and library.
aln_release_source_digest() {
  local hasher="sha256sum"
  command -v sha256sum >/dev/null 2>&1 || hasher="shasum -a 256"
  (
    cd "$1" &&
      find src modules templates \
        tools/eocc.m tools/arlen.m tools/boomhauer.m \
        tools/resolve_gnustep.sh tools/release_prebuilt.sh \
        GNUmakefile bin/arlen bin/boomhauer \
        -type f 2>/dev/null |
      LC_ALL=C sort | tr '\n' '\0' | xargs -0 $hasher -- 2>/dev/null |
      $hasher | awk '{print $1}'
  )
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
# Writes <repo_root>/build/.release-prebuilt for the current tree and toolchain.
aln_release_write_manifest() {
  local root="$1"
  mkdir -p "$root/build"
  {
    printf 'source_digest=%s\n' "$(aln_release_source_digest "$root")"
    printf 'toolchain=%s\n' "$(aln_release_toolchain_value toolchain_version)"
    printf 'toolchain_sha256=%s\n' "$(aln_release_toolchain_value toolchain_artifact_sha256)"
  } >"$root/build/.release-prebuilt"
}

# aln_release_prebuilt_is_current <repo_root> <output...>
# True when <repo_root>/build/.release-prebuilt matches the tree and the
# toolchain and every output exists. A stale manifest is removed.
aln_release_prebuilt_is_current() {
  local root="$1"
  shift
  local manifest="$root/build/.release-prebuilt"
  [[ -f "$manifest" ]] || return 1
  local output
  for output in "$@"; do
    [[ -f "$output" ]] || { rm -f "$manifest"; return 1; }
  done
  if [[ "$(aln_release_manifest_value "$manifest" toolchain)" != "$(aln_release_toolchain_value toolchain_version)" ||
        "$(aln_release_manifest_value "$manifest" source_digest)" != "$(aln_release_source_digest "$root")" ]]; then
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
