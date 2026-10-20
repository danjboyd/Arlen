#!/usr/bin/env bash
# Sourced by install.sh before activating a prebuilt Apple Silicon release.
# The release binaries link Homebrew OpenSSL at the standard arm64 opt path.

aln_install_macos_confirm_brew() {
  local assume_yes="$1"
  local answer
  if [[ "$assume_yes" == "1" ]]; then
    return 0
  fi
  # /dev/tty can have read/write permissions even when this process has no
  # controlling terminal (CI, an agent, or a detached service). Open it first.
  if ! { exec 9<> /dev/tty; } 2>/dev/null; then
    printf 'arlen-install: error: installing openssl@3 needs consent; rerun with --yes or install it manually.\n' >&2
    return 1
  fi
  if ! printf 'arlen-install: install Homebrew openssl@3 now? [y/N] ' >&9 ||
     ! IFS= read -r answer <&9; then
    exec 9>&-
    printf 'arlen-install: error: installing openssl@3 needs consent; rerun with --yes or install it manually.\n' >&2
    return 1
  fi
  exec 9>&-
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) printf 'arlen-install: error: openssl@3 was not installed; rerun with --yes or install it manually.\n' >&2; return 1 ;;
  esac
}

aln_install_macos_prereqs() {
  local setup_mode="${1:-auto}"
  local assume_yes="${2:-0}"
  local macos_version major brew_command
  local openssl_root="/opt/homebrew/opt/openssl@3"

  case "$setup_mode:$assume_yes" in
    auto:0|auto:1|off:0|off:1) ;;
    *) printf 'arlen-install: error: invalid macOS prerequisite mode\n' >&2; return 2 ;;
  esac

  if [[ "$(uname -m)" != "arm64" ]]; then
    printf 'arlen-install: error: the prebuilt macOS release requires Apple Silicon (arm64)\n' >&2
    return 1
  fi
  macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
  major="${macos_version%%.*}"
  if [[ ! "$major" =~ ^[0-9]+$ ]] || (( major < 14 )); then
    printf 'arlen-install: error: the prebuilt release requires macOS 14 or newer (found %s)\n' "${macos_version:-unknown}" >&2
    return 1
  fi

  if ! command -v xcrun >/dev/null 2>&1 ||
     ! xcrun --find clang >/dev/null 2>&1 ||
     ! xcrun --show-sdk-path >/dev/null 2>&1; then
    printf 'arlen-install: error: Apple clang and the macOS SDK are required to build your apps.\n' >&2
    printf 'Install Xcode Command Line Tools with `xcode-select --install`, finish the system dialog, then rerun this installer.\n' >&2
    return 1
  fi

  if [[ -d "$openssl_root/include/openssl" && -f "$openssl_root/lib/libcrypto.3.dylib" ]]; then
    return 0
  fi

  if [[ "$setup_mode" == "off" ]]; then
    printf 'arlen-install: error: missing Homebrew openssl@3 at %s; run `/opt/homebrew/bin/brew install openssl@3` and retry.\n' "$openssl_root" >&2
    return 1
  fi

  brew_command="/opt/homebrew/bin/brew"
  if [[ ! -x "$brew_command" ]]; then
    printf 'arlen-install: error: Homebrew at /opt/homebrew is required for the prebuilt Apple Silicon release.\n' >&2
    printf 'Install Homebrew from https://brew.sh/, then rerun this installer.\n' >&2
    return 1
  fi

  aln_install_macos_confirm_brew "$assume_yes" || return 1
  printf 'arlen-install: installing Homebrew openssl@3 for the prebuilt framework\n'
  "$brew_command" install openssl@3 || {
    printf 'arlen-install: error: Homebrew could not install openssl@3; rerun after resolving its error.\n' >&2
    return 1
  }
  if [[ ! -d "$openssl_root/include/openssl" || ! -f "$openssl_root/lib/libcrypto.3.dylib" ]]; then
    printf 'arlen-install: error: openssl@3 is still missing at %s after Homebrew finished.\n' "$openssl_root" >&2
    return 1
  fi
}
