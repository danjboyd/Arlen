# Public Test Contract

Status: Phase 37 complete
Last updated: 2026-04-24

This document defines the release-confidence contract for Arlen's public
surfaces. The machine-readable source of truth is
`tests/fixtures/phase37/public_surface_contract.json`; this document explains
how to use it.

## Contract Levels

- `required`: must pass for a default public release candidate.
- `conditional`: must pass when the relevant platform or service is explicitly
  in scope for the release.
- `optional`: characterization or live-service evidence that strengthens the
  release pack but does not block the default gate.

Default Phase 37 checks are intentionally service-free. Live PostgreSQL, MSSQL,
Dataverse, OpenSearch, Meilisearch, Windows preview, and Apple baseline evidence
remain conditional unless release scope or branch protection changes.

## Public Surfaces

The Phase 37 matrix covers:

- EOC transpiler/runtime
- view/controller/routing
- HTTP server and protocol parsing
- middleware, security headers, sessions, CSRF, rate limits, and route policy
- CLI and generated app scaffolds
- first-party modules
- data adapters, SQL builder, migrations, ORM, and Dataverse
- live UI and realtime
- TypeScript/client generation
- deploy, packaged release, `boomhauer`, jobs worker, and propane accessories
- Windows preview and Apple baseline

## Required Evidence

Run the contract check:

```sh
make phase37-contract
```

Run the acceptance harness:

```sh
make phase37-acceptance
```

Run the explicit fast or runtime acceptance modes:

```sh
make phase37-acceptance-fast
make phase37-acceptance-runtime
```

Run the regression-intake and packaged-deploy proof checks:

```sh
make phase37-intake
make phase37-packaged-deploy-proof
```

Generate the current Phase 37 evidence pack:

```sh
make phase37-confidence
```

The confidence artifacts are written under
`build/release_confidence/phase37/`.

Phase 37 is a release-confidence lane, not a branch-protection change by
itself. The current required merge-gate checks remain defined in
`docs/CI_ALIGNMENT.md`.

## Acceptance Sites

The default `phase37-acceptance` manifest is service-free and currently covers:

- `eoc_kitchen_sink`
- `mvc_crud`
- `module_portal`
- `data_orm_reference`
- `live_ui_reference`
- `packaged_deploy`

These sites prove integration contracts and user workflows. They do not replace
focused unit/regression tests, live adapter tests, or the Phase 31/32/36 deploy
confidence lanes that exercise packaged deployment behavior more deeply.

Runtime-mode entries in `tests/fixtures/phase37/acceptance_sites.json` reserve
the real Arlen app variants. They are service-backed and opt-in until the
corresponding generated/runtime apps are stable enough for release
certification.

## Regression Intake

When fixing a public bug:

1. Add the narrowest focused unit/regression test.
2. Add or extend a checked-in fixture/corpus case.
3. Add an acceptance probe when the bug crossed routing, rendering, module,
   process, packaging, or client/runtime boundaries.
4. Update the public contract matrix when a new surface or gate exists.
5. Update user-facing docs when behavior changed.

For acceptance probes, edit `tests/fixtures/phase37/acceptance_sites.json`.
Prefer service-free fixture behavior by default; mark a site `serviceBacked`
only when it requires an explicit external dependency and document the required
environment variables next to the site.

The harness supports `contains`, `notContains`, `orderedContains`, `bodyRegex`,
`headers`, `headerPresent`, `headerRegex`, `jsonEquals`, `jsonPathEquals`, and
`cookieAttributes`.

## Coverage Status

Every public-surface entry carries a `coverageStatus` object so reviewers can
separate listed contract coverage from executable proof depth. Required fields
are `fixture_contract`, `unit_regression`, `integration`,
`acceptance_fixture`, `real_runtime_acceptance`, and `optional_live`.

Allowed values are `covered`, `planned`, `conditional`, and `not_applicable`.
`planned` and `conditional` values are acceptable for the default Phase 37 lane
only when the surface is outside the current service-free release gate or is
reserved for opt-in live/runtime proof.
