# ArlenORM Guide

`ArlenORM` is Arlen's optional ORM layer on top of `ArlenData`.

Import the ORM umbrella when you want reflected descriptors, generated SQL
models, repositories, and association metadata without giving up direct
`ALNSQLBuilder` or direct adapter access:

```objc
#import "ArlenORM/ArlenORM.h"
```

`ArlenORM` is intentionally not part of `Arlen/Arlen.h`. Apps that do not want
an ORM do not pay an API-shape cost for it.

## Scope Today

Phase `26A-26O` is complete:

- optional package surface via `src/ArlenORM/ArlenORM.h`
- descriptor contracts for fields, models, relations, uniqueness, and
  read-only/view semantics
- schema-to-descriptor reflection and deterministic codegen rendering
- generated SQL-model contracts on top of `ALNORMModel`
- repository/query APIs on top of `ALNSQLBuilder`
- first-class `belongs_to`, `has_one`, `has_many`, and many-to-many relation
  metadata with explicit pivot fields
- explicit joined/select-in/no-load/raise-on-access relation load plans
- query-level and context-level strict-loading controls plus query-budget
  diagnostics
- `ALNORMChangeset`, `ALNORMValueConverter`, and `ALNORMWriteOptions` for
  converter-backed casting, validation, and writes
- request-scoped unit-of-work behavior with identity tracking, reload/detach,
  and transaction/savepoint coordination
- save/delete/upsert helpers with opt-in optimistic locking, timestamps, and
  explicit belongs-to graph-save behavior
- insert/upsert helpers now preserve explicitly assigned primary keys and
  hydrate database-generated primary keys on adapters that expose
  `returning_mode` (`RETURNING` / `OUTPUT`) before dependent writes in the same
  unit of work
- descriptor snapshots and schema/codegen drift diagnostics for
  migration-history safety
- explicit backend capability matrices and admin/resource integration helpers
- split confidence lanes for unit, generated, integration, backend parity,
  perf, live, and full release confidence artifacts
- separate Dataverse ORM descriptors, context, model, repository, and
  changeset contracts for lookup relations, reverse collections, writes, and
  batch flows

## Public Contracts

The main public types are:

- `ALNORMContext`
- `ALNORMRepository`
- `ALNORMQuery`
- `ALNORMModel`
- `ALNORMFieldDescriptor`
- `ALNORMRelationDescriptor`
- `ALNORMModelDescriptor`
- `ALNORMChangeset`
- `ALNORMValueConverter`
- `ALNORMWriteOptions`
- `ALNORMCodegen`
- `ALNORMTypeScriptCodegen`
- `ALNORMDescriptorSnapshot`
- `ALNORMSchemaDrift`
- `ALNORMAdminResource`
- `ALNORMDataverseFieldDescriptor`
- `ALNORMDataverseRelationDescriptor`
- `ALNORMDataverseModelDescriptor`
- `ALNORMDataverseCodegen`
- `ALNORMDataverseContext`
- `ALNORMDataverseModel`
- `ALNORMDataverseChangeset`
- `ALNORMDataverseRepository`

These layer directly onto existing `ArlenData` seams:

- `ALNDatabaseAdapter`
- `ALNDatabaseConnection`
- `ALNSQLBuilder`
- `ALNDatabaseInspector`
- `ALNSchemaCodegen`

## Reflection and Codegen

`ALNORMCodegen` consumes normalized schema metadata and returns deterministic
artifacts:

- descriptor objects for runtime use
- a versioned manifest string (`format: arlen-orm-descriptor-v1`)
- generated Objective-C header/implementation source strings
- suggested output paths under `db/schema/` and `src/Generated/`

Current output contracts keep reflected read-only relations read-only by
default in generated models. Historical SQL descriptor snapshots are serialized
through `ALNORMDescriptorSnapshot`, and `ALNORMSchemaDrift` fails closed when
current descriptors diverge from a checked-in history contract.

### Concurrent first use

Generated SQL models initialize each class's descriptor exactly once with
`dispatch_once`. Concurrent first callers receive the same fully initialized,
strongly retained descriptor, without application warm-up. Generated source
imports libdispatch explicitly; the supported Arlen toolchains already provide it.

To adopt the initialization fix, regenerate existing model implementations via
`ALNORMCodegen renderArtifactsFromSchemaMetadata:classPrefix:error:` (or the
variant accepting overrides), then rebuild the application. See the
[migration note](ARLEN_ORM_MIGRATIONS.md#generated-descriptor-initialization-update).
Model/context mutation still follows its existing ownership contract.

### SQL property names

SQL codegen reserves ORM lifecycle/runtime names, standard NSObject names,
Objective-C method families and language keywords. Conflicting properties get a
`Value` suffix (`State` → `stateValue`, `Description` → `descriptionValue`).
Names that would remain in an ARC method family use a `field` prefix instead
(`new` → `fieldNew`). Existing field/column names and explicit aliases are reserved
before allocation; a collision adds a suffix starting at `2`. For example, with
`State` and `state_value`, the former becomes `stateValue2`. Allocation is stable
when schema metadata input order is reversed.

Only `propertyName` changes: `State` still has logical field name `state` and SQL
column name `State`. Queries, relationship keys and column/field lookup retain
those names. `objectForPropertyName:` and generated accessors use the alias.
The manifest records all three names. Case-folded logical field collisions are
rejected, as are duplicate generated helper selectors.

For a stable application-specific API, pass an entity override to the existing
`descriptorOverrides:` codegen methods:

```objc
@{ @"public.tax_rates": @{
    @"property_names": @{ @"State": @"taxState" }
} }
```

Keys inside `property_names` are exact SQL column names. Unknown columns,
reserved/invalid aliases and aliases overlapping another field, column or
property produce an error identifying the entity and offending mapping.
The reserved-name contract is fixed rather than discovered from host categories;
applications adding methods to generated models must choose nonconflicting names.
See [migration notes](ARLEN_ORM_MIGRATIONS.md#generated-property-naming-update)
before regenerating existing models.

### Quoted SQL identifiers

SQL ORM descriptors preserve physical schema, table, and column names exactly,
including case, spaces, punctuation, embedded quotes, and leading/trailing
whitespace. Supply the original name as metadata (`Target ID`), without adding
SQL quote delimiters. Empty names and names containing NUL are rejected.
Generated properties use deterministic ASCII aliases: `Target ID` becomes
`targetId`, `Unit/Well Notes` becomes `unitWellNotes`, and `State` retains its
reserved-name alias `stateValue`. Existing ordinary names keep their generated APIs.

`property_names` changes only the Objective-C property. If distinct SQL columns
normalize to the same logical field (for example `Unit Name` and `Unit_Name`),
codegen fails with `ALNORMErrorIdentifierCollision`. Resolve that ambiguity with
an exact-column `field_names` override; schema renames are unnecessary:

```objc
@{ @"ot.CompulsoryUnitProjects": @{
    @"field_names": @{ @"Unit_Name": @"alternateUnitName" },
    @"property_names": @{ @"Target ID": @"legacyId" }
} }
```

`field_names` sets the logical query/relationship field and its default property;
`property_names` can then provide a separate nonreserved accessor. Both mappings
must use known exact SQL column keys and valid, unambiguous aliases. Primary and
foreign keys reflected from physical metadata resolve to the resulting logical
fields. Explicit relation overrides should use those logical field names.

The ORM encodes each physical component before passing it to the SQL builder.
The builder parses qualified identifier paths into components and quotes each
component for the selected dialect, doubling embedded delimiters. A literal dot
inside a name remains part of that name. Descriptor `schemaName`, `tableName`,
and `columnName` retain raw names; `entityName` and `qualifiedTableName` encode
components requiring quotes, e.g. `legacy."Project.Table"`. Use this encoded
entity name as the descriptor override key. Ordinary entity keys are unchanged.

These names are trusted schema/descriptor data. Resolve request-selected fields
through model descriptors or an application allowlist; do not build physical
identifiers from arbitrary request input. Identifier APIs never evaluate names
as SQL expressions. Values remain bound parameters. Existing explicit trusted
expression APIs retain their trust contract.

PostgreSQL coverage includes insert/generated-key hydration, find, query,
changeset update, reload, delete, upsert, composite keys, and joined relations.
MSSQL identifier/OUTPUT compilation is regression-tested; live quoted-name
persistence qualification in this change is PostgreSQL-only.

Phase `28A-28D` adds a first consumer-contract bridge for React / TypeScript
apps without making TypeScript the canonical ORM source. `ALNORMTypeScriptCodegen`
consumes:

- checked-in ORM descriptor manifests
- raw schema metadata (via `ALNORMCodegen`)
- exported OpenAPI JSON

and emits a generated TypeScript package with:

- `models.ts` read/create/update contracts plus relation metadata
- `validators.ts` framework-neutral validator schemas plus form-field adapters
- `query.ts` explicit relation metadata and resource query-shape contracts
- `client.ts` typed `fetch` transport helpers from OpenAPI operations
- optional `react.ts` TanStack Query-oriented helpers
- `meta.ts` module/resource/admin metadata registries plus workspace hints
- a versioned manifest (`format: arlen-typescript-contract-v1`)

The recommended CLI path is:

```bash
source tools/source_gnustep_env.sh
bin/arlen typescript-codegen \
  --orm-input db/schema/arlen_orm_manifest.json \
  --openapi-input build/openapi.json \
  --output-dir frontend/generated/arlen \
  --manifest db/schema/arlen_typescript.json \
  --target all \
  --force
```

This stays descriptor-first:

- Objective-C models and TypeScript contracts are sibling generated outputs
- top-level OpenAPI `x-arlen` metadata adds resource/module/workspace contracts
  without turning TypeScript into the canonical persistence model
- `react` output is optional and package-scoped
- missing OpenAPI schemas or unstable operation IDs fail closed
- generated `query.ts` stays additive; it does not widen `client.ts` request
  types beyond what the OpenAPI contract actually declares

Framework-side verification for this surface now ships as repo-native lanes:

- `make phase28-ts-generated`
- `make phase28-ts-unit`
- `make phase28-ts-integration`
- `make phase28-react-reference`
- `make phase28-confidence`

## Query Model

`ArlenORM` is SQL-first, not SQL-hiding:

- repositories lower queries into inspectable `ALNSQLBuilder` plans
- apps can still compose or execute raw `ALNSQLBuilder` instances directly
- unsupported query shapes fail closed with explicit diagnostics

Example:

```objc
ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:database];
ALNORMRepository *posts = [context repositoryForModelClass:[BlogPostModel class]];
ALNORMQuery *query = [[posts query] whereField:@"authorId" equals:@"user-1"];
NSDictionary *plan = [posts compiledPlanForQuery:query error:&error];
NSArray *models = [posts allMatchingQuery:query error:&error];
```

Strict-loading and eager-loading controls are explicit:

```objc
ALNORMQuery *query = [[[posts query] withSelectInRelationNamed:@"author"] strictLoading:YES];
NSArray *models = [posts allMatchingQuery:query error:&error];
```

For mutation-heavy flows, prefer changesets and write options:

```objc
ALNORMChangeset *changeset = [ALNORMChangeset changesetWithModel:post];
[changeset applyInputValues:payload error:&error];
[repository saveModel:post
            changeset:changeset
              options:[ALNORMWriteOptions options]
                error:&error];
```

When a new SQL model relies on a database-generated primary key default, Arlen
now requests the generated key back through the adapter's `returning_mode`
contract and hydrates it onto the in-memory model before the surrounding
transaction continues. If your app sets the primary key explicitly on a new
model, that value remains part of the insert plan instead of being dropped.

Dataverse ORM stays separate from the SQL ORM runtime:

```objc
ALNORMDataverseContext *context = [[ALNORMDataverseContext alloc] initWithClient:client];
ALNORMDataverseRepository *accounts =
    [context repositoryForModelClass:[CRMAccount class]];
NSArray *rows = [accounts all:&error];
```

Lookup relations and reverse collections are explicit loads, not implicit lazy
magic.

## Verification

Use the dedicated lanes:

```bash
source tools/source_gnustep_env.sh
make phase26-orm-unit
make phase26-orm-generated
make phase26-orm-integration
make phase26-orm-backend-parity
make phase26-orm-perf
make phase26-orm-live
make phase26-confidence
make phase26-orm-tests
```

API docs also include the ORM umbrella:

```bash
make docs-api
```

Related docs:

- `docs/ARLEN_ORM_MIGRATIONS.md`
- `docs/ARLEN_ORM_BACKEND_MATRIX.md`
- `docs/ARLEN_ORM_SCORECARD.md`
