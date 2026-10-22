#!/usr/bin/env bash
# Explicit functional-CI setup. Dedicated TSan jobs keep their existing bootstrap.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
install_dependencies=0
if [[ "${1:-}" == --install-dependencies ]]; then install_dependencies=1; shift; fi
[[ $# -eq 0 ]] || { echo 'usage: setup_normal_runtime.sh [--install-dependencies]' >&2; exit 2; }
if [[ $install_dependencies -eq 1 ]]; then
  apt_cmd=(env DEBIAN_FRONTEND=noninteractive apt-get)
  [[ $(id -u) -eq 0 ]] || apt_cmd=(sudo env DEBIAN_FRONTEND=noninteractive apt-get)
  "${apt_cmd[@]}" update
  "${apt_cmd[@]}" install -y --no-install-recommends \
    ca-certificates curl git tar gzip tzdata make cmake ninja-build pkg-config autoconf automake libtool python3 clang lld \
    libblocksruntime-dev libssl-dev libsqlite3-0 zlib1g-dev libxml2-dev libxslt1-dev libicu-dev \
    libavahi-client-dev libcurl4-gnutls-dev libgnutls28-dev libffi-dev
fi
state_dir="${ARLEN_NORMAL_RUNTIME_STATE:-${RUNNER_TEMP:?set RUNNER_TEMP or ARLEN_NORMAL_RUNTIME_STATE}/arlen-normal-runtime}"
mkdir -m 700 -p "$state_dir"
state_dir="$(cd "$state_dir" && pwd -P)"
if [[ -n "${ARLEN_RUNTIME_PREFIX:-}" ]]; then
  python3 "$repo_root/tools/setup_runtime.py" select --prefix "$ARLEN_RUNTIME_PREFIX" --select-for "$state_dir" >/dev/null
else
  python3 "$repo_root/tools/setup_runtime.py" build \
    --runtime-root "${ARLEN_CI_NORMAL_RUNTIME_ROOT:-$HOME/.cache/arlen/normal-runtimes}" \
    --select-for "$state_dir" --jobs 4 >/dev/null
fi
export ARLEN_RUNTIME_PREFIX="$(cat "$state_dir/.arlen-runtime")"
export ARLEN_GNUSTEP_CONFIG_FILE="$state_dir/GNUstep.conf"
# GNUstep's config overrides HOME/defaults environment variables. An explicit
# owned config isolates Foundation defaults while retaining actual prefix domains.
python3 - "$ARLEN_RUNTIME_PREFIX" "$state_dir" <<'PY'
from pathlib import Path
import os
import shlex
import sys
prefix, state = map(Path, sys.argv[1:])
config = (prefix / 'etc/GNUstep/GNUstep.conf').read_text()
defaults = state / 'Defaults'
defaults.mkdir(mode=0o700, exist_ok=True)
config += '\nGNUSTEP_USER_DEFAULTS_DIR=' + shlex.quote(str(defaults)) + '\n'
config += 'GNUSTEP_USER_CONFIG_FILE=' + shlex.quote(str(state / 'absent-user.conf')) + '\n'
path = state / 'GNUstep.conf'
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.fchmod(fd, 0o600)
with os.fdopen(fd, 'w') as f:
    f.write(config)
PY
source "$repo_root/tools/source_gnustep_env.sh"
python3 "$repo_root/tools/setup_runtime.py" check --full > "$state_dir/verified-prefix.txt"
cp "$ARLEN_RUNTIME_PREFIX/gnustep-toolchain-provenance.json" "$state_dir/"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    printf 'ARLEN_RUNTIME_PREFIX=%s\n' "$ARLEN_RUNTIME_PREFIX"
    printf 'ARLEN_GNUSTEP_CONFIG_FILE=%s\n' "$ARLEN_GNUSTEP_CONFIG_FILE"
  } >> "$GITHUB_ENV"
fi
printf 'Functional CI selected patched runtime: %s\n' "$ARLEN_RUNTIME_PREFIX"
printf 'Private GNUstep defaults config: %s\n' "$ARLEN_GNUSTEP_CONFIG_FILE"
