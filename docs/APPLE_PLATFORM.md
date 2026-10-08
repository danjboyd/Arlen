# Apple Platform

## Purpose

This document defines the Apple-runtime contract for Arlen on macOS.

Arlen historically assumed a GNUstep-native build and runtime environment. On
the `mac` branch, macOS is being ported to Apple's Objective-C runtime and
Foundation APIs instead of reusing the GNUstep bootstrap path.

## Current Contract

- macOS uses Apple Foundation, not GNUstep Foundation.
- macOS builds must not require `GNUSTEP_SH`, `GNUSTEP_MAKEFILES`,
  `gnustep-config`, or `GNUstep.sh`.
- Apple builds use Apple clang through `xcrun --sdk macosx clang`.
- Apple builds currently depend on Homebrew `openssl@3` for existing OpenSSL
  imports in the runtime and security layers.
- Linux remains on the existing GNUstep toolchain path for now.

## Initial Supported Baseline

- OS baseline: macOS 15.x
- Architecture baseline: `arm64`
- Toolchain baseline:
  - full Xcode selected through `xcode-select`
  - Apple clang available through `xcrun`
  - `python3`
  - `curl`
- Current recommended package dependency:
  - `brew install openssl@3`

Optional dependencies that will be normalized later:

- `libpq` / PostgreSQL client libraries
- ODBC manager and headers for MSSQL transport

## Build Entry Path

Use the Apple builder:

```bash
./bin/build-apple
```

Build the optional repo-root `boomhauer` smoke target too:

```bash
./bin/build-apple --with-boomhauer
```

The Apple builder currently emits artifacts under `build/apple/`.

## Doctor Entry Path

Use:

```bash
./bin/arlen doctor
```

On macOS, `arlen doctor` now validates the Apple toolchain path rather than
GNUstep bootstrap scripts.

## Current Verified Scope

- `./bin/build-apple` builds `eocc`, `libArlenFramework.a`, and `arlen`.
- `./bin/build-apple` also builds `build/apple/apple-auth-audit`, which
  exercises the Apple-native password hashing, OIDC, and WebAuthn seams
  against the built framework archive.
- `./bin/build-apple --with-boomhauer` builds the repo-root Apple boomhauer
  target.
- `./bin/test --smoke-only` now uses the Apple runtime path on macOS:
  - runs an Apple XCTest smoke through `tools/apple_xctest_smoke.sh` when full
    Xcode is active
  - runs `arlen doctor`
  - builds the Apple artifacts
  - runs the Apple-native auth/security audit binary
  - scaffolds a fresh app
  - starts it through the Apple runtime
  - verifies `/`, `/healthz`, and `/openapi`
  - builds and runs `examples/auth_primitives`
  - verifies local login + TOTP MFA elevation and stub OIDC provider login
- `./bin/boomhauer` now has an Apple app-root path as well as a repo-root
  runtime path, including watch-mode rebuild/restart.
- `./tools/test_apple.sh` builds and runs the repo-native Apple XCTest unit
  bundle (`tools/build_apple_xctest.sh --suite unit`) before the runtime
  checks above.

## Known Characterized Gaps

The Apple path covers the core build/test/run loop. These areas are still
Linux-only or narrower on macOS:

- Test coverage:
  - `tools/build_apple_xctest.sh` builds only the `unit` suite. The
    integration suite, durable jobs, `tests/phase20`, and the browser error
    audit run only on GNUstep.
  - The `apple-baseline` CI lane is non-required. It runs the smoke lane and
    selected XCTest filters, not the full unit bundle. Run
    `./tools/test_apple.sh` locally for the full bundle.
  - PostgreSQL- and MSSQL-backed tests skip unless `ARLEN_PG_TEST_DSN` or the
    MSSQL test DSN is set.
- Tooling:
  - `propane` and `jobs-worker` expect GNUstep build output
    (`.boomhauer/build/`) and read `/proc`.
  - `arlen build`, `arlen check`, `arlen test`, and `arlen perf` call GNU
    `make`.
  - Deploy packaging and the systemd runbook target Linux.
  - Sanitizer, fault-injection, fuzz, soak, and perf lanes are Linux-only.
- Runtime:
  - File-descriptor pressure diagnostics read `/proc` and do nothing on macOS.
  - File responses use read/write instead of `sendfile`.
  - Apple builds target `arm64` only.
- Shell scripts that run on macOS must work with `/bin/bash` 3.2. In particular,
  expand arrays that may be empty as `${a[@]+"${a[@]}"}` under `set -u`.

## Non-Goals

- deprecating Linux/GNUstep support
- shipping an Xcode project as the primary build path
- claiming full Apple parity for every module before runtime validation closes
- removing OpenSSL-backed crypto code in favor of Apple Security APIs

## Current State

The Apple-runtime path now includes:

1. `30P` repo-native Objective-C Apple XCTest build/run integration for the full test suite
2. `30Q` Apple-aware optional dependency normalization for PostgreSQL and ODBC-style backends
3. `30R` Apple runtime ergonomics, including watch-mode rebuild/restart handling in `boomhauer`

## HTTP/data contract verification

The additive `ALNSynchronousHTTPResult` API uses system libcurl on Apple to retain
received reason phrases and complete redirect-boundary bodies. Build scripts
link `-lcurl`; custom consumers must do so too. Existing synchronous helpers
continue using NSURLSession. See [HTTP client](HTTP_CLIENT.md).

Apple confidence installs `postgresql@17` and `libpq` for a private database and
runs `tools/ci/run_apple_client_data_regressions.sh` with Apple XCTest. This covers
the shared HTTP/retry contracts and NSDate timestamp precision without a live
provider. These dependencies are for database testing, not an application server
requirement. See [Testing workflow](TESTING_WORKFLOW.md).
