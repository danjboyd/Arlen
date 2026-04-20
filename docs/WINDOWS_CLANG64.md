# Windows CLANG64 Preview

Last updated: 2026-04-20

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
support. Runtime parity, packaged-release parity, deploy/doctor parity, and
preview CI coverage are now forward ported, but Windows remains a preview
target rather than a general production support claim.

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

For Phase 34K runner provisioning, Arlen pins `gnustep-cli-new` as a submodule
at `vendor/gnustep-cli-new`. Use that checkout as the source of truth for the
MSYS2 `CLANG64` GNUstep managed-toolchain manifests and Windows bootstrap
validation helpers when preparing a self-hosted `windows-preview` runner.

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

Packaged release confidence lane:

```sh
make phase31-confidence
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

## 4. Packaged Release Contract

The current Windows packaged-release contract is now explicit:

- build releases from an MSYS2 `CLANG64` shell with the GNUstep environment
  initialized
- packaged release manifests record the actual runtime/helper paths for
  `arlen`, `boomhauer`, `propane`, `jobs-worker`, the app runtime binary, and
  the operability probe helper
- deploy/runtime entrypoints resolve compiled binaries through `.exe` siblings
  instead of assuming Unix-only filenames
- `arlen deploy doctor` reads those manifest-backed helper paths when checking
  a packaged release root
- `make phase31-confidence` exercises packaged release smoke, packaged
  `deploy doctor --base-url`, packaged `jobs-worker --once`, and a synthetic
  `.exe` fallback check suitable for CI/manual runner validation

Minimum assumptions that still remain external on Windows:

- MSYS2 `CLANG64` remains the supported host shell for the preview workflow,
  provisioned for CI through the pinned `vendor/gnustep-cli-new` contract
- the packaged app still expects the GNUstep/MSYS2 runtime and required DLLs
  to be available on the host
- the preview path is validated through a self-hosted Windows workflow rather
  than a generic GitHub-hosted runner image

## 5. Current Non-Claims

Not yet claimed on current `main`:

- full unit/integration/live/perf confidence parity
- generic supported production hosting on Windows
- a Windows operator path that does not depend on MSYS2 `CLANG64` and the
  GNUstep/MSYS2 runtime stack

## 6. Support Statement

Current Windows support statement:

- Windows on MSYS2 `CLANG64` is a supported preview workflow for framework
  development, runtime parity checks, and packaged release/deploy validation
- the authoritative preview verification entrypoints are
  `make phase24-windows-confidence` and `make phase31-confidence`
- Arlen does not yet claim broad production support for Windows deployments;
  Linux remains the authoritative production baseline
