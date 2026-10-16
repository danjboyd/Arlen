# Windows CLANG64

Last updated: 2026-10-16

Windows is supported for **development** from Arlen 0.3.0, on the
gnustep-cli managed MSYS2 `CLANG64` toolchain. You can install Arlen with
`install.ps1`, create apps with `arlen new`, build them, and run them under
`boomhauer`. **Production on Windows is not supported yet**: `propane`,
`jobs-worker` and service deploys are planned for 0.4.0. To install and get
started, see [Getting Started on Windows](GETTING_STARTED_WINDOWS.md).

This document covers the `CLANG64` entry path, the Windows CI lanes, and the
packaged-release contract.

Current scope on `main`:

- checked-in CLANG64 entry wrappers
- GNUstep path resolution that recognizes `/clang64`
- a platform seam for time/process/path helpers
- Windows-aware `boomhauer`, `jobs-worker`, and `propane` shell entrypoints
- Windows transport loader support for PostgreSQL and ODBC
- a Windows socket/runtime portability layer in `ALNHTTPServer`
- focused Windows DB smoke and runtime parity lanes
- a main-based Windows preview workflow

Development is the supported scope. Production hosting stays out of scope
until 0.4.0; see the support statement below.

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

For Windows runner provisioning, Arlen pins `gnustep-cli-new` as a submodule
at `vendor/gnustep-cli-new`. Use that checkout as the source of truth for the
MSYS2 `CLANG64` GNUstep managed-toolchain manifests and Windows bootstrap
validation helpers when preparing a self-hosted `windows-preview` runner. See
`docs/PLATFORM_RUNNERS.md` for the runner labels and validation commands.

## 2. Required Tools

Expected inside the active `CLANG64` environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `libdispatch`
- libcurl headers/library with TLS and asynchronous DNS (`mingw-w64-clang-x86_64-curl`)

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
make windows-confidence
```

Convenience preview runner:

```sh
bash ./tools/ci/run_windows_preview.sh
```

Those lanes are intended to verify:

- PostgreSQL (`libpq`)
- MSSQL / ODBC
- `boomhauer` watch-mode recovery
- `jobs-worker` queued-job execution
- `propane` request serving and reload handling

The preview lanes use `arlen-xctest-runner` so a Windows host can load and run
the XCTest bundle without depending on the stock bundle discovery path. They
don't use the vendored `tools-xctest` fork that Linux and macOS lanes use yet,
so Windows runs have no test filters, per-test time limits, JUnit reports or
skips. GitHub issue #116 tracks the switch. The known blockers and the
migration steps are listed in "Windows Test Runner" in
[CI Alignment](CI_ALIGNMENT.md).

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
- `make windows-confidence` exercises packaged release smoke, packaged
  `deploy doctor --base-url`, packaged `jobs-worker --once`, and a synthetic
  `.exe` fallback check suitable for CI/manual runner validation

Minimum assumptions that still remain external on Windows:

- MSYS2 `CLANG64` remains the supported host shell for the preview workflow,
  provisioned for CI through the pinned `vendor/gnustep-cli-new` contract
- the packaged app still expects the GNUstep/MSYS2 runtime and required DLLs
  to be available on the host
- the preview path is validated through a self-hosted Windows workflow rather
  than a generic GitHub-hosted runner image

## 5. Not Supported Yet

Planned for 0.4.0:

- `propane`. Its prefork worker model assumes POSIX `fork`, which Windows
  lacks, so it needs its own design.
- Supervised `jobs-worker` processes and Windows service deploys
  (`arlen deploy` targets).

Not planned:

- A Windows path that does not depend on MSYS2 `CLANG64` and the
  GNUstep/MSYS2 runtime.

## 6. Support Statement

- **Development: supported.** Installing from the release
  (`arlen-X.Y.Z-windows-x64.zip` through `install.ps1`), `arlen new`, building
  apps, and running them under `boomhauer` with watch mode are supported on
  64-bit Windows with the gnustep-cli managed `CLANG64` toolchain.
- **Production: not supported until 0.4.0.** Deploy production apps to Linux,
  the authoritative production baseline, or to macOS.
- The `windows-preview` CI lane runs `make phase24-windows-confidence` and
  `make test-unit`. `make windows-confidence` (packaged release and deploy
  parity) is a manual lane until Windows production support lands in 0.4.0.
