# Testing Workflow

This guide describes the fastest path from a bug report to a permanent Arlen
regression test.

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
- `make phase24-windows-tests`
  - focused Windows CLANG64-safe XCTest lane using the linked repo-local test
    runner
  - currently scoped to the `ArlenPhase21TemplateTestsRunner` executable
- `make phase24-windows-db-smoke`
  - focused Windows CLANG64 data-layer transport smoke executable
  - asserts ODBC load and validates the documented PostgreSQL host-library
    contract before expected connection failure
- `make phase24-windows-runtime-tests`
  - focused Windows CLANG64 runtime parity executable
  - covers `boomhauer` watch/dev-error recovery, `jobs worker`, and `propane`
- `make phase24-windows-confidence`
  - Windows confidence lane: build, focused tests, DB transport smoke, runtime
    parity, and app-root CLI smoke
- `make phase24-windows-parity`
  - full Windows `24Q-24R` parity lane
  - runs build, default `make test-unit` / `make test-integration`, the
    PostgreSQL and MSSQL live-backend suites, and the broader perf/robustness
    confidence scripts wired through `tools/ci/run_phase24_windows_parity.sh`

Current Windows caveat:
- the focused Phase 24 lanes deliberately use linked test executables because
  CLANG64 test discovery remains more reliable through the checked-in repo-local
  runner contract than through a stock bundle-only `xctest` path
- the remaining warning seen on this host is the upstream CLANG64/GNUstep
  `-fobjc-exceptions` unused-command-line warning rather than an Arlen source
  warning

Phase 20 data-layer-focused lanes remain available:

- `make phase20-sql-builder-tests`
- `make phase20-schema-tests`
- `make phase20-routing-tests`
- `make phase20-postgres-live-tests`
- `make phase20-mssql-live-tests`
- `make phase20-focused`

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
   - raw protocol framing / parser behavior:
     `tests/fixtures/protocol/phase21_protocol_corpus.json`
   - generated-app setup/config/module issues:
     `tests/fixtures/phase21/generated_app_matrix.json`
3. Add or extend a checked-in fixture so the failure is replayable.
4. Run the matching focused lane until it passes.
5. Promote the change through `make test-unit`, broader integration coverage
   when applicable, and `make phase21-confidence`.

For the native Windows preview branch, use the focused `phase24-windows-*`
lanes for fast reproduction, then promote through `make test-unit`,
`make test-integration`, `make phase20-postgres-live-tests`,
`make phase20-mssql-live-tests`, and `make phase24-windows-parity`.
`make phase24-windows-confidence` remains the quicker checked-in smoke path for
runtime/app-root validation before the full parity sweep.

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
