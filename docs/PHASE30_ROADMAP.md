# Phase 30 Roadmap

Status: in progress
Last updated: 2026-04-09

## Goal

Port Arlen to a first-class Apple-runtime path on macOS so the framework can
build and run against Apple's Objective-C/Foundation toolchain without
requiring GNUstep for that platform.

Phase 30 keeps the existing Linux/GNUstep path intact for now. The work in
this phase is additive: establish the Apple contract, stand up an Apple-native
build/bootstrap path, create the portability seams needed for the rest of the
port, and validate that the Apple runtime can boot a scaffolded app.

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

Acceptance checkpoint:

- macOS can attempt a native Arlen build without GNUstep setup
- the build path fails with Apple-specific remediation instead of GNUstep-only
  guidance

## 30F. Apple XCTest Migration

Goal:

- move the macOS test path off GNUstep `xctest` assumptions and onto an
  Apple-native entrypoint

Shipped in this subphase:

- `bin/test` now dispatches to `tools/test_apple.sh` on Darwin
- the Apple test lane runs `arlen doctor`, builds the Apple artifacts, and
  performs scaffold-app smoke verification instead of incorrectly attempting
  GNUstep test commands on macOS
- the Apple lane now reports the current environment limitation honestly when
  full Xcode-backed XCTest execution is unavailable

Current boundary:

- full XCTest bundle/executable integration remains blocked on activating a
  full Xcode developer directory in the macOS environment used for bring-up

Acceptance checkpoint:

- macOS no longer falls through to GNUstep `make test`
- the Apple test entrypoint is deterministic about what it verifies today

## 30G. Shell and Tooling Portability Hardening

Goal:

- remove Apple-hostile shell assumptions from the core dev entrypoints

Shipped in this subphase:

- `bin/boomhauer` now uses `tools/platform.sh` helpers and has an explicit
  Apple runtime path
- Apple app-root and repo-root boomhauer flows avoid GNUstep bootstrap
  assumptions
- `tools/build_apple_app.sh` provides a Bash 3 compatible scaffold-app build
  helper for the Apple runtime
- Apple path builders now keep `--print-path` stdout clean so script callers
  can reliably capture binary paths

Current boundary:

- wider CI/deploy helper cleanup remains future work outside the core Apple
  developer loop

Acceptance checkpoint:

- the primary macOS build/test/run scripts execute without GNU/Linux-only shell
  features

## 30H. Dependency Discovery for PostgreSQL and Optional Backends

Goal:

- make the Apple runtime fail with actionable dependency guidance instead of
  Linux-centric assumptions

Shipped in this subphase:

- the Apple build and app-root builder both detect Homebrew `openssl@3`
  through `ARLEN_OPENSSL_PREFIX` or Homebrew probing
- `ALNPg` now has broader Apple-aware dynamic-library candidate paths from the
  earlier portability seam work, and that discovery remains the current `libpq`
  baseline on macOS

Current boundary:

- `libpq`, ODBC, and other optional backend headers/libs are not yet fully
  normalized into the Apple builder with the same completeness as OpenSSL

Acceptance checkpoint:

- Apple build/test flows now emit macOS-specific remediation for the required
  crypto dependency and no longer assume Linux-only library layouts

## 30I. Runtime Validation on macOS

Goal:

- prove that the Apple runtime can actually serve requests through `boomhauer`
  and a generated app

Shipped in this subphase:

- `bin/boomhauer` can now run on macOS in both repo-root and app-root modes
- app-root execution on Apple now builds a dedicated
  `.boomhauer/apple/boomhauer-app` binary via `tools/build_apple_app.sh`
- watch mode is explicitly disabled with a clear warning on the current Apple
  runtime path instead of silently assuming Linux/GNUstep behavior
- `tools/test_apple.sh --smoke-only` scaffolds a fresh app, builds it, launches
  it on a random local port, and verifies `/`, `/healthz`, and `/openapi`

Acceptance checkpoint:

- a scaffolded macOS app can boot and answer smoke requests on Apple APIs
- repo-root and app-root boomhauer launches no longer depend on GNUstep

## 30J. Security/Auth Surface Audit

Goal:

Validate the security-sensitive contracts that still rely on OpenSSL or
security-adjacent runtime seams on the Apple path.

Shipped in this subphase:

- `tools/build_apple.sh` now builds `build/apple/apple-auth-audit` as an
  Apple-native verification binary against the same framework archive used by
  the runtime path
- `tools/test_apple.sh` now executes that audit binary as part of the default
  macOS verification lane
- the Apple audit covers:
  - Argon2id password hashing defaults and verification through
    `ALNPasswordHash`
  - OIDC authorization/callback/token verification contracts through
    `ALNOIDCClient`
  - WebAuthn registration/assertion verification plus session AAL elevation
    through `ALNWebAuthn` and `ALNAuthSession`

Current boundary:

- this is still a native runtime audit, not a full Apple XCTest bundle lane
- broader module-specific auth product coverage remains outside the core Phase
  30 Apple bring-up scope

Acceptance checkpoint:

- the macOS Apple lane exercises OpenSSL-backed password/OIDC/WebAuthn paths
  without falling back to GNUstep tooling

## 30K. Scaffold and Example App Validation

Goal:

Prove the generated app path works on macOS, not just framework binaries.

Shipped in this subphase:

- `tools/test_apple.sh` now validates two Apple app-root paths:
  - a freshly scaffolded app created with `build/apple/arlen new`
  - the checked-in `examples/auth_primitives` example app
- the scaffold lane now verifies `/`, `/healthz`, and `/openapi`
- the example-app lane now verifies:
  - local login plus TOTP MFA elevation
  - persisted session state at AAL2 after step-up
  - stub OIDC provider login completing successfully at AAL1

Acceptance checkpoint:

- the Apple path proves both generated apps and a checked-in example app can
  build and run through `tools/build_apple_app.sh`

## 30L. Documentation Closeout

Goal:

Finish onboarding/reference docs for the Apple-native path.

Shipped in this subphase:

- `docs/APPLE_PLATFORM.md` now defines the verified Apple security/runtime
  boundary through the current audit lane
- `docs/GETTING_STARTED_MACOS.md` now points contributors at the full
  Apple-runtime verification flow, including the auth/example coverage
- `README.md`, `docs/README.md`, and `docs/STATUS.md` now describe the current
  Phase 30 checkpoint as `30A-30L`

Acceptance checkpoint:

- onboarding and status docs agree on what the Apple path verifies today and
  what is still deferred

## Remaining Subphases

## 30M. CI Expansion

Add a macOS CI lane so the Apple path is continuously verified.

Shipped in this subphase:

- `.github/workflows/phase30-apple.yml` now runs the Apple baseline on
  `macos-15`
- the Apple CI lane explicitly selects full Xcode, bootstraps Homebrew
  `openssl@3`, and runs the repo-native `phase30-confidence` gate
- `tools/ci/install_ci_dependencies.sh` now has a macOS/Apple CI path instead
  of assuming GNUstep/Linux-only provisioning

Acceptance checkpoint:

- the Apple runtime path is continuously verified on macOS CI
- CI bootstrap no longer treats Apple verification as an out-of-band manual
  setup

## 30N. Compatibility Cleanup

Decide which seams remain dual-platform and which can be simplified.

Shipped in this subphase:

- `bin/arlen doctor` now resolves Apple XCTest through `xcrun` instead of
  warning incorrectly when `xctest` is not on `PATH`
- `tools/apple_xctest_smoke.sh` now provides a deterministic Apple XCTest smoke
  helper that exercises the active full-Xcode toolchain
- `tools/test_apple.sh` now runs the Apple XCTest smoke whenever the Xcode
  developer directory is active, while still preserving the runtime/auth smoke
  lane when it is not
- `GNUmakefile` now uses a portable SHA-256 helper at parse time so
  `make phase30-confidence` is callable on macOS without `sha256sum`

Acceptance checkpoint:

- the remaining Apple-versus-GNUstep seams in the core phase-closeout path are
  explicit rather than accidental
- the Apple developer loop can use the repo-native confidence entrypoint

## 30O. Phase Closeout

Publish a confidence pack and mark the Apple baseline complete only after build,
runtime, docs, and verification are all repeatable.

Shipped in this subphase:

- `tools/ci/run_phase30_confidence.sh` now produces a Phase 30 confidence pack
  under `build/release_confidence/phase30/`
- `tools/ci/generate_phase30_confidence_artifacts.py` now emits the eval,
  markdown summary, and manifest for the Apple baseline
- `GNUmakefile` now exposes a `phase30-confidence` helper target for GNU Make
  environments, while the direct script remains the Apple baseline entrypoint
- onboarding/status/toolchain docs now describe the completed Apple baseline,
  the new confidence lane, and the remaining post-Phase-30 follow-up scope

Acceptance checkpoint:

- `bash ./tools/ci/run_phase30_confidence.sh` and the macOS CI lane both
  verify the same Apple baseline
- build, XCTest availability, runtime smoke, auth/example smoke, and docs all
  agree on the closed Phase 30 contract

## Current Delivered Baseline

Phase 30 has delivered `30A-30R`, with `30S` remaining. The current Apple
baseline means:

- macOS contributors can build Arlen through `./bin/build-apple`
- `./bin/test --smoke-only` verifies Apple XCTest availability when full Xcode
  is active, then runs the Apple build, auth/security audit, scaffold-app
  smoke, and `examples/auth_primitives` coverage
- `tools/build_apple_xctest.sh` and `tools/test_apple_xctest.sh` provide the
  repo-native Apple XCTest bundle build/run contract for the Objective-C unit
  suite
- `tools/test_apple.sh` now runs the Apple XCTest unit suite before the Apple
  runtime verification steps
- Apple optional backend discovery now supports explicit prefix env vars and
  Homebrew-first `libpq`/ODBC prefix resolution
- Apple `boomhauer` watch mode now rebuilds on change, restarts only after a
  successful build, and preserves the last good server on failed rebuilds
- `bash ./tools/ci/run_phase30_confidence.sh` publishes the repeatable artifact
  pack for that same baseline
- macOS CI continuously enforces that contract on `macos-15`

## 30P. Apple XCTest Suite Migration

Delivered:

- defined the supported Apple XCTest bundle contract in
  `tools/build_apple_xctest.sh` and `tools/test_apple_xctest.sh`
- added a real Apple Objective-C XCTest bundle for the repo-native unit suite
- proved focused and full-suite execution on macOS through `xcrun xctest`

## 30Q. Optional Backend Normalization

Delivered:

- normalized Apple header/library discovery for PostgreSQL `libpq`
- added Apple-aware ODBC/MSSQL candidate discovery and doctor diagnostics
- upgraded Apple build/test diagnostics so optional backend gaps point to
  explicit macOS remediation paths

## 30R. Apple Runtime Ergonomics

Delivered:

- landed Apple watch-mode rebuild/restart behavior in `bin/boomhauer`
- tightened Apple app-root/runtime ergonomics around the existing `boomhauer`
  contract
- documented the steady-state Apple runtime expectations around the now-green
  Apple verification lane

## 30S. Cross-Platform Compatibility Shim Cleanup

Goal:

Build the remaining Apple-versus-GNUstep compatibility shims so the shared
Arlen source compiles warning-free against both GNUstep libs-base 1.30 and the
current macOS SDK without scattering ad hoc platform conditionals throughout
the codebase.

Planned scope:

- centralize Foundation availability and enum-name differences behind shared
  compatibility helpers instead of repeated source-local `#if` blocks
- replace deprecated Apple-only API usage where a cross-platform wrapper can
  preserve the GNUstep libs-base 1.30 contract
- migrate Apple-hostile networking and crypto seams onto compatibility
  abstractions that remain valid on both supported platforms
- remove the current Apple compile/link warning buckets from the framework and
  tooling entrypoints used by `arlen new`, `build-apple`, and app-root
  `boomhauer`

Acceptance checkpoint:

- `./bin/build-apple` completes without compiler/linker warnings on the current
  supported macOS/Xcode baseline
- the GNUstep/libs-base 1.30 build and test path remains clean and functionally
  unchanged
- platform-specific compiler conditionals are centralized behind documented
  compatibility seams rather than spread across app-facing code

## Follow-On Scope

Phase 30 is no longer closed at `30A-30R`; it now remains open through `30S`
for the warning-free Apple/GNUstep compatibility cleanup.
