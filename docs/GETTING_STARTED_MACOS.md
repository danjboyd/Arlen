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

What is still being completed:

- Apple XCTest integration
- `boomhauer` runtime validation
- scaffolded app verification
- broader optional dependency normalization

## 5. Read Next

- `docs/APPLE_PLATFORM.md`
- `docs/PHASE30_ROADMAP.md`
- `docs/GETTING_STARTED.md`
