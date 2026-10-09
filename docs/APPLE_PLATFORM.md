# Apple Platform

## Purpose

This document defines the Apple-runtime contract for Arlen on macOS. macOS runs
Arlen on Apple's Objective-C runtime and Foundation, not GNUstep, and is
supported for both development and production.

## Current Contract

- macOS uses Apple Foundation, not GNUstep Foundation.
- macOS builds must not require `GNUSTEP_SH`, `GNUSTEP_MAKEFILES`,
  `gnustep-config`, or `GNUstep.sh`, and do not use GNU `make`.
- Apple builds use Apple clang through `xcrun`, and are incremental: objects,
  archives and links are rebuilt only when their inputs change.
- Apple builds depend on Homebrew `openssl@3` for the OpenSSL imports in the
  runtime and security layers.
- Shell scripts that run on macOS work with the system `/bin/bash` 3.2;
  `ShellPortabilityTests` guards them.
- Linux remains on the GNUstep toolchain.

## Supported Baseline

- OS baseline: macOS 15.x
- Architecture baseline: `arm64`
- Toolchain baseline:
  - full Xcode selected through `xcode-select`
  - Apple clang available through `xcrun`
  - `python3` (the system 3.9 is enough)
  - `curl`
- Package dependency: `brew install openssl@3`
- Optional: `libpq` (`brew install postgresql@17`) for PostgreSQL, an ODBC
  manager for MSSQL. Both are found through Homebrew prefixes.

## Build Entry Path

```bash
./bin/build-apple                  # eocc, libArlenFramework.a, arlen
./bin/build-apple --with-boomhauer # plus the repo-root boomhauer
./bin/arlen build                  # the same, through the CLI
```

Artifacts go to `build/apple/`. Apps build into `.boomhauer/apple/` through
`tools/build_apple_app.sh`, which `boomhauer`, `propane`, `jobs-worker` and
`arlen test --app` call.

## What Works on macOS

Development:

- `arlen new`, `generate`, `build`, `check`, `routes`, `config`, `doctor`.
- `boomhauer`, including watch mode with the diagnostic build-error page and
  `.boomhauer/last_build_error.{log,meta}`.
- `arlen test`: the Apple XCTest unit and integration bundles
  (`tools/test_apple_xctest.sh --suite unit|integration`), and
  `arlen test --app` for an app's own tests.
- `bash tools/ci/run_durable_jobs.sh`: the durable-jobs suite against a
  disposable PostgreSQL cluster.
- `arlen perf`, gated against a baseline recorded on the same Mac
  (`build/perf/baselines/macos-<arch>`).

Production:

- `propane` and `jobs-worker`, including reload, respawn, async workers and
  FD-pressure retirement (through `lsof`).
- `arlen deploy push`/`release`/`rollback`/`status`/`doctor`/`logs`: releases
  are packaged with the Apple build in the same layout as Linux.
- launchd service management: `arlen deploy init` generates a launchd daemon
  plist and env-sourcing wrappers for `macos-*-apple-foundation` targets, and
  `arlen deploy` reads and restarts the job through `launchctl`. See
  [Deployment](DEPLOYMENT.md#8b-macos-launchd-runbook).

Verification:

- `./tools/test_apple.sh` runs the unit bundle, then the runtime checks:
  doctor, the Apple auth/security audit, a scaffolded app on `/`, `/healthz`
  and `/openapi`, and `examples/auth_primitives` login, TOTP MFA and stub
  OIDC.
- The integration bundle discovers every test in
  `tests/fixtures/test_inventory/ArlenIntegrationTests.tests.txt`. Tests of
  GNUstep-only lanes report as skipped through `ALNSkipOnApple()`.

## Known Characterized Gaps

These areas are still Linux-only or narrower on macOS:

- Test lanes: the `tests/phase20` focused bundles, the browser error audit, and
  the sanitizer, fault-injection, fuzz, soak and perf-pack generators run only
  on GNUstep. Apple CI (`apple-baseline`, non-required) does not run the
  integration or durable-jobs bundles yet (GitHub issue 158).
- PostgreSQL- and MSSQL-backed tests skip unless `ARLEN_PG_TEST_DSN` or the
  MSSQL test DSN is set. The tests pass the DSN to `psql` unquoted, so use the
  URI form (`postgresql://user@/db?host=/socket/dir`).
- Runtime: the server's own file-descriptor pressure diagnostics read `/proc`
  and report nothing on macOS (`propane` uses `lsof` instead). File responses
  use read/write instead of `sendfile`. Apple builds target `arm64` only.
- Deploy: a Mac can deploy only to a Mac (`macos-*-apple-foundation`); Apple
  to GNUstep and Apple cross-profile remote rebuilds are unsupported.
- `arlen perf` baselines are host-local; the committed baselines are Linux
  host recordings.

## Portability Rules

- Detect NSNumber booleans with `ALNNumberIsBoolean()` (`ALNPlatform.h`), never
  by comparing `objCType` with `@encode(BOOL)`. Apple arm64 encodes `BOOL` as
  `"B"` while `@YES` reports `"c"`, and GNUstep encodes `BOOL` as `"C"`.
- Hold dispatch objects strongly under ARC on Apple (`OS_OBJECT_USE_OBJC`);
  an `assign` queue property is freed right after creation.
- Don't put `%{...}` in a format string unless it is meant for os_log: Apple
  Foundation consumes it as a privacy annotation (escape a literal as `%%{`).
- Shell: macOS ships bash 3.2, BSD tools, and no `/proc`. Expand arrays that
  may be empty as `${a[@]+"${a[@]}"}` under `set -u`; avoid `${x,,}`,
  `mapfile`, a heredoc inside `$(...)` or `<(...)`, `find -printf`,
  `stat -c`, `date +%N`, `ps --ppid` and GNU `timeout`. BSD `wc -c` pads
  its output.
- Tests: skip a GNUstep-only lane with `ALNSkipOnApple(reason)` rather than
  `#if`-ing the test out, so every platform discovers the same tests.

## Non-Goals

- deprecating Linux/GNUstep support
- shipping an Xcode project as the primary build path
- claiming full Apple parity for every module before runtime validation closes
- removing OpenSSL-backed crypto code in favor of Apple Security APIs

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
