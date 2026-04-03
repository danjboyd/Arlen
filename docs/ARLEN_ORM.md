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

Use the Phase 26 lanes:

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
