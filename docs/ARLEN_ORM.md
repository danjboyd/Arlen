# ArlenORM Guide

`ArlenORM` is Arlen's optional SQL ORM layer on top of `ArlenData`.

Import the ORM umbrella when you want reflected descriptors, generated SQL
models, repositories, and association metadata without giving up direct
`ALNSQLBuilder` or direct adapter access:

```objc
#import "ArlenORM/ArlenORM.h"
```

`ArlenORM` is intentionally not part of `Arlen/Arlen.h`. Apps that do not want
an ORM do not pay an API-shape cost for it.

## Scope Today

The current shipped foundation is Phase `26A-26I`:

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

Not in scope yet:

- migration-history isolation (`26J`)
- Dataverse ORM support (`26N-26O`)

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
default in generated models.

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

## Verification

Use the focused ORM lane:

```bash
source tools/source_gnustep_env.sh
make phase26-orm-tests
```

API docs also include the ORM umbrella:

```bash
make docs-api
```
