#!/usr/bin/env bash
set -euo pipefail

phase28_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

phase28_source_gnustep() {
  local repo_root="$1"
  set +u
  source "$repo_root/tools/source_gnustep_env.sh"
  set -u
}

phase28_require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "phase28: required command is missing: $command_name" >&2
    return 1
  fi
}

phase28_ensure_npm_deps() {
  local package_dir="$1"
  local required_bin="$2"
  if [[ -x "$package_dir/node_modules/.bin/$required_bin" ]]; then
    return 0
  fi
  (
    cd "$package_dir"
    npm install --package-lock=false
  )
}

phase28_pick_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

phase28_wait_for_server() {
  local port="$1"
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

phase28_now_ms() {
  python3 - <<'PY'
import time

print(int(time.time() * 1000))
PY
}

phase28_file_size_bytes() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import os
import sys

print(os.path.getsize(sys.argv[1]))
PY
}

phase28_directory_size_bytes() {
  local dir_path="$1"
  python3 - "$dir_path" <<'PY'
import os
import sys

total = 0
for root, _, files in os.walk(sys.argv[1]):
    for name in files:
        total += os.path.getsize(os.path.join(root, name))
print(total)
PY
}
