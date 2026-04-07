# Getting Started on macOS

This guide is the Apple-runtime path for Arlen on macOS.

## 1. Prerequisites

- macOS with Xcode Command Line Tools installed
- `python3`
- `curl`
- Homebrew
- Homebrew `openssl@3`

Install the package dependency:

```bash
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

The Apple path is still in bring-up.

What exists now:

- Apple-native bootstrap/build entrypoint
- Apple doctor checks
- centralized portability helpers
- Apple `bin/test --smoke-only` scaffold smoke lane
- Apple `bin/boomhauer` support for repo-root and app-root execution

What is still being completed:

- full Xcode-backed Apple XCTest integration
- Apple watch-mode support in `boomhauer`
- broader optional dependency normalization

## 5. Smoke Test the Apple Runtime

Run:

```bash
./bin/test --smoke-only
```

On macOS this verifies the Apple path by scaffolding a fresh app, building it,
starting it on a local port, and probing the default routes.

## 6. Read Next

- `docs/APPLE_PLATFORM.md`
- `docs/PHASE30_ROADMAP.md`
- `docs/GETTING_STARTED.md`
