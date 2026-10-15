#!/usr/bin/env bash
# Install an Arlen release and put an `arlen` command on your PATH.
#
#   curl -fsSL https://github.com/danjboyd/Arlen/releases/latest/download/install.sh | bash
#   curl -fsSL https://github.com/danjboyd/Arlen/releases/latest/download/install.sh | bash -s -- --version 0.2.1
#
# Options:
#   --version X.Y.Z   release to install (default: the latest release)
#   --prefix DIR      where releases are unpacked (default: ~/.local/share/arlen)
#   --bin-dir DIR     where the `arlen` launcher goes (default: ~/.local/bin)
#   --archive FILE    install from a downloaded release archive instead
#   --no-build        unpack only; skip the one-time framework build
#
# Linux:  the archive is built once against your clang-built GNUstep
#         toolchain (about a minute). See docs/GETTING_STARTED.md for getting
#         that toolchain.
# macOS:  Apple Silicon only; gets prebuilt framework tools. Needs the Xcode
#         Command Line Tools and Homebrew openssl@3 and libpq; see
#         docs/GETTING_STARTED_MACOS.md. Intel Macs are not supported yet.
#
# Must stay bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

repo_slug="danjboyd/Arlen"
version=""
prefix="${HOME}/.local/share/arlen"
bin_dir="${HOME}/.local/bin"
archive=""
do_build=1

say() { printf 'arlen-install: %s\n' "$*"; }
die() { printf 'arlen-install: error: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,21p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --prefix) prefix="${2:-}"; shift 2 ;;
    --bin-dir) bin_dir="${2:-}"; shift 2 ;;
    --archive) archive="${2:-}"; shift 2 ;;
    --no-build) do_build=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done
version="${version#v}"

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found"; }
need tar
need uname

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux) platform="linux" ;;
  Darwin) platform="macos" ;;
  *) die "unsupported OS '$os'. Windows uses the CLANG64 preview path: docs/WINDOWS_CLANG64.md" ;;
esac

# The Apple build scripts target arm64 only (-arch arm64), so Intel Macs are
# not supported yet.
if [[ "$platform" == "macos" && "$arch" != "arm64" ]]; then
  die "macOS on $arch is not supported; Arlen's Apple build targets Apple Silicon (arm64) only"
fi

# Apple Silicon gets the prebuilt archive; Linux builds the source one.
if [[ "$platform" == "macos" && "$arch" == "arm64" ]]; then
  asset_suffix="-macos-arm64"
  prebuilt=1
else
  asset_suffix=""
  prebuilt=0
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/arlen-install.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

if [[ -z "$archive" ]]; then
  need curl
  if [[ -z "$version" ]]; then
    latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo_slug/releases/latest")" ||
      die "could not look up the latest release"
    version="${latest_url##*/}"
    version="${version#v}"
    case "$version" in
      [0-9]*.[0-9]*.[0-9]*) ;;
      *) die "could not determine the latest release version (got '$version')" ;;
    esac
  fi
  asset="arlen-$version$asset_suffix.tar.gz"
  base_url="https://github.com/$repo_slug/releases/download/v$version"
  say "downloading Arlen $version ($asset)"
  curl -fSL --progress-bar -o "$work_dir/$asset" "$base_url/$asset" ||
    die "download failed: $base_url/$asset"
  curl -fsSL -o "$work_dir/SHA256SUMS" "$base_url/SHA256SUMS" ||
    die "download failed: $base_url/SHA256SUMS"
  expected="$(awk -v name="$asset" '$2 == name {print $1}' "$work_dir/SHA256SUMS")"
  [[ -n "$expected" ]] || die "SHA256SUMS has no entry for $asset"
  actual="$(sha256_of "$work_dir/$asset")"
  [[ "$expected" == "$actual" ]] || die "checksum mismatch for $asset (expected $expected, got $actual)"
  say "checksum verified"
  archive="$work_dir/$asset"
else
  [[ -f "$archive" ]] || die "archive not found: $archive"
fi

say "unpacking"
mkdir -p "$work_dir/unpack"
tar -xzf "$archive" -C "$work_dir/unpack"
top="$(cd "$work_dir/unpack" && ls)"
[[ -f "$work_dir/unpack/$top/.arlen-dist" ]] || die "$archive is not an Arlen release archive"
archive_version="$(awk -F= '$1 == "version" {print $2}' "$work_dir/unpack/$top/.arlen-dist")"
[[ -n "$archive_version" ]] || die "$archive has no version in .arlen-dist"
version="$archive_version"

mkdir -p "$prefix"
dest="$prefix/$version"
if [[ -e "$dest" ]]; then
  say "replacing existing $dest"
  rm -rf "$dest"
fi
mv "$work_dir/unpack/$top" "$dest"

if [[ "$platform" == "macos" ]]; then
  # Browser downloads carry the quarantine flag; curl and tar do not.
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
fi

if [[ $do_build -eq 1 ]]; then
  if [[ "$platform" == "linux" ]]; then
    # shellcheck disable=SC1091
    if ! ( source "$dest/tools/source_gnustep_env.sh" >/dev/null 2>&1 &&
           gnustep-config --objc-flags 2>/dev/null | grep -q -- '-fobjc-runtime=gnustep-2.2' ); then
      cat >&2 <<EOF
arlen-install: error: no clang-built GNUstep toolchain was found.

Arlen needs clang + libobjc2 + gnustep-base. The quickest way to get them on
Debian 13 or Ubuntu 26.04 LTS is the managed toolchain from gnustep-cli
(no root needed), plus the OpenSSL headers:

  curl -fsSL https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0/gnustep-bootstrap.sh | sh -s -- --yes setup --user
  sudo apt-get install -y libssl-dev

Then rerun this installer. Arlen $version is unpacked at $dest; to finish by
hand, run: $dest/bin/arlen doctor
EOF
      exit 1
    fi
    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    say "building the framework once against your GNUstep toolchain (make -j$jobs all)"
    # shellcheck disable=SC1091
    ( source "$dest/tools/source_gnustep_env.sh" >/dev/null && make -C "$dest" -j"$jobs" all >"$dest/build-install.log" 2>&1 ) ||
      die "framework build failed; see $dest/build-install.log"
  elif [[ $prebuilt -eq 0 ]]; then
    say "building the framework once with Apple clang (bin/build-apple)"
    "$dest/bin/build-apple" >"$dest/build-install.log" 2>&1 ||
      die "framework build failed; see $dest/build-install.log"
  fi
fi

ln -sfn "$version" "$prefix/current"

mkdir -p "$bin_dir"
launcher="$bin_dir/arlen"
cat >"$launcher" <<EOF
#!/usr/bin/env bash
# Installed by Arlen's tools/install.sh. Set ARLEN_HOME to use another install.
arlen_home="\${ARLEN_HOME:-$prefix/current}"
# Apps live outside the install, so arlen cannot find the framework by walking
# up from the app directory.
export ARLEN_FRAMEWORK_ROOT="\${ARLEN_FRAMEWORK_ROOT:-\$arlen_home}"
if [[ "\$(uname -s)" != "Darwin" ]]; then
  # shellcheck disable=SC1091
  source "\$arlen_home/tools/source_gnustep_env.sh" >/dev/null || exit 1
fi
exec "\$arlen_home/bin/arlen" "\$@"
EOF
chmod 755 "$launcher"

say "installed Arlen $version at $dest"
say "launcher: $launcher"
# Name the startup file the user's login shell actually reads: zsh (the macOS
# default) ignores ~/.profile, and macOS Terminal starts bash as a login shell.
case "$(basename "${SHELL:-}")" in
  zsh) shell_rc="~/.zprofile" ;;
  bash) if [[ "$platform" == "macos" ]]; then shell_rc="~/.bash_profile"; else shell_rc="~/.bashrc"; fi ;;
  *) shell_rc="~/.profile" ;;
esac
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) say "add $bin_dir to your PATH, for example: echo 'export PATH=\"$bin_dir:\$PATH\"' >> $shell_rc" ;;
esac
cat <<EOF

Next:
  arlen doctor
  arlen new MyApp && cd MyApp && arlen boomhauer --port 3000
EOF
