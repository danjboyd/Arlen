# Windows CLANG64 Preview

Last updated: 2026-04-07

This document records the first `main`-branch reintegration slice of Arlen's
native Windows work for MSYS2 `CLANG64`.

Current scope on `main`:

- checked-in CLANG64 entry wrappers
- GNUstep path resolution that recognizes `/clang64`
- a platform seam for time/process/path helpers
- a focused Windows DB transport smoke lane

This is not yet a full claim that current `main` has complete Windows runtime
parity. The heavier `boomhauer`, `jobs-worker`, `propane`, and deployment
forward-ports still need to be transplanted from the historical
`origin/windows/clang64` branch onto current `main`.

## 1. Host Entry Path

Use PowerShell as the outer launcher and MSYS2 `CLANG64` as the inner GNUstep
shell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1
```

Run one command directly:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make arlen"
```

Checked-in wrappers:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`

## 2. Required Tools

Expected inside the active `CLANG64` environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `libdispatch`

Recommended for the current focused Windows lane:

- `python3`
- `curl`
- `pkg-config`
- `libpq`
- `libodbc` or `odbc32.dll`

## 3. Current Mainline Windows Lane

Focused transport loader smoke:

```sh
make phase24-windows-db-smoke
```

Convenience preview runner:

```sh
bash ./tools/ci/run_phase24_windows_preview.sh
```

That lane is intended to verify the Windows DLL loading contract for:

- PostgreSQL (`libpq`)
- MSSQL / ODBC

The focused lane uses `arlen-xctest-runner` so a Windows host can load and run
the XCTest bundle without depending on the stock bundle discovery path.

## 4. Current Non-Claims

Not yet claimed on current `main`:

- full Windows `boomhauer` parity
- full Windows `jobs-worker` parity
- full Windows `propane` parity
- full unit/integration/live/perf confidence parity
- Windows release/install/package closeout

Those still belong to the remaining Phase 24 reintegration work from the
historical `origin/windows/clang64` branch.
