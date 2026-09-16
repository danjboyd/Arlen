#!/usr/bin/env bash
set -euo pipefail

has_server_tools() {
  [[ -x "$1/initdb" && -x "$1/pg_ctl" ]]
}

# An explicit selection must fail if invalid, rather than silently changing version.
if [[ -n "${ARLEN_TEST_PG_BIN:-}" ]]; then
  if has_server_tools "$ARLEN_TEST_PG_BIN"; then
    printf '%s\n' "$ARLEN_TEST_PG_BIN"
    exit 0
  fi
  echo "PostgreSQL server tools missing from ARLEN_TEST_PG_BIN=$ARLEN_TEST_PG_BIN" >&2
  exit 1
fi

pg_config_bin="$(pg_config --bindir 2>/dev/null || true)"
if [[ -n "$pg_config_bin" ]] && has_server_tools "$pg_config_bin"; then
  printf '%s\n' "$pg_config_bin"
  exit 0
fi
initdb_path="$(command -v initdb || true)"
if [[ -n "$initdb_path" ]] && has_server_tools "$(dirname "$initdb_path")"; then
  dirname "$initdb_path"
  exit 0
fi

# Debian/Ubuntu can have client development tools and a different server version.
# Select the newest complete installed server directory deterministically.
if [[ -d /usr/lib/postgresql ]]; then
  while IFS= read -r candidate; do
    if has_server_tools "$candidate"; then
      printf '%s\n' "$candidate"
      exit 0
    fi
  done < <(printf '%s\n' /usr/lib/postgresql/*/bin | sort -Vr)
fi

echo "PostgreSQL initdb and pg_ctl are required; install server tools or set ARLEN_TEST_PG_BIN" >&2
exit 1
