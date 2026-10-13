# Getting Started on macOS

This guide is the closed Apple-runtime baseline for Arlen on macOS.

## Install a Release

On Apple Silicon, the release installer unpacks prebuilt framework tools
(`arlen`, `boomhauer`, `eocc`, and `libArlenFramework.a`), so nothing in the
framework is compiled at install time. Your apps are still compiled on your
Mac, so you need:

- Xcode Command Line Tools (`xcode-select --install`). Full Xcode is needed
  only for `arlen test`, which runs Apple XCTest.
- Homebrew `openssl@3` and `libpq` (`brew install openssl@3 libpq`), at the
  default `/opt/homebrew` prefix. The prebuilt tools link against that
  OpenSSL.
- macOS 14 or later.

```bash
curl -fsSL https://github.com/danjboyd/Arlen/releases/latest/download/install.sh | bash
arlen doctor
arlen new MyApp && cd MyApp && arlen boomhauer --port 3000
```

The installer verifies the download against the release's `SHA256SUMS`,
unpacks it to `~/.local/share/arlen/<version>`, points
`~/.local/share/arlen/current` at it, and writes an `arlen` launcher to
`~/.local/bin`. The launcher sets `ARLEN_FRAMEWORK_ROOT` to the install, so
apps can live anywhere. Run `install.sh --help` for the prefix and version
options. If you downloaded the archive with a browser, pass it with
`--archive`; the installer clears the quarantine flag.

The prebuilt tools stay in use while the installed framework sources and the
OpenSSL location match the release. If you edit the installed sources, or
OpenSSL moves, `build-apple` rebuilds the framework once with your toolchain
(about 20 seconds) and builds incrementally from then on.

Intel Macs are not supported yet: the Apple build scripts target arm64 only.

To work from a source checkout instead, which you need in order to change the
framework or run its test suites, follow the sections below.

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
- repo-native Apple XCTest bundle build/run entrypoints through
  `tools/build_apple_xctest.sh` and `tools/test_apple_xctest.sh`
- Apple `tools/test_apple.sh` verification lane for the full Apple XCTest unit
  suite plus runtime, security, scaffolded-app, and example-app coverage
- repo-native `tools/ci/run_apple_baseline_confidence.sh` artifact lane under
  `build/release_confidence/phase30/`
- Apple `bin/boomhauer` support for repo-root and app-root execution,
  including watch-mode rebuild/restart handling
- optional backend discovery for `libpq` and ODBC-style transports through
  Apple-aware environment and Homebrew prefix detection
- macOS CI coverage for the Apple-runtime baseline

## 5. Verify the Apple Runtime

Run:

```bash
./tools/test_apple.sh
```

On macOS this verifies the Apple path by running the Apple XCTest unit suite,
then building, auditing, scaffolding, and probing the Apple runtime path.

It also:

- runs the Apple XCTest smoke when full Xcode is active
- runs the Apple-native `apple-auth-audit` binary for password hashing, OIDC,
  and WebAuthn verification
- builds and runs `examples/auth_primitives`
- verifies local login, TOTP MFA elevation, and the stub OIDC provider flow on
  the Apple runtime path

For the repeatable artifact pack, run:

```bash
bash ./tools/ci/run_apple_baseline_confidence.sh
```

## 6. Read Next

- `docs/APPLE_PLATFORM.md`
- `build/release_confidence/phase30/`
- `docs/GETTING_STARTED.md`

The build links macOS system libcurl for `ALNSynchronousHTTPResult`; custom link
commands also need `-lcurl`. For live database and client contract regressions,
install `postgresql@17` and `libpq`, then run
`bash tools/ci/run_apple_client_data_regressions.sh`. See
[HTTP client](HTTP_CLIENT.md) and [Testing workflow](TESTING_WORKFLOW.md).
