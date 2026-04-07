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
  - Xcode Command Line Tools or full Xcode
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

## Known Characterized Gaps

- Apple XCTest integration is not complete yet.
- Some shell tooling and CI helpers still assume GNU/Linux utilities.
- PostgreSQL and ODBC discovery still need broader macOS normalization.
- `boomhauer` and full scaffold validation still require dedicated runtime
  verification beyond the initial build bootstrap.

## Non-Goals of Phase 30A-E

- deprecating Linux/GNUstep support
- shipping an Xcode project as the primary build path
- claiming full Apple parity for every module before runtime validation closes
- removing OpenSSL-backed crypto code in favor of Apple Security APIs

## Short-Term Direction

The next implementation slice after `30E` is:

1. Apple XCTest build/run integration
2. broader shell portability cleanup
3. dependency discovery normalization
4. runtime validation with `boomhauer`
