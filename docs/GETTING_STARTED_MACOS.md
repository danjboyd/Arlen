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

macOS is supported for development and production. On a Mac:

- `./bin/arlen new|generate|build|check|routes|test|perf|doctor` work without
  GNU `make`; builds are incremental and land in `build/apple/`.
- `bin/boomhauer` runs repo-root and app-root servers, with watch mode and the
  diagnostic build-error page.
- `arlen test` runs the Apple XCTest unit and integration bundles, and
  `arlen test --app` runs an app's own tests.
- `propane` and `jobs-worker` supervise production workers.
- `arlen deploy` packages releases and manages them as launchd daemons; see
  [Deployment](DEPLOYMENT.md#8b-macos-launchd-runbook).
- `libpq` and ODBC-style transports are found through Homebrew prefixes.

What is still Linux-only is listed in
[Apple Platform](APPLE_PLATFORM.md#known-characterized-gaps).

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

The integration and durable-jobs suites also build as Apple XCTest bundles:

```bash
./tools/test_apple_xctest.sh --suite integration   # or: ./bin/arlen test --integration
bash tools/ci/run_durable_jobs.sh                   # disposable PostgreSQL cluster
```

`tools/build_apple_xctest.sh --suite integration` also builds the binaries the
suite launches (the example servers and `eoc-smoke-render`) under
`build/apple/`, with exec wrappers at the `build/` paths the tests use. Set
`ARLEN_PG_TEST_DSN` to include the PostgreSQL integration tests. Tests of
GNUstep-only lanes (the GNU make build graph, perf, fault-injection, fuzz and
sanitizer generators) report as skipped.

## 6. Read Next

- `docs/APPLE_PLATFORM.md`
- `build/release_confidence/phase30/`
- `docs/GETTING_STARTED.md`

The build links macOS system libcurl for `ALNSynchronousHTTPResult`; custom link
commands also need `-lcurl`. For live database and client contract regressions,
install `postgresql@17` and `libpq`, then run
`bash tools/ci/run_apple_client_data_regressions.sh`. See
[HTTP client](HTTP_CLIENT.md) and [Testing workflow](TESTING_WORKFLOW.md).
