#!/usr/bin/env bash

arlen_phase24_windows_powershell() {
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoLogo -NoProfile -NonInteractive "$@"
    return $?
  fi
  local powershell_path="/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  if [[ -x "$powershell_path" ]]; then
    "$powershell_path" -NoLogo -NoProfile -NonInteractive "$@"
    return $?
  fi
  echo "phase24-windows-parity: powershell.exe is required to configure native Windows backends" >&2
  return 1
}

arlen_phase24_windows_preferred_sql_driver() {
  arlen_phase24_windows_powershell -Command \
    "\$drivers = Get-ItemProperty 'HKLM:\\SOFTWARE\\ODBC\\ODBCINST.INI\\ODBC Drivers' -ErrorAction SilentlyContinue; if (\$drivers.'ODBC Driver 18 for SQL Server' -eq 'Installed') { 'ODBC Driver 18 for SQL Server' } elseif (\$drivers.'ODBC Driver 17 for SQL Server' -eq 'Installed') { 'ODBC Driver 17 for SQL Server' } elseif (\$drivers.'SQL Server' -eq 'Installed') { 'SQL Server' }"
}

arlen_phase24_windows_start_localdb() {
  arlen_phase24_windows_powershell -Command \
    "\$candidates = @('C:\\Program Files\\Microsoft SQL Server\\170\\Tools\\Binn\\SqlLocalDB.exe', 'C:\\Program Files\\Microsoft SQL Server\\160\\Tools\\Binn\\SqlLocalDB.exe', 'C:\\Program Files\\Microsoft SQL Server\\150\\Tools\\Binn\\SqlLocalDB.exe'); \$exe = \$candidates | Where-Object { Test-Path \$_ } | Select-Object -First 1; if (-not \$exe) { \$cmd = Get-Command SqlLocalDB.exe -ErrorAction SilentlyContinue; if (\$cmd) { \$exe = \$cmd.Source } }; if (-not \$exe) { exit 1 }; & \$exe start MSSQLLocalDB | Out-Null"
}

arlen_phase24_windows_configure_defaults() {
  if ! arlen_ci_is_windows_preview; then
    return 0
  fi

  local postgres_bin="C:/Program Files/PostgreSQL/17/bin"
  if [[ -z "${ARLEN_PG_TEST_DSN:-}" ]]; then
    export ARLEN_PG_TEST_DSN="host=127.0.0.1 port=55432 dbname=arlen_phase20 user=postgres password=ArlenP24Q_pg! connect_timeout=5"
  fi
  if [[ -z "${ARLEN_LIBPQ_LIBRARY:-}" && -f "${postgres_bin}/libpq.dll" ]]; then
    export ARLEN_LIBPQ_LIBRARY="${postgres_bin}/libpq.dll"
  fi
  if [[ -z "${ARLEN_PSQL:-}" && -f "${postgres_bin}/psql.exe" ]]; then
    export ARLEN_PSQL="${postgres_bin}/psql.exe"
  fi
  if [[ -z "${ARLEN_ODBC_LIBRARY:-}" ]]; then
    export ARLEN_ODBC_LIBRARY="odbc32.dll"
  fi
  if [[ -z "${ARLEN_MSSQL_TEST_DSN:-}" ]]; then
    local driver=""
    driver="$(arlen_phase24_windows_preferred_sql_driver | tr -d '\r' | tail -n 1)"
    if [[ -z "$driver" ]]; then
      echo "phase24-windows-parity: unable to detect a Windows SQL Server ODBC driver; set ARLEN_MSSQL_TEST_DSN explicitly" >&2
      return 1
    fi
    arlen_phase24_windows_start_localdb || {
      echo "phase24-windows-parity: failed to start MSSQLLocalDB; set ARLEN_MSSQL_TEST_DSN explicitly if you are using another SQL Server instance" >&2
      return 1
    }
    export ARLEN_MSSQL_TEST_DSN="Driver={${driver}};Server=(localdb)\\\\MSSQLLocalDB;Database=master;Trusted_Connection=Yes;Encrypt=no;TrustServerCertificate=yes;"
  fi
}

arlen_phase24_windows_validate_env() {
  if ! arlen_ci_is_windows_preview; then
    return 0
  fi

  if [[ -z "${ARLEN_PG_TEST_DSN:-}" ]]; then
    echo "phase24-windows-parity: ARLEN_PG_TEST_DSN is required for the Windows live-backend parity lane" >&2
    return 1
  fi
  if [[ -z "${ARLEN_MSSQL_TEST_DSN:-}" ]]; then
    echo "phase24-windows-parity: ARLEN_MSSQL_TEST_DSN is required for the Windows live-backend parity lane" >&2
    return 1
  fi
  return 0
}
