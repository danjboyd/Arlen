# Windows CLANG64

Last updated: 2026-04-07

This document records the native Windows workflow for Arlen on MSYS2
`CLANG64`.

Phase `24A-24T` is complete on branch `windows/clang64`, so this is now the
checked-in first-class Windows contract for Arlen development, runtime,
testing, and release packaging.

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
- `bin/arlen.ps1`
- `bin/arlen.cmd`
- `bin/boomhauer.ps1`
- `bin/boomhauer.cmd`

For direct PowerShell use, put the framework `bin` directory on `PATH`:

```powershell
$env:PATH = "C:\path\to\Arlen\bin;$env:PATH"
arlen doctor
```

When `bin` is on `PATH`, PowerShell resolves `arlen` and `boomhauer` through
the checked-in `.cmd` shims, which in turn launch the `.ps1` wrappers with
`ExecutionPolicy Bypass`. Those wrappers bootstrap the same MSYS2 `CLANG64`
environment as `scripts/run_clang64.ps1`, preserve the current working
directory, and delegate directly to the existing `bin/arlen` / `bin/boomhauer`
bash launchers.

## 2. Required Tools

Expected inside the active `CLANG64` environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `openapp`
- `libdispatch`

Recommended for the broader Windows lanes:

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

On Windows CLANG64, `make all` builds:

- `build/eocc`
- `build/arlen`
- `build/lib/libArlenFramework.a`

Compatibility alias:

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

Full Windows parity lane:

```sh
make phase24-windows-parity
```

Release runbook smoke:

```sh
make deploy-smoke
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
- `make deploy-smoke` also completed successfully on this host on 2026-04-06,
  exercising the packaged Windows release helpers against the checked-in
  `examples/tech_demo` app.
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
- `arlen test`
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
- `make deploy-smoke`
- `arlen boomhauer` for app-root watch and non-watch flows, including fallback
  dev error recovery
- `arlen jobs worker`
- `arlen propane`
- `arlen routes`
- `arlen migrate`
- `arlen schema-codegen`
- `arlen typed-sql-codegen`
- `arlen module add/remove/list/doctor/migrate/assets/eject/upgrade`
- `tools/deploy/build_release.sh`
- `tools/deploy/activate_release.sh`
- `tools/deploy/rollback_release.sh`
- `tools/deploy/smoke_release.sh`
- `tools/deploy/windows/invoke_release_migrate.ps1`
- `tools/deploy/windows/start_release.ps1`
- `tools/deploy/windows/send_release_control.ps1`
- PostgreSQL/ODBC transport loading through the checked-in Windows DLL
  discovery contract
- direct PowerShell/`cmd.exe` wrapper invocation for `arlen` and `boomhauer`
- Windows service install/uninstall through `arlen service --mode dev|runtime`
  over the checked-in NSSM-backed contract

## 6. Release Helpers

Build a release artifact from CLANG64:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "tools/deploy/build_release.sh --app-root C:/srv/MyApp --framework-root C:/Users/Support/git/Arlen --releases-dir C:/srv/MyApp/releases"
```

From the packaged release, use the checked-in PowerShell helpers:

```powershell
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\invoke_release_migrate.ps1 -ReleasesDir C:\srv\MyApp\releases
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\start_release.ps1 -ReleasesDir C:\srv\MyApp\releases
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\send_release_control.ps1 -ReleasesDir C:\srv\MyApp\releases -Action reload
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\send_release_control.ps1 -ReleasesDir C:\srv\MyApp\releases -Action term
```

If `bash.exe` is not under the default MSYS2 or Git-for-Windows locations, set
`ARLEN_BASH_PATH` or pass `-BashPath`.

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

Full parity and release rerun:

```sh
make test-unit
make test-integration
make phase20-postgres-live-tests
make phase20-mssql-live-tests
make phase24-windows-parity
make deploy-smoke
```

For app-root smoke:

```sh
./bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen jobs worker --env development --once
```

Equivalent plain-PowerShell app-root smoke:

```powershell
$env:PATH = "C:\path\to\Arlen\bin;$env:PATH"
arlen new MyApp --lite
Set-Location .\MyApp
boomhauer --port 3000
```

Windows service flows use the same wrappers:

```powershell
arlen service install --mode dev --dry-run --json
```

- run from an app root for `boomhauer` service autodiscovery
- run from a packaged release layout for `arlen service install --mode runtime`
- live install/uninstall require an elevated PowerShell session
- install `NSSM` first with `winget install NSSM.NSSM` if it is not already
  available
