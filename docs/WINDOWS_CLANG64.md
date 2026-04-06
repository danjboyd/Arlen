# Windows CLANG64 Preview

Last updated: 2026-04-06

This document records the native Windows workflow for Arlen on MSYS2
`CLANG64`.

The checked-in Phase 24 preview/runtime contract plus the `24Q-24R` Windows
parity work are complete on branch `windows/clang64`. Phase `24S` still
remains for release/package/first-class platform closeout, so this document
continues to record the current supported preview boundary.

## 1. Host Entry Path

Use PowerShell as the outer launcher and MSYS2 `CLANG64` as the inner GNUstep
shell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1
```

Run one command directly:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make all"
```

The checked-in wrappers are:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`

## 2. Required Tools

Expected inside the active `CLANG64` environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `openapp`
- `libdispatch`

Recommended for the wider Windows lanes:

- `python3`
- `curl`
- `pkg-config`
- `pg_config`
- `libpq`
- `libodbc` or `odbc32.dll`

`arlen doctor` checks both `ARLEN_LIBPQ_LIBRARY` / `ARLEN_ODBC_LIBRARY` and
the standard `CLANG64` DLL locations when present.

## 3. Build Contract

From the documented `CLANG64` shell:

```sh
make all
```

On Windows preview, `make all` builds:

- `build/eocc`
- `build/arlen`
- the Windows preview `libArlenFramework.a`, including the data-layer sources

Convenience alias:

```sh
make clang64-preview
```

## 4. Verification Lanes

Focused template lane:

```sh
make phase24-windows-tests
```

Focused DB transport smoke lane:

```sh
make phase24-windows-db-smoke
```

Focused runtime parity lane:

```sh
make phase24-windows-runtime-tests
```

Broader Windows confidence lane:

```sh
make phase24-windows-confidence
```

Default Linux-matching test entrypoints on Windows:

```sh
make test-unit
make test-integration
```

Live-backend suites on Windows:

```sh
make phase20-postgres-live-tests
make phase20-mssql-live-tests
```

Full `24Q-24R` parity lane:

```sh
make phase24-windows-parity
```

PowerShell wrappers:

- `scripts/run_phase24_windows_tests.ps1`
- `scripts/run_clang64.ps1 -InnerCommand "make phase24-windows-db-smoke"`
- `scripts/run_clang64.ps1 -InnerCommand "make phase24-windows-runtime-tests"`
- `scripts/run_clang64.ps1 -InnerCommand "make phase24-windows-confidence"`
- `scripts/run_phase24_windows_parity.ps1`

Backend env contract for the Windows live-backend/parity lanes:

- `ARLEN_PG_TEST_DSN`
- `ARLEN_LIBPQ_LIBRARY`
- `ARLEN_PSQL`
- `ARLEN_ODBC_LIBRARY`
- `ARLEN_MSSQL_TEST_DSN`

On the checked-in parity hosts, `tools/ci/_phase24_windows_env.sh` can
populate those defaults automatically and start `MSSQLLocalDB` when the MSSQL
DSN is unset.

Current verification note:

- As of 2026-04-06, `make phase24-windows-tests`,
  `make phase24-windows-db-smoke`, `make phase24-windows-runtime-tests`,
  `make phase24-windows-confidence`, `make test-unit`,
  `make test-integration`, `make phase20-postgres-live-tests`, and
  `make phase20-mssql-live-tests` completed on the checked-in CLANG64 path in
  this workspace.
- The broader `24Q-24R` perf/robustness lanes wired through
  `make phase24-windows-parity` were also rerun successfully on this host on
  2026-04-06.
- The focused Windows lanes still use repo-local linked test executables so
  test discovery stays reliable on CLANG64.
- The only remaining warning observed in this workspace is the upstream
  CLANG64/GNUstep `-fobjc-exceptions` unused-command-line warning rather than
  an Arlen portability warning.

## 5. Supported Native Windows Surface

Supported on the current branch:

- `arlen doctor`
- `arlen config`
- `arlen new`
- `arlen generate`
- `arlen build`
- `arlen check`
- `make all`
- `make phase24-windows-tests`
- `make phase24-windows-db-smoke`
- `make phase24-windows-confidence`
- `make test-unit`
- `make test-integration`
- `make phase20-postgres-live-tests`
- `make phase20-mssql-live-tests`
- `make phase24-windows-runtime-tests`
- `make phase24-windows-parity`
- `arlen boomhauer` for app-root watch and non-watch flows, including fallback
  dev error recovery
- `arlen jobs worker`
- `arlen propane`
- `arlen routes`
- `arlen test --unit` as the focused Windows XCTest lane
- `arlen migrate`
- `arlen schema-codegen`
- `arlen typed-sql-codegen`
- `arlen module add/remove/list/doctor/migrate/assets/eject/upgrade`
- PostgreSQL/ODBC transport loading through the checked-in Windows DLL
  discovery contract

## 6. Explicit Native Windows Non-Support

Still intentionally unsupported:

- Windows release/install/package closeout
- Windows service-integration guidance beyond direct `propane` usage
- first-class Windows deployment/docs packaging outside the checked-in CLANG64
  path

The runtime/deployment boundary is documented in:

- `docs/WINDOWS_RUNTIME_STORY.md`

## 7. Suggested Windows Sequence

Fast smoke:

```sh
./bin/arlen doctor
make all
make phase24-windows-tests
make phase24-windows-db-smoke
make phase24-windows-runtime-tests
make phase24-windows-confidence
```

Full `24Q-24R` parity rerun:

```sh
make test-unit
make test-integration
make phase20-postgres-live-tests
make phase20-mssql-live-tests
make phase24-windows-parity
```

For app-root smoke:

```sh
./bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen jobs worker --env development --once
```
