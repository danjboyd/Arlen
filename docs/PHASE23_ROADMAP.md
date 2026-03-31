# Arlen Phase 23 Roadmap

Status: planned
Last updated: 2026-03-31

Related docs:
- `docs/STATUS.md`
- `docs/ARLEN_DATA.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`
- `docs/CONFIGURATION_REFERENCE.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/PLUGIN_SERVICE_GUIDE.md`
- `docs/DOCUMENTATION_POLICY.md`
- `docs/PHASE17_ROADMAP.md`
- `docs/PHASE20_ROADMAP.md`

Reference inputs reviewed for this roadmap:
- `../PerlDatabaseObjectModel/Database/DataSource/Dataverse.pm`
- `../PerlDatabaseObjectModel/OData/Abstract.pm`
- `https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/overview`
- `https://learn.microsoft.com/en-us/power-apps/developer/data-platform/work-with-data`

## 1. Objective

Add a runtime-inactive-by-default Dataverse integration to Arlen that feels
native to the framework without forcing Dataverse through the SQL-only seams in
the current data layer.

Phase 23 is an integration-surface phase, not a module phase and not a generic
database-abstraction rewrite. The result should be:

- a first-class Dataverse Web API client/toolkit in Arlen
- explicit opt-in app/runtime wiring
- no startup or config burden for apps that do not use Dataverse
- no pretense that Dataverse is just another SQL dialect

## 1.1 Why Phase 23 Exists

Arlen's current data layer is mature enough to support multiple SQL backends,
but it is still intentionally SQL-shaped:

- `ALNDatabaseAdapter` centers on SQL strings, pooled connections, and
  transaction callbacks
- `ALNSQLBuilder` is the primary composition surface for SQL backends
- runtime/config docs still frame persistence around relational database
  targets

That is the right shape for PostgreSQL and MSSQL, but it is the wrong primary
shape for Dataverse.

The production Perl reference reinforces that point. The stable path there is
not "Dataverse pretending to be SQL"; it is a dedicated Dataverse datasource
plus an OData-oriented query builder. Arlen should borrow that lesson directly
instead of trying to force Dataverse into the `ALNDatabaseAdapter` /
`ALNSQLBuilder` contract.

Phase 23 exists to introduce that separate but Arlen-native integration seam.

## 1.2 Design Principles

- Target the Dataverse Web API/OData surface, not Microsoft Graph as the
  primary application contract.
- Keep the feature compiled in but runtime-inactive by default.
- Do not require a module install or a compile-time feature flag for ordinary
  use.
- Reuse Arlen patterns where they still fit:
  - capability metadata
  - deterministic code generation
  - explicit diagnostics
  - named targets/config
- Do not force Dataverse into SQL transactions, migrations, or dialect
  semantics that the platform does not honestly provide.
- Preserve raw escape hatches for Dataverse-specific operations such as custom
  actions/functions and request details that do not belong in the fluent
  builder.
- Keep the first authentication slice server-side and practical:
  - client credentials first
  - pluggable token-provider seam
- Preserve GNUstep/Foundation compatibility and deterministic tests.

## 2. Scope Summary

1. Phase 23A: core client, auth, transport, and inactive-by-default wiring.
2. Phase 23B: OData query builder and read-path correctness.
3. Phase 23C: write semantics, lookup bindings, choices, and batch flows.
4. Phase 23D: metadata inspection and deterministic typed code generation.
5. Phase 23E: Arlen runtime/config ergonomics and example integration path.
6. Phase 23F: reliability, diagnostics, and confidence lanes.
7. Phase 23G: docs, reference updates, and release closeout.

## 2.1 Recommended Rollout Order

1. `23A`
2. `23B`
3. `23C`
4. `23D`
5. `23E`
6. `23F`
7. `23G`

That order keeps the transport/auth baseline in place before Arlen commits to
query composition, write semantics, codegen, and public docs/examples.

## 3. Scope Guardrails

- Do not model Dataverse as a generic SQL adapter behind
  `ALNDatabaseAdapter`.
- Do not claim transaction guarantees that Dataverse does not honestly expose.
- Do not widen this phase into a full admin UI, search product, or sync engine.
- Do not require a new module lifecycle for Dataverse adoption.
- Do not add compile-time feature fragmentation to the public API surface.
- Do not make generated code mandatory for basic use; codegen is an ergonomic
  layer, not the only path.
- Do not promise FetchXML, TDS/SQL endpoint, change tracking orchestration, or
  file/image-column productization in the initial phase unless an earlier
  subphase proves they are required.
- Do not introduce Graph-specific abstractions unless a later requirement
  actually needs them.

## 4. Milestones

## 4.1 Phase 23A: Core Client + Auth + Runtime-Inactive Defaults

Deliverables:

- Add a low-level Dataverse client surface, expected to include types such as:
  - `ALNDataverseClient`
  - `ALNDataverseRequest`
  - `ALNDataverseResponse`
  - `ALNDataverseError` / structured error user-info contracts
- Add an auth/token-provider seam for client-credentials-first usage.
- Add capability metadata describing support boundaries such as:
  - read/write support
  - batch support
  - lookup binding support
  - option-set/choice support
  - transaction support (`NO`)
- Define optional config conventions for named Dataverse targets without making
  them part of the default app path.
- Ensure Arlen runtime/config loading ignores Dataverse-specific settings
  cleanly when they are absent.

Acceptance (required):

- Arlen builds and boots unchanged when no Dataverse target is configured.
- A stubbed or smoke-tested connectivity flow can authenticate and execute a
  minimal Dataverse request.
- The public integration shape does not require a module install or compile-time
  enablement switch.

## 4.2 Phase 23B: OData Query Builder + Read Path

Deliverables:

- Add an OData-native composition surface, expected to cover:
  - `$select`
  - `$filter`
  - `$orderby`
  - `$top`
  - `$skip`
  - `$count`
  - `$expand`
- Support deterministic filter composition for common operators:
  - equality/inequality
  - comparison operators
  - null tests
  - `in` / expanded-or fallback
  - common text matching
- Add result paging helpers for `@odata.nextLink`.
- Add formatted-value opt-in and normalized row materialization.
- Keep a raw-request/raw-query escape hatch for cases the fluent builder does
  not yet cover.

Acceptance (required):

- Common list/detail reads can be expressed without hand-building query URLs.
- Read-path tests cover deterministic builder output and multi-page iteration.
- Unsupported or ambiguous query constructs fail closed with explicit
  diagnostics.

## 4.3 Phase 23C: Write Semantics + Dataverse-Specific Mutations

Deliverables:

- Add helpers for:
  - create
  - update
  - delete
  - alternate-key addressing and upsert where the API supports it
- Add lookup-binding helpers so callers do not hand-assemble
  `@odata.bind` payloads for common cases.
- Add option-set / choice coercion helpers for single-select and
  multi-select fields.
- Add batch-request support for grouped write flows.
- Add a generic custom action/function invocation escape hatch.

Acceptance (required):

- Common create/update/delete flows are ergonomic without hiding Dataverse's
  platform-specific payload rules.
- Alternate-key, lookup-binding, and choice coercion behavior each have
  regression coverage.
- Batch and custom-operation surfaces exist without pretending they are SQL
  transactions.

## 4.4 Phase 23D: Metadata Inspection + Typed Code Generation

Deliverables:

- Add Dataverse metadata inspection for:
  - entity sets
  - attributes/columns
  - lookups/navigation metadata
  - choices/option sets
  - primary id/name fields
- Add deterministic code generation for typed helpers such as:
  - logical/entity-set names
  - field-name constants/helpers
  - lookup metadata helpers
  - choice/option-set enums or mappings
  - typed record wrappers or decode helpers
- Add machine-readable generated manifests similar in spirit to Arlen's SQL
  schema artifacts.

Acceptance (required):

- A caller can generate typed Dataverse helpers from live metadata.
- Generated artifacts materially reduce stringly-typed logical-name usage.
- Fixture-backed metadata/codegen tests exist alongside gated live verification.

## 4.5 Phase 23E: Runtime Ergonomics + Example Integration Path

Deliverables:

- Add explicit app/runtime wiring for named Dataverse targets or services.
- Define a recommended config shape for Dataverse targets that remains
  dormant unless populated.
- Add service-registration or retrieval helpers so Dataverse clients are easy
  to reach from normal Arlen app code.
- Add an example integration path demonstrating:
  - config
  - client acquisition
  - one read flow
  - one write flow
  - one metadata/codegen flow

Acceptance (required):

- An app can opt into Dataverse with minimal boilerplate.
- Apps that do not use Dataverse pay no new startup or config complexity cost.
- The example path is deterministic and reflects the recommended production
  shape.

## 4.6 Phase 23F: Reliability + Diagnostics + Confidence

Deliverables:

- Add retry/throttling handling for bounded transient failures, including:
  - `429`
  - `Retry-After`
  - selected retryable transport failures
- Add structured diagnostics for:
  - request method/path/query shape
  - status code
  - retry decisions
  - Dataverse correlation/request identifiers where available
- Add a fixture-backed transport stub/harness for deterministic failure-path
  coverage.
- Add gated live confidence lanes for:
  - authentication
  - paging
  - writes
  - metadata/codegen smoke validation

Acceptance (required):

- Throttling/service-protection behavior is explicit and test-covered.
- Diagnostics are sufficient to debug ordinary Dataverse failures without
  packet capture or ad hoc logging patches.
- Confidence lanes distinguish fixture-only guarantees from live-environment
  guarantees.

## 4.7 Phase 23G: Docs + Release Closeout

Deliverables:

- Update summary surfaces and add Dataverse-specific user docs covering:
  - what the feature is
  - how it differs from the SQL adapters
  - how runtime-inactive defaults work
  - the supported v1 subset
  - the recommended app wiring path
- Update API/reference surfaces for the new public types.
- Add a short example-driven getting-started flow.
- Close the phase with updated roadmap/status summary surfaces and documented
  confidence gates.

Acceptance (required):

- Users can discover the Dataverse path without confusing it with modules,
  compile-time feature flags, or SQL adapters.
- Docs clearly separate shipped guarantees from deferred Dataverse depth.
- The phase closes with docs, examples, and test coverage aligned.

## 5. Exit Criteria

Phase 23 is complete when:

1. Arlen ships a compiled-in but runtime-inactive-by-default Dataverse
   integration surface with no default-path regression for non-Dataverse apps.
2. Common read and write flows work through Arlen-native APIs without forcing
   callers to hand-assemble most Dataverse/OData details.
3. Metadata inspection and deterministic typed helper generation exist for the
   supported v1 slice.
4. Reliability, diagnostics, and confidence lanes are strong enough for real
   early-adopter use.
5. Public docs explain the Dataverse path clearly and truthfully.

## 6. Explicit Non-Goals

- Full Microsoft Graph abstraction or Graph-first Dataverse integration.
- Treating Dataverse as a generic SQL backend or adding fake transaction
  semantics.
- First-phase support for Dataverse search as a separate product surface.
- First-phase change-tracking synchronization orchestration.
- Full FetchXML builder parity.
- TDS/SQL endpoint integration.
- File/image-column productization.
- Admin UI productization for Dataverse-backed resources.
