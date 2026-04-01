# Arlen Phase 26 Roadmap

Status: in progress on 2026-04-01 (`26A-26E` complete, `26F-26O` planned)
Last updated: 2026-04-01

Related docs:
- `README.md`
- `docs/README.md`
- `docs/STATUS.md`
- `docs/ARLEN_DATA.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`
- `docs/TESTING_WORKFLOW.md`
- `docs/DATAVERSE.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/PHASE20_ROADMAP.md`
- `docs/PHASE23_ROADMAP.md`

Reference inputs reviewed for this roadmap:
- `docs/ARLEN_DATA.md`
- `docs/PHASE20_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `src/Arlen/Data/ALNDatabaseAdapter.h`
- `src/Arlen/Data/ALNSQLBuilder.h`
- `src/Arlen/Data/ALNSchemaCodegen.m`
- `../PerlDatabaseObjectModel/Database/Metadata/Split.pm`
- `../PerlDatabaseObjectModel/Database/Metadata/TypedDescriptor.pm`
- `../PerlDatabaseObjectModel/Database/Query/Plan.pm`
- `https://guides.rubyonrails.org/active_record_querying.html`
- `https://guides.rubyonrails.org/active_record_migrations.html`
- `https://docs.djangoproject.com/en/5.2/ref/models/querysets/`
- `https://docs.djangoproject.com/en/5.2/topics/migrations/`
- `https://laravel.com/docs/12.x/eloquent`
- `https://laravel.com/docs/12.x/eloquent-relationships`
- `https://docs.sqlalchemy.org/20/orm/session.html`
- `https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html`
- `https://docs.sqlalchemy.org/en/20/core/reflection.html`
- `https://hexdocs.pm/ecto/Ecto.html`
- `https://hexdocs.pm/ecto/Ecto.Changeset.html`
- `https://hexdocs.pm/ecto/Ecto.Multi.html`
- `https://learn.microsoft.com/en-us/ef/core/change-tracking/`
- `https://learn.microsoft.com/en-us/ef/core/querying/related-data/eager`
- `https://www.prisma.io/docs/v6/orm/overview/introduction/what-is-prisma`
- `https://docs.prisma.io/docs/orm/reference/prisma-client-reference`

## 0. Numbering Note

There is no checked-in `Phase 24` or `Phase 25` roadmap in this repository.
This document intentionally reserves `Phase 26` as the next roadmap bucket for
optional ORM work.

## 1. Objective

Add an optional ORM layer to Arlen that sits on top of `ArlenData`, keeps
explicit SQL and `ALNSQLBuilder` first-class, and gives migration-minded teams
a serious ORM path without turning ORM into a framework requirement.

Phase 26 is an additive data-toolkit phase, not a rewrite of Arlen's existing
SQL-first architecture. The result should be:

- an optional `ArlenORM` package layered on `ArlenData`
- deterministic reflection, descriptors, model codegen, and query semantics
- explicit relation loading and transaction scope
- strong PostgreSQL support plus an honest MSSQL capability matrix
- a test suite that can credibly support a "best-in-class optional ORM"
  claim for Arlen's target ecosystem
- a tail set of subphases that extend the ORM model to Dataverse after the SQL
  ORM contracts are stable

## 1.1 Why Phase 26 Exists

Arlen's current data layer is already deep:

- adapters and pooled connections
- a substantial SQL builder and dialect seam
- typed row materialization and result helpers
- schema inspection and typed schema code generation
- multi-target routing and migration tooling

That makes Arlen unusually ready for an ORM layer compared to a framework that
would need to invent its whole SQL toolkit first.

The missing piece is adoption ergonomics for teams coming from Rails, Laravel,
Django, Mojolicious, SQLAlchemy, Ecto, or EF-style application habits. Some of
those teams will not seriously evaluate Arlen unless ORM is available, but
Arlen also cannot afford to let ORM displace its current SQL-first strengths.

Phase 26 exists to solve that tension directly:

- keep SQL-first users first-class
- add ORM as a serious optional layer
- adopt the best ideas from competitor frameworks without copying their worst
  tradeoffs

## 1.2 Reference Bar

Phase 26 should borrow selectively:

- Rails and Laravel:
  - ergonomic associations
  - practical query scopes
  - strict-loading style guardrails against accidental N+1s
- Django:
  - disciplined query composition
  - migration-history safety
  - explicit read-vs-write model evolution rules
- SQLAlchemy:
  - layered Core/ORM architecture
  - relation-loading strategy control
  - backend capability honesty
  - reflection and result/test infrastructure depth
- Ecto:
  - explicit preload discipline
  - changeset-driven mutations
  - explicit transaction composition
- EF Core:
  - short-lived unit-of-work and identity consistency
  - optimistic concurrency patterns
  - value conversion discipline
- Prisma:
  - brownfield introspection/codegen ergonomics
  - generated typed access surfaces

Arlen should not copy:

- hidden global session state
- callback-heavy persistence magic
- template-driven implicit database IO
- a design where ORM is the only ergonomic path
- any pretense that Dataverse is just another SQL dialect

## 1.3 Design Principles

- Keep ORM optional and separately consumable from Arlen core app scaffolds.
- Build ORM on `ArlenData`, not alongside a second persistence stack.
- Preserve `ALNSQLBuilder`, adapters, migrations, and explicit SQL as canonical
  contracts.
- Prefer data-mapper plus explicit context/repository semantics as the core
  design; Active Record-style sugar may exist, but it must remain sugar.
- Make relationship loading explicit:
  - joined
  - select-in
  - raise/no-load
- Default to development-friendly strictness rather than silent lazy-loading
  convenience.
- Separate mutation validation/casting from model instances through a dedicated
  changeset layer.
- Prefer database-first reflection/codegen first, declarative overrides second.
- Keep persistence metadata separate from UI/admin/form metadata.
- Treat PostgreSQL as the reference backend and MSSQL as an explicit supported
  subset that must fail closed where needed.
- Keep Dataverse out of early subphases and add it only after SQL ORM
  semantics are stable.
- Preserve deterministic artifacts, diagnostics, test fixtures, and generated
  naming contracts.

## 2. Scope Summary

1. Phase 26A: package and public-contract foundation.
2. Phase 26B: descriptor, reflection, and codegen foundation.
3. Phase 26C: model runtime and generated SQL-model surface.
4. Phase 26D: query, repository, and scope APIs.
5. Phase 26E: associations and relation metadata.
6. Phase 26F: explicit load plans, strict loading, and N+1 diagnostics.
7. Phase 26G: changesets, casting, converters, and validation.
8. Phase 26H: unit-of-work, identity map, and transaction coordination.
9. Phase 26I: write-graph semantics, optimistic locking, timestamps, and
   upsert.
10. Phase 26J: migration-history safety and schema evolution contracts.
11. Phase 26K: cross-backend SQL ORM parity and integration ergonomics.
12. Phase 26L: ORM-focused regression matrix, performance, and confidence
   lanes.
13. Phase 26M: docs, examples, API reference, and release closeout.
14. Phase 26N: Dataverse descriptor and model bridge.
15. Phase 26O: Dataverse relation loading, mutation semantics, and confidence
   closeout.

## 2.1 Recommended Rollout Order

1. `26A`
2. `26B`
3. `26C`
4. `26D`
5. `26E`
6. `26F`
7. `26G`
8. `26H`
9. `26I`
10. `26J`
11. `26K`
12. `26L`
13. `26M`
14. `26N`
15. `26O`

That order keeps the architecture and descriptor/codegen substrate stable
before Arlen commits to higher-level loading, graph writes, backend parity, and
the Dataverse tail work.

## 3. Scope Guardrails

- Do not introduce a default ORM dependency in core runtime, scaffolds, or
  first-party modules.
- Do not weaken Arlen's SQL-first story or position ORM as the new canonical
  path.
- Do not add template-triggered implicit lazy-loading behavior.
- Do not create a hidden process-global or thread-global ORM session.
- Do not mix persistence metadata with admin/form/navigation metadata.
- Do not require `admin-ui` or any other first-party module to consume ORM.
- Do not widen SQL ORM v1 into polymorphic associations, STI/class-table
  inheritance, or callback-heavy lifecycle automation.
- Do not claim backend transparency where PostgreSQL, MSSQL, and Dataverse
  materially differ.
- Do not add a PDOM import tool; conceptual migration compatibility is enough.
- Do not start Dataverse ORM work until the SQL ORM contracts, tests, and docs
  are stable.

## 4. Milestones

## 4.1 Phase 26A: Package + Public Contract Foundation

Deliverables:

- Add an optional package surface, expected to include an umbrella such as:
  - `src/ArlenORM/ArlenORM.h`
- Add core ORM contracts, expected to include types/protocols such as:
  - `ALNORMContext`
  - `ALNORMRepository`
  - `ALNORMModelDescriptor`
  - `ALNORMFieldDescriptor`
  - `ALNORMRelationDescriptor`
  - `ALNORMChangeset`
- Define adapter seams from ORM into:
  - `ALNDatabaseAdapter`
  - `ALNDatabaseConnection`
  - `ALNSQLBuilder`
  - `ALNDatabaseInspector`
  - `ALNSchemaCodegen`
- Add capability metadata describing ORM support boundaries per backend.

Acceptance (required):

- Arlen builds and boots unchanged when the ORM package is not imported.
- `ArlenORM` can be compiled and tested independently on top of `ArlenData`.
- Public contracts are explicit enough that later subphases do not need to
  backfill a second hidden abstraction layer.

## 4.2 Phase 26B: Descriptor + Reflection + Codegen Foundation

Deliverables:

- Add a deterministic descriptor format for:
  - models/entities
  - fields/columns
  - primary keys
  - foreign keys
  - uniqueness metadata
  - defaults/nullability
  - read-only/view semantics
  - relation candidates
- Add a reflection path that maps database inspection output into ORM
  descriptors.
- Add deterministic generated artifacts such as:
  - manifest JSON under `db/schema/`
  - generated Objective-C model/descriptor helpers under `src/Generated/`
- Add a clean override seam for app-owned descriptor adjustments without
  editing generated files directly.

Acceptance (required):

- A reflected PostgreSQL schema produces stable descriptor artifacts across
  repeated runs.
- View/read-only relations stay read-only in descriptors and generated code.
- Descriptor manifests are versioned so Arlen can evolve the format without
  ambiguity.

## 4.3 Phase 26C: Model Runtime + Generated SQL Models

Deliverables:

- Add a model runtime for typed generated models that can represent:
  - new state
  - loaded state
  - dirty state
  - detached state
- Generate model classes and helpers for the supported descriptor baseline:
  - field constants/helpers
  - typed property accessors
  - primary-key helpers
  - row decode/materialization helpers
  - repository access helpers
- Keep generated model contracts separate from mutation-validation contracts.

Acceptance (required):

- Generated models can materialize from live rows without dictionary-only app
  code.
- Read-only relations do not expose write helpers by default.
- Generated code stays deterministic and compile-valid in focused tests.

## 4.4 Phase 26D: Query + Repository + Scope APIs

Deliverables:

- Add repository/query APIs for common read flows:
  - `get`
  - `find`
  - `all`
  - `first`
  - `count`
  - `exists`
  - delete/update-by-query helpers where honest
- Add reusable scope/query-composition primitives.
- Ensure ORM query composition lowers into inspectable SQL-builder shapes
  rather than hidden query strings.
- Preserve raw escape hatches:
  - direct `ALNSQLBuilder`
  - direct adapter execution
  - direct SQL when needed

Acceptance (required):

- Common read flows are ergonomic without hiding the compiled SQL plan.
- Repository queries can interoperate with app-owned `ALNSQLBuilder`
  composition.
- Unsupported query shapes fail closed with clear diagnostics.

## 4.5 Phase 26E: Associations + Relation Metadata

Deliverables:

- Add first-class association contracts for:
  - `belongsTo`
  - `hasOne`
  - `hasMany`
  - many-to-many
- Support explicit pivot metadata and extra pivot columns.
- Reflect or declare inverse relation metadata where safe and deterministic.
- Add relation helper APIs that can build association-aware query plans without
  forcing immediate loads.

Acceptance (required):

- Basic one-to-one, one-to-many, and many-to-many associations are usable from
  generated descriptors/models.
- Many-to-many relations with extra pivot columns are supported through
  explicit metadata rather than ad hoc app code.
- Relation metadata remains persistence-only and does not absorb admin or form
  concerns.

## 4.6 Phase 26F: Explicit Load Plans + Strict Loading + N+1 Diagnostics

Deliverables:

- Add relation load strategies inspired by SQLAlchemy/Ecto discipline:
  - joined eager loading
  - select-in eager loading
  - no-load / raise-on-access
- Add context-level and query-level strict-loading controls.
- Add query-budget and relation-load tracing for N+1 detection.
- Add deterministic diagnostics that identify:
  - model
  - relation
  - load strategy
  - query-count overrun

Acceptance (required):

- Accessing an unloaded relation in strict mode raises a deterministic ORM
  diagnostic.
- Joined/select-in strategies do not change root-result semantics.
- Query-budget guards catch accidental N+1 regressions in automated tests.

## 4.7 Phase 26G: Changesets + Casting + Converters + Validation

Deliverables:

- Add a changeset layer for mutation workflows:
  - casting input payloads
  - required/nullability checks
  - type coercion
  - dirty-field tracking
  - validation errors without SQL emission
- Add value-converter support for:
  - enums/choices
  - timestamps/dates
  - JSON values
  - array values
  - custom app-owned conversion rules
- Add controlled nested-association mutation support where the graph semantics
  are explicit and bounded.

Acceptance (required):

- Invalid mutations fail before write execution with field-level diagnostics.
- Value converters round-trip through live adapter reads/writes for the
  supported scalar baseline.
- Partial updates only write changed fields unless the app asks for full
  overwrite behavior explicitly.

## 4.8 Phase 26H: Unit of Work + Identity Map + Transaction Coordination

Deliverables:

- Add an explicit `ALNORMContext` or equivalent short-lived unit-of-work
  runtime.
- Add request-scoped identity resolution semantics when enabled by the context.
- Add attach/detach/reload semantics that stay explicit and testable.
- Integrate context-level writes with:
  - adapter transactions
  - savepoints
  - read/write routing where applicable

Acceptance (required):

- Within one context, repeated fetches of the same primary key can resolve to
  one tracked model instance when identity tracking is enabled.
- Context disposal cleanly drops tracking state.
- Transaction helpers compose with existing adapter/savepoint seams.

## 4.9 Phase 26I: Write Graphs + Optimistic Locking + Timestamps + Upsert

Deliverables:

- Add explicit save/delete semantics for the supported mutation baseline.
- Add optimistic locking support using configured version columns.
- Add explicit timestamp automation support for configured created/updated
  fields.
- Add upsert helpers where backend capability metadata says the backend can
  honestly support them.
- Keep graph-save behavior bounded and explicit:
  - no surprise cascading reads
  - no surprise write fanout

Acceptance (required):

- Optimistic-lock conflicts surface as deterministic, typed ORM errors.
- Timestamp automation stays opt-in or explicitly configured.
- Graph writes do not silently load unrelated associations to finish a flush.

## 4.10 Phase 26J: Migration History Safety + Schema Evolution Contracts

Deliverables:

- Add ORM-safe migration guidance and supporting contracts so migrations do not
  depend on current live model code.
- Add descriptor snapshots or migration-local historical contracts for schema
  evolution flows.
- Ensure reflected/generated ORM artifacts cooperate with Arlen's existing SQL
  migration toolchain rather than replacing it.
- Add clear compatibility rules for descriptor-format changes.

Acceptance (required):

- Old migration sequences can be replayed after later model evolution without
  importing current ORM classes directly.
- Schema/codegen drift produces explicit diagnostics rather than undefined
  behavior.
- ORM adoption does not require a second migration system.

## 4.11 Phase 26K: Cross-Backend SQL ORM Parity + Integration Ergonomics

Deliverables:

- Publish an explicit capability matrix for PostgreSQL and MSSQL ORM support.
- Keep PostgreSQL as the reference backend for the full SQL ORM baseline.
- Add a generated or checked-in ORM reference app that demonstrates:
  - HTML-first usage
  - JSON-first usage
  - relation loading
  - transactional writes
  - raw SQL escape hatches
- Add optional integration seams so admin/resource providers can consume ORM
  repositories without requiring ORM.

Acceptance (required):

- PostgreSQL support is broad and documented as the reference path.
- MSSQL support is honest, explicit, and fail-closed for unsupported features.
- Admin/resource registration remains possible with or without ORM.

## 4.12 Phase 26L: ORM Regression Matrix + Performance + Confidence Lanes

Deliverables:

- Add focused ORM test families, expected to include:
  - descriptor/codegen tests
  - query/render snapshot tests
  - relation-loading strategy tests
  - strict-loading and N+1 budget tests
  - changeset/casting tests
  - unit-of-work/identity-map tests
  - migration-history replay tests
  - backend parity tests
  - generated-app tests
  - live-backed optional backend tests
- Add machine-readable artifacts under `tests/fixtures/phase26/`.
- Add focused lane targets, expected to include:
  - `make phase26-orm-unit`
  - `make phase26-orm-integration`
  - `make phase26-orm-generated`
  - `make phase26-orm-backend-parity`
  - `make phase26-orm-perf`
  - `make phase26-orm-live`
  - `make phase26-confidence`
- Add explicit skipped-manifest behavior when optional live backends are not
  configured.

Acceptance (required):

- The ORM regression suite is decomposed enough that new bugs can be captured
  in focused lanes instead of one monolithic target.
- Performance and query-count regressions are visible in CI artifacts.
- Confidence output reports backend capability, skipped requirements, and
  parity results explicitly.

## 4.13 Phase 26M: Docs + Examples + API Reference + Release Closeout

Deliverables:

- Add user-facing docs for:
  - ORM positioning and adoption guidance
  - descriptor/codegen workflow
  - query/load strategy usage
  - changesets and transactions
  - backend capability differences
  - integration with existing SQL-first Arlen apps
- Add at least one SQL ORM reference example app.
- Regenerate API docs for the new public ORM surface.
- Add a machine-readable or checked-in "best-in-class" scorecard that maps
  shipped ORM capabilities against the specific reference bars Arlen chose to
  compete with.

Acceptance (required):

- A new user can understand when to choose raw SQL, `ALNSQLBuilder`, or ORM.
- Example apps and docs are validated in CI.
- Public docs are explicit about ORM being optional and Dataverse support
  arriving only through the tail subphases.

## 4.14 Phase 26N: Dataverse Descriptor + Model Bridge

Deliverables:

- Add a Dataverse ORM descriptor layer that parallels SQL ORM concepts without
  forcing Dataverse through SQL seams.
- Map normalized Dataverse metadata into ORM-friendly descriptors for:
  - entity sets
  - logical names
  - primary id/name fields
  - choices/option sets
  - lookups/navigation metadata
- Add generated Dataverse model/repository surfaces on top of
  `ALNDataverseMetadata` and the existing Dataverse codegen/runtime helpers.
- Add explicit capability metadata that distinguishes Dataverse ORM features
  from SQL ORM features.

Acceptance (required):

- Dataverse models can be generated from metadata without pretending they are
  SQL-backed table objects.
- Unsupported descriptor or relation shapes fail closed with explicit
  diagnostics.
- Dataverse ORM descriptors remain separate from SQL ORM descriptors even where
  the high-level concepts align.

## 4.15 Phase 26O: Dataverse Relations + Mutations + Confidence Closeout

Deliverables:

- Add Dataverse relation-loading semantics for:
  - lookup/reference relations
  - collection/navigation relations
  - explicit `$expand`-backed eager loading where honest
  - explicit multi-request preload plans where `$expand` is not the right tool
- Add Dataverse changeset/value-coercion helpers for:
  - choice values
  - multi-select choices
  - lookup bindings
  - alternate keys where supported
- Add explicit unit-of-work-style composition for Dataverse batch/write flows
  without claiming SQL transaction semantics.
- Add focused Dataverse ORM examples, test fixtures, live-smoke lanes, and
  confidence artifacts.

Acceptance (required):

- Dataverse ORM relation loading is explicit and deterministic.
- Dataverse ORM writes preserve Dataverse-specific payload rules instead of
  hiding them behind false SQL metaphors.
- Optional live confidence lanes validate at least one real Dataverse model
  graph when credentials are configured, and emit explicit skipped manifests
  when they are not.

## 5. Competitor-Inspired Verification Strategy

Phase 26 should carry a deliberately broad verification strategy informed by
the strongest testing ideas from the reviewed frameworks.

## 5.1 Core Test Families

- SQL/render snapshots:
  - inspired by SQLAlchemy Core and Arlen's own SQL-builder conformance work
  - verify deterministic SQL lowering from ORM query objects and load plans
- Loader-strategy matrix:
  - inspired by SQLAlchemy and Ecto
  - verify joined/select-in/raise/no-load behavior across relation shapes
- Strict-loading and lazy-load violation coverage:
  - inspired by Rails strict loading and Laravel lazy-loading prevention
  - ensure accidental lazy loads fail loudly in development-focused modes
- Query-budget and N+1 coverage:
  - inspired by SQLAlchemy requirement discipline plus the PDOM query-plan
    lessons already proven useful
  - assert query counts for representative endpoints and repository flows
- Changeset and mutation validation coverage:
  - inspired by Ecto changesets
  - cover cast errors, nested-association mutation rules, and partial updates
- Unit-of-work and identity-map coverage:
  - inspired by EF Core and SQLAlchemy session testing
  - verify attach/detach/reload, context lifetime, and optimistic locking
- Migration-history replay coverage:
  - inspired by Django migration discipline
  - replay old descriptor snapshots and migration sequences against current code
- Introspection/codegen snapshot coverage:
  - inspired by Prisma and Arlen's existing schema-codegen discipline
  - verify stable manifests and generated Objective-C output
- Backend parity coverage:
  - inspired by SQLAlchemy's backend requirement matrix
  - verify PostgreSQL and MSSQL capability accounting and fail-closed behavior
- Optional live-backed smoke coverage:
  - inspired by Arlen Phase 20 and Phase 23 confidence lanes
  - compile and optionally run live PostgreSQL, MSSQL, and later Dataverse ORM
    smoke paths with explicit skipped manifests

## 5.2 Planned Test Layout

Expected checked-in structure:

- `tests/unit/ORM/`
- `tests/integration/ORM/`
- `tests/shared/ALNORMTestSupport.{h,m}`
- `tests/shared/ALNORMLiveTestSupport.{h,m}`
- `tests/fixtures/phase26/`
- `build/release_confidence/phase26/`

Expected fixture families:

- descriptor manifests
- generated-model snapshots
- loader-plan normalization fixtures
- query-count budget contracts
- backend capability matrices
- migration-history replay fixtures
- performance baselines
- Dataverse ORM characterization artifacts for the tail subphases

## 5.3 Phase 26 Exit Standard

Arlen can claim Phase 26 complete only if:

- non-ORM apps remain unaffected
- the SQL-first path remains first-class and documented
- PostgreSQL ORM support is broad and stable
- MSSQL support is explicit and fail-closed
- relation-loading behavior is deterministic and test-covered
- strict-loading and N+1 controls are operational
- migration-history replay and generated-artifact determinism are verified
- docs/examples/API reference are current
- Dataverse ORM tail phases (`26N-26O`) are either complete or explicitly
  deferred in a way that does not confuse SQL ORM scope

## 6. Phase-Level Acceptance

- Arlen ships a serious optional ORM without converting ORM into a framework
  requirement.
- `ALNSQLBuilder`, adapters, and direct SQL remain fully viable first-class
  paths.
- The ORM architecture is explicit enough that apps can reason about SQL,
  load strategies, and transaction boundaries without hidden runtime magic.
- The phase exits with a robust confidence story, not only feature checkboxes.
- Dataverse ORM support, if delivered through `26N-26O`, is honest about where
  its semantics differ from SQL ORM semantics.

## 7. Explicit Non-Goals

- Replacing the current SQL-first data layer with ORM-only flows.
- Default ORM coupling in core scaffolds, `admin-ui`, or other first-party
  modules.
- Template-driven implicit DB access or automatic lazy-loads from rendering
  surfaces.
- Full callback/lifecycle-magic parity with Rails or Laravel.
- PDOM metadata import tooling.
- Full inheritance/polymorphic-association productization in ORM v1.
- Pretending Dataverse is a SQL adapter or a second SQL dialect.
