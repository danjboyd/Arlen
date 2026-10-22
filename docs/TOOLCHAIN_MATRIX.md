# Arlen Toolchain Matrix

Last updated: 2026-10-22

This document records known-good local toolchain baselines for Arlen onboarding and CI parity.

Use `bin/arlen doctor` as the first preflight check. A healthy baseline should also pass:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
make test-unit
make test-integration
```

Windows development entry path (gnustep-cli managed MSYS2 `CLANG64`
toolchain; see `docs/GETTING_STARTED_WINDOWS.md`):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make arlen"
```

Windows is supported for development from 0.3.0. Production (`propane`,
`jobs-worker`, service deploys) is planned for 0.4.0.

## Linux release runtime

Linux release setup builds a normal, uninstrumented runtime with the existing
custom builder at commit `5469b5dfd442f1091475fa6600cfd487af878e8f`. Its source
archive SHA256 is `55703ff2354613af3b37c92acc3daef4f33e0d3b7bbc66ede2858a5fd5a03197`.
Locks under `tools/runtime/` identify Debian 13 amd64/arm64 and Ubuntu 26.04
amd64 independently. All use identical component revisions and patch digests;
Debian amd64 retains the original lock SHA256
`2bc1f69a6f2b4073adaa0c8892204995bc2b0672d1d136ffb2af611cd5d15058`.
The patches are shared with the diagnostic toolchain in
`tools/ci/tsan-toolchain/`; production output has no TSan instrumentation.

Native build dependencies on supported Debian/Ubuntu hosts:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends ca-certificates curl git tar gzip tzdata \
  make cmake ninja-build pkg-config autoconf automake libtool python3 clang lld \
  libblocksruntime-dev libssl-dev libsqlite3-0 zlib1g-dev libxml2-dev libxslt1-dev \
  libicu-dev libavahi-client-dev libcurl4-gnutls-dev libgnutls28-dev libffi-dev
python3 tools/setup_runtime.py build
source tools/source_gnustep_env.sh
```

The helper builds directly at its final absolute prefix and records source,
patch, build-host and ELF provenance. It refuses system/managed roots and
existing invalid prefixes. It never replaces a managed gnustep-cli pin or
changes `ld.so.conf`. Native target qualification must cover the actual CPU,
compiler and ICU: Debian uses clang 19/ICU 76, Ubuntu uses clang 21/ICU 78.
The public install CI runs the installed app and fourteen concurrency controls
on each native target, including arm64. These normal controls exercise weak
memory paths; race-detector acceptance remains the separate instrumented TSan
gate. A successful amd64 run alone does not establish arm64 qualification.
See [Getting Started](GETTING_STARTED.md#manual-toolchain-setup) for selection
and service paths.

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
| XCTest runner | `make test-unit` | Vendored `vendor/tools-xctest` v0.5.0 |

## Apple Baseline (2026-10-08)

This is the closed Apple-runtime baseline. It is a verified build/runtime
contract, not a claim that every Linux/GNUstep test lane runs on Apple; see
`docs/APPLE_PLATFORM.md` for the Linux-only areas.

| Component | Command | Observed baseline |
| --- | --- | --- |
| OS family | `uname -s` | `Darwin` |
| Architecture | `uname -m` | `arm64` |
| OS version | `sw_vers -productVersion` | `26.5.1` |
| Active developer dir | `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Apple SDK | `xcrun --show-sdk-path` | `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk` |
| C/ObjC compiler | `xcrun --find clang` | `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang` |
| XCTest CLI | `xcrun --find xctest` | `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest` |
| Homebrew | `brew --prefix` | `/opt/homebrew` |
| OpenSSL package | `brew list --versions openssl@3` | `openssl@3 3.6.2` |

Apple path notes:

- use `./bin/arlen doctor`
- use `./bin/build-apple`
- use `./bin/test --smoke-only`
- use `bash ./tools/ci/run_apple_baseline_confidence.sh` for the artifact-backed
  Apple baseline
- do not source GNUstep bootstrap scripts on the Apple path
- Apple XCTest availability is verified with `tools/apple_xctest_smoke.sh`
- the repo-native Apple XCTest bundles are built by
  `tools/build_apple_xctest.sh --suite unit|integration|durable-jobs` and run
  by `./tools/test_apple_xctest.sh` (`arlen test`); `./tools/test_apple.sh`
  runs the unit bundle plus the runtime checks

## Known libobjc2 Defect: Instance `@synchronized`

GNUstep libobjc2 (v2.3 and current master) publishes the lock for the first
`@synchronized` on an object before initializing it
([gnustep/libobjc2#424](https://github.com/gnustep/libobjc2/issues/424)).
When several threads lock a fresh object for the first time at once, they can
hang, lose mutual exclusion, or abort with
`pthread_mutex_lock.c:130: mutex->__data.__owner == 0`. Class objects
(`@synchronized([SomeClass class])`) use a different path and are not affected.

Arlen does not use `@synchronized` on instances. Framework objects that request
threads share create an `NSLock` or `NSRecursiveLock` in their initializer;
static registries create theirs in the same `dispatch_once` block as the
registry. Application code on GNUstep should do the same: create the lock
before the object can reach another thread, and use `NSRecursiveLock` when a
section may re-enter. `BuildPolicyTests` rejects instance `@synchronized` in
`src/`, `modules/`, `tools/` and `examples/`. No runtime upgrade or
configuration change is required.

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
6. a gnustep-cli managed toolchain at `~/.local/share/gnustep-cli` or
   `/opt/gnustep-cli`. When the resolved toolchain is a gnustep-cli root
   (it has `toolchain-manifest.json`), the helper also prepends `<root>/lib`
   to `LD_LIBRARY_PATH`, because that is where those toolchains keep
   `libdispatch` and GNUstep.sh does not add it.

The gnustep-cli stable `v0.1.0` managed toolchain (`linux-amd64-clang`,
libobjc2 2.3, gnustep-base 1.31.1, republished 2026-10-13 as a Debian 13
build) was verified with Arlen on Debian 13 amd64 on 2026-10-13. Install it
with the release-asset bootstrap,
`https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0/gnustep-bootstrap.sh`.
That script verifies the production-signed manifest. The raw script at the
repo's `v0.1.0` tag installs the `0.1.0-dev` prerelease instead.

gnustep-cli builds a toolchain per distribution:

| Distribution | Toolchain target | ICU | glibc | clang |
|---|---|---|---|---|
| Debian 13 (amd64) | `linux-amd64-clang` | 76 | 2.41 | 19 |
| Debian 13 (arm64) | `linux-arm64-clang` | 76 | 2.41 | 19 |
| Ubuntu 26.04 LTS | `linux-ubuntu2604-amd64-clang` | 78 | 2.43 | 21 |

Both are verified with Arlen by the `linux-public-toolchain` CI lane, which
runs in clean containers (arm64 on a GitHub arm runner). Debian 12,
Ubuntu 24.04, and Ubuntu arm64 have not been verified with Arlen. Besides the toolchain's own host prerequisites, Arlen
needs `libssl-dev`. The GnuTLS libcurl that the toolchain installs
(`libcurl4-gnutls-dev`) satisfies Arlen's libcurl requirement. The
check covered bootstrap `setup --user`, `make all`, `arlen new`, and
`boomhauer` serving `/healthz`. It is the documented public Linux toolchain
path; see `docs/GETTING_STARTED.md`.

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
  - `tools/ci/run_apple_baseline_confidence.sh` as the canonical artifact gate

The workflow bootstrap entry point is:

- `tools/ci/install_ci_dependencies.sh`

Current GitHub Actions workflow surface:

- `linux-quality`
  - authoritative Linux/GNUstep merge gate
- `linux-sanitizers`
  - authoritative Linux/GNUstep sanitizer merge gate
- `static-analysis`
  - required scan-build and clang-tidy merge gate; scan-build comes from the
    `clang-tools-<major>` package matching the runner's `clang`, clang-tidy
    is pinned to `clang-tidy==22.1.8` from PyPI
- `docs-quality`
  - required docs/API-reference/browser-doc merge gate
- `apple-baseline`
  - non-required Apple baseline-confidence lane
- `windows-preview`
  - non-required Windows preview-confidence lane
- `release-certification`
  - release-only certification lane

Current documented required checks for `main`:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `static-analysis / scan-build`
- `static-analysis / clang-tidy`
- `docs-quality / docs-gate`

Current documented non-required checks:

- `apple-baseline / apple-baseline`
- `windows-preview` (exact Actions job context)
- `release-certification / release-certification`

Windows preview helpers:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`
- `tools/ci/run_windows_preview.sh`
- `tools/ci/run_windows_confidence.sh`
- `vendor/gnustep-cli-new` pins the Windows MSYS2/GNUstep
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
  - installs Homebrew `openssl@3`, `postgresql@17`, and `libpq` and validates the Apple toolchain path
- `ARLEN_CI_APPLE_STRATEGY=preinstalled`
  - validates an Apple runner image that already has the required dependencies

If CI migrates to a first-party source-built GNUstep toolchain, install it into `/usr/GNUstep` so the existing build scripts, tests, and shell-generated probes continue to work without per-file path rewrites.

Optional contributor override:

- Arlen vendors the maintained fork `danjboyd/tools-xctest` (upstream
  GNUstep/tools-xctest is dormant) at `vendor/tools-xctest`, pinned to a
  release tag; test bundles compile and link against its `libXCTest`
- `make test-unit`, `make test-integration`, and focused filter targets build
  and use `vendor/tools-xctest/obj/xctest` by default
- set `ARLEN_USE_VENDORED_XCTEST=0` to use the system `xctest`
- set `ARLEN_XCTEST=/path/to/xctest` and, when needed,
  `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj` to test a
  different local runner

Platform runner provisioning:

- Arlen vendors `gnustep-cli-new` at `vendor/gnustep-cli-new` for the Windows
  Windows runner path
- use the pinned checkout's Windows integration docs, managed-toolchain
  manifests, and bootstrap validation helpers when preparing the MSYS2
  `CLANG64` GNUstep environment for `windows-preview`
- the runner labels, validation commands, and package-manager boundary are
  documented in `docs/PLATFORM_RUNNERS.md`
- this pin supports the non-required Windows preview lane; it does not change
  the authoritative Linux/GNUstep merge gate

Windows preview CI validates these development layers serially:

- runtime parity via `make phase24-windows-confidence`
- the unit suite via `make test-unit`
- the complete integration suite via `make test-integration`, with existing
  platform and live-service skips reported explicitly
- focused static/realtime transport security regressions

The job retains its 90-minute budget and existing branch-protection policy.

Packaged release/deploy parity (`make windows-confidence`) is a manual lane
until Windows production support in 0.4.0.

Linux/GNUstep deploy confidence now validates three layers:

- local deploy orchestration via `make phase29-confidence`
- packaged release/deploy parity via `make windows-confidence`
- target-aware deploy compatibility and `propane` handoff coverage via
  `make phase32-confidence`

## Doctor Check Mapping

`bin/arlen-doctor` currently validates:

- framework root resolution (`ARLEN_FRAMEWORK_ROOT` or auto-detected checkout)
- app config presence (`config/app.plist`)
- GNUstep script availability
- required tool commands (`clang`, `make`, `bash`)
- test runner: the vendored `tools-xctest` when `vendor/tools-xctest` is
  present, otherwise `xctest` on `PATH`
- recommended tool commands (`python3`, `curl`)
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

Apple builds additionally link the system libcurl for the received HTTP result
API. HTTP/data contract confidence uses Apple XCTest and a disposable PostgreSQL
cluster; GNUstep runs equivalent coverage with the vendored tools-xctest runner.

Native runtime qualification also runs the fixed-date contract in
`tests/fixtures/runtime/icu_runtime_contract.m`. It verifies Chicago winter and
summer offsets through `NSTimeZone`, exact POSIX-locale date formatting through
`NSDateFormatter`, and records the actual ICU library/data/timezone versions.
Install `tzdata` for system zoneinfo; each target keeps its distribution's ICU
without an external timezone-data override. Native-control and ICU failure logs
are retained by the installer smoke's artifact cleanup path.
