# Arlen Status Checkpoint

Last updated: 2026-04-01

## Leaving Off (2026-04-01)

- Phase 25 is complete (`25A-25L` delivered on 2026-04-01):
  - shipped the fragment-first live UI surface through `ALNLive`, the built-in
    `/arlen/live.js` runtime, and the `application/vnd.arlen.live+json`
    response contract
  - extended live request metadata with keyed collection and region semantics,
    plus controller helpers for keyed fragment rendering/publishing
  - added keyed collection operations, live regions (`data-arlen-live-src`,
    poll/lazy/defer), upload-progress-aware live forms, and broader
    reconnect/backpressure/auth-expiry runtime behavior
  - shipped `/tech-demo/live`, the repo-native `phase25-confidence` lane, and
    the Phase 25 docs closeout in `docs/LIVE_UI.md` and
    `docs/PHASE25_ROADMAP.md`
  - added shared `ALNLiveTestSupport` helpers, a Node-backed executable
    runtime harness, focused DOM/runtime interaction/stream suites,
    adversarial fixtures, and targeted tech-demo pulse/upload/push/recovery
    integration coverage
  - strengthened `phase25-confidence` with websocket push and negative-path
    backpressure artifacts, so the live closeout now fails closed on both
    success and failure-path regressions
- Verification completed at this checkpoint:
  - `source tools/source_gnustep_env.sh && make build-tests`
  - `source tools/source_gnustep_env.sh && make phase25-live-tests`
  - `source tools/source_gnustep_env.sh && make phase25-confidence`
  - `source tools/source_gnustep_env.sh && make test-unit`
  - `source tools/source_gnustep_env.sh && make docs-api`
  - `bash tools/ci/run_docs_quality.sh`

## Leaving Off (2026-03-31)

- Phase 23 is complete again:
  - delivered `23A-23I` for the runtime-inactive Dataverse Web API client,
    OData query composition, CRUD/upsert/batch helpers, metadata
    normalization, typed Dataverse codegen, lazy app/controller target
    helpers, shared retry/diagnostic contracts, split Dataverse regression
    suites, characterization snapshots, Perl parity accounting, the optional
    `phase23-live-smoke` lane, focused confidence artifacts, and docs/example
    closeout
  - Dataverse parity hardening now ships through focused suites in
    `tests/unit/Dataverse*Tests.m`, shared support in
    `tests/shared/ALNDataverseTestSupport.{h,m}`, and checked-in artifacts
    under `tests/fixtures/phase23/`
  - `phase23-confidence` now records parity evaluation and live-smoke status,
    failing closed if the machine-readable parity matrix regresses
  - live Dataverse execution remains optional and runtime-inactive by default;
    the confidence lane compiles the smoke tool and emits explicit skipped
    manifests when `ARLEN_PHASE23_DATAVERSE_*` or `ARLEN_DATAVERSE_*`
    credentials are not fully present
- Verification completed at this checkpoint:
  - `source tools/source_gnustep_env.sh && make build-tests`
  - `source tools/source_gnustep_env.sh && make test-unit`
  - `source tools/source_gnustep_env.sh && make phase23-dataverse-tests`
  - `source tools/source_gnustep_env.sh && make phase23-confidence`
  - `source tools/source_gnustep_env.sh && make /home/danboyd/git/Arlen/build/phase23-dataverse-live-smoke`
  - `source tools/source_gnustep_env.sh && make docs-api`
  - `bash tools/ci/run_docs_quality.sh`
- Reconciled and fixed the managed-GNUstep bootstrap bug reported from
  `iep-platform`:
  - added `tools/resolve_gnustep.sh` and `tools/source_gnustep_env.sh`
  - updated `GNUmakefile`, `bin/arlen-doctor`, `bin/boomhauer`,
    `tools/arlen.m`, and the repo test harness to resolve GNUstep shell init
    from `GNUSTEP_SH`, `GNUSTEP_MAKEFILES`, `gnustep-config`, then the
    historical `/usr/GNUstep` fallback
  - taught `arlen doctor` to fail early on missing `dispatch/dispatch.h`
    instead of deferring that toolchain problem to a later compile step
  - recorded upstream status in
    `docs/PLATFORM_REPORT_RECONCILIATION_2026-03-31.md`
  - updated active onboarding/toolchain docs plus `AGENTS.md` to prefer
    `tools/source_gnustep_env.sh`

## Completed Today (2026-03-31)

- Completed Phase `23H-23I`:
  - replaced the monolithic Dataverse test file with focused runtime, query,
    read, write, metadata, regression, and artifact suites backed by shared
    Dataverse test support helpers
  - added fixture-backed OData/query characterization,
    `dataverse_contract_snapshot.json`, and
    `dataverse_perl_parity_matrix.json` so Arlen's shipped Dataverse surface
    is explicitly mapped against the Perl OData/Dataverse/datasource test
    families
  - tightened Dataverse error wrapping so token and transport failures retain
    Dataverse diagnostics and preserve underlying errors
  - added the optional `phase23-live-smoke` build/run lane plus richer
    `phase23-confidence` artifacts, including explicit skipped manifests when
    live credentials are absent
  - updated `docs/DATAVERSE.md`, `docs/TESTING_WORKFLOW.md`,
    `docs/PHASE23_ROADMAP.md`, and status surfaces to reflect completed
    Dataverse parity hardening
- Completed Phase `23A-23G`:
  - added a runtime-inactive Dataverse Web API surface with
    `ALNDataverseClient`, OData query composition, CRUD/upsert helpers,
    lookup/choice serialization, batch execution, metadata normalization, and
    deterministic typed codegen
  - added app/runtime Dataverse helpers through `ALNApplication`,
    `ALNContext`, and `ALNController` with lazy named-target resolution and
    runtime config/env merging
  - consolidated Dataverse request execution around one authorized transport
    path with structured retry/throttle diagnostics, redacted request headers,
    correlation IDs, and shared batch behavior
  - added focused Dataverse regression coverage, `phase23-dataverse-tests`,
    `phase23-confidence`, and optional live codegen smoke artifacts under
    `build/release_confidence/phase23/`
  - added the Dataverse reference example plus updated `README.md`,
    `docs/README.md`, `docs/DATAVERSE.md`, `docs/CONFIGURATION_REFERENCE.md`,
    `docs/TESTING_WORKFLOW.md`, `docs/PHASE23_ROADMAP.md`, and generated API
    docs for the new public runtime helpers
- Planned Phase 23 as the next roadmap phase:
  - added `docs/PHASE23_ROADMAP.md`
  - scoped `23A-23G` around runtime-inactive-by-default Dataverse Web API
    integration, OData query composition, write semantics, metadata/codegen,
    app wiring, diagnostics, and docs closeout
  - recorded the key planning decisions: Dataverse Web API over Microsoft
    Graph, no Arlen module packaging, and compiled-in but runtime-inactive
    behavior by default
- Closed the managed-GNUstep bootstrap bug reported from `iep-platform`:
  - replaced the hard-coded `/usr/GNUstep` assumption across build/bootstrap
    entry points with explicit GNUstep resolution helpers
  - added repo-local shell bootstrap via `tools/source_gnustep_env.sh`
  - added `dispatch_headers` doctor coverage for early libdispatch-header
    diagnostics
  - updated the active docs/toolchain contract and recorded the upstream
    closure note in `docs/PLATFORM_REPORT_RECONCILIATION_2026-03-31.md`

## Leaving Off (2026-03-30)

- Phase 22 is complete:
  - reran the live-backed integration suite against the local PostgreSQL
    instance plus the local SQL Server 2022 Developer test container:
    `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && source /home/danboyd/.config/arlen/mssql-test.env && export ARLEN_PG_TEST_DSN='postgresql:///postgres' && make test-integration`
  - reran `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen build-tests`
  - reran `bash tools/ci/run_docs_quality.sh`
  - verified `git diff --check` stays clean
  - updated `README.md`, `docs/README.md`, `docs/PHASE22_ROADMAP.md`, and
    `docs/STATUS.md` so the summary surfaces now mark Phase 22 complete
- No remaining open items from Phase 22. The next roadmap phase is not planned
  in this checkpoint.

## Completed Today (2026-03-30)

- Completed Phase `22A-22G`:
  - reworked newcomer entry surfaces in `README.md` and `docs/README.md`
  - rewrote the main onboarding path around one generator-first flow in
    `docs/GETTING_STARTED.md`, `docs/GETTING_STARTED_QUICKSTART.md`, and
    `docs/FIRST_APP_GUIDE.md`
  - added dedicated user-facing guides for app authoring, configuration, lite
    mode, plugin/service generation, and frontend starters
  - expanded `docs/MODULES.md` into a connected lifecycle guide
  - tightened docs/code parity by exposing `module ... eject` in CLI help,
    deduplicating generated API reference output, and fixing
    `arlen generate endpoint` route wiring so it inserts the required
    controller import
  - landed docs navigation quality enforcement via
    `tools/ci/check_docs_navigation.py`,
    `tools/ci/run_docs_quality.sh`, and updated review policy in
    `docs/DOCUMENTATION_POLICY.md`
  - closed the phase with `make arlen build-tests`,
    `bash tools/ci/run_docs_quality.sh`, and the live-backed
    `make test-integration` rerun on 2026-03-30

## Leaving Off (2026-03-27 EOD)

- Phase 22 is in progress with `22A-22F` drafted/implemented in the working
  tree and `22G` partially complete:
  - newcomer-first navigation landed in `README.md` and `docs/README.md`
  - onboarding docs were rewritten around one generator-first app path in
    `docs/GETTING_STARTED.md`, `docs/GETTING_STARTED_QUICKSTART.md`, and
    `docs/FIRST_APP_GUIDE.md`
  - new user-facing guides were added for app authoring, configuration,
    lite mode, plugin/service generation, and frontend starters
  - `docs/MODULES.md` was expanded into a lifecycle guide, and the relevant
    historical/spec docs now point at the new practical guides
  - docs-quality hardening landed via
    `tools/ci/check_docs_navigation.py`,
    `tools/ci/run_docs_quality.sh`, and updated review policy in
    `docs/DOCUMENTATION_POLICY.md`
- The docs pass also uncovered a real generator regression:
  - `arlen generate endpoint` was wiring routes into `src/main.m` /
    `app_lite.m` without adding the required controller import
  - fixed in `tools/arlen.m`
  - regression coverage added in
    `tests/integration/DeploymentIntegrationTests.m`
- Verification completed at this checkpoint:
  - `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen build-tests`
  - `bash tools/ci/run_docs_quality.sh`
- Verification still pending at handoff:
  - full integration rerun with the local PostgreSQL instance plus the local
    SQL Server 2022 Developer test container:
    `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && source /home/danboyd/.config/arlen/mssql-test.env && export ARLEN_PG_TEST_DSN='postgresql:///postgres' && make test-integration`
- Next-session closeout path:
  - finish or rerun `make test-integration`
  - if green, mark Phase 22 complete in `docs/PHASE22_ROADMAP.md`,
    `README.md`, `docs/README.md`, and `docs/STATUS.md`
  - regenerate docs if needed, run `git diff --check`, and commit the
    Phase 22 closeout

## Completed Today (2026-03-27)

- Planned Phase 22 as the next roadmap phase:
  - audited the current documentation set for newcomer accessibility,
    code-accuracy, and missing user-facing guides across `README.md`,
    `docs/README.md`, the getting-started family, CLI/help output, generated
    scaffolds, and the current module/service docs
  - scoped `22A-22G` around entrypoint/navigation reset, onboarding
    consolidation, docs/code parity hardening, app-author guides,
    module-lifecycle + lite-mode docs, plugin/frontend guidance, and docs
    quality closeout
  - kept the guardrails explicit: prioritize user-facing workflows over deep
    internal design notes, avoid turning onboarding into contributor checklists,
    and add lightweight drift prevention where it materially improves trust
- Completed Phase `21D-21G`:
  - replaced the broad template/transpiler unit surface with focused
    `TemplateParserTests`, `TemplateCodegenTests`, `TemplateSecurityTests`,
    and `TemplateRegressionTests`, backed by shared helper support in
    `tests/shared/ALNTemplateTestSupport.{h,m}`
  - added parser/security/regression fixture namespaces plus a checked-in
    regression catalog under `tests/fixtures/templates/`
  - promoted a clearer raw protocol corpus under `tests/fixtures/protocol/`
    with dedicated replay tooling in `tools/ci/phase21_protocol_replay.py`
    and the focused `make phase21-protocol-tests` lane
  - added a curated generated-app/module/config matrix under
    `tests/fixtures/phase21/generated_app_matrix.json` with the focused
    `make phase21-generated-app-tests` lane for scaffold, module, and UI-mode
    verification
  - added repo-native Phase 21 focused/confidence entrypoints:
    `make phase21-template-tests`, `make phase21-protocol-tests`,
    `make phase21-generated-app-tests`, `make phase21-focused`, and
    `make phase21-confidence`
  - added `docs/TESTING_WORKFLOW.md` so contributors can turn bug reports into
    focused regressions and confidence reruns without depending on
    `xctest -only-testing`
  - verified the slice with `make build-tests`, `make test-unit`,
    `make phase21-focused`, `make phase21-confidence`,
    `python3 tools/ci/check_roadmap_consistency.py --repo-root .`, and
    `bash tools/ci/run_docs_quality.sh`
- Completed Phase `21A-21C`:
  - added `tests/shared/ALNWebTestSupport.{h,m}` as a shared in-process
    request harness with disposable app construction, config injection, route
    and middleware introspection, request builders, response decoders, and
    reusable status/header/content-type/body/redirect assertions
  - moved multi-request auth/session/CSRF coverage in `ApplicationTests` and
    `MiddlewareTests` onto shared cookie/session recycling and pipeline helper
    seams instead of repeated inline response parsing
  - generalized `tests/shared/ALNTestSupport.{h,m}` and
    `tests/shared/ALNDatabaseTestSupport.{h,m}` with wider JSON/file/shell
    helpers plus explicit DB worker ownership modes (`explicit_borrowed` and
    `shared_owner`) for deterministic concurrency/liveness coverage
  - moved large PostgreSQL/live suites onto the shared support layer so
    temp-dir, file-write, shell-capture, DSN, and cleanup logic are less
    duplicated across integration coverage
  - verified the slice with `make build-tests`, `make test-unit`, and
    `make test-integration` using the local PostgreSQL instance plus the local
    SQL Server 2022 Developer test container
- Planned Phase 21 as the next roadmap phase:
  - audited Mojolicious `Test::Mojo`, Phoenix `ConnTest` + Ecto SQL sandbox,
    Jinja's test-suite structure, and llhttp's request/response/fuzzer corpus
    as the most relevant upstream testing references for Arlen's next
    robustness pass
  - added `docs/PHASE21_ROADMAP.md` and scoped `21A-21G` around in-process
    request harnesses, shared request/pipeline assertions, explicit async DB
    ownership rules, template security/regression decomposition, raw protocol
    corpora with replayable fuzz inputs, generated-app/module matrix coverage,
    and focused contributor rerun lanes
  - kept the guardrails explicit: stay on GNUmake + XCTest, complement rather
    than replace spawned-server integration tests, and avoid adopting foreign
    test frameworks or browser automation as a release gate
- Completed Phase `20P-20R`:
  - added shared Phase 20 test support under `tests/shared` for fixture loading,
    temp dirs, unique identifiers, DSN/env lookup, MSSQL temp-table naming, and
    disposable PostgreSQL/MSSQL schema harnesses
  - moved Phase 20-sensitive Pg/MSSQL/inspector suites onto the shared support
    helpers so repeated DSN, fixture, temp-dir, and unique-name boilerplate is
    no longer duplicated inside the large test files
  - added shared SQL/result assertion helpers and focused backend conformance
    suites for builder, schema/reflection, PostgreSQL live coverage, MSSQL live
    coverage, and routing/pool seam behavior
  - added deterministic pool seam regressions for liveness recycle and
    rollback-on-release behavior on PostgreSQL and MSSQL without depending on
    live backend timing
  - added repo-native focused Phase 20 lanes:
    `make phase20-sql-builder-tests`, `make phase20-schema-tests`,
    `make phase20-routing-tests`, `make phase20-postgres-live-tests`,
    `make phase20-mssql-live-tests`, `make phase20-focused`, and
    `tools/ci/run_phase20_focused.sh`
  - verified the focused runner path end-to-end plus a fresh `make build-tests`
    rebuild; the focused Phase 20 commands no longer depend on stock
    `xctest -only-testing` support
- Completed Phase `20L-20O`:
  - tightened `ALNMSSQL` bind/result transport around native ODBC scalar and
    binary paths, added capability metadata for native transport, and extended
    the backend support fixture/confidence snapshot to record that subset
  - preserved select-list order in `ALNDatabaseResult` / `ALNDatabaseRow` via
    stable `columns` metadata plus `objectAtColumnIndex:` while keeping the
    dictionary-backed contract intact
  - widened PostgreSQL inspector metadata additively for `schemas`,
    `check_constraints`, `view_definitions`, `relation_comments`, and
    `column_comments` without widening schema-codegen into cross-backend
    promises
  - replaced silent DSN-gated early returns in the Phase 20-sensitive Pg/MSSQL
    live suites with explicit requirement logging for missing backend
    prerequisites
  - verified the slice with `make build-tests` plus a broad unit-bundle run
    that exercised `PgTests`, `Phase20DTests`, and `Phase17BTests`; the stock
    `xctest` filter still ignored `-only-testing`, but the relevant suites
    passed within that broader batch
- Audited SQLAlchemy Core test-suite ideas against Arlen's current data-layer
  tests and extended the Phase 20 roadmap with a rollout that keeps Arlen on
  GNUmake + XCTest instead of chasing Python runner parity:
  - added `20O` for explicit test requirements and environment accounting so
    DSN/driver-gated coverage stops passing silently via early returns
  - added `20P` for shared test support and disposable backend harnesses so
    repeated repo-root/fixture/temp-dir/shell helpers stop proliferating across
    large test files
  - added `20Q` for SQL/result assertion helpers and unified backend
    conformance so PostgreSQL/MSSQL overlap gets one stronger reusable
    regression surface
  - added `20R` for focused test topology and confidence-lane decomposition so
    remaining Phase 20 work can be verified without depending on the stock
    `xctest` filter path staying usable
  - recorded the recommended remaining rollout order as `20O`, `20P`, `20Q`,
    `20L`, `20M`, `20R`, with `20N` still conditional

## Completed Today (2026-03-26)

- Completed the Phase 20J-20K execution-ergonomics and backend-tier closeout:
  - added `ALNDatabaseResult` / `ALNDatabaseRow` and generic
    query-result/batch/savepoint helpers without replacing the existing row
    array contract
  - exposed bounded batch execution and explicit savepoints on PostgreSQL and
    MSSQL connections, plus adapter-level result convenience methods
  - added backend `support_tier` metadata, MSSQL checkout liveness checks,
    rollback-on-release pool hygiene, and backend-split phase20 confidence
    artifacts
- Completed the Phase 20G-20I follow-on depth slice:
  - preserved relation kind/read-only metadata end-to-end and made generated
    schema codegen view-safe on the write path
  - added explicit PostgreSQL array-vs-JSON parameter wrappers, bounded array
    decode, fixture-backed codec coverage, and a documented typed MSSQL scalar
    baseline
  - widened `ALNDatabaseInspector` to inspector-v2 metadata for relations,
    primary keys, uniques, foreign keys, and indexes with deterministic
    fixtures/tests
- Completed the Phase 20A-20C data-layer depth slice:
  - added typed PostgreSQL bind/result materialization for the supported scalar
    baseline (`BOOL`, integer, numeric, float, `date`, `timestamp`,
    `bytea`, `json/jsonb`) so live adapter rows now align with generated typed
    contracts
  - extended schema codegen row helpers with
    `decodeTypedFirstRowFromRows:error:` and added live PostgreSQL coverage so
    generated decode contracts are exercised against real adapter results
  - made nested builder compilation dialect-aware so MSSQL validation and
    rewrite behavior now applies recursively inside subqueries instead of only
    at the root builder
  - added lightweight adapter result helpers for first-row and scalar
    extraction (`ALNDatabaseFirstRow`,
    `ALNDatabaseScalarValueFromRow`,
    `ALNDatabaseScalarValueFromRows`,
    `ALNDatabaseExecuteScalarQuery`)
  - updated the public data-layer docs and Phase 20 roadmap/status surfaces to
    reflect the delivered slice
- Verification for the delivered slice:
  - `make test-unit-filter TEST=SchemaCodegenTests`
  - `make test-unit-filter TEST=Phase17BTests`
  - `ARLEN_PG_TEST_DSN=postgresql:///postgres make test-unit-filter TEST=PgTests`
  - note: the current `tools-xctest` runner still ignores the focused filter
    flag and executes a broader unit batch; the 20A-20C coverage passed within
    those broader runs, while the remaining unrelated failure was the existing
    auth-table environment assumption in `Phase13ETests`

This document is a running checkpoint log. For authoritative current roadmap
status, prefer the individual phase roadmap docs and `README.md`. Historical
"Next Session Focus" notes below are preserved as contemporaneous checkpoint
entries, not current plan-of-record items.

## Completed Today (2026-03-24)

- Stabilized the experimental `phase5e` TSAN lane locally without promoting
  TSAN to blocking:
  - bootstrapped `eocc` unsanitized and held that binary old for the
    instrumented `boomhauer` / `arlen` / `test-unit` builds so template
    transpilation no longer trips the GNUstep `libobjc` startup signature
    before the sanitizer lane reaches Arlen code
  - replaced TSAN-hot-path `@synchronized` usage in `ALNResponse`,
    `ALNPg`, and the pg loader concurrency test with explicit `dispatch_once`
    and `NSLock` coordination
  - added repo-managed `phase9h_tsan.supp` suppressions plus lifecycle
    metadata for the current GNUstep `libobjc` / `libgnustep-base`
    deadlock-and-monitor false-positive budget
  - fixed `tools/ci/run_phase5e_tsan_experimental.sh` so it preserves the
    first failing non-zero exit code instead of falling through to the runtime
    probe after a failed `test-unit`, and so it stages its TSAN artifacts
    outside the clean build tree
  - kept nested shell/tooling assertions out of the active TSAN runtime:
    the build-policy fixture wrappers and the auth-ui eject scaffolding test
    now bail out when the outer unit process is already instrumented, because
    standalone `arlen` still emits GNUstep `libobjc` lock-order-inversion
    noise that pollutes stderr-bound JSON/script assertions even though the
    lane itself is otherwise green
  - verified a fresh serial `tools/ci/run_phase5e_tsan_experimental.sh` pass
    now completes through `runtime-concurrency-probe`, but TSAN promotion
    remains blocked until the remaining GNUstep runtime/toolchain false
    positives are resolved and two deterministic pass cycles are observed
- Revisited the remaining TSAN/thread-race follow-up from the 2026-03-22
  self-hosted CI handoff:
  - confirmed the scheduled 2026-03-23 and 2026-03-24 `thread-race-nightly`
    lanes still reproduce the same GNUstep `libobjc` lock-order-inversion
    signature during TSAN-instrumented `eocc` transpilation, so TSAN
    promotion remains blocked on the runtime/toolchain stack rather than an
    Arlen race report
  - fixed `tools/ci/run_phase10m_thread_race_nightly.sh` so TSAN failures
    preserve the real non-zero exit code instead of reporting `0`
  - staged thread-race summary/log artifacts outside the clean build tree so
    `make clean` inside the TSAN helper no longer deletes the outer
    `thread_race.log` before it can be retained
  - added focused regression coverage for nightly wrapper failure propagation
    and retained-log preservation
- Resumed the 2026-03-22 self-hosted GitHub CI handoff and closed the open
  sanitizer follow-up:
  - confirmed the failed March 22 push-triggered sanitizer runs were isolated
    to the `phase10m` soak lane on `iep-apt`, while later reruns of the same
    self-hosted path passed
  - hardened only the sanitizer workflow by raising its self-hosted soak retry
    budget from `2` to `3` without changing shared perf-script defaults
  - added build-policy coverage so the workflow-scoped retry override remains
    pinned in repo policy
- Reconciled the `StateCompulsoryPoolingAPI` `boomhauer --prepare-only`
  report against the current Arlen workspace:
  - recorded the upstream-only status note in
    `docs/STATECOMPULSORYPOOLINGAPI_REPORT_RECONCILIATION_2026-03-24.md`
  - kept closure ownership explicit: Arlen records `fixed in current
    workspace; awaiting downstream revalidation`, while
    `StateCompulsoryPoolingAPI` keeps app-level closure authority
  - fixed app-root `boomhauer --prepare-only` / `--print-routes` so they
    preserve the underlying non-zero build exit status instead of reporting
    success against a failed build
  - hardened `propane` and `jobs-worker` to stop on failed prepare steps and
    point operators at `.boomhauer/last_build_error.log` instead of reusing an
    existing app binary
  - added focused regression coverage for a forced app-root framework-build
    failure in `tests/integration/HTTPIntegrationTests.m`

## Session Handoff (2026-03-24 EOD)

- Added explicit end-of-day handoff note for the TSAN/runtime-toolchain
  follow-up and the freshly pushed `3037bbc` GitHub run set:
  - `docs/SESSION_HANDOFF_2026-03-24.md`
- Resume point recorded there includes:
  - clean Arlen HEAD at `3037bbc`
  - local TSAN helper path verified green
  - pushed GitHub runs on `3037bbc` still settling at stand-down
  - remaining open blocker is TSAN promotion against GNUstep
    `libobjc` runtime/toolchain false positives in standalone instrumented
    `arlen`

## Session Handoff (2026-03-22 EOD)

- Added explicit end-of-day handoff note for the self-hosted GitHub CI
  recovery work:
  - `docs/SESSION_HANDOFF_2026-03-22.md`
- Resume point recorded there includes:
  - clean Arlen HEAD at `d40c0b4`
  - self-hosted runner `iep-apt-arlen` stable and working again
  - `phase5e-quality`, `docs-quality`, and `phase3c-quality` green on
    `d40c0b4`
  - `phase5e-sanitizers` still in progress at stand-down
  - checked-in `iep-apt` perf baselines now pin the 4-core self-hosted perf
    gate to host-matched thresholds

## Session Handoff (2026-03-21 EOD)

- Added explicit end-of-day handoff note for the cross-repo CI/toolchain work:
  - `docs/SESSION_HANDOFF_2026-03-21.md`
- Resume point recorded there includes:
  - clean Arlen HEAD at `c699d39`
  - clean `apt_portstree` HEAD at `93e1f83`
  - verified shared GNUstep images built on `iep-apt`
  - next task: add a generic GitHub Actions runner image on top of the shared
    GNUstep CI image, then retry TSAN on that runner path

## Benchmark Handoff (2026-02-24 EOD)

- Added end-of-day checkpoint for benchmark work:
  - `docs/BENCHMARK_HANDOFF_2026-02-24.md`
  - preserves latest verified in-repo Phase D run (`20260224T233744Z`), artifact paths, and the original 2026-02-24 handoff notes
- Current comparative benchmark source of truth:
  - `docs/COMPARATIVE_BENCHMARKING.md`
  - sibling program `../ArlenBenchmarking` now owns comparative reporting/publication work

## Current Milestone State

- Phase 1: complete
- Phase 2A: complete
- Phase 2B: complete
- Phase 2C: complete (2026-02-19)
- Phase 2D: complete (2026-02-19)
- Phase 3A: complete (2026-02-19)
- Phase 3B: complete (2026-02-19)
- Phase 3C: complete (2026-02-20)
- Phase 3D: complete (2026-02-20)
- Phase 3E: complete (2026-02-20)
- Phase 3F: complete (2026-02-20)
- Phase 3G: complete (2026-02-20)
- Phase 3H: complete (2026-02-20)
- Phase 4A: complete (2026-02-20)
- Phase 4B: complete (2026-02-20)
- Phase 4C: complete (2026-02-20)
- Phase 4D: complete (2026-02-20)
- Phase 4E: complete (2026-02-20)
- Phase 5A: complete (2026-02-23)
- Phase 5B: complete (2026-02-23)
- Phase 5C: complete (2026-02-23)
- Phase 5D: complete (2026-02-23)
- Phase 5E: complete (2026-02-23)
- Phase 7: complete for current first-party scope (initial slices landed 2026-02-23; closeout verified 2026-03-13)
- Phase 8A: complete (2026-02-24)
- Phase 8B: complete (2026-02-24)
- Phase 9A: complete (2026-02-24)
- Phase 9B: complete (2026-02-24)
- Phase 9C: complete (2026-02-24)
- Phase 9D: complete (2026-02-24)
- Phase 9E: complete (2026-02-25)
- Phase 9F: complete (2026-02-25)
- Phase 9G: complete (2026-02-25)
- Phase 9H: complete (2026-02-25)
- Phase 9I: complete (2026-02-25)
- Phase 9J: complete (2026-02-25)
- Phase 10: complete (10A/10B/10C/10D/10E/10F/10G/10H/10I/10J/10K/10L/10M complete on 2026-02-26)
- Phase 11A: complete (2026-03-06)
- Phase 11B: complete (2026-03-06)
- Phase 11C: complete (2026-03-06)
- Phase 11D: complete (2026-03-06)
- Phase 11E: complete (2026-03-06)
- Phase 11F: complete (2026-03-06)
- Phase 12: complete (12A/12B/12C complete on 2026-03-06; 12D/12E/12F complete on 2026-03-09)
- Phase 13: complete (13A/13B/13C/13D/13E/13F/13G/13H/13I complete on 2026-03-09)
- Phase 14: complete (14A/14B/14C/14D/14E/14F/14G/14H/14I complete on 2026-03-10)
- Phase 15: complete (15A/15B/15C/15D/15E complete on 2026-03-10)
- Phase 16: complete (`16A/16B/16C` complete on 2026-03-10; `16D/16E/16F/16G` complete on 2026-03-11)
- Phase 17: complete (`17A-17D` delivered on 2026-03-12 for backend-neutral data-layer seams and optional MSSQL support)
- Phase 18: complete (`18A-18H` delivered on 2026-03-14 for fragment-first MFA
  UI, headless MFA contracts, optional SMS/Twilio Verify support, and generated-app-ui include-path hardening)
- Phase 19: complete (`19A-19F` delivered on 2026-03-14 for incremental
  GNUmake/GNUstep build-graph narrowing, generated-template object reuse, and
  clearer `boomhauer` build scope/progress)
- Phase 20: complete (`20A-20R` complete as of 2026-03-27 for typed codecs/live
  rows, recursive nested dialect compilation, result/savepoint ergonomics,
  reflection/codegen alignment, routing/pool hardening, relation-kind-safe
  reflection, richer type parity, inspector-v2 metadata, backend support
  tiers, MSSQL native transport tightening, ordered result semantics, bounded
  PostgreSQL metadata expansion, explicit live-test requirement accounting,
  shared test support/assertion helpers, and focused Phase 20 confidence lanes)
- Phase 21: complete (`21A-21G` complete as of 2026-03-27 for in-process
  request harnesses, shared request/pipeline assertions, explicit async DB
  ownership rules, template-suite decomposition, raw protocol corpus replay,
  generated-app matrix coverage, and focused contributor rerun lanes)
- Phase 22: complete (`22A-22G` delivered on 2026-03-30 for newcomer-first
  onboarding cleanup, docs/code parity hardening, app-author guides,
  module/lite-mode guidance, plugin/frontend guides, and docs quality closeout)
- Phase 23: complete (`23A-23I` delivered on 2026-03-31 for the
  runtime-inactive Dataverse Web API client, OData query composition,
  CRUD/upsert/batch helpers, metadata normalization, typed Dataverse codegen,
  app/controller Dataverse helpers, focused confidence lanes, split
  regression-matrix coverage, characterization/parity artifacts, optional
  live Dataverse smoke support, and docs/example closeout)

## Completed Today (2026-03-26)

- Extended the Phase 20 roadmap with follow-on substeps:
  - added `20L` for MSSQL native bind/result transport tightening
  - added `20M` for result row-order and projection semantics
  - added `20N` as an explicit optional broader-reflection slice only if
    cross-backend tooling becomes a product goal
- Completed Phase 20 reflection/tooling, routing/pool hardening, and closeout:
  - added `ALNDatabaseInspector` / `ALNPostgresInspector` and moved
    `arlen schema-codegen` onto one normalized reflection contract
  - extended schema-codegen manifests with
    `reflection_contract_version`, relation metadata, and per-table
    `column_metadata`
  - tightened `ALNDatabaseRouter` read fallback defaults to
    connectivity-only with explicit `readFallbackPolicy`
  - added PostgreSQL pool checkout liveness checks, idle stale-connection
    recycling, active-transaction rollback-on-release, and prepared-statement
    cache eviction instead of saturation starvation
  - added Phase 20 fixtures, unit coverage, and `make phase20-confidence`
- Completed Phase 20 relation-kind reflection, richer type parity, and
  inspector-v2 metadata:
  - preserved `relation_kind`, `read_only`, and `supports_write_contracts`
    through schema manifests and generated helper decisions so reflected views
    no longer get default write contracts
  - added `ALNDatabaseJSONParameter(...)` / `ALNDatabaseArrayParameter(...)`,
    bounded PostgreSQL array decode, fixture-backed live codec coverage, and a
    documented typed scalar baseline on MSSQL
  - widened `ALNDatabaseInspector` metadata output to relations, primary keys,
    unique constraints, foreign keys, and indexes with deterministic fixtures
    and tests

## Completed Today (2026-03-21)

- Recorded downstream confirmation for the two app-reported issues we closed
  upstream this session:
  - `Structurizer` confirmed the external `ARLEN_FRAMEWORK_ROOT` sanitizer
    reuse issue is resolved; upstream note updated in
    `docs/STRUCTURIZER_REPORT_RECONCILIATION_2026-03-21.md`
  - `MusicianApp` confirmed the earlier upstream-fixed report set is resolved on
    its branch/config; upstream note updated in
    `docs/MUSICIANAPP_REPORT_RECONCILIATION_2026-03-21.md`
- Reconciled the `Structurizer` external-framework override report against the
  current Arlen workspace:
  - recorded the upstream-only status note in
    `docs/STRUCTURIZER_REPORT_RECONCILIATION_2026-03-21.md`
  - kept closure ownership explicit: Arlen records `fixed upstream` or
    `awaiting downstream revalidation`, while `Structurizer` keeps app-level
    closure authority
  - fixed app-root `boomhauer` so an external `ARLEN_FRAMEWORK_ROOT` no longer
    reuses sanitizer-contaminated framework archives through to a late raw
    linker failure
- Reconciled the remaining `MusicianApp`-reported open items against the
  current Arlen workspace:
  - recorded the upstream-only status matrix in
    `docs/MUSICIANAPP_REPORT_RECONCILIATION_2026-03-21.md`
  - kept closure ownership explicit: Arlen records `fixed/implemented upstream`
    or `awaiting downstream revalidation`, while `MusicianApp` keeps app-level
    closure authority
  - confirmed that most still-open downstream filings are already satisfied by
    current upstream work from Phases 15-18 plus the current workspace
    `boomhauer` recovery fixes
- Closed the remaining direct upstream bug from that open set:
  - normalized shared auth action typography across `<button>` and `<a>`
    controls in the stock auth stylesheet
  - added focused regression coverage for the shared auth stylesheet contract
- Added focused migration coverage for the original `MusicianApp`
  multi-statement SQL report:
  - verified generic migration execution handles multiple top-level statements,
    including dollar-quoted content with embedded semicolons

## Completed Today (2026-03-14)

- Added optional XCTest runner override + focused rerun helpers:
  - `make test-unit`, `make test-integration`, and the Phase 12-16 confidence scripts now honor `ARLEN_XCTEST` instead of hardcoding `xctest`
  - added optional `ARLEN_XCTEST_LD_LIBRARY_PATH` support so a local uninstalled `tools-xctest` checkout can load its matching patched `libXCTest`
  - added `make test-unit-filter` and `make test-integration-filter` for Apple-style `-only-testing` / `-skip-testing` reruns using `TEST=TestClass[/testMethod]` plus optional `SKIP_TEST=...`
  - kept stock Debian `tools-xctest` as the default baseline for normal unfiltered verification
- Completed Phase 19 incremental build-graph narrowing:
  - refactored `GNUmakefile` around deterministic object/dependency outputs
    under `build/obj/...` plus shared framework reuse through
    `build/lib/libArlenFramework.a`
  - narrowed template invalidation to per-template generated object rebuilds
    while keeping manifest-backed garbage collection for removed template
    outputs
  - tightened integration bundle prerequisites to concrete example binaries
    instead of phony targets so warm `make build-tests` can stay no-op
- Completed Phase 19 app-root `boomhauer` scope/progress UX:
  - `--prepare-only` and `--print-routes` now emit explicit `[1/4]` through
    `[4/4]` build stages and mode banners that distinguish route inspection
    from normal server startup
  - app-root `.boomhauer/build/` artifacts now reuse warm objects/binaries
    instead of recompiling every non-watch launch
- Completed Phase 19 confidence + measurement closeout:
  - added `make phase19-confidence` / `tools/ci/run_phase19_confidence.sh`
    with reproducible timing + rebuild-scope artifacts under
    `build/release_confidence/phase19`
  - current confidence baseline records `make build-tests` at `70.99s` cold
    and `0.37s` warm, `make test-unit` at `3.30s`, and app-root
    `boomhauer --prepare-only` / `--print-routes` at `0.89s` cold,
    `0.43s` warm, and `0.44s`

## Completed Today (2026-03-13)

- Planned Phase 19 as the next roadmap phase:
  - added `docs/PHASE19_ROADMAP.md` for GNUmake/GNUstep-friendly incremental
    build graph work
  - scoped the work around object-file compilation, shared framework artifact
    reuse, incremental EOC transpilation, `boomhauer` scope/progress UX, and
    narrower test prerequisites
  - made the acceptance bar explicit: faster incremental rebuilds without
    weakening deterministic `eocc` diagnostics or app-root correctness
- Completed Phase 18E-18G optional SMS MFA and factor-management follow-on:
  - added disabled-by-default SMS MFA via Twilio Verify with policy-gated route
    registration, resend/verify limits, and test-code seams
  - added stock factor-management pages/fragments so users can manage
    authenticator-app and SMS factors together while keeping TOTP preferred
  - extended generated-app-ui eject, docs/examples, and confidence coverage for
    SMS enrollment, challenge, removal, and headless `/auth/api/mfa` discovery
- Completed Phase 18A-18D auth module reuse maturity:
  - promoted coarse embeddable auth fragments for server-rendered EOC apps and
    refactored the stock auth UI to consume those same fragments
  - split TOTP HTML into enrollment, challenge, and recovery-code completion
    states with local browser-side QR rendering and manual-entry fallback
  - strengthened `/auth/api/mfa/totp` and `/auth/api/mfa/totp/verify` with
    explicit `flow` and `mfa` payloads for React/native clients
  - extended `generated-app-ui` eject, examples, and confidence coverage around
    the fragment-first MFA contract

## Completed Today (2026-03-12)

- Completed Phase 17 backend-neutral data-layer seams and optional MSSQL support:
  - added `ALNSQLDialect`, `ALNPostgresDialect`, and `ALNMSSQLDialect` as the explicit SQL dialect/capability seam
  - added `ALNSQLBuilder buildWithDialect:` / `buildSQLWithDialect:` / `buildParametersWithDialect:` while preserving PostgreSQL-default `build:`
  - refactored `ALNMigrationRunner` to use `id<ALNDatabaseAdapter>` plus adapter-provided dialect metadata instead of `ALNPg *` in its public API
  - normalized MSSQL `GO` batch separators during migration execution and rejected top-level `SAVE TRANSACTION` alongside the existing transaction-control checks
- Completed Phase 17 optional MSSQL adapter transport + compiler support:
  - added `ALNMSSQL` with runtime ODBC transport loading so core Arlen does not hard-link to Microsoft’s driver
  - added MSSQL SQL compilation for identifier quoting, `OUTPUT INSERTED/DELETED` return semantics, and `OFFSET ... FETCH` pagination
  - made unsupported PostgreSQL-only builder features fail closed on MSSQL with explicit diagnostics (`ON CONFLICT`, `ILIKE`, `NULLS FIRST/LAST`, lateral joins, `JOIN ... USING`, and PostgreSQL row-lock clauses)
- Completed Phase 17 tooling/docs/conformance closeout:
  - updated `arlen migrate` and `arlen module migrate` to instantiate the configured adapter for the selected target (`postgresql`, `gdl2`, or optional `mssql`)
  - kept `arlen schema-codegen` PostgreSQL-only and documented that scope explicitly
  - expanded the shared adapter conformance harness to emit dialect-appropriate DDL/placeholder SQL for PostgreSQL/GDL2 and MSSQL
  - added `Phase17ATests.m` and `Phase17BTests.m` coverage for generic migration execution, MSSQL SQL compilation, and adapter initialization/conformance hooks

## Completed Today (2026-03-11)

- Planned Phase 17 as the next roadmap step:
  - added `docs/PHASE17_ROADMAP.md` for backend-neutral data-layer seams plus optional MSSQL support
  - made the dependency boundary explicit: no hard dependency on Microsoft's ODBC driver in core Arlen
  - scoped the work around dialect/migration refactoring first, then an optional MSSQL adapter target, then docs/conformance closeout
- Triaged new `MusicianApp` Arlen filings against the current workspace:
  - kept `ARLEN-BUG-009` open as a narrower watch-recovery follow-up rather than a broad missing-recovery claim
  - identified `ARLEN-BUG-010` (`admin-ui` `legacyPath` HTML action/update parity) as a current framework bug to fix
  - identified `ARLEN-FR-004` (safer module path defaults and clearer `*.paths.*` config) as a current open enhancement after restoring `modules/jobs/`
  - identified `ARLEN-FR-005` (first-class invite-claim/email-link acquisition flow) as a legitimate open auth enhancement
  - marked `ARLEN-FR-002` and `ARLEN-FR-003` as already addressed by the shipped Phase 16 notifications surface and `arlen jobs worker`
  - reclassified `ARLEN-BUG-011` under `ARLEN-FR-005` unless the same delivery failure reproduces through the supported forgot-password flow
- Executed the remaining `MusicianApp` queue items (`ARLEN-BUG-009`, `ARLEN-BUG-010`, `ARLEN-FR-004`, `ARLEN-FR-005`):
  - fixed `boomhauer` watch-mode stale recovery by invalidating the prior build fingerprint after EOC compile failures and added regression coverage for the stale-after-fix case
  - fixed `admin-ui` `legacyPath` parity so provider-defined legacy aliases keep list/detail/update/action/export/autocomplete coverage across both HTML and JSON surfaces
  - restored the safer first-party jobs module path default (`jobsModule.paths.apiPrefix = "api"`) and documented the nested `jobsModule.paths.*` override contract
  - added a supported public auth runtime primitive for trusted email claim / invite acquisition flows, including optional password-setup email issuance and session claim via `email_link`
  - re-applied the missing Phase 16A jobs runtime behavior that had been dropped when `modules/jobs/` was restored from an older snapshot, including persisted operator state, per-job retry backoff, uniqueness-derived idempotency, and scheduled-at worker context
- Completed Phase 16D search engine and indexing maturity:
  - expanded `modules/search/` with durable index/generation state, a stronger `ALNSearchEngine` boundary, full-reindex swap activation, incremental sync paths, richer filter/sort/pagination metadata, and protected resource drilldowns
  - added shared admin integration through the `search_indexes` resource plus stronger ops-ready reindex history and failure visibility
  - added `Phase16DTests.m` and `Phase16ModuleIntegrationTests.m` coverage for generation persistence, incremental sync, fail-closed query validation, and admin/search/ops composition
- Completed Phase 16E ops drilldown and historical visibility:
  - expanded `modules/ops/` with persisted history snapshots, `/ops/modules/:module` and `/ops/api/modules/:module` drilldowns, contributed card/widget seams, and stronger `healthy/degraded/failing/informational` status shaping
  - kept the dashboard useful when only a subset of the shipped modules is installed by scoping summaries to the active application runtime
  - added `Phase16ETests.m` coverage for persistence, drilldown payloads, card/widget contribution, and subset-runtime behavior
- Completed Phase 16F admin UI productivity maturity:
  - expanded `modules/admin-ui/` with typed filter metadata, stable pagination/sort descriptors, bulk actions, JSON/CSV export routes, autocomplete hooks, and richer shared list/detail templates
  - made the built-in `users` resource conditional on a configured database while keeping provider-only app resources valid without a database connection
  - added `Phase16FTests.m` and focused integration coverage for bulk actions, exports, typed filters, autocomplete, and resource metadata parity
- Completed Phase 16G docs, example app, and confidence closeout:
  - added `examples/phase16_modules_demo/` as the canonical matured-module reference app spanning `auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, and `search`
  - added `make phase16-confidence` plus deterministic artifact generation under `build/release_confidence/phase16/`
  - finished the Phase 16 docs/status pass across the top-level onboarding path and the `search`, `ops`, and `admin-ui` module guides
- Tightened mounted admin runtime behavior and stale expectations uncovered by the new confidence path:
  - made the mounted `admin-ui` child app inherit parent middleware classes so app auth/session middleware continues to apply on `/admin/...`
  - updated `Phase14JobsNotificationsIntegrationTests.m` so its outbox expectations match the shipped queued-plus-delivered audit trail from Phase 16B

## Completed Today (2026-03-10)

- Completed Phase 16A jobs maturity pass:
  - expanded `modules/jobs/` with persisted operator history, multi-queue pause/resume state, richer queue summaries, and explicit system schedule registration
  - added deterministic enqueue metadata for queue priority, tags, retry backoff, and uniqueness-derived idempotency keys
  - added `Phase16ATests.m` coverage for persisted operator metadata and uniqueness-derived enqueue behavior
- Completed Phase 16B notifications durability and channel maturity:
  - expanded `modules/notifications/` with persisted inbox/outbox/preferences state, realtime inbox fanout tracking, and first-party webhook delivery support
  - added channel-policy metadata for per-channel queue and retry routing plus queued delivery audit entries on the split-channel path
  - added `Phase16BTests.m` coverage for durable notification state, realtime fanout, and split-channel queueing
- Completed Phase 16C storage durability and media maturity:
  - expanded `modules/storage/` with persisted object/upload-session/activity state, cleanup scheduling, attachment capability summaries, and retention-aware maintenance jobs
  - added transform-based variant generation with explicit failure state, recovery, and cleanup activity tracking
  - added `Phase16CTests.m` coverage for durable catalog state, transform-backed variants, and cleanup-surface registration
- Planned Phase 16 as the next module roadmap phase:
  - added `docs/PHASE16_ROADMAP.md` for the first post-Phase-15 maturity pass
  - scoped the follow-on around `jobs`, `notifications`, `storage`, `search`, `ops`, and `admin-ui`
  - made the sequencing explicit: `jobs` first, `admin-ui` polish late, and docs/examples/confidence as the closeout
- Completed Phase 15 auth UI integration closeout:
  - finished the Phase 15 docs/status pass across `README.md`, `docs/README.md`, `docs/CLI_REFERENCE.md`, `docs/GETTING_STARTED.md`, `docs/AUTH_MODULE.md`, and `docs/AUTH_UI_INTEGRATION_MODES.md`
  - added `examples/auth_ui_modes/` covering `headless`, `module-ui`, and `generated-app-ui`
  - added `make phase15-confidence` with artifacts under `build/release_confidence/phase15/`
  - added focused HTTP integration coverage for the auth UI mode split in `tests/integration/Phase13AuthAdminIntegrationTests.m`
- Completed Phase 14G ops module foundation and protected runtime dashboard:
  - added vendored `modules/ops/` with protected `/ops` HTML plus `/ops/api/{summary,signals,metrics,openapi}` JSON/OpenAPI routes
  - composed runtime health/readiness/live signals, metrics, jobs, notifications, storage, and search summaries into one operator/admin surface
  - added `Phase14GTests.m` and `Phase14OpsIntegrationTests.m` coverage for deterministic summaries and protected operator flows
- Completed Phase 14H search module foundation and admin/search integration:
  - added vendored `modules/search/` with explicit searchable-resource contracts, public query routes, and protected reindex routes
  - added job-backed `search.reindex` execution, `admin-ui` auto-resource indexing, shared `search_indexes` admin resource, and ops summary integration
  - added `Phase14HTests.m` and `Phase14SearchIntegrationTests.m` coverage for metadata normalization, fail-closed query parsing, and reindex/admin/ops visibility
- Completed Phase 14I docs, sample app, and confidence artifacts:
  - added `examples/phase14_modules_demo/` showing `auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, and `search` installed together
  - added `docs/OPS_MODULE.md` and `docs/SEARCH_MODULE.md` and updated the module/bootstrap documentation path
  - added `make phase14-confidence` with artifact generation under `build/release_confidence/phase14/`
- Completed Phase 14D notifications channels, previews, preferences, and admin integration:
  - expanded `modules/notifications/` with inbox/preferences/outbox/preview/test-send HTML routes plus matching JSON routes
  - added deterministic preview/test-send runtime APIs, per-recipient preference storage, and optional `ALNNotificationPreferenceHook`
  - added `admin-ui` resources for notification outbox history and notification-definition inspection
  - added `Phase14DTests.m` and `Phase14NotificationsIntegrationTests.m` coverage for preview/delivery parity, preference evaluation, inbox access control, and admin preview/test-send flows
- Completed Phase 14E storage module foundation:
  - added vendored `modules/storage/` with deterministic collection/provider contracts on top of `ALNAttachmentAdapter`
  - added signed upload/download token flows, runtime-managed object metadata, and collection policy validation
  - added `Phase14ETests.m` coverage for deterministic collection metadata and fail-closed signed download-token behavior
- Completed Phase 14F uploads, media variants, and storage-management UX:
  - added protected `/storage` HTML routes plus `/storage/api/...` JSON/OpenAPI routes for collections, objects, direct uploads, download tokens, delete, and variant regeneration
  - added async variant generation through the shared jobs runtime via `storage.generate_variant`
  - integrated storage records into `admin-ui` with list/detail metadata plus delete/regenerate actions
  - added `Phase14FTests.m` and `Phase14StorageIntegrationTests.m` coverage for direct-upload tamper/expiry rejection, signed downloads, variant processing, and storage-management surfaces
- Tightened Phase 14 auth coverage and regressions:
  - required authenticated user context for the notifications user JSON routes and preserved admin/AAL2 requirements for privileged notification and storage routes
  - updated `Phase14JobsNotificationsIntegrationTests.m` to inject auth state explicitly under the current route protections
  - updated `Phase14CTests.m` so outbox expectations match the shipped in-app plus email delivery recording model

## Open Follow-up

- No remaining open items from the current `MusicianApp` queue review.
- `ARLEN-BUG-011` remains folded into `ARLEN-FR-005` unless the same delivery failure reproduces through the supported forgot-password path on current Arlen.

## Triage Notes

- `ARLEN-FR-002` is already addressed in the current Arlen workspace:
  - Phase 16B added durable inbox/outbox/preferences state, read/unread mutations, deep-link metadata, and first-party HTML inbox surfaces
- `ARLEN-FR-003` is already addressed in the current Arlen workspace:
  - Arlen now ships `arlen jobs worker`, documents it in the CLI reference, and includes a first-party `bin/jobs-worker` entrypoint
- `ARLEN-BUG-011` is reclassified for now:
  - the app report relies on `ALNAuthModuleRuntime` methods that exist in implementation but are not part of the public runtime header, so this is not yet a clear framework bug on a supported surface
- `ARLEN-BUG-009` is now fixed on the current workspace:
  - `boomhauer` clears the last successful build fingerprint after template compile failures, so watch mode rebuilds once the template is fixed instead of reusing the prior successful binary

## Completed Today (2026-03-09)

- Planned Phase 15 as the next roadmap phase:
  - added `docs/PHASE15_ROADMAP.md` for auth UI integration modes
  - made the sequencing explicit: Phase 15 lands before resuming Phase 14D-14I
  - linked the supporting design contract in `docs/AUTH_UI_INTEGRATION_MODES.md`

- Completed Phase 14A jobs module foundation:
  - added vendored `modules/jobs/` with deterministic job-definition and schedule-provider contracts on top of `ALNJobAdapter`/`ALNJobWorker`
  - added protected `/jobs` HTML dashboard plus `/jobs/api/...` JSON/OpenAPI routes for definitions, schedules, queues, pending/leased/dead-letter inspection, enqueue, scheduler, worker, replay, and queue pause/resume
  - added `Phase14ATests` coverage for deterministic registration/config contracts and combined jobs/notifications integration coverage in `Phase14JobsNotificationsIntegrationTests.m`
- Completed Phase 14B jobs scheduler and queue operations surface:
  - added cron-like and interval-like scheduler normalization with deterministic worker execution through the shared job runtime
  - added dead-letter replay, leased-job inspection, and default-queue pause/resume support
  - added HTML + JSON jobs operator flows guarded by shared auth/admin/AAL2 contracts and included in module OpenAPI output
- Completed Phase 14C notifications module foundation:
  - added vendored `modules/notifications/` with deterministic notification-definition/provider contracts on top of mail + jobs
  - added async dispatch through the system `notifications.dispatch` job plus `/notifications/api/...` JSON routes for definitions, outbox, inbox, and queueing
  - added `Phase14CTests` coverage for registration order, unsupported-channel rejection, and jobs-backed delivery behavior
- Added `docs/PHASE14_ROADMAP.md` planning the next five first-party modules on top of the Phase 13 module system:
  - `jobs`
  - `notifications`
  - `storage`
  - `ops`
  - `search`
- Completed Phase 13A module contract and loader:
  - added `ALNModule`, manifest-backed `ALNModuleDefinition`, deterministic dependency ordering, version compatibility checks, principal-class validation, and runtime module loading
  - integrated module loading into `ALNApplication` and config resolution via `ALNModuleSystem`
  - added Phase 13A unit coverage for malformed manifests, duplicate identifiers, dependency ordering, and protocol validation
- Completed Phase 13B packaging, resources, and overrides:
  - added vendored `modules/<id>/...` build support in `bin/boomhauer` for module Objective-C sources and namespaced EOC templates
  - added release packaging support for vendored `modules/`
  - added asset staging with app override precedence and unit coverage for override/collision behavior
- Completed Phase 13C module CLI and lifecycle:
  - added `arlen module add/remove/list/doctor/migrate/assets/upgrade`
  - added plist-backed deterministic modules lock handling and JSON workflow payloads for module operations
  - added integration coverage for install/list/doctor/assets/upgrade plus boomhauer/release packaging workflow
- Completed Phase 13D config, migrations, compatibility, and diagnostics:
  - added module config-default merging, required-config diagnostics, Arlen-version compatibility checks, and module-specific doctor output
  - added module-aware migration planning plus namespaced migration application in `ALNMigrationRunner`
  - added Postgres integration coverage for module migration apply and upgrade paths
- Completed Phase 13E auth module foundation:
  - added vendored `modules/auth/` with default account schema, namespaced migrations, EOC templates, and JSON session/bootstrap endpoints
  - added deterministic hook seams for registration policy, password policy, user provisioning, notification customization, provider mapping, and post-login/session policy
  - added `Phase13ETests` coverage for stable defaults and deterministic hook invocation
- Completed Phase 13F auth product flows and provider bridge:
  - shipped first-party registration, login/logout, password reset/change, email verification, TOTP enrollment/step-up, and stub provider-login flows
  - kept provider-login sessions on the same local auth-assurance model used by local auth
  - added `Phase13FTests` hook coverage plus `Phase13AuthAdminIntegrationTests.m` for end-to-end auth/admin install + flow coverage when `ARLEN_PG_TEST_DSN` is set
- Completed Phase 13G admin UI module foundation:
  - added vendored `modules/admin-ui/` mounted child app with default `/admin` HTML routes and `/admin/api` JSON routes
  - enforced shared admin policy defaults: authenticated session, `admin` role, and AAL2 step-up
  - added default admin dashboard/user screens plus `Phase13GTests` route-contract coverage
- Completed Phase 13H admin resource system and headless API:
  - refactored `admin-ui` around `ALNAdminUIResource` and `ALNAdminUIResourceProvider` contracts instead of hard-coded `/users` handlers
  - added machine-readable resource metadata, generic HTML/JSON resource routes, custom action support, and per-resource policy hooks
  - added `/auth/api/...` aliases for the auth module so SPA clients can consume the same auth contract via a stable headless namespace
  - added `Phase13HTests` plus expanded end-to-end auth/admin integration coverage for a registered app-owned `orders` resource
- Completed Phase 13I docs, sample app, and confidence artifacts:
  - added `examples/auth_admin_demo/` showing module install flow plus app-owned admin resource registration
  - added `docs/MODULES.md`, `docs/AUTH_MODULE.md`, and `docs/ADMIN_UI_MODULE.md`
  - added `make phase13-confidence` and artifact generation under `build/release_confidence/phase13/`
- Completed Phase 12D OIDC/OAuth2 client foundation:
  - added `ALNOIDCClient` for authorization-code + PKCE request generation, callback validation, token parsing, and HS256/RS256 ID-token verification
  - added hostile-input fixture coverage in `tests/fixtures/auth/phase12_oidc_cases.json`
  - added `tests/unit/OIDCClientTests.m` for PKCE/state/nonce, callback tamper, nonce mismatch, JWKS rotation/expiry, token redaction, and normalized identity coverage
- Completed Phase 12E provider presets and session/login bridge contracts:
  - added `ALNAuthProviderPresets` first-party provider defaults (Google, GitHub, Microsoft, Apple, Okta, Auth0-style OIDC)
  - added `ALNAuthProviderSessionBridge` for provider-identity resolution plus local session bootstrap hooks
  - added provider preset merge regression coverage in `tests/unit/ApplicationTests.m`
  - added auth-provider login/step-up integration coverage in `tests/integration/HTTPIntegrationTests.m`
- Completed Phase 12F hardening, DX contracts, and confidence artifacts:
  - added `examples/auth_primitives/` sample app showing provider login plus local TOTP step-up on top of core primitives
  - added `make phase12-confidence` with artifact generation under `build/release_confidence/phase12/`
  - updated docs and examples index to reference the new helper surface and sample app

## Phase 10M Completion (2026-02-26)

- completed 10M.9 large-body response throughput hardening:
  - added `NSData` implicit return fast path and explicit `renderData:contentType:` helper
  - converted `/api/blob` to cached binary payload generation and added `impl=legacy-string` comparison mode
  - added `mode=sendfile` blob variant to isolate transport throughput path
  - added split performance profile (`blob_legacy_string_e2e`, `blob_binary_e2e`, `blob_binary_sendfile`)
  - added throughput artifact gate + thresholds + make target:
    - `tools/ci/run_phase10m_blob_throughput.sh`
    - `tools/ci/generate_phase10m_blob_throughput_artifacts.py`
    - `tests/fixtures/performance/phase10m_blob_throughput_thresholds.json`
    - `make ci-blob-throughput`

## Completed Today (2026-02-26)

- Completed Phase 10A yyjson foundation tranche:
  - yyjson C source is wired into framework build targets (`GNUmakefile`) and app-root `bin/boomhauer` compile path
  - `ALNJSONSerialization` exposes deterministic backend selection (`ARLEN_JSON_BACKEND`) plus yyjson version metadata
- Completed Phase 10B parity/regression tranche:
  - added serializer contract tests covering backend selection, round-trip parity, mutable container/leaf behavior, fragment handling, invalid JSON failures, object-validity rules, and sorted-key equivalence
  - added encapsulation regression test ensuring direct yyjson API usage remains constrained to serialization module
- Completed Phase 10C runtime migration tranche:
  - migrated runtime JSON call sites to `ALNJSONSerialization` across response, schema, envelope middleware, session middleware, auth, logger, application, pg diagnostics, and controller rendering paths
  - added regression guard test to prevent direct runtime `NSJSONSerialization` usage in migrated files
- Completed Phase 10D CLI/tooling migration tranche:
  - migrated JSON handling in `tools/arlen.m` and `tools/boomhauer.m` to `ALNJSONSerialization`
  - standardized deterministic CLI JSON output options (pretty + sorted-keys when available) and added deterministic output regression coverage for `arlen config --json`
- Completed Phase 10E JSON performance confidence tranche:
  - added in-repo JSON microbenchmark tool (`tools/json_perf_bench.m`) and fixture corpus (`tests/fixtures/performance/json/*.json`)
  - added Phase 10E CI gate + artifact generator (`tools/ci/run_phase10e_json_performance.sh`, `tools/ci/generate_phase10e_json_perf_artifacts.py`)
  - added threshold policy fixture and release confidence manifest pack under `build/release_confidence/phase10e`
- Completed Phase 10F cutover/guardrails tranche:
  - added runtime lint/check rule preventing direct runtime `NSJSONSerialization` usage (`tools/ci/check_runtime_json_abstraction.py`, `make ci-json-abstraction`)
  - integrated JSON abstraction/performance gates into quality pipeline (`make ci-quality`) and check path (`make check`)
  - updated release packaging to require Phase 10E JSON performance evidence by default (`tools/deploy/build_release.sh`)
  - published foundation fallback deprecation timeline metadata (`ALNJSONSerialization foundationFallbackDeprecationDate = 2026-04-30`)
- Completed Phase 10G dispatch/runtime invocation hardening tranche:
  - introduced explicit runtime invocation modes (`cached_imp` default, `selector` fallback) with config/env controls and runtime introspection (`ALNApplication runtimeInvocationMode`)
  - preserved action/guard contract semantics while removing the reflection-heavy default dispatch path
  - added dispatch benchmark tooling + CI artifact generation (`tools/dispatch_perf_bench.m`, `tools/ci/run_phase10g_dispatch_performance.sh`, `tools/ci/generate_phase10g_dispatch_perf_artifacts.py`)
  - added regression coverage for invocation-path correctness + policy wiring (`tests/unit/ApplicationTests.m`, `tests/integration/DeploymentIntegrationTests.m`, `tests/unit/BuildPolicyTests.m`)
- Completed Phase 10H llhttp parser migration tranche:
  - integrated vendored llhttp `9.3.1` into framework/app builds and boomhauer compile path
  - added parser backend abstraction + rollout control (`ARLEN_HTTP_PARSER_BACKEND`, config `httpParserBackend`) with llhttp default and legacy fallback
  - preserved request parsing contracts (headers/query/body/cookies, missing-version normalization, websocket upgrade handling) across both parser backends
  - added HTTP parser benchmark tooling + CI artifact generation (`tools/http_parse_perf_bench.m`, `tools/ci/run_phase10h_http_parse_performance.sh`, `tools/ci/generate_phase10h_http_parse_perf_artifacts.py`)
  - added differential/regression coverage for parser equivalence and deployment artifacts (`tests/unit/RequestTests.m`, `tests/integration/DeploymentIntegrationTests.m`)
  - reduced small-request adapter overhead in `ALNRequest`:
    - shared one-time llhttp settings initialization
    - span-first callback collection (reduced per-callback mutable-data appends)
    - removed unconditional request-line normalization copy from hot path (fallback/compatibility only)
    - deferred query/cookie parsing until first access
- Completed Phase 10G/10H performance-threshold calibration tranche:
  - switched benchmark timing to monotonic clock sampling in tooling (`tools/dispatch_perf_bench.m`, `tools/http_parse_perf_bench.m`) to reduce per-sample allocator/jitter noise
  - added median aggregation across repeated benchmark rounds in both confidence generators (`--rounds`, default `3`) for stable gate decisions
  - added CI/runtime controls for round count tuning (`ARLEN_PHASE10G_ROUNDS`, `ARLEN_PHASE10H_ROUNDS`)
  - calibrated default threshold fixtures to enforce llhttp parity-or-better on small fixtures and stronger gains on large fixtures:
    - `tests/fixtures/performance/phase10g_dispatch_perf_thresholds.json`
    - `tests/fixtures/performance/phase10h_http_parse_perf_thresholds.json`
  - expanded parser fixture corpus with a large-request stress fixture (`tests/fixtures/performance/http_parse/large_headers_query.http`)
- Completed Phase 10I compile-time backend toggle tranche:
  - added build-time switches in `GNUmakefile` (`ARLEN_ENABLE_YYJSON`, `ARLEN_ENABLE_LLHTTP`) with strict `0|1` validation and compile-flag propagation
  - wired app-root compile path (`bin/boomhauer`) to honor the same toggles and pass deterministic feature macros
  - hardened runtime fallback behavior/metadata when compiled without yyjson or llhttp (`ALNJSONSerialization`, `ALNRequest`)
  - added regression coverage for feature-disabled compile path (`tests/integration/DeploymentIntegrationTests.m`)
- Completed Phase 10J HTTP runtime hot-path optimization tranche:
  - added per-request autorelease pools in the HTTP accept/request loops and added keep-alive RSS churn regression coverage (env-gated lane)
  - reduced request identity and observability overhead (`arc4random_buf`-backed hex IDs; logger-level-gated info field construction)
  - reduced response-path copies via header/body split serialization (`ALNResponse serializedHeaderData`, `ALNHTTPServer` send path)
  - removed duplicated read-path parse work with a single head metadata parse pass (content-length/header-limit enforcement retained)
  - applied queue/static mount micro-optimizations (O(1)-style dequeue with compaction, cached effective static mounts)
  - hardened cluster header defaults so `cluster.emitHeaders` inherits `cluster.enabled` when unset
- Completed Phase 10K benchmark-driven optimization tranche:
  - optimized `H_blob_large`/large static write paths:
    - gathered header+body writes via `writev` with deterministic fallback
    - static file fast path via `sendfile` with read-loop fallback
    - static mount serving now streams regular files from disk instead of eager `NSData` loads
  - optimized `E/F` parser/metadata path:
    - thread-local llhttp parse-state reuse
    - byte-level header trim/lowercase normalization to reduce copy churn
    - URI span split before string materialization for path/query extraction
    - route matching now reuses one split path-segment array per candidate sweep
  - optimized baseline request-path overhead without bypassing middleware/security contracts:
    - per-request preferred-format + info-log-level gating reuse in dispatch
    - lazy middleware execution-array allocation
    - response header serialization cache with invalidation
  - added/expanded regression coverage:
    - `tests/unit/ResponseTests.m`
    - `tests/unit/RequestTests.m`
    - `tests/unit/RouterTests.m`
    - `tests/integration/HTTPIntegrationTests.m` (`testStaticLargeAssetReturnsExpectedBodyAndLength`)
- Completed Phase 10L targeted native C hot-path follow-on:
  - completed 10L.1/10L.2/10L.3 runtime hardening:
    - peer address cached once per connection lifecycle
    - incremental C request-read/head state machine with reusable per-connection buffers
    - safe bounded static-file fd cache with strict metadata validation and lifecycle reset
  - completed 10L.4 response serialization refinement:
    - stable ordered header layout replaces per-request key sorting
    - no-op header sets no longer invalidate serialized-header cache
  - completed 10L.5 request lazy-parse contention reduction:
    - removed `@synchronized` monitor path for lazy `queryParams`/`cookies`
    - switched to lock-free atomic cached fields while preserving lazy semantics
  - completed 10L.6 route-matcher investigation gate:
    - added large-route-table benchmark tool (`tools/route_match_perf_bench.m`)
    - added CI artifact gate with optional flamegraph evidence capture (`tools/ci/run_phase10l_route_match_investigation.sh`, `tools/ci/generate_phase10l_route_match_artifacts.py`)
    - added thresholds fixture + deployment regression coverage for artifact pack generation
- Completed Phase 10M initial reliability/safety tranche:
  - completed 10M.1 sanitizer matrix hardening:
    - added fixture + artifact generator + runner:
      - `tests/fixtures/sanitizers/phase10m_sanitizer_matrix.json`
      - `tools/ci/generate_phase10m_sanitizer_matrix_artifacts.py`
      - `tools/ci/run_phase10m_sanitizer_matrix.sh`
    - added nightly thread-race lane and workflow scheduling/artifact wiring:
      - `tools/ci/run_phase10m_thread_race_nightly.sh`
      - `.github/workflows/phase4-sanitizers.yml`
  - completed 10M.2 differential backend parity matrix:
    - added backend contract matrix tool + artifact gate:
      - `tools/backend_contract_matrix.m`
      - `tools/ci/generate_phase10m_backend_parity_artifacts.py`
      - `tools/ci/run_phase10m_backend_parity_matrix.sh`
    - added make target: `make ci-backend-parity-matrix`
  - completed 10M.3 protocol adversarial corpus gate:
    - added strict-limit corpus fixture + probe + gate:

      - `tests/fixtures/protocol/phase10m_protocol_adversarial_cases.json`
      - `tools/ci/protocol_adversarial_probe.py`
      - `tools/ci/run_phase10m_protocol_adversarial.sh`
    - added make target: `make ci-protocol-adversarial`
  - completed 10M.4 syscall fault-injection resilience:
    - expanded runtime harness scenarios and fixture:
      - `tests/fixtures/fault_injection/phase10m_syscall_fault_scenarios.json`
      - `tools/ci/runtime_fault_injection.py`
      - `tools/ci/run_phase10m_syscall_fault_injection.sh`
    - hardened transient syscall retry + one-shot fault seams in:
      - `src/Arlen/HTTP/ALNHTTPServer.m`
    - added make target: `make ci-syscall-faults`
  - completed 10M.5 allocation-failure resilience:
    - added deterministic allocation failpoint seams and hard-failure recovery paths in:
      - `src/Arlen/HTTP/ALNHTTPServer.m`
      - `src/Arlen/HTTP/ALNRequest.m`
      - `src/Arlen/HTTP/ALNResponse.m`
    - added fixture + gate:
      - `tests/fixtures/fault_injection/phase10m_allocation_fault_scenarios.json`
      - `tools/ci/runtime_fault_injection.py`
      - `tools/ci/run_phase10m_allocation_fault_injection.sh`
    - added make target: `make ci-allocation-faults`
  - completed 10M.6 long-run soak lane:
    - added thresholds + artifact generator + gate:
      - `tests/fixtures/performance/phase10m_soak_thresholds.json`
      - `tools/ci/generate_phase10m_soak_artifacts.py`
      - `tools/ci/run_phase10m_soak.sh`
    - added make target: `make ci-soak`
  - completed 10M.7 chaos/restart lane:
    - added thresholds + artifact generator + gate:
      - `tests/fixtures/runtime/phase10m_chaos_restart_thresholds.json`
      - `tools/ci/generate_phase10m_chaos_restart_artifacts.py`
      - `tools/ci/run_phase10m_chaos_restart.sh`
    - added make target: `make ci-chaos-restart`
  - completed 10M.8 static analysis/security lint lane:
    - added policy + artifact generator + gate:
      - `tests/fixtures/static_analysis/phase10m_static_analysis_policy.json`
      - `tools/ci/generate_phase10m_static_analysis_artifacts.py`
      - `tools/ci/run_phase10m_static_analysis.sh`
    - added make target: `make ci-static-analysis`
  - extended sanitizer matrix + workflow artifact wiring for 10M.5-10M.8 lanes:
    - `tests/fixtures/sanitizers/phase10m_sanitizer_matrix.json`
    - `tools/ci/run_phase10m_sanitizer_matrix.sh`
    - `.github/workflows/phase4-sanitizers.yml`
  - added deployment/build-policy regression coverage for new 10M gates:
    - `tests/integration/DeploymentIntegrationTests.m`
    - `tests/unit/BuildPolicyTests.m`
  - completed 10M.9 throughput hardening follow-on for `H_blob_large`:
    - `NSData` return fast-path + `renderData:contentType:` helper
    - blob payload generation/caching optimization + legacy-string comparison lane
    - explicit sendfile transport-isolation benchmark coverage
    - split perf gate + confidence artifacts (`make ci-blob-throughput`)

## Completed Today (2026-03-06)

- Completed Phase 11A session/bearer/CSRF hardening:
  - fail-fast startup validation for weak or missing `session.secret` and weak `auth.bearerSecret`
  - encrypted session-cookie payload round-trip with standard crypto primitives and constant-time signature verification
  - CSRF unsafe-method verification now defaults to header/body-first with query fallback opt-in only
- Completed Phase 11B HTTP header and parser-boundary hardening:
  - response-header validation rejects invalid names plus CRLF/NUL injection payloads
  - content header canonicalization is deterministic and case-insensitive
  - legacy parser rejects duplicate `Content-Length`, unsupported `Transfer-Encoding`, and mixed `Content-Length` + `Transfer-Encoding`
- Completed Phase 11C websocket hardening:
  - strict websocket version/key validation for upgrades
  - optional websocket `Origin` allowlist enforcement
  - unmasked-frame rejection and bounded stalled-frame timeout closure
- Completed Phase 11D filesystem containment hardening:
  - static asset serving now denies symlink-backed leaf paths and opens files with nofollow semantics
  - filesystem attachment IDs are strict `att-<32 hex>` values with root-constrained, nofollow-backed reads
  - file-backed job/mail/attachment adapters enforce private `0700` directories and `0600` files
- Completed Phase 11E proxy/log hardening:
  - forwarded proxy headers now activate from an explicit trusted CIDR list even without the legacy boolean toggle
  - text logger escapes newline/tab/control characters to prevent log-forging payloads
- Completed Phase 11F hostile-traffic verification expansion:
  - added Phase 11 adversarial protocol corpus and deterministic mutation harness
  - added mixed hostile HTTP/websocket live probe with release-confidence artifacts under `build/release_confidence/phase11`
  - added Phase 11 sanitizer matrix lane wiring plus deployment-pack artifact verification

## Completed Today (2026-02-25)

- Completed Phase 9E documentation quality gate tranche:
  - added CI docs-quality entrypoint script (`tools/ci/run_docs_quality.sh`)
  - added Makefile gate target (`make ci-docs`)
  - added dedicated workflow (`.github/workflows/docs-quality.yml`)
  - updated docs policy + PR checklist contracts for API/docs regeneration validation

- Completed Phase 9F inline concurrency/backpressure hardening tranche:
  - realtime websocket channel admission now applies deterministic `503` overload diagnostics when subscriber caps are reached:
    - `X-Arlen-Backpressure-Reason: realtime_channel_subscriber_limit`
    - `X-Arlen-Backpressure-Reason: realtime_total_subscriber_limit`
  - extended mixed lifecycle integration stress path to include:
    - websocket echo
    - websocket channel fanout
    - SSE stream delivery checks
    - concurrent HTTP slow/fast churn
    - both `concurrent` and `serialized` dispatch modes
  - added integration regression:
    - `tests/integration/HTTPIntegrationTests.m` (`testRealtimeChannelSubscriberLimitReturns503UnderBackpressure`)
  - added unit regression for deterministic realtime rejection reason contracts:
    - `tests/unit/Phase3DTests.m` (`testRealtimeHubSubscriptionRejectionReasonsAreDeterministic`)
  - expanded runtime concurrency gate probe:
    - mixed websocket channel + SSE validation
    - startup/shutdown overlap under active load with post-restart recovery validation
  - updated runtime operator docs:
    - `docs/RUNTIME_CONCURRENCY_GATE.md`
    - `docs/CLI_REFERENCE.md`
    - `docs/GETTING_STARTED.md`

- Completed Phase 9G worker lifecycle + signal durability tranche:
  - added deterministic propane lifecycle diagnostics contract:
    - `propane:lifecycle event=<name> manager_pid=<pid> key=value ...`
    - optional mirrored log file via `ARLEN_PROPANE_LIFECYCLE_LOG`
    - stable churn/stop fields (`reason`, `status`, `exit_reason`, `restart_action`)
  - added propane integration regressions in `tests/integration/HTTPIntegrationTests.m`:
    - repeated boot/stop/restart loops under active HTTP traffic
    - graceful shutdown drain behavior for in-flight + queued + keep-alive connections
    - mixed signal supervision path (`SIGHUP` reload + `SIGTERM` shutdown) with diagnostics assertions
  - updated operator docs for lifecycle diagnostics:
    - `docs/PROPANE.md`
    - `docs/CLI_REFERENCE.md`

- Completed Phase 9H sanitizer + race-detection maturity tranche:
  - added sanitizer matrix + suppression fixtures:
    - `tests/fixtures/sanitizers/phase9h_sanitizer_matrix.json`
    - `tests/fixtures/sanitizers/phase9h_suppressions.json`
  - added suppression registry validator:
    - `tools/ci/check_sanitizer_suppressions.py`
  - added sanitizer confidence artifact generator:
    - `tools/ci/generate_phase9h_sanitizer_confidence_artifacts.py`
    - emits lane status + delta/suppression summaries under `build/release_confidence/phase9h`
  - hardened sanitizer CI orchestration:
    - `tools/ci/run_phase5e_sanitizers.sh` now validates suppressions, records blocking/TSAN status, and always emits confidence artifacts
    - `tools/ci/run_phase5e_tsan_experimental.sh` now retains `build/sanitizers/tsan/tsan.log` + `summary.json`
    - `.github/workflows/phase4-sanitizers.yml` uploads sanitizer confidence and TSAN artifacts
  - expanded runtime sanitizer probe surface in `tools/ci/runtime_concurrency_probe.py`:
    - route contracts (`/`, `/about`, `/api/status`, `/api/echo/:name`)
    - data-layer API contracts (`/api/db/items` read/write validation + error-shape checks)
  - added suppression lifecycle policy documentation:
    - `docs/SANITIZER_SUPPRESSION_POLICY.md`

- Completed Phase 9I deterministic fault-injection tranche:
  - added runtime seam fault-injection harness + entrypoint:
    - `tools/ci/runtime_fault_injection.py`
    - `tools/ci/run_phase9i_fault_injection.sh`
    - `make ci-fault-injection`
  - added fault seam/scenario matrix fixture:
    - `tests/fixtures/fault_injection/phase9i_fault_scenarios.json`
  - added replay controls for deterministic scenario ordering and scope:
    - `ARLEN_PHASE9I_SEED`
    - `ARLEN_PHASE9I_ITERS`
    - `ARLEN_PHASE9I_MODES`
    - `ARLEN_PHASE9I_SCENARIOS`
  - added confidence artifacts under `build/release_confidence/phase9i`:
    - `fault_injection_results.json`
    - `phase9i_fault_injection_summary.md`
    - `manifest.json`
  - integrated Phase 9I gate into quality pipeline:
    - `tools/ci/run_phase5e_quality.sh`
  - added tooling regression tests:
    - `tests/integration/DeploymentIntegrationTests.m`
  - added operator/developer guide:
    - `docs/PHASE9I_FAULT_INJECTION.md`

- Completed Phase 9J enterprise release-certification tranche:
  - added certification pack generator and gate entrypoint:
    - `tools/ci/generate_phase9j_release_certification_pack.py`
    - `tools/ci/run_phase9j_release_certification.sh`
    - `make ci-release-certification`
  - added threshold + known-risk fixtures:
    - `tests/fixtures/release/phase9j_certification_thresholds.json`
    - `tests/fixtures/release/phase9j_known_risks.json`
  - added release certification artifact pack under `build/release_confidence/phase9j`:
    - `manifest.json`
    - `certification_summary.json`
    - `release_gate_matrix.json`
    - `known_risk_register_snapshot.json`
    - `phase9j_release_certification.md`
  - enforced certification in release packaging script:
    - `tools/deploy/build_release.sh` now requires a valid Phase 9J manifest (`status=certified`) by default
    - non-RC opt-out available via `--allow-missing-certification`
  - linked known-risk register from release notes:
    - `docs/KNOWN_RISK_REGISTER.md`
    - `docs/RELEASE_NOTES.md`
  - added integration regressions for certification generation, stale risk-register rejection, and build-release enforcement:
    - `tests/integration/DeploymentIntegrationTests.m`

## Completed Today (2026-02-24)

- Implemented Phase 8A/8B completion documentation updates in roadmap index files.
- Implemented Phase 9 documentation platform and API reference generator:
  - added `tools/docs/generate_api_reference.py`
  - added curated API metadata (`tools/docs/api_metadata.json`)
  - generated API index + per-symbol pages (`docs/API_REFERENCE.md`, `docs/api/*.md`)
- Expanded docs HTML pipeline and local serving support:
  - recursive docs rendering + API generation in `tools/build_docs_html.sh`
  - `make docs-api` and `make docs-serve` targets in `GNUmakefile`
- Added track-based onboarding docs:
  - `docs/GETTING_STARTED_TRACKS.md`
  - `docs/GETTING_STARTED_QUICKSTART.md`
  - `docs/GETTING_STARTED_API_FIRST.md`
  - `docs/GETTING_STARTED_HTML_FIRST.md`
  - `docs/GETTING_STARTED_DATA_LAYER.md`
- Added Arlen-for-X migration guide suite:
  - `docs/ARLEN_FOR_X_INDEX.md`
  - `docs/ARLEN_FOR_RAILS.md`
  - `docs/ARLEN_FOR_DJANGO.md`
  - `docs/ARLEN_FOR_LARAVEL.md`
  - `docs/ARLEN_FOR_FASTAPI.md`
  - `docs/ARLEN_FOR_EXPRESS_NESTJS.md`
  - `docs/ARLEN_FOR_MOJOLICIOUS.md`
- Updated docs governance and indexes:
  - `docs/DOCUMENTATION_POLICY.md`
  - `docs/README.md`
  - `README.md`
  - `docs/PHASE2_PHASE3_ROADMAP.md`
  - `docs/PHASE9_ROADMAP.md`
- Added competitive benchmarking execution roadmap:
  - `docs/COMPETITIVE_BENCHMARK_ROADMAP.md`
  - completed Phase A claim-matrix freeze for v1 Arlen-vs-FastAPI benchmark scenarios
- Completed Phase B parity implementation for frozen benchmark scenarios:
  - FastAPI reference service + dependency contract (`tests/performance/fastapi_reference/`)
  - executable parity gate (`tests/performance/check_parity_fastapi.py`, `make parity-phaseb`)
  - parity report artifact (`build/perf/parity_fastapi_latest.json`)
  - checklist doc (`docs/PHASEB_PARITY_CHECKLIST_FASTAPI.md`)
- Completed Phase C benchmark protocol hardening:
  - protocol contract file (`tests/performance/protocols/phasec_comparison_http.json`)
  - executable warmup + concurrency ladder runner (`tests/performance/run_phasec_protocol.py`, `make perf-phasec`)
  - fixed host/profile/port + machine/tool/git metadata capture in protocol report
  - protocol artifact entrypoint (`build/perf/phasec/latest_protocol_report.json`)
  - protocol guide (`docs/PHASEC_BENCHMARK_PROTOCOL.md`)
- Completed Phase D baseline campaign execution:
  - FastAPI benchmark profiles for pair parity (`tests/performance/profiles/fastapi_comparison_http.sh`, `tests/performance/profiles/fastapi_middleware_heavy.sh`)
  - fixed campaign protocol contract (`tests/performance/protocols/phased_baseline_campaign.json`)
  - middleware-heavy pair was constrained to ladder `1,4` in the archived in-repo baseline pack; later comparative follow-on moved to the sibling benchmark repo
  - executable campaign runner (`tests/performance/run_phased_campaign.py`, `make perf-phased`)
  - generated deliverables: framework summary + per-scenario comparison table + methodology note + raw artifact bundle
  - campaign artifact entrypoint (`build/perf/phased/latest_campaign_report.json`)
  - campaign guide (`docs/PHASED_BASELINE_CAMPAIGN.md`)

## Completed Today (2026-02-23)

- Implemented Phase 7A initial runtime hardening slice:
  - websocket session backpressure boundary (`runtimeLimits.maxConcurrentWebSocketSessions`)
  - deterministic overload diagnostics (`503` + `X-Arlen-Backpressure-Reason`)
  - runtime limit env contract (`ARLEN_MAX_WEBSOCKET_SESSIONS`)
  - Phase 7A contract fixture + docs (`tests/fixtures/phase7a/runtime_hardening_contracts.json`, `docs/PHASE7A_RUNTIME_HARDENING.md`)
- Implemented Phase 7B initial security-default slice:
  - security profile presets (`balanced`, `strict`, `edge`) with deterministic default policy behavior
  - fail-fast startup diagnostics for missing security-critical secret/dependency contracts
  - middleware wiring hardening for CSRF/session dependency behavior
  - Phase 7B contract fixture + docs (`tests/fixtures/phase7b/security_policy_contracts.json`, `docs/PHASE7B_SECURITY_DEFAULTS.md`)
- Implemented Phase 7C initial observability/operability slice:
  - observability config contract defaults + env/legacy overrides (`observability.tracePropagationEnabled`, `observability.healthDetailsEnabled`, `observability.readinessRequiresStartup`)
  - request correlation + trace propagation response headers (`X-Correlation-Id`, `X-Trace-Id`, `traceparent`) and enriched trace exporter payload metadata
  - JSON signal payload contracts for `/healthz` and `/readyz` with deterministic check objects
  - strict readiness startup gating contract (`readinessRequiresStartup` => deterministic `503 not_ready` before startup)
  - deployment runbook operability validation script and smoke integration (`tools/deploy/validate_operability.sh`, `tools/deploy/smoke_release.sh`)
  - Phase 7C contract fixture + docs (`tests/fixtures/phase7c/observability_operability_contracts.json`, `docs/PHASE7C_OBSERVABILITY_OPERABILITY.md`)
- Implemented Phase 7D initial service-durability slice:
  - jobs idempotency-key contract (`enqueue` option `idempotencyKey`) for in-memory and file job adapters with deterministic dedupe/release semantics
  - expanded cache conformance semantics (zero-TTL persistence and `setObject:nil` key-removal contract)
  - added retry policy wrappers for service durability:
    - `ALNRetryingMailAdapter` (`maxAttempts`, `retryDelaySeconds`, deterministic exhaustion diagnostics)
    - `ALNRetryingAttachmentAdapter` (`maxAttempts`, `retryDelaySeconds`, deterministic exhaustion diagnostics)
  - Phase 7D contract fixture + docs (`tests/fixtures/phase7d/service_durability_contracts.json`, `docs/PHASE7D_SERVICE_DURABILITY.md`)
- Implemented Phase 7E initial template-pipeline maturity slice:
  - `ALNEOCTranspiler` lint diagnostics API for deterministic compile-time warnings (`unguarded_include`)
  - `eocc` warning output contract with stable `path/line/column/code/message` fields
  - expanded multiline/nested/malformed fixture matrix and include-guard lint fixtures
  - guarded include contract in default template render path (`templates/index.html.eoc`)
  - Phase 7E contract fixture + docs (`tests/fixtures/phase7e/template_pipeline_contracts.json`, `docs/PHASE7E_TEMPLATE_PIPELINE_MATURITY.md`, `docs/TEMPLATE_TROUBLESHOOTING.md`)
- Implemented Phase 7F initial frontend-starter slice:
  - added `arlen generate frontend <Name> --preset <vanilla-spa|progressive-mpa>` scaffolding contract
  - deterministic starter layout under `public/frontend/<slug>/` with static assets and starter manifest
  - starter API wiring examples (`/healthz?format=json`, `/metrics`) for zero-extra-controller bootstrap
  - release packaging compatibility contract via `public/` artifact inclusion
  - Phase 7F contract fixture + docs (`tests/fixtures/phase7f/frontend_starter_contracts.json`, `docs/PHASE7F_FRONTEND_STARTERS.md`)
- Implemented Phase 7G initial coding-agent DX slice:
  - added machine-readable JSON contracts for scaffold workflows (`arlen new/generate --json`)
  - added deterministic build/check planning contracts (`arlen build/check --dry-run --json`)
  - added deploy release planning contract (`tools/deploy/build_release.sh --dry-run --json`)
  - added structured fix-it diagnostics (`error.code`, `error.fixit.action`, `error.fixit.example`)
  - Phase 7G contract fixture + docs (`tests/fixtures/phase7g/coding_agent_dx_contracts.json`, `docs/PHASE7G_CODING_AGENT_DX_CONTRACTS.md`)
- Implemented Phase 7H initial distributed-runtime depth slice:
  - added quorum-aware readiness controls (`observability.readinessRequiresClusterQuorum`, `cluster.observedNodes`) with env/legacy override support
  - added deterministic readiness gating contract for quorum-unmet multi-node deployments (`/readyz` => `503 not_ready`)
  - expanded `/clusterz` payload with quorum summary and coordination capability matrix
  - added distributed-runtime diagnostics headers (`X-Arlen-Cluster-Status`, observed/expected node counts)
  - Phase 7H contract fixture + docs (`tests/fixtures/phase7h/distributed_runtime_contracts.json`, `docs/PHASE7H_DISTRIBUTED_RUNTIME_DEPTH.md`)
- Completed Phase 5A-5E implementation tranche.
- Added typed schema contracts + typed SQL generation workflow (5D) and validated compile-time/runtime contract behavior.
- Added Phase 5E hardening coverage:
  - soak query compile/execute churn regression
  - connectivity interruption fault-injection regression
  - transaction-abort rollback fault-injection regression
- Added deterministic release confidence artifact pack generation:
  - `tools/ci/generate_phase5e_confidence_artifacts.py`
  - output: `build/release_confidence/phase5e/`
- Added Phase 5E CI gate entrypoints and Makefile wiring:
  - `tools/ci/run_phase5e_quality.sh`
  - `tools/ci/run_phase5e_sanitizers.sh`
  - `make ci-quality`, `make ci-sanitizers`, `make phase5e-confidence`
- Extended Phase 5 reliability contracts + external regression intake fixtures with 5D/5E mappings.

## Completed Previously (2026-02-20)

- Completed Phase 3C release/distribution/documentation tranche.
- Added profile-based perf expansion and trend reporting:
  - profile pack in `tests/performance/profiles/`
  - per-profile policy/baseline support
  - trend outputs (`latest_trend.json`, `latest_trend.md`)
  - archived run history under `build/perf/history/<profile>/`
- Added CI quality gate entrypoints:
  - `tools/ci/run_phase3c_quality.sh`
  - `.github/workflows/phase3c-quality.yml`
  - `make ci-quality`
- Added Phase 4 quality gate path:
  - `tools/ci/run_phase4_quality.sh`
  - `.github/workflows/phase4-quality.yml`
  - `make ci-quality` now targets Phase 4 gate coverage
- Added OpenAPI docs style option `swagger`:
  - config acceptance for `openapi.docsUIStyle = "swagger"`
  - runtime endpoint `/openapi/swagger`
  - unit/integration coverage for swagger docs rendering
- Added deployment runbook smoke automation:
  - `tools/deploy/smoke_release.sh`
  - `make deploy-smoke`
  - deployment integration coverage for smoke workflow
- Added migration readiness package:
  - guide: `docs/MIGRATION_GSWEB.md`
  - side-by-side sample app: `examples/gsweb_migration`
  - API-first reference app: `examples/api_reference`
  - perf profile coverage for both reference and migration workloads
- Added Phase 3C documentation set:
  - `docs/RELEASE_PROCESS.md`
  - `docs/PERFORMANCE_PROFILES.md`
  - updated `README.md`, `docs/README.md`, `docs/GETTING_STARTED.md`, `docs/CLI_REFERENCE.md`, `docs/DEPLOYMENT.md`, `docs/PHASE3_ROADMAP.md`
- Completed Phase 3D realtime/composition tranche:
  - websocket upgrade + frame handling in `ALNHTTPServer`
  - controller-level realtime helpers (`acceptWebSocketEcho`, `acceptWebSocketChannel`, `renderSSEEvents`)
  - mount/embedding contract via `mountApplication:atPrefix:`
  - realtime channel/pubsub abstraction via `ALNRealtimeHub`
  - boomhauer routes for websocket echo/channel, SSE ticker, and mounted app sample routes
  - unit/integration coverage for realtime and mount composition flows
- Completed Phase 3E ecosystem services tranche:
  - service adapter contracts (`ALNJobAdapter`, `ALNCacheAdapter`, `ALNLocalizationAdapter`, `ALNMailAdapter`, `ALNAttachmentAdapter`)
  - in-memory baseline adapters and compatibility suites (`ALNRun*ConformanceSuite`, `ALNRunServiceCompatibilitySuite`)
  - plugin-first service override wiring through `ALNApplication`
  - controller/context service access helpers and i18n locale fallback config
  - boomhauer sample service routes (`/services/cache`, `/services/jobs`, `/services/i18n`, `/services/mail`, `/services/attachments`)
  - published guide: `docs/ECOSYSTEM_SERVICES.md`
- Completed Phase 3E follow-on execution slice:
  - added `arlen generate plugin --preset` templates for Redis cache, queue-backed jobs, and SMTP mail workflows
  - defined optional worker runtime contract (`ALNJobWorkerRuntime`, `ALNJobWorker`, `ALNJobWorkerRunSummary`)
  - implemented concrete Redis cache backend adapter (`ALNRedisCacheAdapter`) with conformance-compatible behavior
  - implemented concrete filesystem attachment backend adapter (`ALNFileSystemAttachmentAdapter`)
  - added production guidance for service persistence + retention policy baselines
  - added integration coverage for plugin preset generation and unit coverage for worker drain/ack/retry/run-limit + Redis cache/attachment adapter conformance
- Completed Phase 3F DX + reliability hardening tranche:
  - added bootstrap-first doctor path (`bin/arlen doctor` -> `bin/arlen-doctor`) with JSON diagnostics output
  - published known-good toolchain matrix (`docs/TOOLCHAIN_MATRIX.md`)
  - hardened ALNPg diagnostics with SQLSTATE/server metadata and parameterized `SELECT` regression coverage
  - added API convenience primitives (typed query/header parsing, ETag/304 helpers, response-envelope helpers/middleware)
  - implemented static mount ergonomics (explicit mounts, allowlist serving, canonical index redirects)
  - completed concrete jobs/mail file adapters and propane async worker supervision baseline
  - expanded unit/integration acceptance coverage for all new 3F behavior slices
- Completed Phase 3G SQL builder and data-layer reuse tranche:
  - expanded `ALNSQLBuilder` to v2 query surface (nested boolean groups, expanded predicates, joins/aliases, grouping/having, CTE/subquery composition, and `RETURNING`)
  - added advanced expression/query composition APIs:
    - select expressions with aliases and placeholder-safe parameter shifting
    - expression-aware ordering (`NULLS FIRST/LAST`, parameterized order expressions)
    - subquery and lateral join composition
    - tuple/composite cursor predicate support via expression predicates
  - added explicit PostgreSQL dialect extension builder (`ALNPostgresSQLBuilder`) for `ON CONFLICT` upsert semantics
  - extended PostgreSQL conflict/upsert APIs with expression-based `DO UPDATE SET` assignments and optional `DO UPDATE ... WHERE` clauses
  - published standalone data-layer packaging via `src/ArlenData/ArlenData.h`
  - added non-Arlen validation path (`examples/arlen_data`, `make test-data-layer`)
  - wired standalone data-layer validation into CI quality gate (`tools/ci/run_phase3c_quality.sh`)
  - published distribution and versioning guidance in `docs/ARLEN_DATA.md`
- Completed Phase 3H multi-node clustering/distributed-runtime tranche:
  - added cluster config contract defaults/env overrides (`cluster.*`, `ARLEN_CLUSTER_*`)
  - added built-in cluster status endpoint (`/clusterz`)
  - added cluster identity response headers (`X-Arlen-Cluster`, `X-Arlen-Node`, `X-Arlen-Worker-Pid`)
  - added propane cluster CLI/env controls and worker export wiring
  - added unit/integration validation for cluster config/runtime/propane propagation
- Completed Phase 4A query-IR and safety-foundation tranche:
  - added internal trusted-expression IR representation for expression-capable builder clauses
  - added source-compatible identifier-binding expression APIs (`{{token}}`) for select/where/having/order/join-on composition
  - enforced deterministic malformed-shape diagnostics for expression IR, parameter arrays, and identifier-binding contracts
  - added strict placeholder/parameter coverage checks for expression templates
  - added regression suites:
    - `tests/unit/Phase4ATests.m` (snapshot + negative/safety validation)
    - `tests/unit/PgTests.m` identifier-template PostgreSQL execution coverage
- Completed Phase 4D performance and diagnostics tranche:
  - added builder-driven execution APIs in `ALNPgConnection`/`ALNPg` (`executeBuilderQuery`, `executeBuilderCommand`)
  - added builder compilation cache and prepared-statement reuse policy controls (`disabled`/`auto`/`always`)
  - added structured query diagnostics listener pipeline with stage events (`compile`, `execute`, `result`, `error`)
  - added redaction-safe query metadata defaults (`sql` omitted unless explicitly enabled) and optional stderr event emission
  - added runtime cache controls (`preparedStatementCacheLimit`, `builderCompilationCacheLimit`, `resetExecutionCaches`)
  - added PostgreSQL regression coverage for cache-hit behavior and diagnostics metadata contracts
- Completed Phase 4E conformance and migration-hardening tranche:
  - introduced machine-readable SQL builder conformance matrix fixture and docs
  - added deterministic property/long-run regression tests for placeholder shifting, parameter ordering, tuple predicates, and nested expression shapes
  - published migration guide from v2 string-heavy patterns to IR/typed patterns
  - finalized phase-4 transitional API deprecation lifecycle contracts in release docs
  - added dedicated Phase 4 CI quality gate workflow/script and wired `make ci-quality` to the new gate

## Verification State (2026-02-23)

- `make test-unit`: passing
- `make test-integration`: passing
- profile perf checks executed:
  - `default`
  - `middleware_heavy`
  - `template_heavy`
  - `api_reference`
  - `migration_sample`
- New Phase 3D checks executed:
  - websocket echo round-trip integration test
  - websocket channel fanout integration test
  - concurrent SSE integration test
  - mounted app composition unit/integration tests
- New Phase 3E checks executed:
  - plugin-driven service wiring + lifecycle verification
  - service compatibility suite coverage for jobs/cache/i18n/mail/attachments
  - controller-level service helper route verification
  - boomhauer integration tests for service sample routes
- New Phase 7D checks executed:
  - job idempotency-key durability tests for in-memory and file adapters (`tests/unit/Phase7DTests.m`)
  - retry policy wrapper deterministic success/exhaustion diagnostics tests (`tests/unit/Phase7DTests.m`)
  - cache conformance semantics regression for zero-TTL persistence and nil-removal contracts (`tests/unit/Phase7DTests.m`)
- New Phase 7E checks executed:
  - transpiler fixture matrix expansion for multiline/nested/error-shape templates (`tests/unit/TranspilerTests.m`)
  - deterministic transpiler lint diagnostics for guarded/unguarded include contracts (`tests/unit/TranspilerTests.m`)
  - root render integration verification for partial include output (`tests/integration/HTTPIntegrationTests.m`)
  - `eocc` lint warning shape/behavior integration verification (`tests/integration/DeploymentIntegrationTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7ETests.m`)
- New Phase 7F checks executed:
  - frontend starter generation preset coverage + deterministic reproducibility hashing (`tests/integration/DeploymentIntegrationTests.m`)
  - release packaging inclusion coverage for generated frontend assets (`tests/integration/DeploymentIntegrationTests.m`)
  - unsupported preset deterministic rejection diagnostics (`tests/integration/DeploymentIntegrationTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7FTests.m`)
- New Phase 7G checks executed:
  - coding-agent JSON workflow regression (`new/generate/build/check/deploy` planning + fix-it diagnostics) (`tests/integration/DeploymentIntegrationTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7GTests.m`)
- New Phase 7H checks executed:
  - quorum-readiness config default/env/legacy override regression (`tests/unit/ConfigTests.m`)
  - deterministic readiness gating payload regression for degraded/nominal quorum states (`tests/unit/ApplicationTests.m`)
  - `/clusterz` quorum + coordination payload regression (`tests/unit/ApplicationTests.m`, `tests/integration/HTTPIntegrationTests.m`)
  - cluster diagnostics response header emission/disable regression (`tests/integration/HTTPIntegrationTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7HTests.m`)
- New Phase 3F checks executed:
  - `arlen doctor` bootstrap pre-build diagnostics + JSON payload validation
  - ALNPg SQLSTATE/diagnostics regression tests
  - API helper tests (typed query/header parsing, ETag/304, envelope helper + opt-in middleware behavior)
  - static serving integration tests for canonical index redirects and extension allowlist enforcement
  - propane integration test for supervised async worker spawn + respawn behavior
- New Phase 3G checks executed:
  - deterministic SQL snapshot coverage for builder v2 behavior (`tests/unit/Phase3GTests.m`)
  - PostgreSQL conflict/upsert dialect-extension snapshot coverage
  - standalone non-Arlen data-layer build/run validation (`make test-data-layer`)
- New Phase 3H checks executed:
  - cluster config default/override regression coverage (`tests/unit/ConfigTests.m`)
  - `/clusterz` built-in endpoint and cluster response header integration coverage
  - propane cluster override propagation integration coverage
- New Phase 4A checks executed:
  - `tests/unit/Phase4ATests.m` passing (expression IR snapshot, malformed contract rejection, and safety paths)
  - PostgreSQL expression-template execution regression passing (`testSQLBuilderExpressionTemplatesWithIdentifierBindingsExecuteAgainstPostgres`)
- New Phase 4B checks executed:
  - deterministic snapshot coverage for set operations, windows, predicates, joins, CTE columns, and locking (`tests/unit/Phase4BTests.m`)
  - PostgreSQL execution regression for 4B clause families (`testSQLBuilderPhase4BFeaturesExecuteAgainstPostgres`)
  - misuse-path diagnostics for invalid set-operation and locking contracts
- New Phase 4C checks executed:
  - deterministic schema artifact renderer coverage (`tests/unit/SchemaCodegenTests.m`)
  - CLI schema codegen integration and generated-helper compile/execute smoke (`testArlenSchemaCodegenGeneratesTypedHelpers`)
  - `arlen schema-codegen` overwrite and manifest contract coverage
- New Phase 4D checks executed:
  - structured builder diagnostics/caching regression (`testBuilderExecutionEmitsStructuredEventsAndUsesCaches`)
  - redaction + SQLSTATE diagnostics regression (`testBuilderExecutionErrorEventsIncludeSQLStateAndStayRedactedByDefault`)
  - full suite verification after toolchain link update (`make test-unit`, `make test-integration`, `make test-data-layer`)
- New Phase 4E checks executed:
  - conformance matrix snapshot regression (`testConformanceMatrixMatchesExpectedSnapshots`)
  - deterministic property gates for placeholder shifting + parameter ordering (`testPropertyPlaceholderShiftingAcrossExpressionComposition`, `testPropertyDeterministicParameterOrderingForInsertAndUpdate`)
  - tuple/nested long-run shape regression coverage (`testPropertyTuplePredicatesPreserveParameterOrder`, `testLongRunRegressionSuiteForNestedExpressionShapes`)
  - representative migration path validation (`testMigrationGuideRepresentativeFlowCompilesAndPreservesContracts`)
- New Phase 7A checks executed:
  - websocket backpressure overload integration regression (`testWebSocketSessionLimitReturns503UnderBackpressure`)
  - runtime websocket session limit default/env contract (`tests/unit/ConfigTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7ATests.m`)
- New Phase 7B checks executed:
  - security profile preset defaults + legacy/env override regression (`tests/unit/ConfigTests.m`)
  - fail-fast startup misconfiguration diagnostics (`tests/unit/ApplicationTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7BTests.m`)
- New Phase 7C checks executed:
  - observability config default/env/legacy override regression (`tests/unit/ConfigTests.m`)
  - trace propagation response-header + trace exporter metadata regression (`tests/unit/ApplicationTests.m`)
  - deterministic JSON health/readiness signal payload regression (`tests/unit/ApplicationTests.m`, `tests/integration/HTTPIntegrationTests.m`)
  - strict startup-gated readiness regression (`tests/unit/ApplicationTests.m`)
  - release smoke operability validation-script path regression (`tests/integration/DeploymentIntegrationTests.m`)
  - phase fixture schema/reference validation (`tests/unit/Phase7CTests.m`)
- PostgreSQL-backed tests remain gated by `ARLEN_PG_TEST_DSN`.

## Next Session Focus

Historical note: this focus list was captured before the later Phase 7 closeout
work landed. It is preserved for checkpoint provenance and is not the current
roadmap plan.

1. Continue Phase 7H follow-on distributed-runtime depth (dynamic membership/failure-drill automation) (`docs/PHASE7_ROADMAP.md`).
2. Continue remaining Phase 7D ecosystem service durability depth (production-adapter failure/recovery integration coverage) (`docs/PHASE7_ROADMAP.md`).
3. Continue Phase 7G follow-on coding-agent contract coverage and Phase 7E lint/diagnostic follow-on depth (`docs/PHASE7_ROADMAP.md`).

## Planned Phase Mapping (Post-4C)

Historical note: the mapping below preserves the original rollout narrative.
Current authoritative status is reflected in the milestone summary above and in
the individual roadmap documents.

- Phase 3F (complete):
  - onboarding and diagnostics (`arlen doctor`, compatibility matrix)
  - ALNPg reliability and SQL diagnostics hardening
  - optional API convenience helpers (ETag/304, typed query/header parsing, envelope normalization)
  - static mount allowlist/index ergonomics
  - remaining ecosystem runtime follow-on (jobs/mail adapters + worker supervision baseline)
- Phase 3G (complete):
  - `ALNSQLBuilder` v2 capability expansion toward SQL::Abstract-family parity goals (Objective-C-native API design)
  - PostgreSQL dialect-extension layer for PG-specific builder features (`ALNPostgresSQLBuilder`)
  - standalone data-layer packaging/reuse path (`ArlenData`) for non-Arlen applications + CI validation
- Phase 3H (complete):
  - multi-node clustering primitives and distributed runtime hardening
  - cluster-oriented integration validation + operational contracts
- Phase 7 (active):
  - Phase 7A initial runtime hardening slice implemented (websocket backpressure contract + overload diagnostics)
  - Phase 7B initial security-default slice implemented (profile presets + fail-fast startup validation)
  - Phase 7C initial observability/operability slice implemented (trace propagation/correlation headers + JSON health/readiness signals + deploy operability validation script)
  - Phase 7D initial ecosystem service durability slice implemented (idempotency/retry/cache durability contracts)
  - Phase 7E initial template-pipeline maturity slice implemented (lint diagnostics + fixture matrix + include/render-path hardening checks)
  - Phase 7F initial frontend integration starter slice implemented (deterministic starter generation + deploy packaging coverage)
  - Phase 7G initial coding-agent DX slice implemented (JSON workflow contracts + fix-it diagnostics + deploy/build/check planning payloads)
  - Phase 7H initial distributed-runtime depth slice implemented (quorum-gated readiness + expanded `/clusterz` coordination matrix + cluster diagnostics headers)
  - remaining runtime hardening for `boomhauer`/`propane` in progress
  - remaining security policy/default hardening in progress
  - remaining observability/operability + coding-agent DX follow-on
  - ecosystem durability, template pipeline hardening, frontend starters, distributed-runtime follow-on depth
- Maybe Someday backlog:
  - LiveView-like server-driven UI
  - full ORM as default framework layer
- Completed in Phase 4:
  - Phase 4A: query IR + safety foundation
  - Phase 4B: SQL surface completion
  - Phase 4C: typed ergonomics + schema codegen
  - Phase 4D: performance + diagnostics hardening
  - Phase 4E: conformance + migration hardening
- Out of scope for Arlen core (explicitly documented):
  - Django-style admin/backoffice product
  - full account-management product surfaces
  - package-volume ecosystem targets as a core roadmap deliverable
