#!/usr/bin/env bash
# Unpack a windows-x64 release archive, create an app, and check that
# boomhauer serves /healthz and / using the prebuilt framework (no rebuild).
#
#   tools/release/smoke_windows_archive.sh path/to/arlen-X.Y.Z-windows-x64.zip
#
# Runs inside the gnustep-cli MSYS2 CLANG64 shell (scripts/run_clang64.ps1).
set -euo pipefail

archive="${1:-}"
[[ -f "$archive" ]] || { echo "smoke_windows_archive: archive not found: $archive" >&2; exit 2; }
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

work="$(mktemp -d "${TMPDIR:-/tmp}/arlen-win-smoke.XXXXXX")"
server_winpid=""
cleanup() {
  # bash's kill doesn't reach boomhauer-app.exe; end the whole Windows process tree.
  if [[ -n "$server_winpid" ]]; then
    taskkill //F //T //PID "$server_winpid" >/dev/null 2>&1 || true
    sleep 1
  fi
  rm -rf "$work" 2>/dev/null || true
}
trap cleanup EXIT

bsdtar -xf "$archive" -C "$work"
root="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'arlen-*' | head -n 1)"
[[ -n "$root" && -f "$root/.arlen-dist" ]] || { echo "smoke_windows_archive: no arlen-X.Y.Z/.arlen-dist in $archive" >&2; exit 1; }
grep -qx 'kind=windows-x64' "$root/.arlen-dist" || { echo "smoke_windows_archive: .arlen-dist kind is not windows-x64" >&2; exit 1; }
[[ -f "$root/build/.release-prebuilt" ]] || { echo "smoke_windows_archive: build/.release-prebuilt missing" >&2; exit 1; }
if grep -lr $'\r' "$root/bin" "$root/GNUmakefile" "$root"/tools/*.sh >/dev/null 2>&1; then
  echo "smoke_windows_archive: CRLF line endings in shipped scripts:" >&2
  grep -lr $'\r' "$root/bin" "$root/GNUmakefile" "$root"/tools/*.sh >&2
  exit 1
fi

export ARLEN_FRAMEWORK_ROOT="$root"
arlen="$root/bin/arlen"

cd "$work"
"$arlen" new SmokeApp
cd SmokeApp

# The bundled build/dll/libpq.dll and its imports must load. With no server
# needed, a connection to port 1 has to fail inside libpq (connection
# refused), not with "failed to load libpq".
[[ -f "$root/build/dll/libpq.dll" ]] || { echo "smoke_windows_archive: build/dll/libpq.dll missing" >&2; exit 1; }
pg_output="$("$arlen" migrate --dsn 'postgresql://smoke@127.0.0.1:1/smoke?connect_timeout=5' --dry-run 2>&1 || true)"
if printf '%s' "$pg_output" | grep -qiE 'failed to load libpq|libpq shared library not found'; then
  echo "smoke_windows_archive: the bundled libpq did not load:" >&2
  printf '%s\n' "$pg_output" >&2
  exit 1
fi
if ! printf '%s' "$pg_output" | grep -qiE 'connection refused|could not connect|connection to server'; then
  echo "smoke_windows_archive: expected a libpq connection error from port 1, got:" >&2
  printf '%s\n' "$pg_output" >&2
  exit 1
fi

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
"$arlen" boomhauer --port "$port" >"$work/boomhauer.log" 2>&1 </dev/null &
server_pid=$!
server_winpid="$(cat "/proc/$server_pid/winpid" 2>/dev/null || true)"

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
if [[ "$ok" != "1" ]]; then
  echo "smoke_windows_archive: boomhauer never served /healthz; log follows" >&2
  cat "$work/boomhauer.log" >&2
  exit 1
fi
curl -fsS --max-time 5 "http://127.0.0.1:$port/" >/dev/null

if [[ -d "$root/build/obj" ]] || ! grep -q 'reusing current framework tools and libraries' "$work/boomhauer.log"; then
  echo "smoke_windows_archive: boomhauer rebuilt the prebuilt framework; log follows" >&2
  cat "$work/boomhauer.log" >&2
  exit 1
fi
if [[ ! -f "$root/build/.release-prebuilt" ]]; then
  echo "smoke_windows_archive: build/.release-prebuilt was invalidated" >&2
  exit 1
fi

echo "smoke_windows_archive: passed ($(sed -n 's/^version=//p' "$root/.arlen-dist"), toolchain $(sed -n 's/^toolchain=//p' "$root/.arlen-dist"))"
