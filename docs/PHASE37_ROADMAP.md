# Phase 37 Roadmap

Status: planned
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

Status: planned.

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

## 37B. EOC Golden Render Regression Expansion

Status: planned.

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

## 37C. Parser And Protocol Corpus Growth

Status: planned.

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

## 37D. Acceptance Site Harness

Status: planned.

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

## 37E. EOC Kitchen Sink Site

Status: planned.

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

## 37F. MVC CRUD Site

Status: planned.

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

## 37G. Module Portal Site

Status: planned.

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

## 37H. Data And ORM Reference Site

Status: planned.

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

## 37I. Live UI Reference Site

Status: planned.

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

## 37J. Packaged Deploy Site

Status: planned.

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

## 37K. Confidence Lane And CI Alignment

Status: planned.

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

## 37L. Regression Intake And Closeout Docs

Status: planned.

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
