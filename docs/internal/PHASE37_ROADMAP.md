# Phase 37 Roadmap

Status: complete; 37A-37S delivered 2026-04-24
Last updated: 2026-04-24

## Goal

Turn Arlen's broad young surface area into a public-release quality test
contract that is easy to extend, hard to bypass accidentally, and backed by
small executable acceptance sites.

Phase 21 established a public-release test robustness pass for templates,
protocol replay, and generated app coverage. Since then, Arlen's shipped
surface has expanded across MVC, middleware, modules, data adapters, ORM, live
UI, deployment, Windows preview, and TypeScript/client contracts. Phase 37 is
the release-confidence pass that names the public surfaces, maps each one to
required evidence, and adds battle-test applications that exercise realistic
cross-feature workflows.

## North Star

A release candidate should be able to answer three questions with checked-in,
repeatable evidence:

```sh
make phase37-contract
make phase37-acceptance
make phase37-confidence
```

- what public behavior is covered
- which focused lane owns regressions for that behavior
- which acceptance site proves the major integration paths still work together

## Scope

- public-surface test contract matrix
- expanded template regression and golden-render coverage
- deterministic parser/protocol corpus growth
- small acceptance sites for EOC, MVC, modules, data/ORM, live UI, and deploy
- route/probe harnesses for acceptance sites
- CI and docs alignment for the new release-confidence contract
- named Phase 37 confidence artifacts

## Non-Goals

- Do not replace focused unit/regression tests with acceptance sites.
- Do not require live PostgreSQL, MSSQL, Dataverse, OpenSearch, or Meilisearch
  services for the default Phase 37 gate.
- Do not promote Windows preview or Apple baseline checks into required Linux
  merge gates unless branch-protection guidance is deliberately updated.
- Do not claim sandboxing or untrusted-template execution from these tests.
- Do not introduce nondeterministic fuzzing into required CI lanes; randomized
  campaigns may exist as replayable nightly or local tooling only.

## 37A. Public Surface Test Contract Matrix

Status: delivered 2026-04-24.

Goal:

- define the behavior Arlen intends to support publicly and the required test
  evidence for each surface

Required behavior:

- add a checked-in contract matrix that maps public surfaces to:
  - owner area
  - focused unit/regression files
  - integration or acceptance coverage
  - optional live-service evidence
  - required CI/confidence lane
- include at least these surfaces:
  - EOC transpiler/runtime
  - view/controller/routing
  - HTTP server and protocol parsing
  - middleware/security/session/CSRF/rate limit/route policy
  - CLI and generated app scaffolds
  - first-party modules
  - data adapters, SQL builder, migrations, ORM, Dataverse
  - live UI and realtime
  - TypeScript/client generation
  - deploy, packaged release, `boomhauer`, jobs worker, and propane accessories
  - Windows preview and Apple baseline
- document which surfaces block a public release by default and which are
  optional adapter evidence

Acceptance:

- contributors can identify the correct regression home before changing public
  behavior
- release reviewers can see whether a surface is uncovered, optional, or gated

Delivered artifacts:

- `docs/PUBLIC_TEST_CONTRACT.md`
- `tests/fixtures/phase37/public_surface_contract.json`
- `make phase37-contract`

## 37B. EOC Golden Render Regression Expansion

Status: delivered 2026-04-24.

Goal:

- harden the v1 template engine with output-level regressions in addition to
  parser/codegen assertions

Required behavior:

- expand the template regression catalog with stable case IDs for known and
  anticipated bug classes
- add golden render fixtures for:
  - escaped output
  - raw output
  - `nil` output
  - non-string output under default and strict stringify modes
  - dictionary, object, and dotted keypath locals
  - layout, slot, include, collection, empty collection, and overlay locals
  - required locals
  - diagnostics with filename, line, and column metadata
- verify generated symbol names and generated source remain deterministic
- keep fixture inputs and expected outputs checked in

Acceptance:

- `make phase21-template-tests` catches runtime output drift, not only emitted
  source drift
- downstream template bugs can be reduced to a catalog entry plus golden output

Delivered artifacts:

- `tests/fixtures/phase37/eoc_golden_render_cases.json`
- `tests/fixtures/templates/golden/`
- Phase 37 contract validation for golden-render coverage

## 37C. Parser And Protocol Corpus Growth

Status: delivered 2026-04-24.

Goal:

- broaden adversarial coverage for state-machine parsers without making CI
  flaky

Required behavior:

- add deterministic EOC parser corpus cases for malformed tags, nested-looking
  tags, multiline expressions, invalid sigil keypaths, comments, directive
  syntax, and EOF edge cases
- expand HTTP/protocol replay seeds for malformed framing, partial reads,
  keep-alive boundaries, header injection attempts, websocket upgrade
  rejection paths, and body length mismatches
- add a replayable corpus generator that records the seed, case ID, expected
  status/diagnostic, and parser backend
- keep randomized runs outside the required gate unless their generated corpus
  is checked in and deterministic

Acceptance:

- required CI replays a stable corpus
- new parser failures can be captured as raw input plus expected diagnostic

Delivered artifacts:

- `tests/fixtures/phase37/parser_protocol_corpus.json`
- new parser fixtures under `tests/fixtures/templates/parser/`
- new protocol request seeds under `tests/fixtures/protocol/requests/`
- Phase 37 contract validation for deterministic corpus shape

## 37D. Acceptance Site Harness

Status: delivered 2026-04-24.

Goal:

- provide a shared way to build, start, probe, and stop battle-test sites

Required behavior:

- add a repo-local harness for acceptance sites with deterministic ports,
  isolated temp homes, explicit logs, and cleanup
- support HTTP probes, expected status/body/header assertions, JSON assertions,
  and static file checks
- make failures preserve enough artifacts for diagnosis
- add `make phase37-acceptance` as the default acceptance entrypoint
- keep service-backed variants opt-in through environment variables

Acceptance:

- every Phase 37 acceptance site can be exercised from one local command
- failed probes identify the route, expected result, actual result, and log path

Delivered artifacts:

- `tools/ci/phase37_acceptance_harness.py`
- `tests/fixtures/phase37/acceptance_sites.json`
- `tests/acceptance/phase37_harness_site/`
- `make phase37-acceptance`
- `make phase37-confidence`

## 37E. EOC Kitchen Sink Site

Status: delivered 2026-04-24.

Goal:

- exercise the full v1 EOC template surface through a running app

Required behavior:

- add a small site that renders routes for:
  - escaping and raw output
  - locals and keypaths
  - nested control flow
  - layouts, named slots, includes, collections, and empty states
  - strict mode failures surfaced as deterministic errors
- include probes that assert rendered HTML and expected failure diagnostics

Acceptance:

- template runtime regressions are observable through HTTP, not only direct
  render helper calls

Delivered artifacts:

- `tests/acceptance/eoc_kitchen_sink/`
- `eoc_kitchen_sink` entry in `tests/fixtures/phase37/acceptance_sites.json`
- dynamic fixture responses in `tools/ci/phase37_acceptance_site_server.py`

## 37F. MVC CRUD Site

Status: delivered 2026-04-24.

Goal:

- exercise common app authoring behavior with routes, controllers, forms, and
  middleware

Required behavior:

- add a minimal CRUD-style app with:
  - GET/POST routes
  - route parameters
  - query and form body parsing
  - redirects
  - validation errors
  - sessions
  - CSRF success and rejection paths
  - security headers
  - static assets
- probe both success and failure paths

Acceptance:

- the default app workflow works end to end without relying on module-specific
  integration tests

Delivered artifacts:

- `tests/acceptance/mvc_crud/`
- `mvc_crud` entry in `tests/fixtures/phase37/acceptance_sites.json`
- harness support for POST bodies, request headers, redirect assertions, and
  static asset probes

## 37G. Module Portal Site

Status: delivered 2026-04-24.

Goal:

- verify first-party modules can coexist in one app without route, asset,
  layout, middleware, or config collisions

Required behavior:

- compose auth, admin UI, jobs, notifications, search, storage, and ops in one
  acceptance app using fixture-backed/in-memory adapters by default
- probe representative HTML and API routes for each module
- verify module assets are served
- verify disabled-provider and missing-migration guidance paths remain
  actionable
- verify protected routes fail closed

Acceptance:

- first-party modules prove shared runtime compatibility before public release

Delivered artifacts:

- `tests/acceptance/module_portal/`
- `module_portal` entry in `tests/fixtures/phase37/acceptance_sites.json`
- auth, admin, jobs, notifications, search, storage, ops, asset, and protected
  route probes

## 37H. Data And ORM Reference Site

Status: delivered 2026-04-24.

Goal:

- exercise migrations, SQL builder, repositories, ORM descriptors, and
  generated helpers through a small application path

Required behavior:

- provide fixture/in-memory coverage by default
- add optional PostgreSQL and MSSQL modes when explicit DSNs are present
- probe create/read/update/delete behavior, validation failures, transactions,
  pagination, deterministic ordering, and generated-primary-key hydration
- preserve backend-specific expectations in fixtures

Acceptance:

- data-layer regressions have a site-level reproduction path in addition to
  focused unit and live-adapter tests

Delivered artifacts:

- `tests/acceptance/data_orm_reference/`
- `data_orm_reference` entry in `tests/fixtures/phase37/acceptance_sites.json`
- migration, deterministic record ordering, create, validation, descriptor, and
  primary-key hydration probes

## 37I. Live UI Reference Site

Status: delivered 2026-04-24.

Goal:

- exercise live UI, realtime, and client-runtime behavior through a browser-like
  contract without requiring a full browser in the default lane

Required behavior:

- add routes and probes for live DOM updates, event dispatch, region
  replacement, stream reconnect, auth expiry, backpressure, and static runtime
  asset serving
- reuse the existing JavaScript harness where practical
- keep browser-dependent checks optional unless the repo already provisions the
  runner capability

Acceptance:

- live UI regressions can be reproduced from a site route and a deterministic
  client-runtime script

Delivered artifacts:

- `tests/acceptance/live_ui_reference/`
- `live_ui_reference` entry in `tests/fixtures/phase37/acceptance_sites.json`
- live page, DOM operation payload, SSE stream shape, auth expiry,
  backpressure, and runtime asset probes

## 37J. Packaged Deploy Site

Status: delivered 2026-04-24.

Goal:

- prove generated app packaging, deploy helper scripts, `boomhauer`,
  jobs-worker, and propane accessories operate together

Required behavior:

- build a packaged release for a small acceptance app
- verify packaged server startup, health checks, static assets, template
  rendering, and jobs-worker `--once`
- verify deploy dryrun/list/releases/status/rollback paths using local target
  fixtures
- verify propane accessories are read from the expected settings surface
- keep remote SSH mutation optional unless an explicit target is configured

Acceptance:

- the public release bundle can be smoke-tested as users will actually run it

Delivered artifacts:

- `tests/acceptance/packaged_deploy/`
- `packaged_deploy` entry in `tests/fixtures/phase37/acceptance_sites.json`
- packaged manifest, health, static asset, template rendering, jobs-worker,
  deploy local workflow, and propane accessories probes
- real package/deploy behavior remains covered by Phase 31, Phase 32, and
  Phase 36 confidence lanes referenced in the public surface contract

## 37K. Confidence Lane And CI Alignment

Status: delivered 2026-04-24.

Goal:

- make Phase 37 evidence easy to run locally and safe to promote into CI

Required behavior:

- add `make phase37-contract`
- add `make phase37-acceptance`
- add `make phase37-confidence`
- generate artifacts under `build/release_confidence/phase37/`
- document which Phase 37 commands are expected in local development, PR
  validation, and release certification
- update workflow files, branch-protection guidance, and CI alignment docs only
  if required checks change

Acceptance:

- release candidates include a Phase 37 evidence pack
- CI naming and documentation stay aligned with the actual required checks

Delivered artifacts:

- `make phase37-contract`
- `make phase37-acceptance`
- `make phase37-confidence`
- `tools/ci/run_phase37_*.sh`
- `tools/ci/generate_phase37_confidence_artifacts.py`
- `docs/CI_ALIGNMENT.md` documents that Phase 37 is a release-confidence lane
  and does not change required merge-gate checks

## 37L. Regression Intake And Closeout Docs

Status: delivered 2026-04-24.

Goal:

- make the new testing model sustainable after the phase closes

Required behavior:

- update `docs/TESTING_WORKFLOW.md` with the Phase 37 regression intake path
- document how to add a new acceptance site route/probe
- document when to add a unit test, catalog fixture, acceptance probe, or
  optional live-service case
- update docs navigation and status docs at closeout
- add a checklist for public-release bug fixes:
  - minimal focused regression
  - checked-in fixture
  - acceptance probe when integration behavior changed
  - docs update when user-visible behavior changed

Acceptance:

- future bugs have a clear path from report to permanent regression evidence
- Phase 37 closes with the same roadmap, docs, and confidence-lane alignment
  expected of shipped behavior

Delivered artifacts:

- `docs/PUBLIC_TEST_CONTRACT.md`
- `docs/TESTING_WORKFLOW.md`
- `docs/README.md`
- `docs/STATUS.md`
- this roadmap marked complete

## Validation-Depth Follow-Up

The original Phase 37 scope established the public-surface contract, fast
service-free acceptance sites, and confidence lane. The follow-up subphases
below make that evidence stronger by proving more behavior through the real
Arlen runtime instead of fixture servers alone.

## 37M. Real Runtime Acceptance Site Variants

Status: delivered 2026-04-24.

Goal:

- convert the fixture-backed acceptance sites into real Arlen app variants
  incrementally while preserving the current fast lane

Required behavior:

- keep the existing service-free fixture sites as fast contract checks
- add real-runtime variants for:
  - EOC kitchen sink using actual `.html.eoc` templates
  - MVC CRUD using real `ALNApplication`, routes, controllers, and middleware
  - module portal booting actual first-party modules
  - live UI serving the real runtime asset and live payloads
  - packaged deploy using an actual generated app release bundle
- make real-runtime variants opt-in until they are stable enough for release
  certification

Acceptance:

- Phase 37 can distinguish fixture contract coverage from real Arlen runtime
  acceptance coverage

Delivered artifacts:

- runtime-mode acceptance entries in `tests/fixtures/phase37/acceptance_sites.json`
- `runtimeVariantOf` metadata for EOC, MVC, module portal, live UI, and
  packaged deploy surfaces
- `make phase37-contract` validates runtime variant coverage

## 37N. Dual-Mode Acceptance Manifest

Status: delivered 2026-04-24.

Goal:

- split acceptance execution into fast fixture-backed checks and deeper
  real-runtime checks

Required behavior:

- add explicit entrypoints for:
  - `make phase37-acceptance-fast`
  - `make phase37-acceptance-runtime`
- keep `make phase37-acceptance` mapped to the default service-free lane unless
  the CI contract is deliberately changed
- allow `make phase37-confidence` or release certification to include the
  runtime lane through an explicit environment variable or target
- record mode, skipped service-backed sites, and runtime-site results in the
  generated confidence manifest

Acceptance:

- developers can run a quick local contract check and release reviewers can run
  deeper runtime evidence without changing the fixture manifest by hand

Delivered artifacts:

- `make phase37-acceptance-fast`
- `make phase37-acceptance-runtime`
- `make phase37-acceptance` remains mapped to the fast service-free lane
- acceptance manifests record execution mode and skipped runtime/service-backed
  sites

## 37O. Executable EOC Golden Render Assertions

Status: delivered 2026-04-24.

Goal:

- close the gap between cataloged golden fixtures and actual template render
  behavior

Required behavior:

- compile/render every case in `tests/fixtures/phase37/eoc_golden_render_cases.json`
- compare exact expected HTML output where an expected-output fixture exists
- assert exact error domain, code, path, line, column, and local metadata for
  diagnostic cases
- run under `make phase21-template-tests` or a focused Phase 37 template lane
- make the EOC kitchen sink real-runtime site reuse the same fixtures where
  practical

Acceptance:

- EOC golden cases prove actual parser, codegen, runtime, escaping, strict mode,
  and diagnostic behavior

Delivered artifacts:

- `tools/ci/check_phase37_eoc_golden.py`
- `make phase37-eoc-golden`
- `make phase37-contract` runs executable golden assertions and writes
  `build/release_confidence/phase37/eoc_golden_summary.json`

## 37P. Acceptance Harness Assertion Depth

Status: delivered 2026-04-24.

Goal:

- improve probe precision so acceptance failures catch subtle regressions

Required behavior:

- add support for:
  - `notContains`
  - JSON path or nested deep equality
  - regular expression body/header assertions
  - header presence independent of exact value
  - ordered body assertions
  - cookie attribute checks
- include negative self-tests for each assertion type
- preserve deterministic artifact output for failures

Acceptance:

- acceptance probes can express real browser/API expectations without fragile
  ad hoc string checks

Delivered artifacts:

- `notContains`
- `jsonPathEquals`
- `bodyRegex`
- `headerPresent`
- `headerRegex`
- `orderedContains`
- `cookieAttributes`
- `tools/ci/test_phase37_acceptance_assertions.py`
- `make phase37-harness-selftest`

## 37Q. Regression Intake Enforcement

Status: delivered 2026-04-24.

Goal:

- make the Phase 37 testing model a durable bug-fix discipline

Required behavior:

- add contributor-facing checklist coverage for public bug fixes:
  - focused unit regression
  - checked-in fixture or corpus case
  - Phase 37 acceptance probe when behavior crosses a public workflow boundary
  - docs update for user-visible behavior
- add a lightweight script or docs-quality check that validates new Phase 37
  acceptance entries have stable IDs, descriptions, and artifact paths
- document when acceptance coverage is not appropriate

Acceptance:

- future public bug fixes leave permanent evidence in the correct layer instead
  of only adding broad end-to-end checks

Delivered artifacts:

- `tools/ci/check_phase37_intake.py`
- `make phase37-intake`
- `make phase37-confidence` now includes the regression intake check
- acceptance manifest validation for stable IDs, descriptions, runtime
  metadata, probe IDs, and static artifact paths

## 37R. Real Packaged Deploy Release Proof

Status: delivered 2026-04-24.

Goal:

- prove packaged release behavior through an actual generated app and local
  target, not only the fixture deploy site

Required behavior:

- build an actual packaged release for a small acceptance app
- start the packaged server and probe health, static assets, template rendering,
  and runtime metadata
- run packaged `jobs-worker --once`
- run local deploy `dryrun`, `list`, `releases`, `status`, and `rollback`
  probes against an isolated temporary target
- verify propane accessories are read from the expected settings surface
- keep remote SSH mutation optional behind explicit configuration

Acceptance:

- release candidates include evidence that the packaging and deploy path users
  run is operational, not just contract-shaped

Delivered artifacts:

- `tools/ci/run_phase37_packaged_deploy_proof.sh`
- `make phase37-packaged-deploy-proof`
- `build/release_confidence/phase37/packaged_deploy_proof.json`
- proof references for the existing real packaged deployment integration
  tests in `tests/integration/DeploymentIntegrationTests.m`
- `make phase37-confidence` records packaged deploy proof status; the full
  real lane remains `make test-integration-filter TEST=DeploymentIntegrationTests`

## 37S. Contract Coverage Status Tracking

Status: delivered 2026-04-24.

Goal:

- make the public surface matrix show the depth of evidence for each surface

Required behavior:

- extend `tests/fixtures/phase37/public_surface_contract.json` with coverage
  status fields such as:
  - `fixture_contract`
  - `unit_regression`
  - `integration`
  - `acceptance_fixture`
  - `real_runtime_acceptance`
  - `optional_live`
- have `make phase37-contract` validate the required status fields
- have `make phase37-confidence` summarize coverage depth in generated
  artifacts
- document which gaps are acceptable for default release gating and which
  require follow-up before public launch

Acceptance:

- reviewers can see not just that a surface is listed, but how strongly it is
  proven by current evidence

Delivered artifacts:

- `coverageStatus` fields in
  `tests/fixtures/phase37/public_surface_contract.json`
- `make phase37-contract` validates required coverage status fields and values
- `make phase37-confidence` includes coverage status tracking in its generated
  evaluation and evidence manifest
