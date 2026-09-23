# Testing Workflow

This guide describes the fastest path from a bug report to a permanent Arlen
regression test.

## Merge-Gate Validation

The merge gate for `main` is:

- `linux-quality / quality-gate`
 - local entrypoint: `make ci-quality`
- `linux-sanitizers / sanitizer-gate`
 - local entrypoint: `make ci-sanitizers`
- `docs-quality / docs-gate`
 - local entrypoint: `make ci-docs`

Before merging changes that affect runtime behavior, sanitizer behavior, docs,
or workflow policy, make the matching local lane pass and confirm the matching
GitHub required check is green. If workflow names, required checks, release
lanes, or platform support policy move, update `.github/workflows/`,
`docs/CI_ALIGNMENT.md`, branch-protection guidance, and contributor docs in the
same change.

`make test-unit` and `make test-unit-filter` build the Arlen CLI before loading
the unit-test bundle. Unit regressions may execute `build/arlen` directly, and
focused reruns after `make clean` must not depend on a stale CLI from an earlier
lane.

Integration tests that spawn HTTP servers must bound startup, request, and
shutdown waits. A focused integration regression should fail with command, port,
stdout/stderr, and process-status diagnostics rather than requiring an outer
`timeout` wrapper to kill a hung test.

## 1. Focused Lanes

Use the smallest lane that honestly exercises the bug:

- `make phase21-template-tests`
 - parser, codegen, security, and named template regressions
- `make phase21-protocol-tests`
 - raw HTTP corpus replay across `llhttp` and `legacy`
- `make phase21-generated-app-tests`
 - scaffold/module/config matrix for first-user flows
- `make phase21-focused`
 - run all three focused lanes
- `make phase21-confidence`
 - run the focused lanes and regenerate `build/release_confidence/phase21/`

public-release confidence lanes are available:

- `make phase37-contract`
 - validates the public surface matrix, EOC golden-render catalog, and
 deterministic parser/protocol corpus
- `make phase37-acceptance`
 - runs the acceptance-site harness against the checked- manifest
 using deterministic ports, isolated logs, HTTP probes, JSON assertions, and
 static checks
- `make phase37-acceptance-fast`
 - runs only the default service-free fixture-backed acceptance sites
- `make phase37-acceptance-runtime`
 - runs runtime-mode acceptance entries; these are service-backed/opt-in until
 their real Arlen app variants are implemented
- `make phase37-eoc-golden`
 - executes the EOC golden render/diagnostic fixture assertions
- `make phase37-intake`
 - validates the public bug-fix checklist and acceptance manifest metadata
- `make phase37-packaged-deploy-proof`
 - records evidence that packaged deploy behavior is covered by real
 deployment integration tests
- `make phase37-harness-selftest`
 - runs negative and positive self-tests for acceptance harness assertions
- `make phase37-confidence`
 - runs the contract, intake, packaged-deploy proof, and acceptance
 lanes and writes artifacts under `build/release_confidence/phase37/`

Data-layer-focused lanes remain available:

- `make phase20-sql-builder-tests`
- `make phase20-schema-tests`
- `make phase20-routing-tests`
- `make phase20-postgres-live-tests`
- `make phase20-mssql-live-tests`
- `make phase20-focused`

Dataverse-focused lanes are also available:

- `make phase23-dataverse-tests`
- `make phase23-live-smoke`
- `make phase23-focused`
- `make phase23-confidence`

Live-UI-focused lanes are also available:

- `make phase25-live-tests`
- `make phase25-focused`
- `make phase25-confidence`

ORM-focused lanes are also available:

- `make phase26-orm-unit`
 - SQL ORM runtime/repository behavior
 - when `ARLEN_PG_TEST_DSN` is set, this lane also exercises the live
 PostgreSQL generated-primary-key hydration regression
- `make phase26-orm-generated`
 - descriptor rendering, codegen, and snapshot/history drift behavior
- `make phase26-orm-integration`
 - Dataverse ORM runtime behavior
- `make phase26-orm-backend-parity`
 - capability metadata and backend boundary checks
- `make phase26-orm-tests`
 - full ORM regression bundle
- `make phase26-confidence`
 - rerun the full ORM bundle and regenerate
 `build/release_confidence/phase26/`

Windows-focused preview lanes:

- `make phase24-windows-db-smoke`
 - focused PostgreSQL / ODBC loader smoke for MSYS2 `CLANG64`
 - uses `arlen-xctest-runner` to load the XCTest bundle directly
- `make phase24-windows-runtime-tests`
 - Windows runtime/server parity coverage for `boomhauer`, `jobs-worker`, and
 `propane`
- `make phase24-windows-confidence`
 - runs both Windows preview lanes and matches the CI preview entrypoint
- `make windows-confidence`
 - runs packaged release smoke, packaged `deploy doctor --base-url`,
 packaged `jobs-worker --once`, and the synthetic `.exe` manifest fallback
 check
 - writes artifacts under `build/release_confidence/phase31/`
- `make phase32-confidence`
 - runs target-aware deploy compatibility coverage: experimental remote
 rebuild gating, unsupported-target rejection, rollback/status deployment
 metadata, and packaged `propane_handoff` contract checks
 - writes artifacts under `build/release_confidence/phase32/`
- `make phase35-confidence`
 - runs the route-policy confidence set for CIDR/proxy decisions,
 route-side policy metadata, and `/admin` policy attachment
 - writes artifacts under `build/release_confidence/phase35/`
- `make phase36-confidence`
 - runs the deploy operator-UX confidence set for target discovery, dryrun
 aliasing, sample config parsing, uninitialized target guards, release
 inventory listing, named remote release reuse, and bash/PowerShell
 completion safety
 - writes artifacts under `build/release_confidence/phase36/`

## 2. Bug Report To Regression

1. Reproduce the failure in the narrowest possible form.
2. Place the test in the most specific focused area:
 - template parse/diagnostic failures:
 `tests/unit/TemplateParserTests.m`
 - template code generation / metadata:
 `tests/unit/TemplateCodegenTests.m`
 - template lint/security behavior:
 `tests/unit/TemplateSecurityTests.m`
 - fixed downstream template bugs:
 `tests/unit/TemplateRegressionTests.m`
 - EOC golden-render coverage:
 `tests/fixtures/phase37/eoc_golden_render_cases.json`
 - public-surface coverage:
 `tests/fixtures/phase37/public_surface_contract.json`
 - raw protocol framing / parser behavior:
 `tests/fixtures/protocol/phase21_protocol_corpus.json`
 - deterministic parser/protocol corpus expansion:
 `tests/fixtures/phase37/parser_protocol_corpus.json`
 - generated-app setup/config/module issues:
 `tests/fixtures/phase21/generated_app_matrix.json`
 - Dataverse runtime/config regressions:
 `tests/unit/DataverseRuntimeTests.m`
 - Dataverse OData/query-builder regressions:
 `tests/unit/DataverseQueryTests.m`
 - Dataverse read-path/paging/response-normalization regressions:
 `tests/unit/DataverseReadTests.m`
 - Dataverse write/action/delete regressions:
 `tests/unit/DataverseWriteTests.m`
 - Dataverse retry/error/batch regressions:
 `tests/unit/DataverseRegressionTests.m`
 - Dataverse metadata/codegen regressions:
 `tests/unit/DataverseMetadataTests.m`
 - SQL ORM repository/runtime regressions:
 `tests/unit/ORMRuntimeTests.m`
 - SQL ORM descriptor/codegen/history regressions:
 `tests/unit/ORMCodegenTests.m`,
 `tests/unit/ORMMigrationTests.m`
 - SQL ORM backend boundary/capability regressions:
 `tests/unit/ORMBackendParityTests.m`
 - Dataverse parity/characterization artifacts:
 `tests/unit/DataverseArtifactTests.m`,
 `tests/fixtures/phase23/dataverse_query_cases.json`,
 `tests/fixtures/phase23/dataverse_contract_snapshot.json`,
 `tests/fixtures/phase23/dataverse_perl_parity_matrix.json`
 - live protocol/controller regressions:
 `tests/unit/LiveProtocolTests.m`,
 `tests/unit/LiveControllerTests.m`
 - built-in runtime route and override behavior:
 `tests/unit/LiveRuntimeTests.m`
 - executable runtime DOM semantics:
 `tests/unit/LiveRuntimeDOMTests.m`,
 `tests/shared/ALNLiveTestSupport.{h,m}`,
 `tests/shared/live_runtime_harness.js`
 - live form/region/upload interactions:
 `tests/unit/LiveRuntimeInteractionTests.m`
 - live stream/reconnect/auth-expiry/backpressure behavior:
 `tests/unit/LiveRuntimeStreamTests.m`
 - adversarial live protocol/runtime regressions:
 `tests/unit/LiveAdversarialTests.m`,
 `tests/fixtures/phase25/live_adversarial_cases.json`
 - tech-demo live endpoint integration coverage:
 `tests/integration/HTTPIntegrationTests.m`
 - deployment/release packaging regressions:
 `tests/integration/DeploymentIntegrationTests.m`
 - cross-surface acceptance behavior:
 `tests/fixtures/phase37/acceptance_sites.json`
3. Add or extend a checked-in fixture so the failure is replayable.
4. Run the matching focused lane until it passes.
 - for SQL ORM runtime bugs that depend on a real PostgreSQL insert/update
 path, set `ARLEN_PG_TEST_DSN` and rerun `make phase26-orm-unit`
5. Promote the change through `make test-unit`, broader integration coverage
 when applicable, and the matching confidence lane such as
 `make phase21-confidence`, `make phase23-confidence`,
 `make phase25-confidence`, `make phase26-confidence`, or
 `make phase37-confidence`.

## 3. Template Regression Intake

Template regressions should prefer fixture-backed coverage:

- parser negatives:
 `tests/fixtures/templates/parser/invalid/`
- security/lint cases:
 `tests/fixtures/templates/security/`
- named bug reproductions:
 `tests/fixtures/templates/regressions/`

The regression catalog lives in
`tests/fixtures/templates/regressions/regression_catalog.json`.
When a downstream bug is fixed, add a stable case id there and pair it with a
focused test in `TemplateRegressionTests`.

## 4. Protocol Replay

Run the whole checked-in corpus:

```bash
make phase21-protocol-tests
```

Replay one checked-in case:

```bash
python3 tools/ci/phase21_protocol_replay.py \
  --case websocket_invalid_key \
  --backends llhttp \
  --output-dir build/release_confidence/phase21/protocol_replay
```

Replay one saved raw request:

```bash
python3 tools/ci/phase21_protocol_replay.py \
  --raw-request tests/fixtures/protocol/fuzz_seeds/websocket_invalid_key_seed.http \
  --expected-status 400 \
  --case-id websocket_invalid_key_seed \
  --backends llhttp
```

## 5. Generated-App Matrix

Run the curated first-user matrix:

```bash
make phase21-generated-app-tests
```

The checked-in matrix lives in
`tests/fixtures/phase21/generated_app_matrix.json`.
Add only representative cases that cover a real first-user flow or a fixed
downstream bug class; do not explode this into all possible permutations.

## 6. Confidence Entry Point

closes through one reproducible entrypoint:

```bash
make phase21-confidence
```

Artifacts are written to `build/release_confidence/phase21/`.

Dataverse closeout uses:

```bash
make phase23-dataverse-tests
make phase23-live-smoke   # optional; requires ARLEN_PHASE23_DATAVERSE_* live env
make phase23-confidence
```

Artifacts are written to `build/release_confidence/phase23/`.
The Dataverse confidence pack now includes the checked-in Perl parity accounting
snapshot, optional live smoke output, and optional live codegen output.

live UI closeout uses:

```bash
make phase25-live-tests
make phase25-confidence
```

The live UI suite now includes a Node-backed executable runtime harness for
`/arlen/live.js` semantics, focused stream/adversarial suites, and confidence
artifacts for both push-path and negative-path live behavior.

public-release confidence uses:

```bash
make phase37-contract
make phase37-intake
make phase37-packaged-deploy-proof
make phase37-acceptance
make phase37-confidence
```

Artifacts are written to `build/release_confidence/phase37/`. The default
acceptance manifest is service-free; set `ARLEN_PHASE37_INCLUDE_SERVICE_BACKED=1`
only when a later acceptance site explicitly documents required external
services.

To add or update a acceptance probe:

1. Add the route behavior to the relevant acceptance site fixture or helper.
2. Add a probe entry to `tests/fixtures/phase37/acceptance_sites.json`.
3. Keep the default probe service-free unless the site is explicitly marked
 `serviceBacked`.
4. Give every site and probe a stable ID, useful description, and checked-in
 artifact path for any static check.
5. Run `make phase37-intake`.
6. Run `make phase37-acceptance`.
7. Run `make phase37-confidence` before closeout or release-candidate review.

Use runtime-mode entries for real Arlen app variants and keep fixture-backed
entries in fast mode. Do not move runtime-mode entries into the default lane
without updating CI alignment and branch-protection guidance in the same
change.

### Generated ORM naming regressions

After sourcing `tools/source_gnustep_env.sh`, run `make phase26-orm-generated`.
This uses the repo-local XCTest runner and compiles a generated model fixture
with property-type, property-attribute and nullability warnings as errors, then
loads it to exercise typed accessors and ORM runtime state. The Linux quality
workflow runs this target explicitly. Use `make phase26-orm-unit` and
`make phase26-orm-integration` for broader ORM runtime coverage.

## Durable jobs acceptance

Run `source tools/source_gnustep_env.sh` then `make ci-durable-jobs`. The gate
creates a disposable PostgreSQL Unix-socket cluster and runs the repo-local
XCTest bundle plus independent producer/consumer executables. PostgreSQL server
binaries must be installed; `ARLEN_TEST_PG_BIN` overrides `pg_config --bindir`.
No application credentials or database are used. The suite stops/restarts only
its disposable cluster to exercise database outages. A missing server binary or
failed database start is a failure, not a skipped test.

Coverage includes four producers, four consumers, accepted-ID reconciliation,
kill/restart, finite leases and heartbeat renewal, stale-worker mutation
rejection, transaction rollback, retry exhaustion, replay/deduplication,
module payload/results, database outage recovery, and private file initialization.
Lock-contention coverage holds a terminal job or queue-control row locked while
another adapter claims unrelated work, checks same-queue and cross-queue
progress, and verifies eventual cleanup after release. A 205-job backlog verifies
the 100-job cleanup limit and progress across polls; live and retryable leases
must remain untouched by terminal cleanup.
Logs are saved to `build/release_confidence/durable_jobs.log`. The
`durable-jobs-tests` target is the inner bundle runner; use the outer
`ci-durable-jobs` target to supply the isolated database contract.

This runs before the broader gate as an explicit step in
`linux-quality / quality-gate`, so later failures do not skip queue acceptance.
Required check names and branch-protection settings are unchanged.

Server-tool discovery honors `ARLEN_TEST_PG_BIN` first (an invalid explicit path
fails), then a complete `pg_config --bindir`, an `initdb` directory on PATH, and
finally the newest complete Debian/Ubuntu server directory under
`/usr/lib/postgresql`. This allows client development tools and server packages
to have different versions. The Linux quality workflow installs the `postgresql`
server package when tools are missing; clang-based GNUstep provisioning is
unchanged. ORM identifier acceptance uses the same resolver.

The required job display names explicitly emit `linux-quality / quality-gate`,
`linux-sanitizers / sanitizer-gate`, and `docs-quality / docs-gate`, matching the
existing branch-protection contexts exactly. Keep those literal names aligned
when editing workflows. Bare job IDs did not satisfy the configured contexts;
no required check is removed or weakened by this alignment.

## Request-limit and parser-backend regressions

After sourcing `tools/source_gnustep_env.sh`, use:

```bash
make test-unit-filter TEST=ConfigTests
make test-unit-filter TEST=MultipartTests
make test-integration-filter TEST=HTTPIntegrationTests/testMultipartDocumentedPlistLimitsKeepServerAlive
make test-integration-filter TEST=DeploymentIntegrationTests/testCompileTimeFeatureFlagsCanDisableYYJSONAndLLHTTP
```

The multipart socket regression loads an old-style plist and checks configured
file and part caps on both HTTP parsers, including server usability after a
rejected upload. The feature-toggle smoke compiles the legacy request parser
with its multipart implementation while disabling both optional C backends.
Both regressions also run in the existing Linux integration suite.

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

## HTTP/data client regressions

On GNUstep, source `tools/source_gnustep_env.sh`, then run these commands
sequentially (they share build artifacts):

```bash
make test-unit-filter TEST=HTTPCompatTests
make phase23-dataverse-tests
bash tools/ci/run_orm_identifier_regressions.sh
```

The PostgreSQL script provisions a disposable database and runs PgTests alongside
ORM and SQL-builder checks. The HTTP peer binds loopback sockets. Neither path
needs provider credentials. Dataverse policy tests record sleeps without waiting.

On macOS with full Xcode:

```bash
brew install openssl@3 postgresql@17 libpq
bash tools/ci/run_apple_client_data_regressions.sh
```

This builds the Apple XCTest bundle once and runs HTTP, Dataverse policy, and
live timestamp regressions. `ARLEN_TEST_PG_BIN` and `ARLEN_LIBPQ_PREFIX` can select
an existing PostgreSQL installation. Linux CI's clang `/usr/GNUstep` bootstrap
and repo-local tools-xctest runner remain unchanged.

## Live PostgreSQL regression gate

Run `bash tools/ci/run_postgres_regressions.sh` with the supported clang GNUstep
toolchain and PostgreSQL server tools, including `pg_trgm`, installed. It creates
an isolated cluster, sets `ARLEN_PG_TEST_DSN`, and exercises generated-code
consumers, module migrations, PostgreSQL search, and auth server lifecycle tests.
Auth tests run twice; remaining database sessions fail the gate before `dropdb`
without force verifies cleanup. Logs are under
`build/release_confidence/postgres_regressions/`.

The script also supplies a temporary non-default `GNUSTEP_SH`; CI harnesses use
`tools/source_gnustep_env.sh` instead of assuming a system install. Deployment
fixtures resolve the local toolchain while explicit deployment target paths
remain subject to doctor validation. CI provisioning still uses `/usr/GNUstep`.

Generated smoke programs use `make test-client-program` through the shared test
helper, linking `libArlenFramework.a` with canonical build flags. JSON assertions
capture stdout separately from stderr, retaining notices for diagnostics. Auth
servers launch with `exec` so the test owns the server PID; cleanup sends TERM,
waits up to five seconds, escalates to KILL if necessary, and reaps the process.
This cleanup runs in `@finally`, including assertion failures.
