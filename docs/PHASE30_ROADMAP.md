# Phase 30 Roadmap

Status: in progress  
Last updated: 2026-04-07

## Goal

Port Arlen to a first-class Apple-runtime path on macOS so the framework can
build and run against Apple's Objective-C/Foundation toolchain without
requiring GNUstep for that platform.

Phase 30 keeps the existing Linux/GNUstep path intact for now. The work in
this phase is additive: establish the Apple contract, stand up an Apple-native
build/bootstrap path, and create the portability seams needed for the rest of
the port.

## 30A. Apple Platform Contract

Deliver a written support contract for the Apple path.

Shipped in this subphase:

- macOS is now treated as a distinct platform target rather than a GNUstep
  variant.
- The Apple path targets:
  - macOS 15.x baseline for initial bring-up
  - Apple clang from Xcode Command Line Tools or Xcode
  - Apple Foundation and libdispatch
  - `arm64` baseline, with `x86_64` kept as a future validation target
- Linux/GNUstep remains the existing supported path while the Apple port is
  still maturing.
- Apple-platform builds must not require `gnustep-config`, `GNUSTEP_SH`, or
  `GNUstep.sh`.

Acceptance checkpoint:

- this roadmap exists
- `docs/APPLE_PLATFORM.md` defines the contract
- top-level onboarding docs point macOS users to the Apple path

## 30B. Build Strategy Selection

Choose an Apple-native build strategy that avoids pulling the port through the
GNUstep build graph.

Decision:

- use a repo-owned shell build entrypoint first
- keep the existing GNUmake/GNUstep path in place for Linux
- defer Xcode project generation or a broader CMake migration until after the
  Apple-native command line build proves stable

Shipped in this subphase:

- `tools/build_apple.sh`
- `bin/build-apple`
- Darwin-aware `bin/arlen` dispatch to the Apple builder by default

Acceptance checkpoint:

- a macOS contributor can invoke the Apple builder without GNUstep tooling

## 30C. Compatibility Audit

Identify the portability blockers before broad source churn.

Characterized platform assumptions at phase entry:

- shell/bootstrap assumptions:
  - `readlink -f`
  - `sha256sum`
  - `ldconfig`
  - Bash 4 `${var^^}` syntax
- build assumptions:
  - hard dependency on `gnustep-config`
  - hard-coded `/usr/include/postgresql`
  - hard-coded `-ldispatch`
- runtime/tooling assumptions:
  - GNUstep-specific environment setup for doctor/build/test flows
  - Linux-only dynamic library candidate paths for `libpq`

Shipped in this subphase:

- initial Apple compatibility notes in `docs/APPLE_PLATFORM.md`
- centralized shell portability helpers in `tools/platform.sh`
- expanded `libpq` candidate handling in `ALNPg`

Acceptance checkpoint:

- core known blockers are documented and no longer implicit

## 30D. Portability Layer

Create central portability seams instead of scattering ad hoc platform checks.

Shipped in this subphase:

- `src/Arlen/Support/ALNPlatform.h`
- `src/Arlen/Support/ALNPlatform.m`
- `tools/platform.sh`

Current responsibilities:

- compile-time/runtime platform identification
- portable path resolution for shell tools
- portable SHA-256 helper selection for shell flows
- platform-aware Homebrew prefix probing for Apple dependency discovery
- platform-aware dynamic `libpq` candidates in Objective-C runtime code

Acceptance checkpoint:

- Apple-versus-GNUstep logic now has central helper surfaces to grow from

## 30E. Apple Build Bootstrap

Stand up the first Apple-native build path for core tools.

Shipped in this subphase:

- `tools/build_apple.sh` builds against:
  - Apple Foundation
  - Apple libdispatch via the macOS SDK
  - Homebrew `openssl@3` for current crypto imports
- the Apple builder currently targets:
  - `eocc`
  - `libArlenFramework.a`
  - `arlen`
- optional `boomhauer` build support is included behind `--with-boomhauer`
  after template transpilation succeeds

Current scope boundary:

- Apple XCTest integration is deferred to `30F`
- full dependency normalization for `libpq`/ODBC remains broader `30H` work
- broad runtime validation remains `30I`

Acceptance checkpoint:

- macOS can attempt a native Arlen build without GNUstep setup
- the build path fails with Apple-specific remediation instead of GNUstep-only
  guidance

## Remaining Subphases

## 30F. Apple XCTest Migration

Move the test path from GNUstep `xctest` assumptions to Apple XCTest tooling.

## 30G. Shell and Tooling Portability Hardening

Complete the remaining script portability pass across CI helpers, deploy tools,
and ancillary scripts.

## 30H. Dependency Discovery for PostgreSQL and Optional Backends

Normalize `libpq`, ODBC, and other optional dependency discovery on macOS.

## 30I. Runtime Validation on macOS

Run `boomhauer` and a scaffolded app end to end on Apple APIs.

## 30J. Security/Auth Surface Audit

Validate OpenSSL, password hashing, OIDC, MFA, and WebAuthn contracts on the
Apple path.

## 30K. Scaffold and Example App Validation

Prove the generated app path works on macOS, not just framework binaries.

## 30L. Documentation Closeout

Finish onboarding/reference docs for the Apple-native path.

## 30M. CI Expansion

Add a macOS CI lane so the Apple path is continuously verified.

## 30N. Compatibility Cleanup

Decide which seams remain dual-platform and which can be simplified.

## 30O. Phase Closeout

Publish a confidence pack and mark the Apple baseline complete only after build,
runtime, docs, and verification are all repeatable.
