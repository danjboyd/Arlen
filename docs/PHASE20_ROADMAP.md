# Arlen Phase 20 Roadmap

Status: Extended (`20A-20K` delivered on 2026-03-26; `20L-20R` planned)
Last updated: 2026-03-27

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
- reflected relation metadata still does not distinguish base tables from views
  when driving write-side codegen
- type semantics remain deeper on PostgreSQL than on MSSQL and still fall back
  to string transport outside the supported scalar subset
- introspection breadth is still narrower than common tooling needs for keys,
  indexes, and relation kinds
- result/execution ergonomics remain intentionally minimal for power-user flows

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
- Borrow SQLAlchemy-style test-infrastructure ideas only at the concept level:
  explicit requirement gating, shared fixtures/harnesses, reusable assertions,
  and backend-focused lanes; keep Arlen on GNUmake + XCTest instead of widening
  Phase 20 into a pytest/nox migration.

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
7. Phase 20G: relation-kind-aware reflection and view-safe schema codegen.
8. Phase 20H: extended type codecs and dialect-aware bind/result parity.
9. Phase 20I: inspector v2 for keys, indexes, and relation metadata.
10. Phase 20J: lightweight result-set objects, batch execution, and savepoint
    ergonomics.
11. Phase 20K: backend parity contracts and MSSQL operational depth baseline.
12. Phase 20L: MSSQL native bind/result transport tightening.
13. Phase 20M: result row ordering and projection semantics.
14. Phase 20N: optional broader reflection depth for cross-backend tooling.
15. Phase 20O: explicit test requirements and environment accounting.
16. Phase 20P: shared test support and disposable backend harnesses.
17. Phase 20Q: SQL/result assertion helpers and unified backend conformance.
18. Phase 20R: focused test topology and confidence-lane decomposition.

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
- `20D`: complete on 2026-03-26
  - added `ALNDatabaseInspector` / `ALNPostgresInspector` as the normalized
    reflection seam for schema tooling
  - `arlen schema-codegen` now consumes inspector output instead of embedding
    PostgreSQL-specific introspection SQL in the CLI path
  - schema manifests now carry `reflection_contract_version` and structured
    `column_metadata`
- `20E`: complete on 2026-03-26
  - `ALNDatabaseRouter` now defaults to connectivity-only read fallback via
    explicit `readFallbackPolicy`
  - `ALNPg` now supports checkout liveness checks, stale idle connection
    recycle behavior, rollback-on-release for leaked transactions, and
    prepared-statement cache eviction
  - capability metadata and routing diagnostics now expose the new fallback
    and liveness semantics explicitly
- `20F`: complete on 2026-03-26
  - added Phase 20 fixtures for reflection and type-codec contracts
  - added `make phase20-confidence` and deterministic artifact generation
    under `build/release_confidence/phase20`
  - refreshed docs/reference coverage for inspector usage, fallback policy,
    liveness controls, and schema-codegen manifest semantics
- `20G`: complete on 2026-03-26
  - preserved `relation_kind` / `read_only` through reflection, manifests, and
    generated helpers
  - reflected views now keep typed row helpers but no longer receive default
    write contracts/builders
  - added fixture + live PostgreSQL coverage for mixed table/view schemas
- `20H`: complete on 2026-03-26
  - added explicit PostgreSQL JSON/array parameter wrappers, bounded
    one-dimensional array decode, and live codec fixture coverage
  - brought MSSQL bind/result handling up to a documented typed common-scalar
    baseline instead of string-only transport for those cases
- `20I`: complete on 2026-03-26
  - widened `ALNDatabaseInspector` to inspector-v2 metadata for relations,
    primary keys, unique constraints, foreign keys, and indexes
  - added deterministic fixtures/tests for the expanded normalized metadata
- `20J`: complete on 2026-03-26
  - added `ALNDatabaseResult` / `ALNDatabaseRow` plus generic
    query-result/scalar/savepoint helpers without changing the underlying
    `NSArray<NSDictionary *>` contract
  - added bounded batch execution helpers on Pg and MSSQL and explicit
    savepoint helpers on both connections
- `20K`: complete on 2026-03-26
  - added explicit backend `support_tier` capability metadata and documented
    savepoint/liveness asymmetry between PostgreSQL, GDL2 fallback, and MSSQL
  - raised MSSQL to a clearer operational subset with checkout liveness checks,
    pooled rollback-on-release behavior, and phase20 confidence artifacts that
    show backend tiers directly
- `20L`: pending
  - tighten MSSQL bind/result transport so the documented common subset is less
    text-only in practice
  - prioritize explicit binary support and native-path handling where ODBC can
    support it honestly
- `20M`: pending
  - preserve result column order in `ALNDatabaseRow` / `ALNDatabaseResult`
  - improve projection semantics without replacing the dictionary-backed base
    contract
- `20N`: pending if broader cross-backend schema tooling becomes a product goal
  - widen reflection only behind explicit scope, starting from concrete
    tooling/reporting needs instead of chasing SQLAlchemy-style metadata breadth
- `20O`: pending
  - replace silent environment-dependent early returns with explicit test
    requirement accounting for live PostgreSQL, MSSQL, driver, and runner
    prerequisites
- `20P`: pending
  - centralize repeated fixture, temp-dir, shell, and unique-name helpers and
    add disposable live-backend harness seams
- `20Q`: pending
  - add shared SQL/result assertion helpers and push overlapping PostgreSQL /
    MSSQL claims onto one reusable conformance surface
- `20R`: pending
  - break large Phase 20-sensitive verification into focused lanes that do not
    depend on the stock `xctest` filter behavior staying usable

## 3.2 Recommended Rollout Order For Remaining Work

The best rollout is to treat the new testing subphases as enabling work for the
remaining implementation slices rather than as post-facto cleanup:

1. `20O`: make backend/toolchain requirements explicit so local and CI runs stop
   reporting false-green coverage when a DSN, driver, or capability is absent.
2. `20P`: extract common test support and disposable backend harnesses before
   adding more live coverage or more follow-on data-layer code.
3. `20Q`: add reusable SQL/result assertions and unified backend conformance so
   `20L` and `20M` land on stronger, shared regression surfaces.
4. `20L`: tighten MSSQL native bind/result transport on top of the improved
   harness and conformance layers.
5. `20M`: change row-order/projection semantics only once assertion helpers can
   verify ordered-column behavior directly.
6. `20R`: decompose the remaining verification into focused lanes / bundles /
   confidence paths so follow-on Phase 20 work no longer depends on broad suite
   blast radius or the current stock `xctest` filtering limitations.
7. `20N`: keep broader reflection explicitly conditional and out of the critical
   path unless cross-backend tooling becomes a real product goal.

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

Status: complete on 2026-03-26

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

Status: complete on 2026-03-26

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

Status: complete on 2026-03-26

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

## 5.7 Phase 20G: Relation-Kind-Aware Reflection + View-Safe Codegen

Status: complete on 2026-03-26

Deliverables:

- Extend the normalized reflection contract to preserve relation kind for each
  reflected object:
  - base table
  - view
  - materialized view only if the backend can identify it deterministically
- Thread relation kind through:
  - `ALNDatabaseInspector`
  - schema-codegen manifests
  - generated helper decisions
- Make write-side schema codegen honest by default:
  - do not emit misleading insert/update contract helpers for reflected views
    unless a backend-specific writable-view mode is explicitly supported and
    documented
  - preserve read-side typed row generation for views
- Add fixture and live coverage for mixed table/view schemas so relation-kind
  regressions are caught before release.

Acceptance (required):

- reflected views no longer receive default write contracts that imply base
  table semantics
- relation kind is preserved end-to-end in the reflection contract and manifest
- ordinary base-table codegen remains backward compatible

## 5.8 Phase 20H: Extended Type Codecs + Dialect-Aware Bind/Result Parity

Status: complete on 2026-03-26

Deliverables:

- Refactor the current adapter-specific type handling into a small explicit
  codec registry seam per dialect.
- Extend the supported typed subset in a bounded way beyond the current scalar
  baseline:
  - UUID
  - bounded array support for supported scalar element types where practical
  - backend-native date/time and decimal behavior aligned with documented
    precision/shape semantics
- Stop treating collection values as implicit JSON when a dialect-specific
  non-JSON codec applies.
- Bring MSSQL bind/result behavior up to a documented typed baseline for the
  same common scalar subset where the transport allows it.
- Add deterministic fixture coverage for supported-type round trips and explicit
  unsupported-type diagnostics per dialect.

Acceptance (required):

- supported common types round-trip predictably across PostgreSQL and MSSQL for
  the documented subset
- unsupported types stay explicit and diagnostic rather than silently
  stringifying into surprising contracts
- codec behavior is documented as a dialect contract instead of being inferred
  from scattered adapter code paths

## 5.9 Phase 20I: Inspector V2 for Keys, Indexes, + Relation Metadata

Status: complete on 2026-03-26

Deliverables:

- Widen the reflection seam with a bounded inspector v2 surface for:
  - primary-key shape
  - unique constraints
  - foreign keys
  - indexes
  - relation kind / read-only hints
- Keep the inspector read-oriented and deterministic:
  - no schema authoring DSL
  - no mutable metadata graph
  - no ORM-style table objects
- Add normalized machine-readable fixtures for the new inspector contracts.
- Expose enough metadata for audit tooling and codegen/reporting without
  forcing callers back to raw backend SQL for common questions.

Acceptance (required):

- tooling can answer common structure questions without bespoke reflection SQL
- fixture ordering and normalized payload shapes remain deterministic
- the expanded inspector surface remains narrow and clearly non-ORM

## 5.10 Phase 20J: Result Objects + Execution Ergonomics

Status: complete on 2026-03-26

Deliverables:

- Add a lightweight result wrapper on top of the existing row arrays, with
  focused helpers for:
  - `first`
  - `one`
  - `oneOrNil`
  - `scalar`
  - mapping-backed row access without replacing the underlying dictionary
    contract
- Add bounded batch execution helpers for repeated parameter sets where the
  adapter can support them honestly.
- Add explicit savepoint helpers to the public transaction surface where the
  backend supports them.
- Keep streaming cursors, ORM-style identity tracking, and lazy unit-of-work
  behavior out of scope for this phase.

Delivered:

- added `ALNDatabaseResult` and `ALNDatabaseRow` on top of row arrays, with
  `first`, `one`, `oneOrNil`, `scalarValueForColumn:error:`, keyed row access,
  and dictionary passthrough
- added generic helpers
  `ALNDatabaseExecuteQueryResult`, `ALNDatabaseExecuteCommandBatch`,
  `ALNDatabaseCreateSavepoint`, `ALNDatabaseRollbackToSavepoint`,
  `ALNDatabaseReleaseSavepoint`, and `ALNDatabaseWithSavepoint`
- exposed concrete convenience methods on `ALNPg`, `ALNPgConnection`,
  `ALNMSSQL`, and `ALNMSSQLConnection` for result objects, bounded batch
  execution, and savepoints
- kept the underlying `NSArray<NSDictionary *>` execution contract unchanged

Acceptance (required):

- common single-row and scalar flows no longer require manual array/dictionary
  unpacking in user code
- supported adapters expose savepoint behavior explicitly rather than forcing
  nested-transaction users back to raw SQL
- the existing `NSArray<NSDictionary *>` contract remains supported and
  documented

## 5.11 Phase 20K: Backend Parity Contracts + MSSQL Operational Baseline

Status: complete on 2026-03-26

Deliverables:

- Define explicit support tiers per backend in capability metadata and docs:
  - first-class
  - supported subset
  - unavailable at build time
- Raise MSSQL toward a minimum operational parity bar for the documented subset:
  - typed scalar bind/result handling
  - checkout liveness checks where transport support is present
  - clearer diagnostics and confidence coverage for builder execution paths
- Add backend-split confidence artifacts so PostgreSQL-first depth and MSSQL
  subset guarantees are independently visible.
- Tighten docs and release gates so unsupported or unavailable MSSQL features
  fail loudly instead of reading like silent omissions.

Delivered:

- added `support_tier`, savepoint, batch, result-wrapper, and liveness
  metadata to the shipped backend capability contracts
- marked PostgreSQL as `first_class`, GDL2 fallback as `supported_subset`,
  MSSQL as `supported_subset` when ODBC transport is present, and
  `unavailable_at_build_time` when it is not
- added MSSQL pooled checkout liveness checks plus rollback-on-release of
  active pooled transactions so the documented subset is operationally less
  surprising
- extended `phase20-confidence` with `backend_support_matrix_snapshot.json`
  so PostgreSQL depth and MSSQL/GDL2 subset guarantees are visible alongside
  the reflection/type-codec artifacts

Acceptance (required):

- users can tell from docs and capability metadata what each backend actually
  guarantees
- MSSQL subset behavior is explicit, testable, and operationally less
  surprising
- PostgreSQL remains first-class without hiding backend asymmetry

## 5.12 Phase 20L: MSSQL Native Bind/Result Transport Tightening

Status: planned

Deliverables:

- Reduce text-only transport on the supported MSSQL path where ODBC can support
  a more honest native bind/fetch mode.
- Add explicit support for the highest-value missing transport cases first:
  - binary / `NSData` bind and result handling
  - native-path bind/fetch coverage for the documented common scalar subset
- Keep unsupported parameter/result families explicit:
  - do not silently invent array semantics for MSSQL
  - do not broaden the supported subset without docs and coverage
- Expand DSN-gated MSSQL coverage so the supported subset is proven by live
  execution instead of only inferred from conversion helpers.

Acceptance (required):

- documented supported MSSQL types no longer depend entirely on text transport
  where the driver can support a native path
- binary payloads round-trip predictably for the documented subset
- unsupported MSSQL shapes still fail with explicit diagnostics instead of
  silent stringification

## 5.13 Phase 20M: Result Row Ordering + Projection Semantics

Status: planned

Deliverables:

- Preserve query column order in `ALNDatabaseRow` / `ALNDatabaseResult` instead
  of alphabetizing row keys for presentation.
- Add a small amount of extra result ergonomics only where it improves
  correctness expectations:
  - stable ordered column names
  - optional ordered row access helpers if needed
- Keep the underlying `NSArray<NSDictionary *>` execution contract intact.
- Keep streaming cursors, tuple-model APIs, and ORM-style row objects out of
  scope.

Acceptance (required):

- `ALNDatabaseRow.columns` reflects select-list order rather than sorted key
  order
- existing dictionary-backed access remains backward compatible
- common scalar and single-row helpers continue to work without new magic

## 5.14 Phase 20N: Optional Broader Reflection Depth for Cross-Backend Tooling

Status: planned only if cross-backend schema tooling becomes a product goal

Deliverables:

- Decide explicitly whether reflection remains PostgreSQL-first tooling or grows
  into a wider backend contract.
- If broader tooling is required, widen the reflection contract in a bounded
  way around concrete needs such as:
  - schema enumeration
  - check constraints
  - view definitions
  - comments or other audit-relevant metadata
- Define the backend bar before adding more codegen promises:
  - do not advertise cross-backend reflection unless at least one non-Postgres
    backend reaches the same deterministic contract quality
- Keep full SQLAlchemy-style metadata graphs, schema authoring objects, and ORM
  behavior out of scope.

Acceptance (required):

- docs stay explicit about whether reflection is PostgreSQL-only or truly
  cross-backend
- any widened reflection payload remains deterministic and tooling-oriented
- schema/codegen promises do not outrun the actual supported backend contracts

## 5.15 Phase 20O: Explicit Test Requirements + Environment Accounting

Status: planned

Deliverables:

- Introduce a small Objective-C-native test-requirements layer for live and
  environment-sensitive coverage:
  - PostgreSQL DSN availability
  - MSSQL DSN availability
  - driver/transport availability
  - savepoint/liveness capability availability where applicable
  - optional filter-capable runner availability
- Replace silent environment-dependent `return` patterns in live tests with
  explicit requirement accounting and deterministic skip/reporting behavior.
- Separate coverage expectations more clearly across:
  - pure unit / fixture-backed tests
  - live backend tests
  - runner/toolchain-sensitive tests
- Keep GNUmake + XCTest as the supported harness; do not widen this slice into a
  Python test-runner migration.

Acceptance (required):

- DSN-gated and driver-gated tests no longer appear to pass silently when their
  prerequisites are absent
- local and CI output make it obvious which backend-sensitive coverage ran vs.
  skipped and why
- follow-on verification for `20L` / `20M` can declare concrete prerequisites
  instead of relying on incidental environment knowledge

## 5.16 Phase 20P: Shared Test Support + Disposable Backend Harnesses

Status: planned

Deliverables:

- Introduce shared test support for repeated helpers such as:
  - repo-root resolution
  - fixture JSON loading
  - temp directory / temp file creation
  - shell capture
  - deterministic unique-name generation
  - common cleanup helpers
- Add disposable live-backend harness seams where the backend can support them
  honestly:
  - predictable temporary schema/table namespace setup
  - deterministic teardown on PostgreSQL and MSSQL
- Move obvious repeated helper code out of the large Phase 20-sensitive test
  files and into shared support seams.
- Preserve explicit, deterministic fixtures and avoid introducing a large magic
  meta-test DSL.

Acceptance (required):

- repeated helper logic in Phase 20-sensitive unit/integration tests is
  materially reduced
- live backend tests set up and tear down their own namespace predictably
- adding a new live regression no longer requires re-copying fixture/temp-dir/
  shell helper code into another test file

## 5.17 Phase 20Q: SQL/Result Assertion Helpers + Unified Backend Conformance

Status: planned

Deliverables:

- Add shared assertion helpers for:
  - SQL text snapshots / normalization where applicable
  - placeholder numbering and parameter arity
  - ordered result-column expectations
  - typed scalar / row materialization
  - explicit diagnostics/error-message expectations
- Lift current ad hoc SQL-builder and adapter checks into reusable conformance
  helpers/fixtures rather than scattering `containsString:` and one-off
  equality checks everywhere.
- Expand backend parity coverage so PostgreSQL and MSSQL run the same in-scope
  contract cases where Arlen claims overlapping support.
- Add deterministic seam/mock regressions for failure branches that are hard to
  hit reliably through live databases alone, such as disconnect classification,
  rollback-on-release, stale-checkout recycle, and codec fallback behavior.

Acceptance (required):

- SQL/result regressions fail with precise shared assertions instead of only
  scattered one-off checks
- overlapping PostgreSQL / MSSQL parity claims are proven by one reusable
  conformance surface
- hard-to-reach failure paths have deterministic unit coverage in addition to
  live backend runs

## 5.18 Phase 20R: Focused Test Topology + Confidence-Lane Decomposition

Status: planned

Deliverables:

- Break large Phase 20-sensitive verification into focused execution targets,
  bundles, or confidence lanes such as:
  - SQL builder / dialect compilation
  - PostgreSQL live data-layer coverage
  - MSSQL live data-layer coverage
  - schema codegen / reflection contracts
  - routing/pool/result-wrapper durability
- Stop relying solely on the current stock `xctest` filter behavior for focused
  reruns; add repo-native focused make targets or smaller bundles that remain
  deterministic on the Debian baseline runner.
- Extend confidence-path documentation and scripts so the remaining Phase 20
  follow-ons have narrow verification commands rather than broad suite blast
  radius.
- Keep the broad `test-unit` / `test-integration` runs intact as the umbrella
  regression pass.

Acceptance (required):

- targeted reruns for `20L` / `20M` no longer depend on unrelated unit failures
- CI can execute backend-focused and pure-unit lanes independently
- follow-on Phase 20 verification becomes faster and more legible without
  weakening full-suite regression coverage
