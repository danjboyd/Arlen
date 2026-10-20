# CI Alignment

Last updated: 2026-10-17

This document defines the intended shape of Arlen CI so workflow names,
required checks, and actual project contracts stay aligned.

CI checkouts must include submodules. `vendor/tools-xctest` pins a tagged
release of `danjboyd/tools-xctest`, the maintained fork of the dormant
GNUstep/tools-xctest. It is Arlen's canonical GNUstep XCTest runner: test
bundles compile against its headers, link its `libXCTest`, and run under its
`xctest`, so CI does not depend on the runner host's packaged `tools-xctest`
version. If upstream becomes active again, merging the fork back may be
considered; until then the fork is the contract.

Arlen also vendors `gnustep-cli-new` at `vendor/gnustep-cli-new` 
platform-runner standardization. This pin records the exact Windows
MSYS2/GNUstep provisioning source that Arlen expects for `windows-preview`
runners; it is not a new required merge-gate lane by itself.

## Windows Test Runner

Windows framework, generated-app and vendored-runner builds use
`_FILE_OFFSET_BITS=64`. The existing unit job verifies a sparse file above
2 GiB with stat, Range and HEAD checks without allocating or hashing its full
length. Native pinned-file tests perform pathname substitution using delete
sharing; they retain the old-byte and checksum-mismatch assertions.
The build-flags sentinel invalidates the vendored runner as well as framework,
generated-source and test objects; changing the Windows offset ABI cannot reuse
an older runner build.
The existing Windows transport step also runs the static HTTP probe against a
sparse file above 2 GiB, checking actual tail bytes and HEAD length over HTTP.

The runtime parity suite tests watch recovery, jobs CLI smoke, and explicit
rejection of unsupported Windows `propane` startup. It no longer attempts
multiworker reloads on independently bound Windows sockets; that depended on
unsafe port sharing. The supported-development scope and existing required
check names remain unchanged. Native exclusive-binding coverage stays enabled.

The ordinary unit suite builds `build/file-job-probe` and runs a four-process
file-queue regression without PostgreSQL. This is part of existing unit lanes,
including `windows-preview`; required check names and branch protection stay
unchanged. Focused execution: `make test-unit-filter TEST=Phase7DTests`.
The same Windows job also runs
`make test-integration-filter TEST=HTTPIntegrationTests/testRealtimeOriginsReceiveOnlyChannelsAndWindowsStaticPaths`
for native junction/stream/short-name containment, exclusive binding, Origin
validation, and receive-only channels. This adds a step to an existing required
check; branch-protection check names do not change.
`test-unit` also runs `llhttp-framing-tests` against the actual vendored C
parser, even where Windows defaults to the legacy HTTP backend. It checks empty
Transfer-Encoding rejection and a valid Content-Length control request.

The Windows preview lanes (`make phase24-windows-db-smoke` and
`make phase24-windows-runtime-tests`) build and run the vendored tools-xctest
fork, the same runner as Linux and macOS (issue #116), so they get filters,
per-test time limits, JUnit reports, skips and attachments. The make wiring
for Windows:

- the vendored runner is `obj/xctest.exe` and is built with
  `ADDITIONAL_OBJCFLAGS=-DHAVE_MODE_T=1 -D_FILE_OFFSET_BITS=64` (the gnustep-cli Windows toolchain's
  libdispatch header otherwise clashes with MinGW's `mode_t`);
- `xctest_runtime_env` puts the vendored `XCTest-0.dll` directory on `PATH`
  instead of `LD_LIBRARY_PATH`;
- test bundle binaries are named `<bundle>.dll`, because MinGW appends `.exe`
  to an extensionless `-o` path and GNUstep's `NSBundle` loads `<name>.dll`.

Verified on 2026-10-16 on the `arlen-windows-agent` VM (Windows Server 2022,
gnustep-cli `v0.1.0` managed toolchain): `phase24-windows-db-smoke` passes
(2/2) and `phase24-windows-runtime-tests` passes (3/3, about 160 s) through
the vendored runner. The old `arlen-xctest-runner` bundle loader is gone.

The runtime lane used to exceed its 300 s allowance because boomhauer rebuilt
the whole framework inside the test: a shell started by `xctest.exe` saw
`GNUSTEP_MAKEFILES` as `C:/...`, so `GNUSTEP_SH`, and the build-flags sentinel
hash, had a second spelling. `tools/resolve_gnustep.sh` now prints the
`cygpath -u` form. `tools/ci/run_windows_preview.sh` also stops any process
still running from `build/phase24-temp` on exit, because a test stopped by its
time allowance never reaches its cleanup and Windows does not end children
with their parent.

`windows-preview` runs on the self-hosted runner `arlen-windows-agent`
(labels `self-hosted`, `Windows`, `X64`, `arlen`, `msys2-clang64`). That
runner is a persistent VM, so the job is skipped for pull requests from forks.
It stays non-required. It runs the phase24 lanes (`tools/ci/run_windows_preview.sh`)
and the unit suite (`make test-unit`). `make windows-confidence` (packaged
release, deploy doctor, propane, jobs-worker) left the workflow with 0.3.0's
development-only Windows scope; it returns with Windows production in 0.4.0
(#200). It still fails at deploy doctor: the bash deploy scripts record MSYS
paths that the native `arlen.exe` cannot open.

## Goal

Arlen CI should always be:

- current with the repo's real support statement
- green on the authoritative baseline
- explicit about which lanes are merge-blocking versus informative
- updated in the same change set as any workflow or contract shift

Keeping CI updated and green is a core project goal.

## Current Recommended Contract

The required merge gate should reflect the current authoritative baseline:

- Linux/GNUstep quality gate
 - build/toolchain bootstrap
 - unit, integration, and data-layer coverage
 - runtime concurrency gate
 - blocking fault-injection/performance checks
- Linux/GNUstep sanitizer gate
 - ASAN/UBSAN matrix and the other blocking hardening lanes
- static-analysis gate
 - scan-build (clang static analyzer) over first-party code, gated on a
   reviewed baseline
 - clang-tidy (bugprone, cert, objc checks) over first-party code, warnings
   are errors
- docs quality gate
 - generated API reference freshness
 - docs navigation/roadmap consistency
 - no new sleep-based waits in tests (`tools/ci/check_test_sleeps.py`)
 - browser-doc build output

Additional lanes should stay visible but non-blocking unless the support
statement is raised:

- public-release confidence
- Apple baseline confidence
- Windows preview confidence
- scheduled thread-race / experimental sanitizer follow-up lanes
- scheduled integration-suite ASAN+UBSan lane (`integration-sanitizers-nightly`)

## Progress

Completed:

- `34A`: CI contract audit
- `34B`: workflow naming and topology cleanup
- `34C`: Linux authoritative gate consolidation
- `34D`: docs gate promotion and drift prevention
- `34E`: platform lane policy
- `34F`: failure triage and fast feedback
- `34G`: release lane isolation
- `34H`: branch protection and repo settings closeout
- `34I`: contributor and agent workflow closeout
- `34J`: robustness verification and exit criteria
- `34K`: OracleTestVMs-backed platform runner standardization for Apple and
 Windows confidence lanes. This keeps both lanes non-required under the
 current support statement while defining a repeatable LAN/self-hosted runner
 lifecycle. Arlen pins `gnustep-cli-new` at `vendor/gnustep-cli-new` as the
 Windows MSYS2 `CLANG64` GNUstep provisioning source. The current Apple
 baseline remains GitHub-hosted `macos-15`; OracleTestVMs macOS execution is
 deferred until that provider path is available.

## Current Merge-Gate Contract

- `linux-quality`
- `linux-sanitizers`
- `static-analysis`
- `docs-quality`

Additional lanes remain visible but non-blocking while their support level
stays below the authoritative Linux production baseline:

- `phase37-confidence`
- `apple-baseline`
- `windows-preview`
- nightly thread-race / experimental follow-up lanes
- nightly integration sanitizers (`linux-sanitizers / integration-sanitizers-nightly`)

## Platform Lane Policy

Platform lanes below the authoritative Linux production baseline should remain
visible but non-required:

- `apple-baseline`
 - purpose: maintain the verified Apple runtime baseline
 - status: baseline confidence, not the authoritative production merge gate
 - promotion rule: only promote if the platform support statement becomes
 authoritative and the lane stays stably green
- `windows-preview`
 - purpose: validate Windows runtime parity and the unit suite (packaged
 release parity returns with Windows production in 0.4.0)
 - status: preview confidence, not a required merge gate
 - promotion rule: only promote if Windows leaves preview and the lane is
 operationally stable enough to protect real shipped behavior

Platform lanes should upload artifacts on failure so they remain useful for
diagnosis even while non-blocking.

Release lanes run only on a published release (or `workflow_dispatch`) and are
never merge gates:

- `release-certification / release-certification`: the Linux certification
 pack (`tools/ci/run_release_certification.sh`).
- `release-certification / windows`: builds the windows-x64 zip on the Windows
 runner and certifies the user install path with
 `tools/ci/run_windows_release_certification.ps1` (`install.ps1`, `arlen
 new`, `arlen boomhauer --prepare-only`, and a `boomhauer` `/healthz` and `/`
 smoke through the installed `arlen.cmd`). The installer regression script
 `tools/ci/test_windows_installer.ps1` runs in both `windows-preview` and this
 release lane. It covers pinned prerequisite dispatch with mocked network/setup,
 opt-outs, PATH registration, checksum/download failure and same-version retry.
 The installed-release smoke resolves bare `arlen` outside the checkout in the
 current shell and a fresh PowerShell process using saved user PATH; the test
 restores the runner user PATH afterwards. These are installation checks on a
 provisioned runner, not evidence of a clean Windows host setup.
- `release-assets / *`: the source, macOS arm64 and Windows x64 archives, the
 installers and `SHA256SUMS`.

## Platform Runner Provisioning Direction

The current runner contract standardizes the intended platform-runner path:

- Windows preview currently runs on the persistent `arlen-windows-agent` VM
 (see "Windows Test Runner"); the longer-term direction is still an
 OracleTestVMs-provisioned LAN Windows VM:
- Windows preview should run on an OracleTestVMs-provisioned LAN Windows VM
 with the MSYS2 `CLANG64` GNUstep toolchain installed through
 the pinned `vendor/gnustep-cli-new` revision, then registered as a GitHub
 Actions self-hosted runner with labels `arlen` and `msys2-clang64`.
- Apple baseline remains on GitHub-hosted `macos-15` and should move toward an
 OracleTestVMs-provisioned macOS VM path once that provider is available,
 while preserving the existing full-Xcode and XCTest requirements of
 `apple-baseline`.
- The first operational target can be a dedicated long-lived platform runner;
 ephemeral lease-backed registration/teardown may be documented as a follow-up
 if that is the lower-risk path to a stable signal.
- Future `gnustep install arlen` package-manager support belongs to a later
 distribution phase and is not part of the merge-gate or
 platform-runner contract.

This provisioning work does not change branch protection by itself.

### Per-job temp directory on self-hosted Linux runners

Every job on the self-hosted `iep-apt` runner (linux-quality, both
linux-sanitizers jobs, both static-analysis jobs, docs-quality,
release-certification and
`release-assets / source-archive`) starts with a "Use a per-job temp
directory" step. It points `TMPDIR`, `TMP` and `TEMP` at `$RUNNER_TEMP/tmp`.
On Linux, GNUstep's `NSTemporaryDirectory()` reads `TEMP`/`TMP`, not
`TMPDIR`, so all three are set. The runner's `/tmp` is a 2 GB tmpfs shared
by every job. Test temp directories that leaked there over several weeks
(about 22k entries, 1.4 GB by 2026-10-16) left too little room for the eight
concurrent 20 MiB uploads in
`testPerRouteBodyLimitsSpoolAndBoundMemoryOnBothBackends`, which failed with
500s. `$RUNNER_TEMP` is on disk, and the runner empties it between jobs. New
self-hosted Linux jobs should include the same step.

## Public-Release Confidence

adds a public-surface contract and service-free acceptance suite:

- `make phase37-contract`
- `make phase37-intake`
- `make phase37-packaged-deploy-proof`
- `make phase37-acceptance`
- `make phase37-confidence`

These commands generate evidence under `build/release_confidence/phase37/`.
They are recommended for release-candidate review and broad public-surface
changes, but they do not change required merge-gate checks by themselves. Raise
the confidence lane to a required workflow only after it is deliberately added to
`.github/workflows/`, branch-protection guidance, and the public support
contract in the same change.

## Release Assets

`release-assets` runs when a release is published, and on demand with
`workflow_dispatch` (input `tag`, plus `upload` to attach the results). It
never runs on pull requests, so it is not a merge-gate lane.

- `release-assets / source-archive` (self-hosted `iep-apt` runner) checks the
  tag against `ALNModuleSystemFrameworkVersion`, builds `arlen-X.Y.Z.tar.gz`
  with `tools/release/package_framework.sh --kind source`, and installs it
  with `tools/release/smoke_install.sh`. That script runs `tools/install.sh`,
  creates an app, and checks that `boomhauer` serves `/healthz` and `/`.
- `release-assets / macos-arm64-archive` (`macos-15`) builds the prebuilt
  `arlen-X.Y.Z-macos-arm64.tar.gz` and runs the same install smoke.
- `release-assets / publish` attaches both archives, `install.sh`, and
  `SHA256SUMS` to the release. It runs only if both smokes pass.

`linux-quality` runs `tools/ci/test_release_packaging.py`. It checks the
source archive's layout (one top directory, `.arlen-dist`, vendored
`tools-xctest`, no `.git` and no `gnustep-cli-new`) and the managed-toolchain
`LD_LIBRARY_PATH` handling in `tools/source_gnustep_env.sh`. It also runs
`tools/deploy/build_release.sh` against a stub framework from a shell that
never sourced GNUstep.sh. It checks that the script sources the env before
`make` and packages the binary of an app that has no `src/main.m` (#181). No
PR lane runs the real `smoke_release.sh` on Linux, so this check is the PR-time
guard for the path `release-certification` uses. This is a step inside the
existing job, so no required check names change.

Linux has no prebuilt archive. The framework's build-flags sentinel hashes
absolute toolchain paths, and gnustep-cli managed toolchains live under each
user's home, so `tools/install.sh` builds the source archive once on the
user's machine instead.

## Public Linux Toolchain

`linux-public-toolchain` runs the README's Linux install path in clean
containers on GitHub-hosted runners: `debian:13` on amd64 and arm64
(`ubuntu-24.04-arm`), and `ubuntu:26.04` on amd64. Each job
creates an unprivileged user with sudo, packages a source archive, and runs
`tools/release/smoke_install.sh`. Only download/checkout prerequisites are
preinstalled; the installer itself provisions build dependencies and the
pinned gnustep-cli `v0.1.0` managed toolchain with `--yes`. The container has
no `/usr/GNUstep`. Smoke checks use bare `arlen` outside the checkout, a fresh
interactive bash and the persisted login profile, then generate and serve an
app. This verifies the setup path instead of bypassing it with preprovisioning.
`ReleasePrebuiltTests` also exercises installer failure, retry, and PATH
behavior using deterministic fixtures in the normal unit lane.

It runs on pull requests that touch the installer, packaging, GNUstep env
helpers, or `GNUmakefile`, on release publish, weekly, and on demand. It is not
a merge-gate lane; the self-hosted lanes stay the authoritative Linux
baseline.

## Failure Triage And Fast Feedback

The current workflow policy is:

- merge-gate workflows cancel older in-progress runs for the same PR/ref
- merge-gate workflows upload artifacts on failure so diagnosis does not depend
 on rerunning the entire lane
- timeouts are explicit so hung jobs fail as infrastructure/tooling signals
 instead of lingering indefinitely
- every XCTest run has a per-test time limit (`ARLEN_TEST_TIMEOUT`, default
 300 seconds), so a hung test fails by name long before the job timeout
- every XCTest run writes a JUnit report under `test-results`;
 `linux-quality`, `linux-sanitizers`, and `release-certification` publish a
 summary of failed and skipped tests to the job page with
 `tools/ci/junit_report.py` (failures also become annotations) and upload the
 reports and failure attachments with their other artifacts
- lanes that provision PostgreSQL fail if any test skipped for a missing
 `ARLEN_PG_TEST_DSN`, so a broken database wiring cannot pass as green
- `linux-quality` runs `make test-inventory`, which fails when the unit or
 integration bundle discovers a different set of tests than the baseline in
 `tests/fixtures/test_inventory/` (update it with
 `make update-test-inventory`), so a dropped test cannot pass as green
- no lane retries a failed test: `linux-quality` runs
 `tools/ci/test_xctest_repetition_policy.py`, which fails if
 `-retry-tests-on-failure` appears in the build or CI wiring. Repetition
 (`ITERATIONS`, `UNTIL_FAILURE`) is for local and nightly flake hunting only

These are steps inside the existing jobs; no required check names change.

This keeps required lanes focused on actionable failures and reduces stale
runner churn.

## Recommended Workflow Layout

Use clear workflow filenames that match their actual role:

- `.github/workflows/linux-quality.yml`
- `.github/workflows/linux-sanitizers.yml`
- `.github/workflows/static-analysis.yml`
- `.github/workflows/docs-quality.yml`
- `.github/workflows/apple-baseline.yml`
- `.github/workflows/windows-preview.yml`
- `.github/workflows/release-certification.yml`
- `.github/workflows/release-assets.yml`
- `.github/workflows/linux-public-toolchain.yml`

The workflow `name:` field should match the filename-level intent. Avoid
historical phase-number filenames that now launch newer lanes.

## Branch Protection Guidance

For `main`, require:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `static-analysis / scan-build`
- `static-analysis / clang-tidy`
- `docs-quality / docs-gate`

The two `static-analysis` contexts were added on 2026-10-17. Add them to the
`main` branch-protection rule in repository settings when the workflow first
reports on `main`; until then the verified state below still lists three
checks.

Do not require by default:

- confidence
- Apple baseline (now runs the full Apple unit, integration and durable-jobs
  bundles, but stays nonblocking)
- Windows preview
- nightly thread-race / experimental lanes
- nightly integration sanitizers (`integration-sanitizers-nightly`)
- release certification
- release assets
- linux public toolchain

Verified repo state on 2026-04-16:

- `main` branch protection requires exactly the three checks above
- strict required status checks are enabled
- force pushes and branch deletions are disabled
- Apple baseline, Windows preview, nightly thread-race, and release
 certification are not required checks

Raise a lane to required only when:

- the platform/support statement says it is authoritative
- the lane is stable enough to stay green without manual babysitting
- the lane materially protects shipped behavior

## Update Rules

Whenever CI behavior changes, update in the same change:

- workflow files under `.github/workflows/`
- `docs/RELEASE_PROCESS.md`
- `docs/TOOLCHAIN_MATRIX.md` when toolchain assumptions change
- this document
- `AGENTS.md` if the contributor/agent workflow expectation changed

## Static analysis lanes

`.github/workflows/static-analysis.yml` runs two gating jobs on every push to
`main` and every pull request:

- `static-analysis / scan-build` runs `make ci-static-scan-build`
  (`tools/ci/run_static_scan_build_gate.sh`). It rebuilds `all`, `boomhauer`
  and `tech-demo-server` from a clean `build/` under the clang static analyzer
  with the `core`, `unix`, `security`, `deadcode` and `osx.cocoa` checkers, and
  fails on any report that is not in
  `tests/fixtures/static_analysis/scan_build_baseline.json`. scan-build comes
  from the `clang-tools-<major>` package matching the runner's `clang`.
- `static-analysis / clang-tidy` runs `make ci-static-clang-tidy`
  (`tools/ci/run_static_clang_tidy_gate.sh`). It records
  `compile_commands.json` with `intercept-build` and runs clang-tidy, pinned to
  `clang-tidy==22.1.8` from PyPI, on every first-party `src/` and `modules/`
  translation unit with `--warnings-as-errors=*`. There is no baseline.

Both lanes skip vendored `src/Arlen/Support/third_party` code. Both build with
the same clang-built GNUstep toolchain as `linux-quality`; the scan-build lane
swaps scan-build's analyzer wrapper in through the GNUmakefile's `ARLEN_CC`
variable, which defaults to `clang`, so default builds are unchanged. The
scan-build job uploads its HTML report as an artifact when it fails, and the
clang-tidy job uploads its per-file logs.

The older `make ci-static-analysis` lane (`run_phase10m_static_analysis.sh`)
stays as it is. It analyzes four hot files with `clang --analyze` inside the
`linux-sanitizers` matrix and records release-confidence artifacts, but it
allows warnings, so it never fails on a finding. The new lanes are the
merge-blocking static-analysis gate and cover the whole first-party tree.

See `docs/TESTING_WORKFLOW.md` ("Static analysis") for local runs and baseline
updates.

## Practical Rule For Contributors

If a change causes CI drift, fix the drift immediately. Do not leave behind a
state where docs, branch protection, and workflow names describe different
quality gates.

## Optional MCP coverage

The existing `linux-quality / quality-gate` runs `make oauth-check mcp-check`: the vendored
XCTest runner executes `OAuthResourceServerTests` (controlled signing/JWKS, cache,
transport, maintenance/preflight/readiness latency and REST/MCP authorization fixtures) and `MCPModuleTests`; the optional
example builds in both authentication modes, and a real
HTTP probe verifies protocol, path-prefixed discovery, spoofed-header resistance
and JWT denial behavior. The same target audits eight synthetic discovery
cases offline. No tenant credentials or framework deployment are required. Ordinary unit lanes also
include the module tests. No required check names or branch-protection settings
change. Independent SDK verification is documented in `docs/MCP_MODULE.md`; it
is an additional interoperability check, not a network-dependent CI prerequisite.

OAuth transport coverage in the existing linux-quality `oauth-check` step uses
`MetadataTransportTests` with a Python loopback socket peer on calling and fresh
maintenance threads. It covers successful/exact-limit bodies, declared/chunked
oversize rejection, redirects, non-200 status, stalled and trickling deadlines,
and untrusted HTTPS certificates. GNUstep provisioning also validates libcurl
development files and asynchronous DNS; the clang `/usr/GNUstep` contract stays
in effect. No lanes or branch-protection check names change.
The ordinary unit lane also discovers these tests. No public network is required.
For downstream live verification, run `ARLEN_TEST_ENTRA_TENANT=<tenant-guid> make
test-unit-filter TEST=MetadataTransportTests` after sourcing
`tools/source_gnustep_env.sh`. This additionally exercises the production default
OAuth loader and signing-key preflight on both threads against discovery and JWKS;
it is opt-in because public provider availability is not a deterministic CI gate.

## Generated ORM property coverage

The existing `linux-quality / quality-gate` job explicitly runs
`make phase26-orm-generated`, including reserved-name fixtures, generated-code
compilation with incompatible-property/nullability warnings as errors, and typed
accessor, lifecycle, dirty-tracking and relationship-state regressions. This adds
coverage within the existing required job; branch-protection check names do not
change.

## First-party module version policy

The existing `linux-quality / quality-gate` job first runs
`tools/ci/check_module_versions.py` against the pull request base (or, on
pushes to `main`, the previous `main` commit). It fails when files under
`modules/<name>/` changed but the top-level `version` in that module's
`module.plist` did not increase. `arlen module upgrade` and apps' lock metadata
depend on module versions (issue #54). The job's checkout uses
`fetch-depth: 0` so the merge base is available. The check adds coverage
within the existing required job; branch-protection check names do not change.

## Quoted ORM identifier persistence coverage

The existing `linux-quality / quality-gate` job runs
`bash tools/ci/run_orm_identifier_regressions.sh`. It starts a private temporary
PostgreSQL cluster, runs `phase26-orm-generated`, `phase26-orm-unit`, and
`phase20-sql-builder-tests`, then removes the cluster. Live PostgreSQL tests
cannot skip for missing credentials in this step. Persistence tests use
disposable schemas and the quoted-name test rolls back its writes.

The Linux quality runner requires PostgreSQL server binaries (`initdb`,
`pg_ctl`) in `pg_config --bindir`, or `ARLEN_TEST_PG_BIN`. Apt provisioning
installs `postgresql`; preinstalled/bootstrap runners must provide it. The
clang GNUstep toolchain remains at `/usr/GNUstep`. Contributors can run the same
script as a non-root user; it requires local Unix socket access, no production
credentials, and no TCP listener. This extends coverage within the existing
job. Keep the current branch-protection checks unchanged: no new lane is added.

## Multipart upload coverage

The existing Linux quality unit/integration suites discover `MultipartTests` and
`HTTPIntegrationTests/testMultipartFragmentedReadsLimitsAndAborts`. They cover
binary preservation, ordered fields/files, parser limits, both HTTP backends,
fragmented sockets, and aborted uploads. No CI lanes or required-check names
change. Focused local runs use `make test-unit-filter TEST=MultipartTests` and
`make test-integration-filter TEST=HTTPIntegrationTests/testMultipartFragmentedReadsLimitsAndAborts`
after building `boomhauer` and sourcing `tools/source_gnustep_env.sh`.

Repeated response headers are covered by `ResponseTests` and
`HTTPIntegrationTests/testRepeatedSetCookieSessionAndCookieJar` in the existing
unit/integration suites. The live test builds a temporary app and uses Python's
standard-library cookie jar to verify issuance, session coexistence, scoped
cookies, three-cookie expiration, and HEAD behavior. No new lane or required
check name is introduced.

## Durable jobs reliability coverage

`linux-quality / quality-gate` explicitly runs `make ci-durable-jobs` after
sourcing the repo GNUstep environment, before the broader Linux quality gate so
unrelated later failures do not skip queue acceptance. The entrypoint
`tools/ci/run_durable_jobs.sh` provisions a disposable PostgreSQL cluster and
executes the vendored XCTest runner and independent process probes. It requires
real database concurrency, worker kill/restart, lease fencing/renewal, durable
results, transaction rollback, retry/replay/deduplication, database outages, and
module integration. The same gate also requires nonblocking same-queue and
cross-queue claims under terminal-job/control-row contention, eventual cleanup
after lock release, bounded cleanup backlogs, and preservation of live/retryable
leases. Database provisioning failures fail the gate.

The existing artifact upload includes
`build/release_confidence/durable_jobs.log`. No CI lane is renamed or added;
branch protection must continue requiring the existing three checks listed
above. Local contributor instructions are in `docs/TESTING_WORKFLOW.md` and the
runtime contract is in `docs/DURABLE_JOBS.md`. The clang-based `/usr/GNUstep`
provisioning contract is unchanged.

The quality workflow verifies PostgreSQL server tools before isolated acceptance
and installs the distro `postgresql` package if missing, including on the
preinstalled-GNUstep runner. `tools/ci/resolve_postgres_test_bin.sh` honors an
explicit `ARLEN_TEST_PG_BIN`, then probes `pg_config`, PATH, and installed
Debian/Ubuntu server directories. Both durable jobs and ORM identifier acceptance
use that resolver. This provisions a test dependency without changing the
`/usr/GNUstep` clang toolchain or weakening any gate.

The required job display names explicitly emit `linux-quality / quality-gate`,
`linux-sanitizers / sanitizer-gate`, and `docs-quality / docs-gate`, matching the
existing branch-protection contexts exactly. Keep those literal names aligned
when editing workflows. Bare job IDs did not satisfy the configured contexts;
no required check is removed or weakened by this alignment.

The Linux integration suite verifies the documented multipart plist limits on
both HTTP parsers and compiles the optional-backend-disabled smoke with the
request parser's multipart source dependency. Keep that standalone compile
representative when adding request-parser dependencies; do not remove the
feature-toggle check to address link failures. No additional required lane is
introduced for these regressions.

## Nightly integration sanitizers

`linux-sanitizers / integration-sanitizers-nightly` (issue 271) runs the
integration bundle against an ASAN+UBSan build on the schedule and on
`workflow_dispatch`, never on pull requests, and is not a required check: one
self-hosted runner can't take a sanitized integration run on every PR. A
finding in Arlen code becomes a release-blocking issue.

`tools/ci/run_linux_integration_sanitizers_nightly.sh` builds with clang's
shared sanitizer runtime (`-shared-libsan`), preloads that runtime into the
xctest runner, and collects every process's reports through `log_path` under
`build/sanitizers/integration_nightly/` (`summary.json` classifies them).
Reports in Arlen code, or that can't be attributed, fail the lane; reports
raised inside `/usr/bin` tools that inherited the preload (make, dd) don't.

Tests that build app roots through `bin/boomhauer`/`bin/arlen`, run `make`,
propane or `tools/ci` scripts are skipped: `bin/boomhauer` refuses a
sanitizer-instrumented framework and `make clean`s it. The list is
`tests/fixtures/sanitizers/integration_nightly_skips.txt`. Its generated
section comes from `tools/ci/classify_sanitizer_integration_skips.py`; the lane
fails when it is stale (regenerate with `--write`) and when the instrumented
framework archive is replaced during the run, which means a test that rebuilds
it isn't listed.

## TSAN reliability and retained evidence

The nightly thread-race lane remains informational. Its library-wide
suppressions and 14 TSAN-only test returns were retired on 2026-09-21;
previous green runs are not promotion evidence for the new configuration.
GNUstep queue/CLI findings remain visible. Required check names and branch
protection stay unchanged; do not add the full TSAN nightly as a required check
until the investigation's clean-run criteria are met.

Run `python3 tools/ci/test_tsan_reliability.py` for harness checks (also run by
`make ci-sanitizers`). After sourcing `tools/source_gnustep_env.sh`, run
`python3 tools/ci/tsan_runtime_diagnostics.py --output /tmp/arlen-tsan-diagnostics`
for raw/suppressed Foundation reproducers and the deliberate application race
control, or `bash tools/ci/run_linux_thread_race_nightly.sh` for the complete
lane. Findings can make these commands fail on the current GNUstep toolchain.

Nightly artifacts are uploaded on success and failure, including coverage
counts, raw/suppressed probe logs, and toolchain details. Missing TSAN fails with
exit 77 and `unavailable`, rather than passing. `ARLEN_REQUIRE_TSAN=0` explicitly
permits the legacy local Helgrind fallback; its summary identifies the engine.
Shell helpers remove only TSAN preload entries before launching Bash and keep
TSAN options for linked instrumented binaries. No tests are excluded solely
because TSAN is active; unrelated service-dependent opt-in tests remain.

See [the investigation](internal/TSAN_RELIABILITY_2026-09-21.md) for evidence,
remaining runtime work, and promotion criteria.

## HTTP/data client contract regressions

The existing disposable PostgreSQL step now also runs `PgTests`, including
microsecond decode/rebind equality, fractional digits, negative epochs, offsets,
boundary rounding, arrays, and lossless text values. The DSN is supplied by the
private cluster; a missing server fails provisioning. Existing unit discovery
runs `HTTPCompatTests` and `DataverseRegressionTests`, which use loopback peers
and captured transports/injected sleepers rather than public providers.

`apple-baseline` additionally runs `tools/ci/run_apple_unit_suite.sh`: the full
Apple XCTest unit bundle against a private PostgreSQL, which includes the same
HTTP/retry tests and live timestamp regression, followed by a check of
discovered tests against the shared unit inventory. It then runs
`tools/ci/run_apple_integration_suite.sh` (the Apple integration bundle against
a private PostgreSQL with a URI-form DSN, checked against the shared integration
inventory) and `tools/ci/run_durable_jobs.sh` (the Apple durable-jobs bundle).
Its bootstrap installs Homebrew `postgresql@17` and `libpq` in addition to
`openssl@3`; the script selects their paths explicitly and uses a private Unix
socket PostgreSQL cluster. Apple builds link system libcurl for the new HTTP
result API. The existing NSURLSession helper remains covered too. Before the
runtime gate, the same Apple job checks the macOS installer prerequisite
helper's SDK, minimum OS, and setup-consent behavior, plus offline discovery
of an installed Homebrew formula from an uncached home directory.

The Apple job retains logs under its existing artifact directory. No lane or
required check is renamed or promoted: branch protection continues to require
`linux-quality / quality-gate`, `linux-sanitizers / sanitizer-gate`, and
`docs-quality / docs-gate`. Apple confidence remains nonblocking globally, but
these changes require its contract regression evidence before issue closure.
The integration and durable-jobs steps run inside the same `apple-baseline`
job, so they add no check name; `apple-baseline` stays out of the required set
listed under Branch Protection Guidance. Promote it only under the criteria
there, and update that section and the repository settings in the same change.

## Live PostgreSQL regression coverage

The existing `linux-quality / quality-gate` runs
`tools/ci/run_postgres_regressions.sh` before the general quality suite. This
mandatory isolated-cluster step covers PostgreSQL generated clients, module
migration JSON stdout, word-based fuzzy search, repeated auth server cleanup,
and auth session role refresh across the admin-ui, jobs, and ops APIs.
It supplies a non-default `GNUSTEP_SH` to exercise portable bootstrap. Existing
required check names and branch-protection contexts stay the same; a missing
PostgreSQL server or extension is a failure, not a skipped live test.

The Linux quality job explicitly runs `OpsOptionalModulesIntegrationTests`, which
scaffolds and links both ops alone and auth/jobs/search/ops, then executes an
absent-module summary and authorization probe. This covers link dependencies
that the all-modules test bundle cannot detect.

The Linux quality job explicitly runs `AuthModuleOIDCTests` and
`MetadataTransportTests`: provider routes, PKCE/session completion, identity
policy, default access modes, token rejection, and bounded socket GET/POST.
Real tenant acceptance remains separate from deterministic required CI.

`SecurityHeadersColdStartTests` is explicitly selected in the Linux quality job
and included in the sanitizer matrix's full unit suite. Its child probe retains
ASan/UBSan (or TSan) instrumentation and runs fresh processes, so warmed static
state in the XCTest runner cannot hide initialization races. No required lane
is added or renamed by this regression.

The Apple baseline job also selects `AuthModuleOIDCTests`,
`MetadataTransportTests`, `SecurityHeadersColdStartTests` and `HTTPClientTests`
using Apple XCTest. This exercises the shared libcurl bounded-POST
implementation, the outbound `ALNHTTPClient` (host allowlist, redirects, size
and deadline limits) and the native cold-start probe on Apple, including cookie
isolation and exact size/error contracts. The step and required checks are
unchanged; only its suite list grew.

`InstanceLockColdStartTests` is explicitly selected in the Linux quality job
and included in the sanitizer matrix's full unit suite. It guards the
libobjc2 first-use `@synchronized` workaround
([gnustep/libobjc2#424](https://github.com/gnustep/libobjc2/issues/424)) in
fresh processes, with a per-process alarm so a hang fails instead of stalling
the job. The companion source policy check runs with `BuildPolicyTests`. No
required lane is added or renamed by this regression.

`LazyStaticColdStartTests` is explicitly selected in the Linux quality job and
included in the sanitizer matrix's full unit suite. It guards the
`dispatch_once` initialization of `ALNSQLBuilder`'s process-wide regexes and
operator sets (issue #49) by starting 32 threads on their first SQL build in
each of many fresh processes. The companion source policy check runs with
`BuildPolicyTests`. No required lane is added or renamed by this regression.

The required `linux-quality / quality-gate` also runs
`python3 tests/performance/persistent_http.py` after building `boomhauer` with
the supported clang/GNUstep toolchain. Two retained connections exercise both
health and static-file responses; reconnects and incorrect responses fail.
The policy in `tests/performance/policies/persistent_http.json` gates throughput,
p95 latency, and Linux server CPU per request. Reports and server logs are in
`build/perf/persistent_http.*`, included in existing CI artifacts. This extends
the existing required check; branch-protection check names are unchanged.

The integration sanitizer skip classifier ignores C comments while preserving
command string literals. Direct `build/boomhauer` slow-reader and request-deadline
tests remain eligible for the existing nightly instrumentation lane; required
checks and branch-protection names are unchanged.

Storage persistence now defaults to a transactional SQLite catalog. Linux hosts
need `libsqlite3-0`; macOS and supported Windows use the system SQLite runtime.
CI provisioning validates that runtime. Stop old workers before the one-time
legacy import; see [Storage Module](STORAGE_MODULE.md) for migration and backup rules.

Header-construction optimization regressions run in the existing unit lane
through ResponseTests and MiddlewareTests, with static/error security-header
checks in HTTPIntegrationTests. The optional `response-header-perf-bench` target
provides reproducible local measurements without a timing gate or a new required
CI lane.

The Linux quality and sanitizer runtime concurrency probes assert that WebSocket
channel clients cannot rebroadcast frames, in both concurrent and serialized
modes. Echo coverage remains on `/ws/echo`; channel clients must stay connected
and receive no client-originated frame. This follows the receive-only security
contract already covered by HTTP integration tests.
The same probe also verifies server-originated delivery to both subscribers
(concurrent mode) and the single subscriber (serialized mode). Its separate
`runtime-concurrency-fixture` executable accepts a command only through a pipe
inherited from the test runner; ordinary `boomhauer` has no publishing hook or
new network route. Failed probe runs retain their server log for diagnosis.

### Linux sanitizer runtime consistency

The blocking sanitizer gates source `tools/ci/source_clang_sanitizers.sh` after
GNUstep initialization. Framework code, XCTest bundles and child executables use
clang's shared ASan/UBSan runtime (`-shared-libsan`), with a runtime search path
embedded in executables. The uninstrumented vendored XCTest launcher preloads
that same runtime before loading instrumented bundles. Caller `LD_PRELOAD` and
`XCTEST_LD_PRELOAD` entries are retained after the sanitizer runtime; do not add
GCC sanitizer libraries to a clang-instrumented run.

Each gate first runs `test_clang_sanitizer_runtime.py`: an uninstrumented parent
loads an instrumented bundle and executes an instrumented child. A clean run
must succeed, while ASan memory errors and UBSan overflow errors in either
process must fail with the expected diagnostic. The check also verifies that an
unrelated preload is retained. This corrects runtime selection without changing
lane names, required checks, or branch-protection requirements.
