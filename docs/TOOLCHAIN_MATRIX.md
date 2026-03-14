# Arlen Toolchain Matrix

Last updated: 2026-03-14

This document records known-good local toolchain baselines for Arlen onboarding and CI parity.

Use `bin/arlen doctor` as the first preflight check. A healthy baseline should also pass:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make test-unit
make test-integration
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
- `libpq` presence check (when `ldconfig` is available)

## Update Policy

Update this matrix when:

- CI base images change materially.
- Arlen adds new hard toolchain/runtime dependencies.
- `arlen doctor` check set changes.
