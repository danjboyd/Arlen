# Public Test Contract

Status: Phase 37A baseline
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

Generate the current Phase 37 evidence pack:

```sh
make phase37-confidence
```

The confidence artifacts are written under
`build/release_confidence/phase37/`.

## Regression Intake

When fixing a public bug:

1. Add the narrowest focused unit/regression test.
2. Add or extend a checked-in fixture/corpus case.
3. Add an acceptance probe when the bug crossed routing, rendering, module,
   process, packaging, or client/runtime boundaries.
4. Update the public contract matrix when a new surface or gate exists.
5. Update user-facing docs when behavior changed.
