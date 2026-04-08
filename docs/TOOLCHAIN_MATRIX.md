# Arlen Toolchain Matrix

Last updated: 2026-04-08

This document records known-good local toolchain baselines for Arlen onboarding and CI parity.

Use `bin/arlen doctor` as the first preflight check. A healthy baseline should also pass:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
make test-unit
make test-integration
```

Windows preview entry path:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make arlen"
```

## Known-Good Baseline (2026-02-20)

| Component | Command | Observed baseline |
| --- | --- | --- |
| OS family | `uname -s` | `Linux` |
| C/ObjC compiler | `clang --version` | `Debian clang version 19.1.7 (3+b1)` |
| Build tool | `make --version` | `GNU Make 4.4.1` |
| Shell | `bash --version` | `GNU bash 5.2.37` |
| Python | `python3 --version` | `Python 3.13.5` |
| HTTP client | `curl --version` | `curl 8.14.1` |
| GNUstep bootstrap helper | `source /path/to/Arlen/tools/source_gnustep_env.sh` | Present in repo |
| GNUstep tooling script | `/usr/GNUstep/System/Library/Makefiles/GNUstep.sh` | Present on current known-good baseline |
| GNUstep config tool | `source /path/to/Arlen/tools/source_gnustep_env.sh && command -v gnustep-config` | `/usr/GNUstep/System/Tools/gnustep-config` |
| XCTest runner | `command -v xctest` | `/usr/GNUstep/System/Tools/xctest` |

## Apple Bring-Up Baseline (2026-04-07)

This is the current Apple-runtime characterization baseline for the `mac`
branch. It is a bring-up checkpoint, not yet a full parity claim.

| Component | Command | Observed baseline |
| --- | --- | --- |
| OS family | `uname -s` | `Darwin` |
| Architecture | `uname -m` | `arm64` |
| OS version | `sw_vers -productVersion` | `15.5` |
| Apple SDK | `xcrun --show-sdk-path` | `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` |
| C/ObjC compiler | `xcrun --find clang` | `/Library/Developer/CommandLineTools/usr/bin/clang` |
| Homebrew | `brew --prefix` | `/opt/homebrew` |
| OpenSSL package | `brew list --versions openssl@3` | `openssl@3 3.6.0` |

Apple path notes:

- use `./bin/arlen doctor`
- use `./bin/build-apple`
- do not source GNUstep bootstrap scripts on the Apple path
- Apple XCTest integration is not yet closed out

## GNUstep Resolution Contract

Repo-local shell initialization should prefer:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
```

That helper resolves the active GNUstep shell init path in this order:

1. `GNUSTEP_SH`
2. `GNUSTEP_MAKEFILES/GNUstep.sh`
3. `gnustep-config --variable=GNUSTEP_MAKEFILES`
4. `/clang64/share/GNUstep/Makefiles/GNUstep.sh`
5. `/usr/GNUstep/System/Library/Makefiles/GNUstep.sh`

Contributors who already source a managed toolchain env script can keep doing
that, as long as it exposes a valid `GNUSTEP_SH` or `GNUSTEP_MAKEFILES`.

## CI Toolchain Contract

Arlen CI requires a clang-built GNUstep stack. In practice that means:

- `gnustep-config --objc-flags` includes `-fobjc-runtime=gnustep-2.2`
- `clang`, `gnustep-config`, and `xctest` are all available after sourcing `GNUstep.sh`
- current CI runner baseline installs the toolchain at `/usr/GNUstep`
- repo-local helpers and `arlen doctor` also support `GNUSTEP_SH` /
  `GNUSTEP_MAKEFILES`-driven toolchains for local development

The workflow bootstrap entry point is:

- `tools/ci/install_ci_dependencies.sh`

Windows preview helpers:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`
- `tools/ci/run_phase24_windows_preview.sh`
- `tools/ci/run_phase31_confidence.sh`

Supported CI bootstrap strategies:

- `ARLEN_CI_GNUSTEP_STRATEGY=apt`
  - installs `gnustep-clang-tools-xctest`, `gnustep-clang-make`, and `gnustep-clang-libs-base`
- `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled`
  - current default on `iep-apt` self-hosted runners
  - validates a runner image that already has the clang-built GNUstep stack installed
- `ARLEN_CI_GNUSTEP_STRATEGY=bootstrap`
  - runs `ARLEN_CI_GNUSTEP_BOOTSTRAP_SCRIPT` before validation
  - use this when the runner must build/install its own GNUstep stack

If CI migrates to a first-party source-built GNUstep toolchain, install it into `/usr/GNUstep` so the existing build scripts, tests, and shell-generated probes continue to work without per-file path rewrites.

Optional contributor override:

- set `ARLEN_XCTEST=/path/to/patched/xctest` to use a filter-capable runner for `make test-unit-filter` / `make test-integration-filter`
- if that runner comes from a local uninstalled `tools-xctest` build, also set `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj`
- stock Debian `xctest` remains the baseline for the normal unfiltered test and confidence commands

Windows preview CI currently validates two layers:

- runtime parity via `make phase24-windows-confidence`
- packaged release/deploy parity via `make phase31-confidence`

## Doctor Check Mapping

`bin/arlen-doctor` currently validates:

- framework root resolution (`ARLEN_FRAMEWORK_ROOT` or auto-detected checkout)
- app config presence (`config/app.plist`)
- GNUstep script availability
- required tool commands (`clang`, `make`, `bash`)
- recommended tool commands (`xctest`, `python3`, `curl`)
- `gnustep-config` execution after sourcing GNUstep
- `dispatch/dispatch.h` availability after GNUstep init
- `libpq` presence check (when `ldconfig` is available)
- presence of `docs/TOOLCHAIN_MATRIX.md` itself so the known-good baseline
  remains discoverable

## Update Policy

Update this matrix when:

- CI base images change materially.
- Arlen adds new hard toolchain/runtime dependencies.
- `arlen doctor` check set changes.
