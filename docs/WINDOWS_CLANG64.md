# Windows CLANG64 Preview

Last updated: 2026-04-07

This document records the current `main`-branch reintegration slice of Arlen's
native Windows work for MSYS2 `CLANG64`.

Current scope on `main`:

- checked-in CLANG64 entry wrappers
- GNUstep path resolution that recognizes `/clang64`
- a platform seam for time/process/path helpers
- Windows-aware `boomhauer`, `jobs-worker`, and `propane` shell entrypoints
- Windows transport loader support for PostgreSQL and ODBC
- a Windows socket/runtime portability layer in `ALNHTTPServer`
- focused Windows DB smoke and runtime parity lanes
- a main-based Windows preview workflow

This is still not a full claim that current `main` has complete Windows
support. Runtime parity is now partially forward-ported, but release/install
closeout and broader confidence parity remain open.

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

Recommended for the current Windows preview lanes:

- `python3`
- `curl`
- `pkg-config`
- `libpq`
- `libodbc` or `odbc32.dll`

## 3. Current Mainline Windows Lanes

Focused transport loader smoke:

```sh
make phase24-windows-db-smoke
```

Runtime/server parity checks:

```sh
make phase24-windows-runtime-tests
```

Aggregated preview confidence lane:

```sh
make phase24-windows-confidence
```

Convenience preview runner:

```sh
bash ./tools/ci/run_phase24_windows_preview.sh
```

Those lanes are intended to verify:

- PostgreSQL (`libpq`)
- MSSQL / ODBC
- `boomhauer` watch-mode recovery
- `jobs-worker` queued-job execution
- `propane` request serving and reload handling

The preview lanes use `arlen-xctest-runner` so a Windows host can load and run
the XCTest bundle without depending on the stock bundle discovery path.

## 4. Current Non-Claims

Not yet claimed on current `main`:

- full unit/integration/live/perf confidence parity
- Windows release/install/package closeout
- packaged-release deployment parity on Windows

Those still belong to the remaining Phase 24 reintegration work from the
historical `origin/windows/clang64` branch.
