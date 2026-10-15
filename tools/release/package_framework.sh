#!/usr/bin/env bash
# Build Arlen release assets.
#
#   tools/release/package_framework.sh --version X.Y.Z --kind source [--out DIR]
#   tools/release/package_framework.sh --version X.Y.Z --kind macos-arm64 [--out DIR]
#
# Kinds:
#   source       arlen-X.Y.Z.tar.gz: the tagged tree plus the vendored
#                tools-xctest submodule, without .git. tools/install.sh builds
#                it on Linux (and on Intel Macs) against the user's toolchain.
#   macos-arm64  arlen-X.Y.Z-macos-arm64.tar.gz: the same tree with prebuilt
#                Apple framework tools under build/apple.
#
# Every archive unpacks to a single arlen-X.Y.Z/ directory and carries an
# .arlen-dist file naming its version, kind, and commit. The script also
# appends the archive's checksum to DIR/SHA256SUMS.
#
# Must stay bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version=""
kind=""
out_dir="$repo_root/build/dist"

usage() {
  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --kind) kind="${2:-}"; shift 2 ;;
    --out) out_dir="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "package_framework: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$version" || -z "$kind" ]]; then
  echo "package_framework: --version and --kind are required" >&2
  exit 2
fi
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "package_framework: version must look like X.Y.Z (got '$version')" >&2; exit 2 ;;
esac

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Submodules that ship to users. vendor/gnustep-cli-new only provisions CI
# runners, so it stays out of release archives.
shipped_submodules="vendor/tools-xctest"

stage_source_tree() {
  local dest="$1"
  local commit
  local sub

  commit="$(git -C "$repo_root" rev-parse HEAD)"
  mkdir -p "$dest"
  git -C "$repo_root" archive --format=tar HEAD | tar -xf - -C "$dest"

  for sub in $shipped_submodules; do
    if [[ ! -e "$repo_root/$sub/.git" ]]; then
      echo "package_framework: submodule $sub is not checked out; run 'git submodule update --init $sub'" >&2
      return 1
    fi
    mkdir -p "$dest/$sub"
    git -C "$repo_root/$sub" archive --format=tar HEAD | tar -xf - -C "$dest/$sub"
  done

  {
    printf 'version=%s\n' "$version"
    printf 'kind=%s\n' "$kind"
    printf 'commit=%s\n' "$commit"
  } >"$dest/.arlen-dist"
}

package_source() {
  local stage_root="$1"
  stage_source_tree "$stage_root/arlen-$version"
}

package_macos_arm64() {
  local stage_root="$1"
  if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "package_framework: macos-arm64 archives must be built on an arm64 Mac" >&2
    return 1
  fi
  local dest="$stage_root/arlen-$version"
  stage_source_tree "$dest"

  # Build inside the staged tree so the archive matches its own sources.
  # Target macOS 14 so archives built on newer runners still run on Sonoma.
  echo "package_framework: building build/apple (bin/build-apple --with-boomhauer)"
  MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
    "$dest/bin/build-apple" --with-boomhauer >"$stage_root/build-apple.log" 2>&1 || {
    tail -50 "$stage_root/build-apple.log" >&2
    echo "package_framework: bin/build-apple failed" >&2
    return 1
  }
  if [[ ! -x "$dest/build/apple/boomhauer" ]]; then
    echo "package_framework: bin/build-apple did not produce build/apple/boomhauer" >&2
    return 1
  fi

  # Objects, depfiles, and generated template sources only serve incremental
  # rebuilds, and their recorded paths point into this staging directory.
  rm -rf "$dest/build/apple/obj" "$dest/build/apple/gen"

  # shellcheck source=tools/platform.sh
  source "$dest/tools/platform.sh"
  # shellcheck source=tools/apple_build_cache.sh
  source "$dest/tools/apple_build_cache.sh"
  local openssl_prefix="${ARLEN_OPENSSL_PREFIX:-}"
  if [[ -z "$openssl_prefix" ]]; then
    openssl_prefix="$(aln_platform_first_brew_prefix openssl@3)"
  fi
  aln_apple_release_write_manifest "$dest" "$openssl_prefix"
}

case "$kind" in
  source) archive_name="arlen-$version.tar.gz" ;;
  macos-arm64) archive_name="arlen-$version-macos-arm64.tar.gz" ;;
  *) echo "package_framework: unknown --kind '$kind' (source, macos-arm64)" >&2; exit 2 ;;
esac

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-dist.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT

case "$kind" in
  source) package_source "$stage_root" ;;
  macos-arm64) package_macos_arm64 "$stage_root" ;;
esac

archive_path="$out_dir/$archive_name"
rm -f "$archive_path"
tar -C "$stage_root" -czf "$archive_path" "arlen-$version"

sums_path="$out_dir/SHA256SUMS"
if [[ -f "$sums_path" ]]; then
  grep -v "  $archive_name\$" "$sums_path" >"$sums_path.tmp" || true
  mv "$sums_path.tmp" "$sums_path"
fi
printf '%s  %s\n' "$(sha256_of "$archive_path")" "$archive_name" >>"$sums_path"

echo "package_framework: wrote $archive_path"
