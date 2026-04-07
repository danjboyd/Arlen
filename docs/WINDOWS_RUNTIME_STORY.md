# Windows Runtime Story

Last updated: 2026-04-07

This document defines the native Windows runtime, release, and service-wrapper
contract for Arlen on the `windows/clang64` branch.

## Supported Native Windows Scope

Native Windows support covers development, CI validation, the default
unit/integration/live-backend entrypoints, the checked-in parity lanes, and
the immutable release workflow on MSYS2 `CLANG64`.

Supported entrypoints:

- `make all`
- `make test-unit`
- `make test-integration`
- `make phase20-postgres-live-tests`
- `make phase20-mssql-live-tests`
- `make phase24-windows-tests`
- `make phase24-windows-db-smoke`
- `make phase24-windows-runtime-tests`
- `make phase24-windows-confidence`
- `make phase24-windows-parity`
- `make deploy-smoke`
- `arlen doctor`
- `arlen build`
- `arlen check`
- `arlen test`
- `arlen boomhauer`
- `arlen jobs worker`
- `arlen propane`
- `arlen routes`
- `arlen migrate`
- `arlen schema-codegen`
- `arlen module migrate`
- `tools/deploy/build_release.sh`
- `tools/deploy/activate_release.sh`
- `tools/deploy/rollback_release.sh`
- `tools/deploy/smoke_release.sh`
- `tools/deploy/windows/invoke_release_migrate.ps1`
- `tools/deploy/windows/start_release.ps1`
- `tools/deploy/windows/send_release_control.ps1`

## Release Artifact Contract

Windows release artifacts use the same immutable layout as Linux:

```text
releases/<release-id>/
  app/
  framework/
  metadata/
```

The packaged framework payload includes:

- `bin/`
- `src/`
- `modules/`
- `build/eocc`
- `build/arlen`
- `build/boomhauer`
- `build/lib/libArlenFramework.a`
- `tools/deploy/`

`metadata/release.env` and `metadata/README.txt` capture the resolved app,
framework, PID, and control-file paths for the release.

## Windows Rollout Sequence

1. Build the release artifact from a CLANG64 shell with
   `tools/deploy/build_release.sh`.
2. Activate it with `tools/deploy/activate_release.sh`.
3. Run the packaged migration helper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\invoke_release_migrate.ps1 -ReleasesDir C:\srv\MyApp\releases
```

4. Start the packaged runtime:

```powershell
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\start_release.ps1 -ReleasesDir C:\srv\MyApp\releases
```

5. Reload or stop the running release through the packaged control helper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\send_release_control.ps1 -ReleasesDir C:\srv\MyApp\releases -Action reload
powershell -ExecutionPolicy Bypass -File C:\srv\MyApp\releases\current\framework\tools\deploy\windows\send_release_control.ps1 -ReleasesDir C:\srv\MyApp\releases -Action term
```

The PowerShell helpers resolve the active release through
`releases/current.release-id`, so Windows orchestration does not depend on MSYS
symlink or junction traversal.

## Service Wrapper Guidance

Windows does not use `systemd`, but the supported runtime contract is the same
immutable-release model used on Linux:

- keep one stable `releases` directory per app
- point your Windows service wrapper or orchestrator at
  `start_release.ps1 -ReleasesDir <path>`
- run `invoke_release_migrate.ps1` before switching traffic
- use `send_release_control.ps1 -Action reload` for rolling refreshes
- use `send_release_control.ps1 -Action term` for graceful shutdown
- restart on unexpected `propane` exit the same way the Linux `systemd` unit
  does

Phase 24U adds a higher-level Windows service CLI on top of that runtime
contract:

- `arlen service install --mode dev`
- `arlen service uninstall --mode dev`
- `arlen service install --mode runtime`
- `arlen service uninstall --mode runtime`

Mode semantics:

- `--mode dev`: installs a developer-box `boomhauer` service for an app root
- `--mode runtime`: installs a packaged-release `propane` service through
  `start_release.ps1 -ReleasesDir <path>`

Autodiscovery defaults:

- `dev`: `--app-root` and `--name` are optional when invoked from inside the
  app root
- `runtime`: `--releases-dir` and `--name` are optional when invoked from
  inside the immutable release layout

Default Windows log locations:

- `dev`: `<app-root>\tmp\service\boomhauer.stdout.log` and
  `<app-root>\tmp\service\boomhauer.stderr.log`
- `runtime`: `<releases-dir>\service\propane.stdout.log` and
  `<releases-dir>\service\propane.stderr.log`

Backend note:

- the current Windows implementation uses `NSSM`
- install it with `winget install NSSM.NSSM` when not already present
- Arlen also probes the Winget package cache when the `nssm` alias link is not
  present
- live install/uninstall require an elevated PowerShell session
- Linux `systemd` wiring should later reuse the same `arlen service` contract
  rather than introducing a separate service-management CLI

If `bash.exe` is not installed at `C:\msys64\usr\bin\bash.exe` or
`C:\Program Files\Git\bin\bash.exe`, set `ARLEN_BASH_PATH` or pass `-BashPath`
to the PowerShell helpers.

## Cross-Platform Notes

- Linux `systemd` guidance remains in `docs/SYSTEMD_RUNBOOK.md`.
- The shared deployment model, rollback contract, and `deploy-smoke`
  verification flow remain documented in `docs/DEPLOYMENT.md`.
