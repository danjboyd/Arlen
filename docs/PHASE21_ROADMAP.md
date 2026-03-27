# Arlen Phase 21 Roadmap

Status: Complete (`21A-21G` delivered on 2026-03-27)
Last updated: 2026-03-27

Related docs:
- `docs/STATUS.md`
- `docs/PHASE20_ROADMAP.md`
- `docs/GETTING_STARTED.md`
- `docs/TOOLCHAIN_MATRIX.md`
- `docs/DOCUMENTATION_POLICY.md`
- `docs/PHASE5_ROADMAP.md`
- `docs/PHASE7_ROADMAP.md`

External sources reviewed for this roadmap:
- `https://docs.mojolicious.org/Mojolicious/Guides/Testing`
- `https://hexdocs.pm/phoenix/testing.html`
- `https://hexdocs.pm/phoenix/Phoenix.ConnTest.html`
- `https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html`
- `https://github.com/pallets/jinja/tree/main/tests`
- `https://github.com/pallets/jinja/blob/main/tests/test_lexnparse.py`
- `https://github.com/pallets/jinja/blob/main/tests/test_regression.py`
- `https://github.com/pallets/jinja/blob/main/tests/test_security.py`
- `https://github.com/nodejs/llhttp/tree/main/test/request`
- `https://github.com/nodejs/llhttp/tree/main/test/response`
- `https://github.com/nodejs/llhttp/tree/main/test/fuzzers`

## 1. Objective

Strengthen Arlen's test suite ahead of public OSS release so first-user flows,
compiler edges, protocol boundaries, and contributor-found regressions are
covered with less boilerplate and stronger isolation.

Phase 21 is a test-infrastructure and coverage-depth pass, not a feature
expansion phase.

## 1.1 Why Phase 21 Exists

The current suite is already meaningful, but it still has a few shape problems
that matter more once Arlen has outside users:

- downstream bug reports from real apps catch valuable issues, but they still
  cover only a narrow slice of possible app/module/config combinations
- many web-facing tests rely on spawned servers plus shell/curl flows, which
  are good end-to-end acceptance coverage but too heavy for broad
  request/middleware/session permutations
- request/redirect/cookie/session assertions are still more ad hoc than they
  should be for routine route and middleware verification
- template/compiler coverage is deep, but it is not yet decomposed into the
  clean parser/security/regression buckets used by mature template engines
- hostile protocol coverage exists, but the raw HTTP corpus and replay story is
  not yet as first-class as the parser-focused suites used by projects like
  llhttp
- shared test support improved significantly in Phase 20, but that reuse is
  still concentrated around the data layer rather than the wider web/runtime
  test surface

Phase 21 addresses those directly.

## 1.2 Upstream Audit Summary

The upstream suites reviewed here are useful because they solve different parts
of the same problem:

- Mojolicious `Test::Mojo` shows how much leverage comes from one
  lifecycle-aware in-process app harness:
  - boot the app automatically
  - bind a random port
  - inject configuration directly from the test
  - introspect helpers/plugins/routes from the same object
- Phoenix `ConnCase` and `Phoenix.ConnTest` show the value of a thin request
  harness with reusable assertions:
  - build a request without forking a server
  - run endpoint/router pipelines explicitly when testing middleware in
    isolation
  - recycle cookies/session state between requests
  - assert redirects, params, content type, and wrapped errors through shared
    helpers instead of repeated string parsing
- Ecto's SQL sandbox shows how async DB-backed tests stay trustworthy only when
  state ownership is explicit:
  - explicit allowances for collaborator processes
  - shared mode when worker processes cannot be individually allowed
  - deliberate owner/process shutdown rules so tests do not pass while work is
    still live against borrowed state
- Jinja's suite structure shows the benefit of splitting a compiler/runtime
  surface by concern:
  - parser/lexer tests
  - runtime tests
  - security tests
  - regression tests
  - resource fixtures
- llhttp shows how protocol hardening gets stronger when raw inputs become a
  first-class corpus:
  - request and response fixture directories
  - invalid/lenient/pipelining categories
  - replayable fuzz harnesses tied to raw parser entrypoints

Arlen should borrow those ideas at the concept level while staying on GNUmake +
XCTest and using Objective-C-native helpers.

## 2. Design Principles

- Keep GNUmake + XCTest as the supported test stack.
- Prefer harnesses that exercise real Arlen runtime code over broad mocking.
- Separate fast in-process request coverage from subprocess/live acceptance
  coverage rather than replacing one with the other.
- Keep backend requirements and ownership rules explicit.
- Treat template/security/protocol negatives as first-class fixtures, not
  incidental one-off assertions.
- Promote fixed external bug reports into permanent named regression tests.
- Preserve deterministic fixture output, diagnostics, and GNUstep
  compatibility.
- Improve contributor ergonomics, but do not widen this phase into browser
  automation or a second test framework.

## 3. Scope Summary

1. Phase 21A: in-process request harness and case-template foundation.
2. Phase 21B: request/pipeline assertion helpers and state recycling.
3. Phase 21C: disposable DB/app-state sandboxes and async ownership rules.
4. Phase 21D: template/compiler suite decomposition and regression catalog.
5. Phase 21E: raw protocol corpus and fuzz/replay hardening.
6. Phase 21F: generated-app and module/config matrix coverage.
7. Phase 21G: focused lanes, contributor workflow, docs, and confidence
   closeout.

## 3.1 Recommended Rollout Order

1. `21A`
2. `21B`
3. `21C`
4. `21D`
5. `21E`
6. `21F`
7. `21G`

That order keeps the shared harness and ownership model in place before Arlen
widens request, compiler, protocol, and generated-app coverage on top of it.

## 4. Scope Guardrails

- Do not replace XCTest with ExUnit, pytest, Perl test tooling, or another new
  runner stack.
- Do not delete or weaken the existing spawned-server integration tests; the
  new harnesses are additive.
- Do not make Arlen's public-release story depend on browser automation.
- Do not promise transactional DB sandbox semantics where the adapter/runtime
  cannot honestly provide them; explicit schema/namespace isolation remains
  acceptable when that is the truthful contract.
- Do not widen this phase into new framework features unrelated to test
  robustness.
- Do not compromise deterministic diagnostics or GNUstep compatibility in the
  name of test convenience.

## 5. Milestones

## 5.1 Phase 21A: In-Process Request Harness + Case Templates

Status: complete on 2026-03-27

Delivered:

- Added `tests/shared/ALNWebTestSupport.{h,m}` as a shared in-process web-test
  harness with disposable app construction, config injection, request helpers,
  and controlled route/module/middleware introspection.
- Moved web-facing suites onto the shared harness where it reduces boilerplate,
  including focused in-process coverage in `ApplicationTests`,
  `MiddlewareTests`, `Phase14NotificationsIntegrationTests`, and
  `Phase16ModuleIntegrationTests`.
- Kept spawned-server integration coverage additive rather than replacing it;
  the new harness exists for fast route/controller/middleware exercise, not as
  a second runtime path.

Deliverables:

- Add a shared web-test support layer for in-process route/controller/middleware
  exercise without shelling out to `curl` for common cases.
- Introduce case-template or base-test conventions for:
  - request/response tests
  - app/module harness tests
  - DB-backed request tests
- Allow tests to boot a disposable app/runtime with config overrides supplied
  directly from the test instead of always writing temp config files first.
- Expose controlled app/helper/module introspection from the harness.

Acceptance (required):

- At least one current shell/curl-heavy route suite gains focused in-process
  request coverage for both HTML and JSON responses.
- Feature/config toggles can be exercised directly from tests without requiring
  a hand-authored config file for every case.

## 5.2 Phase 21B: Request Assertions + Pipeline Helpers

Status: complete on 2026-03-27

Delivered:

- Added shared request/response helpers for JSON decoding, request
  construction, cookie extraction, content-type/status/header/body assertions,
  and redirect verification in `tests/shared/ALNWebTestSupport.{h,m}`.
- Reworked multi-request auth/session/CSRF flows in `ApplicationTests` and
  `MiddlewareTests` to recycle cookies/session state through the shared helper
  surface instead of re-parsing responses inline.
- Added explicit isolated-pipeline coverage through the harness helpers so
  middleware-sensitive tests can run the intended path without shell/curl
  orchestration.

Deliverables:

- Add shared response/assertion helpers for:
  - status
  - content type
  - headers
  - HTML body fragments
  - JSON body decoding
  - redirects and redirected path params
  - wrapped error responses
- Add cookie/session recycling helpers for multi-request flows.
- Add explicit pipeline-bypass helpers so middleware can be tested in
  isolation while still running the required endpoint/router setup path.
- Add reusable request-construction helpers for custom headers, query strings,
  and body encodings.

Acceptance (required):

- `ApplicationTests`, `MiddlewareTests`, or equivalent web-facing suites use
  shared redirect/cookie/session/assertion helpers instead of repeated
  response parsing.
- At least one pipeline-sensitive auth/session/security test exercises a
  middleware path through the new isolated helper surface.

## 5.3 Phase 21C: Disposable State Sandboxes + Async Ownership

Status: complete on 2026-03-27

Delivered:

- Generalized `tests/shared/ALNTestSupport.{h,m}` beyond the Phase 20
  data-layer helpers with shared JSON parsing, file writes, temp-directory
  setup, and shell-capture support for wider suite reuse.
- Extended `tests/shared/ALNDatabaseTestSupport.{h,m}` with explicit worker
  ownership modes (`explicit_borrowed` and `shared_owner`) plus a reusable
  worker-group runner so DB-backed concurrency tests stop depending on ad hoc
  thread behavior.
- Moved large PostgreSQL/live integration suites onto the shared support
  surface so temp-file, shell, DSN, and cleanup logic are no longer duplicated
  inline across `PostgresIntegrationTests` and the Phase 13 Postgres module
  coverage.

Deliverables:

- Generalize `tests/shared` so disposable state helpers are reusable beyond the
  current Phase 20 data-layer focus.
- Add DB-backed case support for disposable PostgreSQL/MSSQL schemas,
  namespaces, or transaction-owned state as appropriate to the actual adapter
  contract.
- Define explicit worker/process ownership modes for DB-backed tests:
  - explicit borrowed-state allowance
  - serialized shared-owner mode
- Add reusable shutdown/on-exit helpers so test-owned workers terminate before
  their state owner disappears.

Acceptance (required):

- Large Pg/MSSQL/live suites stop carrying repeated schema/process cleanup
  helpers inline once equivalent shared support exists.
- Background-worker tests can deliberately choose explicit ownership or shared
  mode instead of relying on accidental behavior.

## 5.4 Phase 21D: Template Suite Decomposition + Regression Catalog

Status: complete on 2026-03-27

Delivered:

- Replaced the broad `tests/unit/TranspilerTests.m` bundle with focused
  Jinja-style suite slices:
  - `tests/unit/TemplateParserTests.m`
  - `tests/unit/TemplateCodegenTests.m`
  - `tests/unit/TemplateSecurityTests.m`
  - `tests/unit/TemplateRegressionTests.m`
- Added shared fixture/catalog helpers in
  `tests/shared/ALNTemplateTestSupport.{h,m}`.
- Added fixture namespaces for parser negatives, security/lint cases, and
  named regressions under `tests/fixtures/templates/parser/`,
  `tests/fixtures/templates/security/`, and
  `tests/fixtures/templates/regressions/`.
- Added a checked-in regression catalog at
  `tests/fixtures/templates/regressions/regression_catalog.json` so
  downstream template bugs land as stable named cases instead of expanding one
  catch-all file.

Deliverables:

- Split the current broad template/transpiler coverage into focused buckets
  inspired by Jinja's suite shape:
  - lexer/parser
  - compile/codegen
  - runtime/render
  - security
  - regression
- Add fixture namespaces for invalid syntax, deterministic diagnostics,
  security-sensitive cases, and externally reported regressions.
- Establish a simple regression intake convention so fixed downstream bugs land
  as stable named test cases/fixtures instead of one-off assertions.

Acceptance (required):

- At least one current broad template test file is decomposed into more focused
  suites with fixture-backed coverage.
- New template bug fixes can be added to a dedicated regression/security area
  without editing an increasingly catch-all file.

## 5.5 Phase 21E: Protocol Corpus + Fuzz/Replay Hardening

Status: complete on 2026-03-27

Delivered:

- Promoted `tests/fixtures/protocol` into a clearer raw-request corpus with
  `valid`, `invalid`, `pipelining`, `websocket`, `lenient`, and `fuzz_seeds`
  coverage plus the checked-in manifest
  `tests/fixtures/protocol/phase21_protocol_corpus.json`.
- Added `tools/ci/phase21_protocol_replay.py` to replay either the checked-in
  corpus or one saved raw request with deterministic expected-status
  assertions.
- Added `tools/ci/run_phase21_protocol_corpus.sh` and `make phase21-protocol-tests`
  so protocol-adversarial coverage is rerunnable from one dedicated lane.
- Kept strict-vs-lenient/backend differences explicit through per-case limits
  and backend-specific expected statuses where the parser contracts differ.

Deliverables:

- Promote `tests/fixtures/protocol` into a clearer raw-input corpus with
  request/response categories such as:
  - valid
  - invalid
  - lenient-mode
  - pipelining
  - websocket handshake/frame boundaries where applicable
- Add a replay harness that feeds raw bytes into parser/runtime boundaries and
  asserts deterministic accept/reject behavior.
- Add replayable fuzz/adversarial seed handling for parser/framing regressions.
- Keep strict-vs-lenient behavior explicit when Arlen supports both.

Acceptance (required):

- Existing protocol-adversarial coverage can be rerun from one dedicated corpus
  target instead of only through broader integration wrappers.
- A failing raw input or saved seed can be replayed with one documented
  command.

## 5.6 Phase 21F: Generated-App + Module Matrix Coverage

Status: complete on 2026-03-27

Delivered:

- Added the curated generated-app fixture
  `tests/fixtures/phase21/generated_app_matrix.json`.
- Added `tools/ci/phase21_generated_app_matrix.py` and
  `tools/ci/run_phase21_generated_app_matrix.sh` to exercise scaffold/module
  add-upgrade/eject flows plus representative auth UI mode/config variants.
- Covered realistic first-user paths such as scaffold-contract verification,
  auth module install/upgrade, endpoint generation, dry-run build/check, and
  HTML/API behavior across `module-ui`, `headless`, and
  `generated-app-ui`-sensitive setups.
- Converted downstream-style first-user setup problems into one focused matrix
  surface instead of waiting for broad integration runs to trip them
  incidentally.

Deliverables:

- Add a curated generated-app matrix harness for first-user setup paths:
  - scaffolded app boot/build/test
  - module add/eject/upgrade flows
  - mode toggles such as `headless`, `module-ui`, and `generated-app-ui`
  - representative module feature flags and config variants
- Reuse the new config-injection support wherever possible so matrix cases stay
  concise and deterministic.
- Cover a curated matrix of realistic first-user combinations rather than
  exploding into all possible permutations.

Acceptance (required):

- A representative set of first-user app/module/config combinations is covered
  by one focused matrix suite.
- At least one current downstream bug-report class is converted into generated
  app/mode/config matrix coverage.

## 5.7 Phase 21G: Focused Lanes + Contributor Workflow + Confidence

Status: complete on 2026-03-27

Delivered:

- Added repo-native focused Phase 21 lanes:
  - `make phase21-template-tests`
  - `make phase21-protocol-tests`
  - `make phase21-generated-app-tests`
  - `make phase21-focused`
  - `make phase21-confidence`
- Added explicit runner helpers in `tools/ci/run_phase21_focused.sh`,
  `tools/ci/run_phase21_protocol_corpus.sh`,
  `tools/ci/run_phase21_generated_app_matrix.sh`, and
  `tools/ci/run_phase21_confidence.sh`.
- Added `docs/TESTING_WORKFLOW.md` so contributors can move from bug report to
  fixture/test/lane/confidence promotion without test-suite archaeology.
- Added Phase 21 confidence artifact generation in
  `tools/ci/generate_phase21_confidence_artifacts.py` and
  `build/release_confidence/phase21/`.

Deliverables:

- Add repo-native focused lanes for the new coverage surfaces, for example:
  - fast request harness tests
  - template corpus/regression tests
  - protocol corpus/fuzz replay tests
  - generated-app matrix tests
- Document the contributor workflow from bug report to permanent regression:
  - reproduce
  - add focused fixture/test
  - run focused lane
  - promote through broader suite
- Add Phase 21 confidence/closeout commands and docs updates once the new test
  topology is in place.

Acceptance (required):

- Contributors can identify the right focused rerun path from repo docs without
  test-suite archaeology.
- Phase 21 closes with documented focused lanes and a reproducible confidence
  entrypoint.
