# Testing Workflow

This guide describes the fastest path from a bug report to a permanent Arlen
regression test.

## Merge-Gate Validation

The Phase 34 merge gate for `main` is:

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

## 1. Focused Lanes

Use the smallest lane that honestly exercises the bug:

- `make phase21-template-tests`
  - parser, codegen, security, and named template regressions
- `make phase21-protocol-tests`
  - raw HTTP corpus replay across `llhttp` and `legacy`
- `make phase21-generated-app-tests`
  - scaffold/module/config matrix for first-user flows
- `make phase21-focused`
  - run all three Phase 21 focused lanes
- `make phase21-confidence`
  - run the focused lanes and regenerate `build/release_confidence/phase21/`

Phase 37 public-release confidence lanes are available:

- `make phase37-contract`
  - validates the public surface matrix, EOC golden-render catalog, and
    deterministic parser/protocol corpus
- `make phase37-acceptance`
  - runs the acceptance-site harness against the checked-in Phase 37 manifest
    using deterministic ports, isolated logs, HTTP probes, JSON assertions, and
    static checks
- `make phase37-acceptance-fast`
  - runs only the default service-free fixture-backed acceptance sites
- `make phase37-acceptance-runtime`
  - runs runtime-mode acceptance entries; these are service-backed/opt-in until
    their real Arlen app variants are implemented
- `make phase37-eoc-golden`
  - executes the Phase 37 EOC golden render/diagnostic fixture assertions
- `make phase37-intake`
  - validates the public bug-fix checklist and acceptance manifest metadata
- `make phase37-packaged-deploy-proof`
  - records evidence that packaged deploy behavior is covered by real
    deployment integration tests
- `make phase37-harness-selftest`
  - runs negative and positive self-tests for acceptance harness assertions
- `make phase37-confidence`
  - runs the Phase 37 contract, intake, packaged-deploy proof, and acceptance
    lanes and writes artifacts under `build/release_confidence/phase37/`

Phase 20 data-layer-focused lanes remain available:

- `make phase20-sql-builder-tests`
- `make phase20-schema-tests`
- `make phase20-routing-tests`
- `make phase20-postgres-live-tests`
- `make phase20-mssql-live-tests`
- `make phase20-focused`

Phase 23 Dataverse-focused lanes are also available:

- `make phase23-dataverse-tests`
- `make phase23-live-smoke`
- `make phase23-focused`
- `make phase23-confidence`

Phase 25 live-UI-focused lanes are also available:

- `make phase25-live-tests`
- `make phase25-focused`
- `make phase25-confidence`

Phase 26 ORM-focused lanes are also available:

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
  - full Phase 26 ORM regression bundle
- `make phase26-confidence`
  - rerun the full Phase 26 bundle and regenerate
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
- `make phase31-confidence`
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
   - Phase 37 EOC golden-render coverage:
     `tests/fixtures/phase37/eoc_golden_render_cases.json`
   - Phase 37 public-surface coverage:
     `tests/fixtures/phase37/public_surface_contract.json`
   - raw protocol framing / parser behavior:
     `tests/fixtures/protocol/phase21_protocol_corpus.json`
   - Phase 37 deterministic parser/protocol corpus expansion:
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

Phase 21 closes through one reproducible entrypoint:

```bash
make phase21-confidence
```

Artifacts are written to `build/release_confidence/phase21/`.

Phase 23 Dataverse closeout uses:

```bash
make phase23-dataverse-tests
make phase23-live-smoke   # optional; requires ARLEN_PHASE23_DATAVERSE_* live env
make phase23-confidence
```

Artifacts are written to `build/release_confidence/phase23/`.
The Phase 23 confidence pack now includes the checked-in Perl parity accounting
snapshot, optional live smoke output, and optional live codegen output.

Phase 25 live UI closeout uses:

```bash
make phase25-live-tests
make phase25-confidence
```

The Phase 25 suite now includes a Node-backed executable runtime harness for
`/arlen/live.js` semantics, focused stream/adversarial suites, and confidence
artifacts for both push-path and negative-path live behavior.

Phase 37 public-release confidence uses:

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

To add or update a Phase 37 acceptance probe:

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
