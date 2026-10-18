#!/usr/bin/env bash
# Build Arlen release assets.
#
#   tools/release/package_framework.sh --version X.Y.Z --kind source [--out DIR]
#   tools/release/package_framework.sh --version X.Y.Z --kind macos-arm64 [--out DIR]
#   tools/release/package_framework.sh --version X.Y.Z --kind windows-x64 [--out DIR]
#
# Kinds:
#   source       arlen-X.Y.Z.tar.gz: the tagged tree plus the vendored
#                tools-xctest submodule, without .git. tools/install.sh builds
#                it on Linux (and on Intel Macs) against the user's toolchain.
#   macos-arm64  arlen-X.Y.Z-macos-arm64.tar.gz: the same tree with prebuilt
#                Apple framework tools under build/apple.
#   windows-x64  arlen-X.Y.Z-windows-x64.zip: the same tree with the prebuilt
#                framework tools and library under build/, built inside the
#                gnustep-cli managed MSYS2 CLANG64 shell. tools/install.ps1
#                installs it.
#
# Every archive unpacks to a single arlen-X.Y.Z/ directory and carries an
# .arlen-dist file naming its version, kind, and commit (windows-x64 also names
# the gnustep-cli toolchain it was built against). The script also appends the
# archive's checksum to DIR/SHA256SUMS.
#
# Must stay bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version=""
kind=""
out_dir="$repo_root/build/dist"

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# git, or $ARLEN_GIT. MSYS2's default minimal PATH drops the Windows PATH, so
# inside the CLANG64 shell fall back to Git for Windows' standard location.
git_cmd="${ARLEN_GIT:-git}"
if [[ -z "${ARLEN_GIT:-}" ]] && ! command -v git >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  git_for_windows="$(cygpath -u "${PROGRAMFILES:-C:/Program Files}")/Git/cmd/git.exe"
  if [[ -x "$git_for_windows" ]]; then
    git_cmd="$git_for_windows"
  fi
fi

stage_source_tree() {
  local dest="$1"
  local commit
  local sub

  commit="$("$git_cmd" -C "$repo_root" rev-parse HEAD)"
  mkdir -p "$dest"
  "$git_cmd" -C "$repo_root" archive --format=tar HEAD | tar -xf - -C "$dest"

  for sub in $shipped_submodules; do
    if [[ ! -e "$repo_root/$sub/.git" ]]; then
      echo "package_framework: submodule $sub is not checked out; run 'git submodule update --init $sub'" >&2
      return 1
    fi
    mkdir -p "$dest/$sub"
    "$git_cmd" -C "$repo_root/$sub" archive --format=tar HEAD | tar -xf - -C "$dest/$sub"
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

# Prebuilt outputs a Windows install needs, relative to build/. Everything else
# under build/ (objects, depfiles, test bundles) only serves incremental
# rebuilds, which build/.release-prebuilt makes unnecessary.
windows_prebuilt_outputs="arlen.exe boomhauer.exe eocc.exe lib/libArlenFramework.a"
windows_prebuilt_optional_dirs="gen module-gen"

package_windows_x64() {
  local stage_root="$1"
  if [[ "${MSYSTEM:-}" != "CLANG64" ]]; then
    echo "package_framework: windows-x64 archives must be built in the gnustep-cli MSYS2 CLANG64 shell (scripts/run_clang64.ps1)" >&2
    return 1
  fi
  if ! command -v bsdtar >/dev/null 2>&1; then
    echo "package_framework: windows-x64 archives need bsdtar to write the zip" >&2
    return 1
  fi
  local dest="$stage_root/arlen-$version"
  stage_source_tree "$dest"

  # shellcheck source=tools/release_prebuilt.sh
  source "$dest/tools/release_prebuilt.sh"
  local toolchain toolchain_sha256
  toolchain="$(aln_release_toolchain_value toolchain_version)"
  toolchain_sha256="$(aln_release_toolchain_value toolchain_artifact_sha256)"
  if [[ -z "$toolchain" ]]; then
    echo "package_framework: no gnustep-cli toolchain_version (looked for $(aln_release_toolchain_state_file || echo "${ARLEN_TOOLCHAIN_STATE_FILE:-/state/cli-state.json}")); build inside the managed toolchain" >&2
    return 1
  fi
  {
    printf 'toolchain=%s\n' "$toolchain"
    printf 'toolchain_sha256=%s\n' "$toolchain_sha256"
  } >>"$dest/.arlen-dist"

  # Build inside the staged tree so the archive matches its own sources.
  local jobs
  jobs="$(nproc 2>/dev/null || echo 2)"
  echo "package_framework: building build/ (make -j$jobs all) against gnustep-cli toolchain $toolchain"
  make -C "$dest" -j"$jobs" all >"$stage_root/make.log" 2>&1 || {
    tail -50 "$stage_root/make.log" >&2
    echo "package_framework: make all failed" >&2
    return 1
  }

  local full="$stage_root/build.full"
  local output
  mv "$dest/build" "$full"
  mkdir -p "$dest/build/lib"
  for output in $windows_prebuilt_outputs; do
    if [[ ! -f "$full/$output" ]]; then
      echo "package_framework: make all did not produce build/$output" >&2
      return 1
    fi
    mv "$full/$output" "$dest/build/$output"
  done
  for output in $windows_prebuilt_optional_dirs; do
    if [[ -d "$full/$output" ]]; then
      mv "$full/$output" "$dest/build/$output"
    fi
  done
  rm -rf "$full"

  bundle_windows_dlls "$stage_root" "$dest/build/dll" "$toolchain" "$toolchain_sha256"

  # Last: the manifest digests the staged sources, so nothing may change after it.
  aln_release_write_manifest "$dest"
}

# windows_bundled_dll_lines <list> <toolchain> <toolchain_sha256>
# Prints the `dll ...` lines of the list's section for exactly this toolchain
# (a `toolchain <version> <sha256>` line starts a section). Fails, naming the
# sections it has, when there is none.
windows_bundled_dll_lines() {
  local list="$1" toolchain="$2" toolchain_sha256="$3"
  awk -v want="$toolchain $toolchain_sha256" '
    $1 == "toolchain" { section = $2 " " $3; known = known "\n  " $2 " (" $3 ")"; if (section == want) found = 1; next }
    $1 == "dll" && section == want { print }
    $1 != "" && $1 !~ /^#/ && $1 != "toolchain" && $1 != "dll" { printf "package_framework: unknown line kind %s in the bundled DLL list\n", $1 > "/dev/stderr"; bad = 1 }
    END {
      if (bad) exit 2
      if (!found) { printf "package_framework: the bundled DLL list has no section for toolchain %s; it has:%s\nre-derive the DLLs for this toolchain\n", want, known > "/dev/stderr"; exit 1 }
    }' "$list"
}

# bundle_windows_dlls <stage_root> <dll_dir> <toolchain> <toolchain_sha256>
# Downloads each package pinned for this toolchain in
# tools/release/windows_bundled_dlls.txt, verifies it and the extracted DLL by
# sha256, and checks that every import of a bundled DLL is bundled, in the
# toolchain's clang64/bin, or a system DLL.
bundle_windows_dlls() {
  local stage_root="$1"
  local dll_dir="$2"
  local toolchain="$3"
  local toolchain_sha256="$4"
  local list="$repo_root/tools/release/windows_bundled_dlls.txt"
  local cache="${ARLEN_WINDOWS_PACKAGE_CACHE:-$stage_root/pkg-cache}"
  local kind url pkg_sha member member_sha pkg name dll import lower
  local bundled=""

  local lines
  lines="$(windows_bundled_dll_lines "$list" "$toolchain" "$toolchain_sha256")" || return 1
  mkdir -p "$dll_dir" "$cache"
  while read -r kind url pkg_sha member member_sha; do
    case "$kind" in
      dll)
        pkg="$cache/$(basename "$url")"
        if [[ ! -f "$pkg" || "$(sha256_of "$pkg")" != "$pkg_sha" ]]; then
          echo "package_framework: downloading $url"
          curl -fsSL --retry 3 -o "$pkg" "$url"
        fi
        if [[ "$(sha256_of "$pkg")" != "$pkg_sha" ]]; then
          echo "package_framework: $(basename "$pkg") does not match its pinned sha256" >&2
          return 1
        fi
        name="$(basename "$member")"
        bsdtar -xOf "$pkg" "$member" >"$dll_dir/$name"
        if [[ "$(sha256_of "$dll_dir/$name")" != "$member_sha" ]]; then
          echo "package_framework: $member from $(basename "$pkg") does not match its pinned sha256" >&2
          return 1
        fi
        bundled="$bundled $(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
        ;;
    esac
  done <<<"$lines"

  local system_dir
  system_dir="$(cygpath -u "${SYSTEMROOT:-C:/Windows}")/System32"
  for dll in "$dll_dir"/*.dll; do
    [[ -f "$dll" ]] || continue
    for import in $(llvm-readobj --coff-imports "$dll" | sed -n 's/^ *Name: //p' | tr -d '\r' | sort -u); do
      lower="$(printf '%s' "$import" | tr '[:upper:]' '[:lower:]')"
      case " $bundled " in *" $lower "*) continue ;; esac
      case "$lower" in api-ms-win-*|ext-ms-win-*) continue ;; esac
      if [[ -n "$(find /clang64/bin "$system_dir" -maxdepth 1 -iname "$import" -print -quit 2>/dev/null)" ]]; then
        continue
      fi
      echo "package_framework: $(basename "$dll") imports $import, which is not bundled, not in the toolchain's clang64/bin, and not a system DLL" >&2
      return 1
    done
  done
  echo "package_framework: bundled into build/dll:$bundled"
}

case "$kind" in
  source) archive_name="arlen-$version.tar.gz" ;;
  macos-arm64) archive_name="arlen-$version-macos-arm64.tar.gz" ;;
  windows-x64) archive_name="arlen-$version-windows-x64.zip" ;;
  *) echo "package_framework: unknown --kind '$kind' (source, macos-arm64, windows-x64)" >&2; exit 2 ;;
esac

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-dist.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT

case "$kind" in
  source) package_source "$stage_root" ;;
  macos-arm64) package_macos_arm64 "$stage_root" ;;
  windows-x64) package_windows_x64 "$stage_root" ;;
esac

archive_path="$out_dir/$archive_name"
rm -f "$archive_path"
case "$kind" in
  windows-x64) bsdtar -a -cf "$archive_path" -C "$stage_root" "arlen-$version" ;;
  *) tar -C "$stage_root" -czf "$archive_path" "arlen-$version" ;;
esac

sums_path="$out_dir/SHA256SUMS"
if [[ -f "$sums_path" ]]; then
  grep -v "  $archive_name\$" "$sums_path" >"$sums_path.tmp" || true
  mv "$sums_path.tmp" "$sums_path"
fi
printf '%s  %s\n' "$(sha256_of "$archive_path")" "$archive_name" >>"$sums_path"

echo "package_framework: wrote $archive_path"
