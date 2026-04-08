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
  runtime path.

## Known Characterized Gaps

- Full repo-native Objective-C Apple XCTest bundle migration is still future
  work; the current closed baseline verifies Apple XCTest availability through
  the dedicated `tools/apple_xctest_smoke.sh` helper and the Phase 30
  confidence lane.
- Some shell tooling and CI helpers outside the core build/test/run loop still
  remain GNUstep/Linux-specific because the Linux path is still supported.
- PostgreSQL and ODBC discovery still need broader macOS normalization.
- Apple watch-mode support for `boomhauer` is not implemented yet; the runtime
  falls back to non-watch execution with an explicit warning.

## Non-Goals of Phase 30

- deprecating Linux/GNUstep support
- shipping an Xcode project as the primary build path
- claiming full Apple parity for every module before runtime validation closes
- removing OpenSSL-backed crypto code in favor of Apple Security APIs

## Current Phase 30 State

Phase 30 now includes:

1. `30P` repo-native Objective-C Apple XCTest build/run integration for the full test suite
2. `30Q` Apple-aware optional dependency normalization for PostgreSQL and ODBC-style backends
3. `30R` Apple runtime ergonomics, including watch-mode rebuild/restart handling in `boomhauer`
