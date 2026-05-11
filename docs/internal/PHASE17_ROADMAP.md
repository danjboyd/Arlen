# Arlen Phase 17 Roadmap

Status: Complete
Last updated: 2026-03-12

Related docs:
- `docs/ARLEN_DATA.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE5_ROADMAP.md`
- `docs/STATUS.md`

## 1. Objective

Add the first non-PostgreSQL database backend to Arlen by introducing a
backend-neutral dialect/tooling seam and an optional Microsoft SQL Server
adapter package.

The core requirement is explicit:

- Arlen core must not gain a hard dependency on Microsoft's ODBC driver

Phase 17 should make MSSQL support possible without weakening the current
PostgreSQL developer experience or pretending all SQL backends are identical.

## 1.1 Why Phase 17 Exists

Arlen already has a useful adapter seam in `ALNDatabaseAdapter`, but the wider
data layer is still PostgreSQL-shaped in a few important places:

- `ALNMigrationRunner` is typed directly to `ALNPg`
- builder execution and diagnostics are centered on `ALNPg`
- dialect-specific builder behavior only exists for PostgreSQL
- docs and examples still assume PostgreSQL as the only serious SQL target

That is acceptable for the current shipped surface, but it blocks a clean SQL
Server implementation.

Phase 17 addresses that by separating:

- backend-neutral execution contracts
- dialect-specific SQL compilation
- optional transport/client bindings
- target-specific tooling and docs

## 1.2 Design Principles

- Keep MSSQL support optional, not a core runtime dependency.
- Do not add ODBC headers or Microsoft driver assumptions to Arlen core
  headers.
- Preserve `ALNPg` as a first-class adapter; Phase 17 is additive, not a PG
  retreat.
- Treat SQL dialect differences explicitly through capabilities and dedicated
  dialect layers.
- Fail closed when a builder, migration, or tooling feature is unsupported on
  the selected backend.
- Prefer one conformance surface for adapters instead of backend-specific
  hidden behavior.
- Keep local development ergonomic:
  - PostgreSQL remains the default-first path
  - MSSQL is enabled by installing an optional adapter package and its runtime
    client dependencies

## 1.3 Dependency Strategy

Core Arlen should depend only on backend-neutral contracts such as:

- `ALNDatabaseAdapter`
- `ALNDatabaseConnection`
- a new dialect/compiler capability seam introduced in this phase

The MSSQL adapter itself may depend on one of these transport layers:

- generic ODBC manager APIs (`unixODBC` or `iODBC`)
- FreeTDS/TDS-native client libraries

Microsoft's SQL Server ODBC driver may still be used as a deployment/runtime
dependency where operators choose it, but it must not become a mandatory core
Arlen dependency.

## 2. Scope Summary

1. Phase 17A: backend-neutral dialect and migration seams.
2. Phase 17B: optional MSSQL adapter transport and diagnostics.
3. Phase 17C: MSSQL SQL dialect compilation and capability metadata.
4. Phase 17D: tooling, docs, examples, and conformance confidence.

## 3. Scope Guardrails

- Do not replace PostgreSQL as Arlen's default documented database.
- Do not promise ORM-style backend transparency that the SQL builder cannot
  honestly support.
- Do not couple core Arlen to Microsoft's driver packaging or install model.
- Do not require MSSQL schema codegen/introspection in the first slice if the
  adapter and migration path can ship earlier.
- Do not silently emulate PostgreSQL-only features with lossy behavior.
- Do not widen Phase 17 into a general database-abstraction rewrite beyond what
  MSSQL support actually requires.

## 4. Milestones

## 4.1 Phase 17A: Backend-Neutral Dialect + Migration Seams

Deliverables:

- Introduce a backend-neutral dialect/compiler contract for SQL rendering and
  capability checks.
- Refactor migration execution so it no longer requires `ALNPg *` in its
  public API.
- Separate backend-neutral migration planning from backend-specific migration
  state-table behavior where needed.
- Define capability metadata for:
  - transactions
  - `RETURNING`-style row return semantics
  - pagination syntax
  - upsert/conflict support
  - JSON/query feature families

Acceptance (required):

- core data-layer headers compile without importing PostgreSQL-specific types
  for generic migration workflows
- PostgreSQL continues to pass the existing migration and adapter conformance
  coverage
- unsupported dialect features fail with explicit diagnostics

## 4.2 Phase 17B: Optional MSSQL Adapter Transport + Diagnostics

Deliverables:

- Add an optional MSSQL adapter package/target, for example `ArlenMSSQL`.
- Implement connection management, parameter binding, query execution, command
  execution, and transaction handling for SQL Server.
- Keep transport/client dependencies isolated to the optional adapter target.
- Add structured diagnostics similar in spirit to `ALNPg` without leaking
  backend-specific details into the generic adapter contract.

Acceptance (required):

- Arlen core builds and links without MSSQL client libraries installed
- the MSSQL adapter builds only when its optional transport dependency is
  present
- adapter execution passes a shared conformance suite for basic query/command
  behavior and transactions

## 4.3 Phase 17C: MSSQL Dialect Compilation + Capability Metadata

Deliverables:

- Add MSSQL-specific SQL compilation support for:
  - identifier quoting
  - pagination
  - insert/update/delete return semantics
  - upsert-equivalent behavior where support exists
  - capability-gated unsupported builder features
- Introduce an MSSQL dialect extension parallel to
  `ALNPostgresSQLBuilder` where backend-specific syntax is required.
- Document the supported subset of `ALNSQLBuilder` on MSSQL.

Acceptance (required):

- the shared builder surface compiles deterministically for supported MSSQL
  operations
- unsupported PostgreSQL-only constructs fail closed with clear error messages
- capability metadata is exposed consistently for both PostgreSQL and MSSQL

## 4.4 Phase 17D: Tooling, Docs, Examples, + Confidence

Deliverables:

- Update:
  - `docs/ARLEN_DATA.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/GETTING_STARTED_DATA_LAYER.md`
- Add a focused example app or data-layer example showing optional MSSQL
  adapter wiring.
- Expand adapter conformance coverage to run against both PostgreSQL and MSSQL
  where environment support is available.
- Document deployment expectations clearly:
  - core Arlen does not require Microsoft's driver
  - the optional MSSQL adapter requires an installed transport/runtime client

Acceptance (required):

- docs explain the dependency split clearly enough that operators do not assume
  MSSQL support is built into core Arlen
- example wiring is deterministic and minimal
- confidence artifacts distinguish backend-neutral guarantees from
  backend-specific support
