#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

strategy="${ARLEN_CI_GNUSTEP_STRATEGY:-apt}"
gnustep_sh="$(bash "$repo_root/tools/resolve_gnustep.sh" 2>/dev/null || true)"
if [[ -z "$gnustep_sh" ]]; then
  gnustep_sh="${GNUSTEP_SH:-/usr/GNUstep/System/Library/Makefiles/GNUstep.sh}"
fi

apt_cmd=(apt-get)
if command -v sudo >/dev/null 2>&1; then
  apt_cmd=(sudo apt-get)
fi

install_apt_toolchain() {
  "${apt_cmd[@]}" update
  "${apt_cmd[@]}" install -y \
    clang \
    curl \
    jq \
    make \
    pandoc \
    python3 \
    gnustep-clang-tools-xctest \
    gnustep-clang-make \
    gnustep-clang-libs-base
}

run_bootstrap_script() {
  local bootstrap_script="${ARLEN_CI_GNUSTEP_BOOTSTRAP_SCRIPT:-}"
  if [[ -z "$bootstrap_script" ]]; then
    echo "ci: ARLEN_CI_GNUSTEP_STRATEGY=bootstrap requires ARLEN_CI_GNUSTEP_BOOTSTRAP_SCRIPT" >&2
    exit 1
  fi
  if [[ ! -f "$bootstrap_script" ]]; then
    echo "ci: GNUstep bootstrap script not found: $bootstrap_script" >&2
    exit 1
  fi
  bash "$bootstrap_script"
}

validate_clang_gnustep_toolchain() {
  if [[ ! -f "$gnustep_sh" ]]; then
    echo "ci: GNUstep.sh not found at $gnustep_sh" >&2
    echo "ci: set GNUSTEP_SH, export GNUSTEP_MAKEFILES, or source your toolchain env script before running this helper" >&2
    exit 1
  fi

  set +u
  source "$gnustep_sh"
  set -u

  if ! command -v clang >/dev/null 2>&1; then
    echo "ci: clang is required" >&2
    exit 1
  fi
  if ! command -v gnustep-config >/dev/null 2>&1; then
    echo "ci: gnustep-config is required after sourcing $gnustep_sh" >&2
    exit 1
  fi
  if ! command -v xctest >/dev/null 2>&1; then
    echo "ci: xctest is required after sourcing $gnustep_sh" >&2
    exit 1
  fi

  local gnustep_objc_flags
  gnustep_objc_flags="$(gnustep-config --objc-flags)"
  if [[ "$gnustep_objc_flags" != *"-fobjc-runtime=gnustep-2.2"* ]]; then
    echo "ci: Arlen requires a clang-built GNUstep toolchain; expected gnustep-config --objc-flags to include -fobjc-runtime=gnustep-2.2" >&2
    echo "ci: observed flags: $gnustep_objc_flags" >&2
    exit 1
  fi

  echo "ci: GNUstep strategy: $strategy"
  echo "ci: GNUSTEP_SH: $gnustep_sh"
  echo "ci: gnustep-config: $(command -v gnustep-config)"
  echo "ci: xctest: $(command -v xctest)"
}

case "$strategy" in
  apt)
    install_apt_toolchain
    ;;
  preinstalled)
    echo "ci: using preinstalled clang-built GNUstep toolchain"
    ;;
  bootstrap)
    run_bootstrap_script
    ;;
  *)
    echo "ci: unsupported ARLEN_CI_GNUSTEP_STRATEGY: $strategy" >&2
    echo "ci: supported strategies: apt, preinstalled, bootstrap" >&2
    exit 1
    ;;
esac

validate_clang_gnustep_toolchain
