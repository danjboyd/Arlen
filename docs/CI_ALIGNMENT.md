# CI Alignment

Last updated: 2026-09-21

This document defines the intended shape of Arlen CI so workflow names,
required checks, and actual project contracts stay aligned.

CI checkouts must include submodules while Arlen carries the temporary
`vendor/tools-xctest` runner. That submodule pins GNUstep/tools-xctest PR 5 for
Apple-style `-only-testing` / `-skip-testing` support. Periodically check
upstream `tools-xctest`; once that behavior is available upstream, remove the
submodule and switch the default runner back to upstream `xctest`.

Arlen also vendors `gnustep-cli-new` at `vendor/gnustep-cli-new` 
platform-runner standardization. This pin records the exact Windows
MSYS2/GNUstep provisioning source that Arlen expects for `windows-preview`
runners; it is not a new required merge-gate lane by itself.

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
- docs quality gate
 - generated API reference freshness
 - docs navigation/roadmap consistency
 - browser-doc build output

Additional lanes should stay visible but non-blocking unless the support
statement is raised:

- public-release confidence
- Apple baseline confidence
- Windows preview confidence
- scheduled thread-race / experimental sanitizer follow-up lanes

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
- `docs-quality`

Additional lanes remain visible but non-blocking while their support level
stays below the authoritative Linux production baseline:

- `phase37-confidence`
- `apple-baseline`
- `windows-preview`
- nightly thread-race / experimental follow-up lanes

## Platform Lane Policy

Platform lanes below the authoritative Linux production baseline should remain
visible but non-required:

- `apple-baseline`
 - purpose: maintain the verified Apple runtime baseline
 - status: baseline confidence, not the authoritative production merge gate
 - promotion rule: only promote if the platform support statement becomes
 authoritative and the lane stays stably green
- `windows-preview`
 - purpose: validate Windows preview runtime and packaged release parity
 - status: preview confidence, not a required merge gate
 - promotion rule: only promote if Windows leaves preview and the lane is
 operationally stable enough to protect real shipped behavior

Platform lanes should upload artifacts on failure so they remain useful for
diagnosis even while non-blocking.

## Platform Runner Provisioning Direction

The current runner contract standardizes the intended platform-runner path:

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

## Failure Triage And Fast Feedback

The current workflow policy is:

- merge-gate workflows cancel older in-progress runs for the same PR/ref
- merge-gate workflows upload artifacts on failure so diagnosis does not depend
 on rerunning the entire lane
- timeouts are explicit so hung jobs fail as infrastructure/tooling signals
 instead of lingering indefinitely

This keeps required lanes focused on actionable failures and reduces stale
runner churn.

## Recommended Workflow Layout

Use clear workflow filenames that match their actual role:

- `.github/workflows/linux-quality.yml`
- `.github/workflows/linux-sanitizers.yml`
- `.github/workflows/docs-quality.yml`
- `.github/workflows/apple-baseline.yml`
- `.github/workflows/windows-preview.yml`
- `.github/workflows/release-certification.yml`

The workflow `name:` field should match the filename-level intent. Avoid
historical phase-number filenames that now launch newer lanes.

## Branch Protection Guidance

For `main`, require:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `docs-quality / docs-gate`

Do not require by default:

- confidence
- Apple baseline
- Windows preview
- nightly thread-race / experimental lanes
- release certification

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

`apple-baseline` additionally runs `tools/ci/run_apple_client_data_regressions.sh`
with the same HTTP/retry tests and live timestamp regression using Apple XCTest.
Its bootstrap installs Homebrew `postgresql@17` and `libpq` in addition to
`openssl@3`; the script selects their paths explicitly and uses a private Unix
socket PostgreSQL cluster. Apple builds link system libcurl for the new HTTP
result API. The existing NSURLSession helper remains covered too.

The Apple job retains logs under its existing artifact directory. No lane or
required check is renamed or promoted: branch protection continues to require
`linux-quality / quality-gate`, `linux-sanitizers / sanitizer-gate`, and
`docs-quality / docs-gate`. Apple confidence remains nonblocking globally, but
these changes require its contract regression evidence before issue closure.

## Live PostgreSQL regression coverage

The existing `linux-quality / quality-gate` runs
`tools/ci/run_postgres_regressions.sh` before the general quality suite. This
mandatory isolated-cluster step covers PostgreSQL generated clients, module
migration JSON stdout, word-based fuzzy search, and repeated auth server cleanup.
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
`MetadataTransportTests`, and `SecurityHeadersColdStartTests` using Apple XCTest.
This exercises the Foundation bounded-POST implementation and native cold-start
probe, rather than inferring Apple transport behavior from Linux coverage.
