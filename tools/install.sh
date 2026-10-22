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
#   --no-build        unpack only; skip setup and the one-time framework build
#   --no-setup        never install prerequisites (offline/manual toolchains)
#   --no-modify-path  leave shell startup files unchanged
#   --yes             allow prerequisite installation without prompting
#
# Linux:  builds once against clang GNUstep. Supported Debian/Ubuntu hosts can
#         provision missing prerequisites with consent; use --no-setup for
#         an existing/manual toolchain. See docs/GETTING_STARTED.md.
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
do_setup=1
modify_path=1
yes=0

say() { printf 'arlen-install: %s\n' "$*"; }
die() { printf 'arlen-install: error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [--version X.Y.Z] [--archive FILE] [--prefix DIR] [--bin-dir DIR]
                  [--no-build] [--no-setup] [--no-modify-path] [--yes]
Installs a release; Linux builds with clang GNUstep. Missing prerequisites can
be installed with consent (--yes for unattended use). --no-setup prevents it.
Adds the launcher directory to future shells unless --no-modify-path is used.
The current shell still needs the printed PATH export after installation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--prefix|--bin-dir|--archive)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value" ;;
  esac
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --prefix) prefix="${2:-}"; shift 2 ;;
    --bin-dir) bin_dir="${2:-}"; shift 2 ;;
    --archive) archive="${2:-}"; shift 2 ;;
    --no-build) do_build=0; shift ;;
    --no-setup) do_setup=0; shift ;;
    --no-modify-path) modify_path=0; shift ;;
    --yes) yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done
version="${version#v}"
valid_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]]; }
[[ -z "$version" ]] || valid_version "$version" || die "invalid release version: $version"
# Absolute, canonical directories also make the launcher independent of cwd.
mkdir -p "$prefix" "$bin_dir"
prefix="$(cd "$prefix" && pwd -P)"
bin_dir="$(cd "$bin_dir" && pwd -P)"
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
consent() {
  [[ $yes -eq 1 ]] && return 0
  local answer=""
  if { exec 3<> /dev/tty; } 2>/dev/null; then
    printf 'arlen-install: %s [y/N] ' "$*" >&3
    read -r answer <&3 || true
    exec 3>&-
  fi
  [[ "$answer" == y || "$answer" == Y ]] || die "prerequisite setup needs consent; rerun with --yes, or provision manually with --no-setup"
}
root_command() {
  if [[ "$(id -u)" == 0 ]]; then "$@"; else need sudo; sudo "$@"; fi
}

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
stage=""
backup=""
dest=""
final_dest=""
activating=0
had_previous=0
old_current=""
launcher_stage=""
lock_dir="$prefix/.install-lock"
mkdir "$lock_dir" 2>/dev/null || die "another install is active (lock: $lock_dir); remove the lock only if that installer has stopped"
cleanup() {
  local status=$?
  if [[ $activating -eq 1 ]]; then
    if [[ -n "$backup" && ( -e "$backup" || -L "$backup" ) ]]; then
      rm -rf "$final_dest"
      mv "$backup" "$final_dest"
    elif [[ $had_previous -eq 0 && ! -d "$stage/release" ]]; then
      rm -rf "$final_dest"
    fi
    if [[ -n "$old_current" ]]; then ln -sfn "$old_current" "$prefix/current"
    else rm -f "$prefix/current"; fi
  fi
  [[ -z "$launcher_stage" ]] || rm -f "$launcher_stage"
  [[ -z "$stage" ]] || rm -rf "$stage"
  rm -rf "$work_dir"
  rmdir "$lock_dir" 2>/dev/null || true
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -z "$archive" ]]; then
  need curl
  if [[ -z "$version" ]]; then
    latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo_slug/releases/latest")" ||
      die "could not look up the latest release"
    version="${latest_url##*/}"
    version="${version#v}"
    valid_version "$version" || die "could not determine the latest release version (got '$version')"
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
  sums="$(dirname "$archive")/SHA256SUMS"
  if [[ -f "$sums" ]]; then
    expected="$(awk -v name="$(basename "$archive")" '$2 == name {print $1}' "$sums")"
    [[ -n "$expected" ]] || die "SHA256SUMS has no entry for $(basename "$archive")"
    [[ "$expected" == "$(sha256_of "$archive")" ]] || die "checksum mismatch for $archive"
    say "local archive checksum verified"
  else
    say "using trusted local archive (no sibling SHA256SUMS)"
  fi
fi

say "unpacking"
mkdir -p "$work_dir/unpack"
tar -xzf "$archive" -C "$work_dir/unpack"
top="$(cd "$work_dir/unpack" && ls)"
[[ -f "$work_dir/unpack/$top/.arlen-dist" ]] || die "$archive is not an Arlen release archive"
archive_version="$(awk -F= '$1 == "version" {print $2}' "$work_dir/unpack/$top/.arlen-dist")"
valid_version "$archive_version" || die "$archive has an invalid version in .arlen-dist"
[[ -z "$version" || "$version" == "$archive_version" ]] || die "requested version $version does not match archive $archive_version"
version="$archive_version"
# Build in a sibling staging directory. Failed downloads, setup, or builds never
# remove an existing release or change current/the launcher.
stage="$(mktemp -d "$prefix/.install-$version.XXXXXX")"
mv "$work_dir/unpack/$top" "$stage/release"
dest="$stage/release"
archive_kind="$(awk -F= '$1 == "kind" {print $2}' "$dest/.arlen-dist")"
case "$platform:$archive_kind" in
  linux:source|macos:macos-arm64) ;;
  *) die "archive kind '$archive_kind' is not supported on $platform" ;;
esac
for required in bin/arlen bin/arlen-doctor bin/boomhauer; do
  [[ -x "$dest/$required" ]] || die "archive is incomplete: missing executable $required"
done
for required in tools/source_gnustep_env.sh tools/resolve_gnustep.sh; do
  [[ -r "$dest/$required" ]] || die "archive is incomplete: missing readable $required"
done
if [[ "$platform" == macos ]]; then
  for required in build/apple/arlen build/apple/boomhauer build/apple/eocc; do
    [[ -x "$dest/$required" ]] || die "archive is incomplete: missing executable $required"
  done
  [[ -f "$dest/build/apple/.release-prebuilt" ]] || die "archive is incomplete: missing Apple prebuilt manifest"
  [[ -s "$dest/build/apple/lib/libArlenFramework.a" ]] || die "archive is incomplete: missing Apple framework library"
else
  [[ -f "$dest/GNUmakefile" && -f "$dest/tools/arlen.m" && -d "$dest/src/Arlen" ]] ||
    die "archive is incomplete: missing framework source/build inputs"
fi

linux_toolchain_ready() {
  ( source "$dest/tools/source_gnustep_env.sh" >/dev/null 2>&1 &&
    gnustep-config --objc-flags 2>/dev/null | grep -q -- '-fobjc-runtime=gnustep-2.2' )
}
setup_linux_legacy() {
  local missing=0 package os_id os_version
  for package in make python3 clang; do command -v "$package" >/dev/null 2>&1 || missing=1; done
  if [[ $missing -eq 0 ]]; then
    printf '#include <openssl/ssl.h>\nint main(void) { return OPENSSL_init_ssl(0, 0) == 0; }\n' |
      clang -x c - -lssl -lcrypto -o "$work_dir/openssl-check" >/dev/null 2>&1 || missing=1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ctypes; ctypes.CDLL("libsqlite3.so.0")' >/dev/null 2>&1 || missing=1
  fi
  if linux_toolchain_ready && [[ $missing -eq 0 ]]; then return; fi
  [[ $do_setup -eq 1 ]] || die "missing clang GNUstep or build prerequisites; --no-setup leaves the host unchanged. See docs/GETTING_STARTED.md (make, python3, clang, libssl-dev, libsqlite3-0 and GNUstep libobjc2)."
  os_id="$(. /etc/os-release; printf '%s' "$ID")"
  os_version="$(. /etc/os-release; printf '%s' "$VERSION_ID")"
  case "$os_id:$os_version:$arch" in
    debian:13:x86_64|debian:13:aarch64|ubuntu:26.04:x86_64) ;;
    *) die "automatic setup supports Debian 13 (x86_64/aarch64) and Ubuntu 26.04 (x86_64); provision a clang GNUstep toolchain manually and use --no-setup" ;;
  esac
  consent "Install Linux build prerequisites with apt and, if missing, GNUstep 0.1.0 in your home directory?"
  need curl
  if [[ $missing -eq 1 ]]; then
    root_command apt-get update
    root_command env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates clang make python3 libssl-dev libsqlite3-0
  fi
  if ! linux_toolchain_ready; then
    local bootstrap_url="https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0/gnustep-bootstrap.sh"
    # Pin executable bytes independently of checksums served with the download.
    local bootstrap_sha256="3bdfa7a29a6442ce1bb994b027bfcba78beec649ae820391f009ac9eeb40ba63"
    curl -fsSL "$bootstrap_url" -o "$work_dir/gnustep-bootstrap.sh" || die "GNUstep bootstrap download failed"
    [[ "$(sha256_of "$work_dir/gnustep-bootstrap.sh")" == "$bootstrap_sha256" ]] || die "GNUstep bootstrap checksum mismatch"
    sh "$work_dir/gnustep-bootstrap.sh" --yes setup --user || die "GNUstep setup failed; existing Arlen installation preserved"
  fi
  linux_toolchain_ready || die "GNUstep setup completed but a clang GNUstep 2.2 toolchain is still unavailable"
}

# New archives carry the locked normal runtime; historical --version archives
# retain their existing setup helper rather than downloading newer instructions.
setup_linux() {
  if [[ ! -f "$dest/tools/setup_runtime.py" ]]; then setup_linux_legacy; return; fi
  local missing=0 package runtime_prefix
  for package in make python3 clang; do command -v "$package" >/dev/null 2>&1 || missing=1; done
  if [[ $missing -eq 0 ]]; then
    printf '#include <openssl/ssl.h>\nint main(void) { return OPENSSL_init_ssl(0, 0) == 0; }\n' |
      clang -x c - -lssl -lcrypto -o "$work_dir/openssl-check" >/dev/null 2>&1 || missing=1
    python3 -c 'import ctypes; ctypes.CDLL("libsqlite3.so.0")' >/dev/null 2>&1 || missing=1
  fi
  # A manually supplied, matching custom prefix is accepted without rebuilding.
  if [[ $missing -eq 0 ]] && python3 "$dest/tools/setup_runtime.py" select --select-for "$dest" >/dev/null 2>&1; then return; fi
  [[ $do_setup -eq 1 ]] || die "patched Arlen runtime or build prerequisites unavailable; --no-setup never downloads/builds a runtime. Select a matching prefix with ARLEN_RUNTIME_PREFIX or GNUSTEP_SH; see docs/GETTING_STARTED.md."
  command -v python3 >/dev/null 2>&1 || {
    consent "Install native runtime/build prerequisites with apt?"
    root_command apt-get update
    root_command env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3
  }
  python3 "$dest/tools/setup_runtime.py" target >/dev/null || die "unsupported automatic runtime target; see docs/GETTING_STARTED.md"
  consent "Install native build prerequisites and build Arlen's pinned patched GNUstep runtime at its final versioned prefix? (No managed GNUstep installation is replaced.)"
  root_command apt-get update
  root_command env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl git tar gzip make cmake ninja-build pkg-config autoconf automake libtool python3 clang lld \
    libblocksruntime-dev libssl-dev libsqlite3-0 zlib1g-dev libxml2-dev libxslt1-dev libicu-dev \
    libavahi-client-dev libcurl4-gnutls-dev libgnutls28-dev libffi-dev
  runtime_prefix="${ARLEN_RUNTIME_ROOT:-$prefix/runtimes}"
  # This prefix is final: only the framework stage moves during activation.
  python3 "$dest/tools/setup_runtime.py" build --runtime-root "$runtime_prefix" --select-for "$dest" ||
    die "patched runtime setup failed; previous framework/current and runtimes preserved"
}

if [[ "$platform" == "macos" ]]; then
  # Browser downloads carry the quarantine flag; curl and tar do not.
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
fi

if [[ $do_build -eq 1 ]]; then
  if [[ "$platform" == "macos" ]]; then
    if [[ -f "$dest/tools/release/install_macos_prereqs.sh" ]]; then
      source "$dest/tools/release/install_macos_prereqs.sh"
      setup_mode=auto
      [[ $do_setup -eq 1 ]] || setup_mode=off
      aln_install_macos_prereqs "$setup_mode" "$yes"
    else
      # Older archives predate automatic setup. Keep --version usable with an
      # already provisioned host without downloading an unversioned helper.
      xcrun --find clang >/dev/null 2>&1 && xcrun --show-sdk-path >/dev/null 2>&1 ||
        die "install Xcode Command Line Tools with xcode-select --install, then retry"
      [[ -d /opt/homebrew/opt/openssl@3/include/openssl && -f /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib ]] ||
        die "this older archive needs preinstalled Homebrew openssl@3; run /opt/homebrew/bin/brew install openssl@3, then retry"
    fi
  fi
  if [[ "$platform" == "linux" ]]; then
    setup_linux
    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    [[ "$jobs" -le 4 ]] || jobs=4
    say "building the framework once against your GNUstep toolchain (make -j$jobs all)"
    # shellcheck disable=SC1091
    ( source "$dest/tools/source_gnustep_env.sh" >/dev/null && make -C "$dest" -j"$jobs" all >"$dest/build-install.log" 2>&1 ) ||
      { cp "$dest/build-install.log" "$prefix/last-build-failure.log"; die "framework build failed; see $prefix/last-build-failure.log (existing install preserved)"; }
  elif [[ $prebuilt -eq 0 ]]; then
    say "building the framework once with Apple clang (bin/build-apple)"
    "$dest/bin/build-apple" >"$dest/build-install.log" 2>&1 ||
      { cp "$dest/build-install.log" "$prefix/last-build-failure.log"; die "framework build failed; see $prefix/last-build-failure.log (existing install preserved)"; }
  fi
fi

# Prepare the launcher before changing the active release.
launcher="$bin_dir/arlen"
launcher_stage="$(mktemp "$bin_dir/.arlen-launcher.XXXXXX")"
cat >"$launcher_stage" <<EOF
#!/usr/bin/env bash
# Installed by Arlen's tools/install.sh. Set ARLEN_HOME to use another install.
default_arlen_home=$(quote "$prefix/current")
arlen_home="\${ARLEN_HOME:-\$default_arlen_home}"
# Apps live outside the install, so arlen cannot find the framework by walking
# up from the app directory.
export ARLEN_FRAMEWORK_ROOT="\${ARLEN_FRAMEWORK_ROOT:-\$arlen_home}"
if [[ "\$(uname -s)" != "Darwin" && "\${1:-}" != "doctor" ]]; then
  # shellcheck disable=SC1091
  source "\$arlen_home/tools/source_gnustep_env.sh" >/dev/null || exit 1
fi
exec "\$arlen_home/bin/arlen" "\$@"
EOF
chmod 755 "$launcher_stage"
final_dest="$prefix/$version"
[[ ! -e "$prefix/current" || -L "$prefix/current" ]] || die "$prefix/current must be a symlink"
[[ ! -d "$launcher" ]] || die "$launcher is a directory"
old_current="$(readlink "$prefix/current" 2>/dev/null || true)"
if [[ -e "$final_dest" || -L "$final_dest" ]]; then had_previous=1; fi
backup="$stage/previous"
# Arm rollback before the first rename. Cleanup checks whether the backup
# actually exists, so interruption/failure before mv cannot remove the old tree.
activating=1
if [[ $had_previous -eq 1 ]]; then mv "$final_dest" "$backup"; fi
mv "$dest" "$final_dest"
dest="$final_dest"
ln -sfn "$version" "$prefix/current"
mv -f "$launcher_stage" "$launcher"
# Activation succeeded; the EXIT trap can now remove the previous copy.
activating=0

say "installed Arlen $version at $dest"
say "launcher: $launcher"
# A child shell cannot change its parent's PATH. Persist it for future shells,
# and always give a separate command for this shell, including with --no-build.
path_line="export PATH=$(quote "$bin_dir"):\"\$PATH\""
if [[ $modify_path -eq 1 ]]; then
  case "$(basename "${SHELL:-sh}")" in
    zsh) profiles=("${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc") ;;
    bash)
      profiles=("$HOME/.bashrc")
      if [[ -f "$HOME/.bash_profile" ]]; then profiles+=("$HOME/.bash_profile")
      elif [[ -f "$HOME/.bash_login" ]]; then profiles+=("$HOME/.bash_login")
      else profiles+=("$HOME/.profile"); fi ;;
    *) profiles=("$HOME/.profile") ;;
  esac
  for profile in "${profiles[@]}"; do
    mkdir -p "$(dirname "$profile")"
    if ! grep -Fqx "$path_line" "$profile" 2>/dev/null; then
      printf '\n# Arlen launcher\n%s\n' "$path_line" >> "$profile"
    fi
    say "PATH configured in $profile"
  done
fi
cat <<EOF

Run in your current shell (or open a new terminal):
  $path_line
Then:
  arlen doctor
  arlen new MyApp && cd MyApp && arlen boomhauer --port 3000
EOF
