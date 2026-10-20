#!/usr/bin/env bash
# Install a release archive into a scratch prefix with tools/install.sh, then
# create an app and check that boomhauer serves /healthz and /.
#
#   tools/release/smoke_install.sh path/to/arlen-X.Y.Z[-macos-arm64].tar.gz
#
# Must stay bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
archive="${1:-}"
[[ -f "$archive" ]] || { echo "smoke_install: archive not found: $archive" >&2; exit 2; }
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

work="$(mktemp -d "${TMPDIR:-/tmp}/arlen-smoke.XXXXXX")"
server_pid=""
install_home="$work/home"
mkdir -p "$install_home"
# Preserve a deliberately supplied toolchain, otherwise allow the installer to
# bootstrap into this isolated HOME. Never edit the caller's startup files.
cleanup() {
  if [[ -n "$server_pid" ]]; then
    # boomhauer runs in its own process group; stop the whole group.
    kill -TERM -- "-$server_pid" 2>/dev/null || kill -TERM "$server_pid" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$server_pid" 2>/dev/null || true
  fi
  # A slow-dying server can still be writing under $work; never let cleanup
  # turn a passing smoke into a failure.
  rm -rf "$work" 2>/dev/null || true
}
trap cleanup EXIT

env HOME="$install_home" SHELL=/bin/bash bash "$repo_root/tools/install.sh" --yes --archive "$archive" --prefix "$work/arlen" --bin-dir "$work/bin"
# Exercise persisted shell setup with PATH initially excluding the new bin dir.
env HOME="$install_home" bash --noprofile --norc -c '. "$HOME/.profile"; cd /; command -v arlen; arlen doctor'
env HOME="$install_home" bash -ic 'cd /; command -v arlen; arlen doctor'
# Match the explicit export printed for the current shell; invoke only bare arlen.
export PATH="$work/bin:$PATH"
export GNUSTEP_SH="$(env HOME="$install_home" bash "$work/arlen/current/tools/resolve_gnustep.sh" 2>/dev/null || true)"
arlen doctor

cd "$work"
arlen new SmokeApp
cd SmokeApp

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
if command -v setsid >/dev/null 2>&1; then
  setsid arlen boomhauer --port "$port" >"$work/boomhauer.log" 2>&1 </dev/null &
else
  # macOS has no setsid; bash job control gives the job its own process group.
  set -m
  arlen boomhauer --port "$port" >"$work/boomhauer.log" 2>&1 </dev/null &
  set +m
fi
server_pid=$!

ok=0
for _ in $(seq 1 300); do
  if curl -fsS --max-time 2 "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
    ok=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [[ $ok -ne 1 ]]; then
  echo "smoke_install: boomhauer did not serve /healthz" >&2
  cat "$work/boomhauer.log" >&2
  exit 1
fi

curl -fsS --max-time 5 "http://127.0.0.1:$port/" | grep -q "Welcome to Arlen" || {
  echo "smoke_install: / did not render the welcome page" >&2
  exit 1
}

install_root="$work/arlen/current"
kind="$(awk -F= '$1 == "kind" {print $2}' "$install_root/.arlen-dist")"
if [[ "$kind" == "macos-arm64" ]]; then
  # build-apple removes the manifest and creates build/apple/obj when it
  # stops trusting the prebuilt tools and rebuilds them.
  if [[ ! -f "$install_root/build/apple/.release-prebuilt" || -d "$install_root/build/apple/obj" ]]; then
    echo "smoke_install: the prebuilt Apple framework tools were rebuilt after install" >&2
    cat "$work/boomhauer.log" >&2
    exit 1
  fi
elif grep -q "building framework artifacts" "$work/boomhauer.log"; then
  echo "smoke_install: note: boomhauer rebuilt framework artifacts after install"
fi

echo "smoke_install: ok ($(basename "$archive"))"
