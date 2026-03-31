# Arlen Toolchain Matrix

Last updated: 2026-03-31

This document records known-good local toolchain baselines for Arlen onboarding and CI parity.

Use `bin/arlen doctor` as the first preflight check. A healthy baseline should also pass:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make test-unit
make test-integration
```

For the native Windows preview on branch `windows/clang64`, use the checked-in
MSYS2 launcher instead:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make all"
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
| GNUstep tooling script | `/usr/GNUstep/System/Library/Makefiles/GNUstep.sh` | Present |
| GNUstep config tool | `source GNUstep.sh && command -v gnustep-config` | `/usr/GNUstep/System/Tools/gnustep-config` |
| XCTest runner | `command -v xctest` | `/usr/GNUstep/System/Tools/xctest` |

## Windows Preview Baseline (2026-03-31)

This is the native Windows branch contract on `windows/clang64`. It is a
supported development/CI baseline, not a native Windows production-manager
contract.

| Component | Command | Expected baseline |
| --- | --- | --- |
| Host shell | `powershell` | launches `scripts/run_clang64.ps1` |
| MSYS2 shell | `bash -lc 'echo $MSYSTEM'` | `CLANG64` |
| GNUstep tooling script | `test -f /clang64/share/GNUstep/Makefiles/GNUstep.sh` | Present |
| GNUstep config tool | `command -v gnustep-config` | available inside `CLANG64` shell |
| Compiler | `clang --version` | available inside `CLANG64` shell |
| Build tool | `make --version` | available inside `CLANG64` shell |
| XCTest runner | `command -v xctest` | available inside `CLANG64` shell |
| Preview build | `make all` | builds `eocc`, preview `libArlenFramework.a` including data-layer sources, `arlen`, and `arlen-xctest-runner` |
| Focused Windows test lane | `make phase24-windows-tests` | runs `ArlenPhase21TemplateTests.xctest` through the repo-local bundle runner |
| Focused Windows DB smoke lane | `make phase24-windows-db-smoke` | validates libpq/ODBC transport loading before connection failure |
| Windows confidence lane | `make phase24-windows-confidence` | runs build, focused tests, DB transport smoke, and app-root CLI smoke |
| App-root prepare-only smoke | `arlen boomhauer --no-watch --prepare-only` | scaffolded app artifacts build cleanly |

Related guide:

- `docs/WINDOWS_CLANG64.md`

## CI Toolchain Contract

Arlen CI requires a clang-built GNUstep stack. In practice that means:

- `gnustep-config --objc-flags` includes `-fobjc-runtime=gnustep-2.2`
- `clang`, `gnustep-config`, and `xctest` are all available after sourcing `GNUstep.sh`
- the toolchain is installed at `/usr/GNUstep` unless a workflow explicitly overrides `GNUSTEP_SH`

For the Windows preview branch, the checked-in bootstrap contract is:

- PowerShell outer launcher: `scripts/run_clang64.ps1`
- MSYS inner launcher: `scripts/run_clang64.sh`
- GNUstep bootstrap path: `/clang64/share/GNUstep/Makefiles/GNUstep.sh`
- Windows CI workflow: `.github/workflows/phase24-windows-preview.yml`

The workflow bootstrap entry point is:

- `tools/ci/install_ci_dependencies.sh`

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

## Doctor Check Mapping

`bin/arlen-doctor` currently validates:

- framework root resolution (`ARLEN_FRAMEWORK_ROOT` or auto-detected checkout)
- app config presence (`config/app.plist`)
- GNUstep script availability
- required tool commands (`clang`, `make`, `bash`)
- recommended tool commands (`xctest`, `python3`, `curl`)
- `gnustep-config` execution after sourcing GNUstep
- `libpq` presence check (`ARLEN_LIBPQ_LIBRARY`, CLANG64 DLLs, `pkg-config`, `pg_config`, or `ldconfig`, depending on platform)
- `libodbc` presence check (`ARLEN_ODBC_LIBRARY`, CLANG64/system DLLs, `pkg-config`, or `ldconfig`, depending on platform)
- presence of `docs/TOOLCHAIN_MATRIX.md` itself so the known-good baseline
  remains discoverable

## Update Policy

Update this matrix when:

- CI base images change materially.
- Arlen adds new hard toolchain/runtime dependencies.
- `arlen doctor` check set changes.
