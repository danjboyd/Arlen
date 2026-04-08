# Getting Started on macOS

This guide is the closed Apple-runtime baseline for Arlen on macOS.

## 1. Prerequisites

- macOS with full Xcode installed and selected as the active developer
  directory
- `python3`
- `curl`
- Homebrew
- Homebrew `openssl@3`

Install the package dependency and activate full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
brew install openssl@3
```

## 2. Run Doctor

From the Arlen repository root:

```bash
./bin/arlen doctor
```

The macOS doctor path checks the Apple SDK and Apple clang toolchain instead of
GNUstep.

## 3. Build Core Tools

```bash
./bin/build-apple
```

Artifacts are written under `build/apple/`.

This currently builds:

- `build/apple/eocc`
- `build/apple/lib/libArlenFramework.a`
- `build/apple/arlen`

To also attempt the repo-root smoke server build:

```bash
./bin/build-apple --with-boomhauer
```

## 4. Current Scope

What the closed Apple baseline covers now:

- Apple-native bootstrap/build entrypoint
- Apple doctor checks
- centralized portability helpers
- Apple XCTest smoke verification through `tools/apple_xctest_smoke.sh`
- Apple `bin/test --smoke-only` verification lane for runtime, security,
  scaffolded-app, and example-app coverage
- repo-native `tools/ci/run_phase30_confidence.sh` artifact lane under
  `build/release_confidence/phase30/`
- Apple `bin/boomhauer` support for repo-root and app-root execution
- macOS CI coverage for the same Phase 30 baseline

What is still planned in the remaining Phase 30 subphases:

- `30P`: full repo-native Objective-C Apple XCTest bundle integration for the
  Arlen test suite
- `30Q`: broader optional dependency normalization
- `30R`: Apple runtime ergonomics, including the final watch-mode decision for
  `boomhauer`

## 5. Smoke Test the Apple Runtime

Run:

```bash
./bin/test --smoke-only
```

On macOS this verifies the Apple path by scaffolding a fresh app, building it,
starting it on a local port, and probing the default routes.

It also:

- runs the Apple XCTest smoke when full Xcode is active
- runs the Apple-native `apple-auth-audit` binary for password hashing, OIDC,
  and WebAuthn verification
- builds and runs `examples/auth_primitives`
- verifies local login, TOTP MFA elevation, and the stub OIDC provider flow on
  the Apple runtime path

For the repeatable artifact pack, run:

```bash
bash ./tools/ci/run_phase30_confidence.sh
```

## 6. Read Next

- `docs/APPLE_PLATFORM.md`
- `docs/PHASE30_ROADMAP.md`
- `build/release_confidence/phase30/`
- `docs/GETTING_STARTED.md`
