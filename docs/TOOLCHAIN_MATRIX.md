# Arlen Toolchain Matrix

Last updated: 2026-04-15

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

## Apple Baseline (2026-04-08)

This is the closed Apple-runtime baseline for Phase 30 on the `mac` branch. It
is a verified build/runtime contract, not a claim that every Linux/GNUstep
test lane has already been migrated to Apple-native XCTest bundles.

| Component | Command | Observed baseline |
| --- | --- | --- |
| OS family | `uname -s` | `Darwin` |
| Architecture | `uname -m` | `arm64` |
| OS version | `sw_vers -productVersion` | `26.4` |
| Active developer dir | `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Apple SDK | `xcrun --show-sdk-path` | `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk` |
| C/ObjC compiler | `xcrun --find clang` | `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang` |
| XCTest CLI | `xcrun --find xctest` | `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest` |
| Homebrew | `brew --prefix` | `/opt/homebrew` |
| OpenSSL package | `brew list --versions openssl@3` | `openssl@3 3.6.0` |

Apple path notes:

- use `./bin/arlen doctor`
- use `./bin/build-apple`
- use `./bin/test --smoke-only`
- use `bash ./tools/ci/run_phase30_confidence.sh` for the artifact-backed
  Apple baseline
- do not source GNUstep bootstrap scripts on the Apple path
- Apple XCTest availability is now verified with `tools/apple_xctest_smoke.sh`
- full repo-native Objective-C Apple XCTest bundle migration remains future work

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

Arlen CI now has two platform contracts:

- Linux/GNUstep lanes require a clang-built GNUstep stack. In practice that
  means:

- `gnustep-config --objc-flags` includes `-fobjc-runtime=gnustep-2.2`
- `clang`, `gnustep-config`, and `xctest` are all available after sourcing `GNUstep.sh`
- current CI runner baseline installs the toolchain at `/usr/GNUstep`
- repo-local helpers and `arlen doctor` also support `GNUSTEP_SH` /
  `GNUSTEP_MAKEFILES`-driven toolchains for local development

- macOS Apple lanes require:
  - full Xcode selected through `xcode-select`
  - `xcrun --find xctest` resolving successfully
  - Homebrew `openssl@3`
  - `tools/ci/run_phase30_confidence.sh` as the canonical artifact gate

The workflow bootstrap entry point is:

- `tools/ci/install_ci_dependencies.sh`

Current GitHub Actions workflow surface:

- `linux-quality`
  - authoritative Linux/GNUstep merge gate
- `linux-sanitizers`
  - authoritative Linux/GNUstep sanitizer merge gate
- `docs-quality`
  - required docs/API-reference/browser-doc merge gate
- `apple-baseline`
  - non-required Apple baseline-confidence lane
- `windows-preview`
  - non-required Windows preview-confidence lane
- `release-certification`
  - release-only Phase 9J certification lane

Current documented required checks for `main`:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `docs-quality / docs-gate`

Current documented non-required checks:

- `apple-baseline / apple-baseline`
- `windows-preview / windows-preview`
- `release-certification / release-certification`

Windows preview helpers:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`
- `tools/ci/run_phase24_windows_preview.sh`
- `tools/ci/run_phase31_confidence.sh`
- `vendor/gnustep-cli-new` pins the Phase 34K Windows MSYS2/GNUstep
  provisioning source for self-hosted `windows-preview` runners

Supported CI bootstrap strategies:

- `ARLEN_CI_GNUSTEP_STRATEGY=apt`
  - installs `gnustep-clang-tools-xctest`, `gnustep-clang-make`, and `gnustep-clang-libs-base`
- `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled`
  - current default on `iep-apt` self-hosted runners
  - validates a runner image that already has the clang-built GNUstep stack installed
- `ARLEN_CI_GNUSTEP_STRATEGY=bootstrap`
  - runs `ARLEN_CI_GNUSTEP_BOOTSTRAP_SCRIPT` before validation
  - use this when the runner must build/install its own GNUstep stack
- `ARLEN_CI_APPLE_STRATEGY=brew`
  - installs Homebrew `openssl@3` and validates the Apple toolchain path
- `ARLEN_CI_APPLE_STRATEGY=preinstalled`
  - validates an Apple runner image that already has the required dependencies

If CI migrates to a first-party source-built GNUstep toolchain, install it into `/usr/GNUstep` so the existing build scripts, tests, and shell-generated probes continue to work without per-file path rewrites.

Optional contributor override:

- Arlen vendors GNUstep/tools-xctest at `vendor/tools-xctest` and pins the
  Apple-style filter patch from PR 5 until that support is available upstream
- `make test-unit`, `make test-integration`, and focused filter targets build
  and use `vendor/tools-xctest/obj/xctest` by default
- set `ARLEN_USE_VENDORED_XCTEST=0` to use the system `xctest`
- set `ARLEN_XCTEST=/path/to/xctest` and, when needed,
  `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj` to test a
  different local runner

Platform runner provisioning:

- Arlen vendors `gnustep-cli-new` at `vendor/gnustep-cli-new` for the Phase 34K
  Windows runner path
- use the pinned checkout's Windows integration docs, managed-toolchain
  manifests, and bootstrap validation helpers when preparing the MSYS2
  `CLANG64` GNUstep environment for `windows-preview`
- the runner labels, validation commands, and package-manager boundary are
  documented in `docs/PLATFORM_RUNNERS.md`
- this pin supports the non-required Windows preview lane; it does not change
  the authoritative Linux/GNUstep merge gate

Windows preview CI currently validates two layers:

- runtime parity via `make phase24-windows-confidence`
- packaged release/deploy parity via `make phase31-confidence`

Linux/GNUstep deploy confidence now validates three layers:

- local deploy orchestration via `make phase29-confidence`
- packaged release/deploy parity via `make phase31-confidence`
- target-aware deploy compatibility and `propane` handoff coverage via
  `make phase32-confidence`

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
