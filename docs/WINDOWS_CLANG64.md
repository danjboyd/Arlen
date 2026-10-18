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

`run_clang64.ps1` finds the MSYS2 root itself: `-MsysRoot`, then
`ARLEN_MSYS_ROOT`, then the gnustep-cli managed toolchain
(`%LOCALAPPDATA%\gnustep-cli`, then `%ProgramFiles%\gnustep-cli`), then a stock
MSYS2 at `C:\msys64`. Arlen's runtime uses the same search order to find
`bash.exe`, `libpq` and ODBC (`ALNPlatformWindowsMSYSRoots`).

### Toolchain from gnustep-cli

The public way to get a `CLANG64` GNUstep toolchain is the gnustep-cli
PowerShell bootstrap. Arlen 0.3.0 needs gnustep-cli `v0.1.1`:

```powershell
iwr https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.1/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1
powershell -ExecutionPolicy Bypass -File gnustep-bootstrap.ps1 setup --user --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.1/release-manifest.json
```

It installs to `%LOCALAPPDATA%\gnustep-cli` (pass `--root DIR` for another
location), which is itself an MSYS2 root. `v0.1.1` includes libcurl (with TLS
and asynchronous DNS), so nothing else needs to be installed into it. The
prebuilt Windows release bundles `libpq.dll`.

Never run `pacman -Sy` or `pacman -Syu` against the managed root, and don't
install anything into it. The managed root is a pinned toolchain: a database
refresh makes later installs partial upgrades (one left the root's `python3`
newer than its `expat`, so `import pyexpat` failed), and the live repository's
current clang breaks the shipped gnustep-base headers.

`v0.1.1` fixes the `v0.1.0` toolchain's libdispatch header clashes over
`mode_t` and `pthread_attr_t`. Arlen's build keeps its workarounds
(`-DHAVE_MODE_T=1`, no `<pthread.h>` in Arlen sources), which are harmless on
`v0.1.1`. Arlen also avoids `+dataWithContentsOfFile:options:error:`, which
the `v0.1.0` gnustep-base lacked (it uses `ALNPlatformMappedFileData`). The
managed root mounts drives under `/cygdrive/c` rather than `/c`, so Arlen's
scripts convert paths with `cygpath`.

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
- `libdispatch`
- libcurl headers/library with TLS and asynchronous DNS (`mingw-w64-clang-x86_64-curl`, included in gnustep-cli `v0.1.1`)

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

The preview lanes run through the vendored `tools-xctest` fork, the same
runner the Linux and macOS lanes use (GitHub issue #116), so Windows runs get
test filters, per-test time limits, JUnit reports and skips. The Windows make
wiring is described in "Windows Test Runner" in [CI Alignment](CI_ALIGNMENT.md).

Windows checkout and shell notes:

- the repository's `.gitattributes` checks every file out with LF, whatever
  `core.autocrlf` says (Git for Windows defaults it to `true`); clone after
  that file exists, or re-checkout with `git rm --cached -r . && git reset
  --hard` if an older clone has CRLF scripts
- the `CLANG64` `python3` is a native Windows program and prints CRLF; shell
  code that captures its output must strip `\r`
- a shell started by a native process (xctest, an app) sees MSYS2 path
  variables in `C:/...` form; `tools/resolve_gnustep.sh` prints one spelling so
  the framework's build-flags sentinel stays stable across both
- `arlen test --app` works: `boomhauer --build-tests` builds
  `.boomhauer/build/tests/AppTests.xctest/AppTests.dll` against the
  framework's vendored tools-xctest (no XCTest ships in the toolchain), and
  `tools/run_app_tests.sh` puts its `XCTest-0.dll` on `PATH`
- the gnustep-cli `v0.1.1` toolchain ships no MSYS2 `perl`; test helpers use
  coreutils `timeout` instead

## 4. Packaged Release Contract

The current Windows packaged-release contract is now explicit:

- build releases from an MSYS2 `CLANG64` shell with the GNUstep environment
  initialized
- a release tree that ships `build/arlen.exe`, `build/boomhauer.exe`,
  `build/eocc.exe` and `build/lib/libArlenFramework.a` without `build/obj`
  carries `build/.release-prebuilt` (`source_digest`, `toolchain`,
  `toolchain_sha256`; written by `aln_release_write_manifest` in
  `tools/release_prebuilt.sh`). While the digest over the framework sources
  and the gnustep-cli `toolchain_version` both still match, `bin/arlen` and
  `boomhauer` use the prebuilt outputs instead of `make`. Any mismatch deletes
  the manifest and the normal make checks rebuild from then on; a
  `toolchain_sha256` mismatch alone only warns.
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

- `propane` as a production manager. `arlen propane` starts from a Windows
  console, but its worker supervision, reloads and signal handling are not
  validated on Windows yet.
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
