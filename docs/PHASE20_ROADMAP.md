# Arlen Phase 20 Roadmap

Status: Active (`20A-20C` delivered on 2026-03-26; `20D-20F` pending)
Last updated: 2026-03-26

Related docs:
- `docs/ARLEN_DATA.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`
- `docs/SQL_BUILDER_CONFORMANCE_MATRIX.md`
- `docs/PHASE5_ROADMAP.md`
- `docs/PHASE17_ROADMAP.md`
- `docs/STATUS.md`

## 1. Objective

Deepen Arlen's data-layer semantics so typed contracts, SQL compilation,
connection handling, and schema tooling behave more like a mature SQL toolkit
without expanding Arlen into ORM territory.

Phase 20 is a depth pass, not a breadth pass. Arlen already has:

- adapters and pooled connections
- a substantial SQL builder surface
- dialect seams
- migration tooling
- typed schema codegen
- read/write routing

The remaining problem is that some of those pieces are still shallower than the
contracts around them. Phase 20 closes those gaps directly.

## 1.1 Why Phase 20 Exists

The current data layer is useful, but it still has a few maturity gaps that
show up once the surface is used as a real toolkit instead of as isolated
features:

- typed schema codegen currently outpaces live adapter row materialization
- non-PostgreSQL dialect adaptation is still too root-level in nested SQL
  cases
- result ergonomics remain intentionally thin, which pushes routine scalar and
  typed-row flows back to manual dictionary extraction
- schema tooling still lacks a narrow backend-neutral reflection seam
- pooled connection liveness and read-fallback behavior need tighter, more
  explicit failure semantics

Phase 20 addresses those directly rather than widening Arlen into new
backends, ORM abstractions, or a second query language.

## 1.2 Reference Bar

SQLAlchemy Core is the quality reference for a few internal concepts that are
useful here:

- typed bind/result processors
- dialect-aware recursive compilation
- lightweight reflection/introspection
- row/result convenience helpers
- pool liveness checks on checkout

Arlen should adopt those ideas where they improve correctness and ergonomics,
while keeping Objective-C-native, SQL-first contracts.

Phase 20 is explicitly not an API-compatibility effort with SQLAlchemy, and it
does not include ORM features.

## 2. Design Principles

- Keep this Core-like, not ORM-like.
- Preserve `ALNSQLBuilder`, adapters, and explicit SQL as the primary data
  layer.
- Prefer small internal seams over a large new abstraction stack:
  - type codecs
  - recursive dialect compilation
  - narrow reflection contracts
  - result helpers
  - liveness/fallback policy
- Fail closed when a dialect, type mapping, or nested builder feature is not
  honestly supported.
- Keep PostgreSQL first-class while remaining explicit about the supported
  MSSQL subset.
- Preserve deterministic SQL output, generated symbol naming, diagnostics, and
  fixture-driven regression coverage.
- Improve common app flows without forcing users into magic object mapping or
  implicit model lifecycle behavior.

## 3. Scope Summary

1. Phase 20A: typed codec pipeline and live typed-row correctness.
2. Phase 20B: recursive dialect compilation and structural builder cache keys.
3. Phase 20C: lightweight result helpers and contract-aware fetch ergonomics.
4. Phase 20D: lightweight reflection/inspector seam and schema-tooling
   alignment.
5. Phase 20E: connection liveness, safer routing fallback semantics, and
   execution-cache hardening.
6. Phase 20F: docs, examples, conformance expansion, and
   `phase20-confidence`.

## 3.1 Current Delivery Status

- `20A`: complete on 2026-03-26
  - PostgreSQL now materializes the supported scalar baseline as typed
    Objective-C values instead of string-only rows for those columns
  - generated typed row helpers now include
    `decodeTypedFirstRowFromRows:error:`
  - live PostgreSQL coverage now exercises generated typed decode helpers
- `20B`: complete on 2026-03-26
  - nested builders now compile through the active dialect context
  - MSSQL unsupported-feature validation and rewrite behavior now apply inside
    nested subqueries
  - the existing canonical builder-shape compile signature remains the
    structural cache key for PostgreSQL builder compilation reuse
- `20C`: complete on 2026-03-26
  - added explicit first-row and scalar extraction helpers in
    `ALNDatabaseAdapter.h`
  - docs/examples now show typed live-row decode and scalar fetch flows
- `20D-20F`: pending

## 4. Scope Guardrails

- Do not add an ORM, identity map, unit of work, or relationship loader.
- Do not replace `ALNSQLBuilder` with a second public query DSL or a large new
  expression-object universe.
- Do not introduce a broad `MetaData` / `Table` / `Column` authoring layer in
  this phase; reflection is read-oriented and tooling-oriented.
- Do not claim backend transparency beyond what each dialect/compiler path can
  actually guarantee.
- Do not silently coerce unknown database types into surprising Objective-C
  values; unmapped types must remain explicit.
- Do not widen this phase into async drivers, new database families, or admin
  tooling unrelated to the current data-layer seams.
- Do not weaken GNUstep build compatibility or the current deterministic
  testing posture.

## 5. Milestones

The intended delivery slices are:

## 5.1 Phase 20A: Typed Codecs + Live Typed Rows

Status: complete on 2026-03-26

Deliverables:

- Introduce a small dialect type-codec contract for bind values and result
  values.
- Support a required baseline of explicit runtime mappings for:
  - text/string
  - integer / bigint
  - numeric / decimal
  - boolean
  - date / timestamp
  - binary / bytea
  - JSON / JSONB
- Make PostgreSQL row materialization and generated typed decode helpers agree
  end-to-end for supported types.
- Keep unknown or unmapped column types explicit and documented instead of
  silently guessing.
- Add end-to-end regression coverage from live adapter rows into generated
  typed decode helpers.

Acceptance (required):

- generated typed row contracts succeed on real PostgreSQL result sets for the
  supported scalar types
- bind/result behavior is deterministic and documented per dialect
- unsupported or unmapped runtime types fail with explicit diagnostics instead
  of class-mismatch surprises at decode time

## 5.2 Phase 20B: Recursive Dialect Compilation + Structural Cache Keys

Status: complete on 2026-03-26

Deliverables:

- Compile subqueries, CTEs, set operations, and nested builder fragments
  through the active dialect rather than through root-only default rendering.
- Move MSSQL unsupported-feature validation from shallow builder inspection to
  nested dialect-aware compilation paths.
- Add nested conformance fixtures for:
  - pagination
  - `ILIKE` / unsupported operator handling
  - `JOIN ... USING`
  - lateral joins
  - row-locking clauses
  - return-value semantics
- Introduce internal structural compile-cache keys based on builder shape plus
  dialect context where it materially improves reuse.

Acceptance (required):

- unsupported nested PostgreSQL-only constructs fail closed under MSSQL with
  the same clarity as top-level constructs
- dialect adaptation no longer leaves PostgreSQL syntax stranded inside nested
  MSSQL SQL
- compile-cache reuse remains correct for equivalent builder shapes and never
  returns SQL for stale mutable state

## 5.3 Phase 20C: Result Helpers + Contract-Aware Fetch Ergonomics

Status: complete on 2026-03-26

Deliverables:

- Add opt-in result helpers while preserving `NSArray<NSDictionary *>` as the
  base adapter contract.
- Provide small convenience helpers for:
  - scalar queries
  - first-row fetch
  - contract-aware typed-row decode from live results
  - explicit single-column extraction with diagnostics
- If a lightweight row wrapper is introduced, keep it dictionary-backed and
  transparent rather than magical.
- Remove common manual "first row, then index, then cast" flows from examples
  and docs.

Acceptance (required):

- apps can perform common aggregate and single-row flows without open-coded
  index/cast boilerplate
- helpers work with the current adapters/builders and do not introduce model
  lifecycle behavior
- the base adapter API remains backward compatible

## 5.4 Phase 20D: Lightweight Reflection + Schema Tooling Alignment

Deliverables:

- Add a narrow inspector/reflection contract for table metadata sufficient for
  codegen and tooling:
  - columns
  - normalized data type
  - nullability
  - primary-key membership
  - default presence/value shape where feasible
- Implement PostgreSQL inspector support first.
- Ship MSSQL reflection as a documented subset only if it reaches the same
  deterministic contract bar.
- Refactor schema codegen and related tooling to depend on this inspector seam
  instead of embedding backend-specific assumptions in multiple places.
- Add deterministic machine-testable reflection fixtures for the supported
  backends.

Acceptance (required):

- schema codegen consumes one explicit reflection contract instead of ad hoc
  backend-specific assumptions
- reflected metadata is deterministic enough to drive typed contract
  generation reproducibly
- the inspector remains a tooling seam, not a full SQLAlchemy-style metadata
  authoring layer

## 5.5 Phase 20E: Connection Liveness + Safer Routing Failure Semantics

Deliverables:

- Add connection-liveness checking on adapter pool checkout, equivalent in
  spirit to `pre_ping`, with explicit stale-connection recycle behavior.
- Tighten read-routing fallback semantics:
  - move from blanket "retry any read error on writer" behavior to explicit
    policy
  - distinguish replica unavailability from query/contract errors where
    practical
- Improve prepared-statement and execution-cache behavior so saturation or
  reconnect paths degrade predictably:
  - eviction or bounded rotation instead of permanent cache starvation where
    practical
  - explicit diagnostics when execution falls back from prepared to direct
    paths
- Expand fault-injection coverage around:
  - stale pooled connections
  - database restart/reconnect paths
  - replica failure
  - fallback policy decisions

Acceptance (required):

- dead pooled connections are detected before ordinary query execution when the
  liveness feature is enabled
- read fallback does not mask ordinary query, type-contract, or compile-path
  bugs
- cache behavior under saturation and reconnect paths is deterministic and
  observable

## 5.6 Phase 20F: Docs, Examples, + `phase20-confidence`

Deliverables:

- Update:
  - `docs/ARLEN_DATA.md`
  - `docs/GETTING_STARTED_DATA_LAYER.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/SQL_BUILDER_CONFORMANCE_MATRIX.md`
  - `docs/STATUS.md`
- Add focused examples showing:
  - typed fetch flows
  - inspector/codegen usage
  - explicit liveness and routing policy configuration
- Introduce a `phase20-confidence` artifact pack covering:
  - live typed round-trip matrix
  - nested dialect compilation matrix
  - reflection/codegen stability
  - liveness/failover fault scenarios
- Generate machine-readable fixtures for typed codec mappings and reflection
  contracts.

Acceptance (required):

- docs describe the new semantics clearly enough that users do not assume
  ORM-like behavior
- confidence artifacts make regressions in typing, dialect recursion, and
  failover behavior obvious before release
- examples stay small, deterministic, and aligned with the documented
  PostgreSQL-first developer path
