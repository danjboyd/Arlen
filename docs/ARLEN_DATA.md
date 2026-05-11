# ArlenData Reuse Guide

This guide defines how to consume Arlen's data layer independently of the HTTP/MVC runtime.

## 1. Scope

`ArlenData` is the standalone data-layer surface composed of:

- `src/Arlen/Data/*`
- `src/ArlenData/ArlenData.h` (umbrella header)

Primary contracts:

- `ALNSQLBuilder` (v2 query builder with expression selects/predicates/order clauses, subquery+lateral joins, and tuple-friendly cursor predicates)
- `ALNSQLDialect` / `ALNPostgresDialect` / `ALNMSSQLDialect` (backend-neutral dialect seam plus shipped PostgreSQL and MSSQL dialect implementations)
- `ALNMSSQLSQLBuilder` (thin MSSQL-named builder surface over the dialect compiler)
- `ALNPostgresSQLBuilder` (PostgreSQL dialect extension for conflict/upsert, including expression-based `DO UPDATE SET` and optional `DO UPDATE ... WHERE`)
- `ALNMSSQL` (optional SQL Server adapter with runtime ODBC loading; no hard core dependency on Microsoft's driver)
- `ALNDataverseClient`, `ALNDataverseQuery`, `ALNDataverseMetadata`, and `ALNDataverseCodegen` (Dataverse Web API/OData client, query builder, metadata normalization, and typed code generation)
- `ALNSchemaCodegen` (deterministic typed schema helper artifact rendering)
- `ALNPg` builder execution/caching/diagnostics and typed PostgreSQL bind/result APIs (`executeBuilderQuery`, `executeBuilderCommand`, query stage listener events)
- `ALNDatabaseAdapter` / `ALNDatabaseConnection`
- `ALNDatabaseRouter` (multi-target runtime routing with stickiness and diagnostics)
- `ALNDisplayGroup`
- `ALNAdapterConformance` helpers
- `ALNPg`, `ALNMigrationRunner`, `ALNGDL2Adapter`

Dataverse is intentionally not routed through `ALNDatabaseAdapter` or
`ALNSQLBuilder`. Use the Dataverse client/query surface directly for Dataverse
workloads, and keep using the SQL adapter path for PostgreSQL/MSSQL.

The optional SQL ORM surface now lives in `src/ArlenORM/ArlenORM.h` on top of
these contracts. See `docs/ARLEN_ORM.md` for the optional ORM foundation.

## 2. Non-Arlen Consumption

Compile only data-layer sources and import the umbrella header:

```objc
#import "ArlenData/ArlenData.h"
```

Reference build/usage validation:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
make test-data-layer
```

`make test-data-layer` builds and runs `build/arlen-data-example` using only ArlenData sources.

For the optional ORM layer on top of ArlenData, run:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
make phase26-orm-tests
```

For Dataverse-specific usage, config shape, and codegen examples, see
`docs/DATAVERSE.md`.

## 3. Git Partial Checkout

If consumers only need ArlenData, use sparse checkout:

```bash
git clone --filter=blob:none --no-checkout https://github.com/danjboyd/Arlen.git
cd Arlen
git sparse-checkout init --cone
git sparse-checkout set src/Arlen/Data src/ArlenData docs/ARLEN_DATA.md examples/arlen_data GNUmakefile
git checkout main
```

This keeps clone size focused on the data layer and its example/docs.

## 4. Optional Split-Repo Workflow

For teams that want a separate distribution repository, export ArlenData-only history/worktree:

```bash
git subtree split --prefix=src/Arlen/Data --branch arlen-data-split
```

Then publish `arlen-data-split` to a dedicated repository and add `src/ArlenData/ArlenData.h` as the umbrella include surface.

## 5. Versioning Policy

ArlenData follows semantic versioning aligned with framework release tags:

- `MAJOR`: breaking API or behavior changes in `src/Arlen/Data` or `src/ArlenData`
- `MINOR`: additive APIs/capabilities (for example, new query-builder features)
- `PATCH`: bug fixes and diagnostics hardening without API breaks

Compatibility contract:

- Changes to SQL rendering behavior require deterministic snapshot updates in unit tests.
- Data-layer standalone validation (`make test-data-layer`) must pass in CI.
- Dialect-specific additions must remain in explicit dialect modules (`ALNPostgresSQLBuilder`) and not leak into base builder requirements.
- `ALNSQLBuilder build:` remains PostgreSQL-default for backward compatibility; cross-dialect compilation should use `buildWithDialect:` / `buildSQLWithDialect:` / `buildParametersWithDialect:`.

## 6. Dialect and Backend Portability

Arlen ships a backend-neutral seam around SQL compilation and migrations:

- `ALNSQLBuilder` now exposes:
  - `buildWithDialect:error:`
  - `buildSQLWithDialect:error:`
  - `buildParametersWithDialect:error:`
- `ALNMigrationRunner` now accepts any `id<ALNDatabaseAdapter>` that exposes
  `sqlDialect`
- shipped dialects:
  - `ALNPostgresDialect`
  - `ALNMSSQLDialect`

Default behavior is intentionally unchanged:

- `build:` still emits PostgreSQL SQL
- `ALNPg` still compiles/executes builders as a first-class default path

Optional MSSQL path:

- instantiate `ALNMSSQL` with an ODBC connection string
- compile explicitly for SQL Server with `ALNMSSQLDialect`
- core Arlen/ArlenData does not link to Microsoft’s driver
- runtime MSSQL use requires an installed ODBC manager (`unixODBC` or `iODBC`)
  plus an appropriate SQL Server driver/runtime client

Example:

```objc
NSError *error = nil;
ALNSQLBuilder *builder = [[[ALNSQLBuilder selectFrom:@"users"
                                              columns:@[@"id", @"email"]]
                           whereField:@"status" equals:@"active"]
                           orderByField:@"id" descending:NO];
NSDictionary *compiled =
    [builder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
ALNMSSQL *database =
    [[ALNMSSQL alloc] initWithConnectionString:odbcConnectionString
                                 maxConnections:4
                                          error:&error];
NSArray *rows = [database executeBuilderQuery:builder error:&error];
```

Current MSSQL builder subset:

- supported:
  - select/insert/update/delete
  - CTEs and recursive CTEs
  - set operations
  - window clauses
  - `OUTPUT INSERTED/DELETED`-style returning semantics
  - `OFFSET ... FETCH` pagination (requires explicit `ORDER BY`)
- fail-closed unsupported features:
  - PostgreSQL `ON CONFLICT`
  - `ILIKE`
  - `NULLS FIRST/LAST`
  - lateral joins
  - `JOIN ... USING (...)`
  - PostgreSQL-style `FOR UPDATE` / `SKIP LOCKED`

## 7. CI Enforcement

ArlenData reuse remains continuously validated by CI via:

- `tools/ci/run_phase3c_quality.sh` calling `make test-data-layer`
- unit snapshots in `tests/unit/Phase3GTests.m`
- Phase 4A safety/IR regressions in `tests/unit/Phase4ATests.m`
- PostgreSQL execution regression for identifier-bound templates in `tests/unit/PgTests.m`

## 8. Expression Template Safety Contracts

Expression-capable builder APIs now route through a trusted-template IR (`trusted-template-v1`) with explicit contracts:

- Identifier slots use `{{token}}` and must be satisfied by `identifierBindings`.
- Identifier bindings must resolve to safe SQL identifiers/wildcards (for example `d.state_code`, `d.*`, `*`).
- Expression parameters must be an array and placeholders must map exactly to `$1..$N`.
- Malformed expression IR shapes fail deterministically with `ALNSQLBuilderErrorDomain` diagnostics.

These contracts apply to:

- `selectExpression:...identifierBindings:parameters:`
- `whereExpression:identifierBindings:parameters:`
- `havingExpression:identifierBindings:parameters:`
- `orderByExpression:...identifierBindings:parameters:`
- subquery/lateral join `onExpression` APIs with `identifierBindings`

## 9. Typed Schema Codegen Workflow

Use the CLI in an app root with PostgreSQL config:

```bash
/path/to/Arlen/bin/arlen schema-codegen --env development
```

This introspects `information_schema` and writes deterministic artifacts:

- `src/Generated/ALNDBSchema.h`
- `src/Generated/ALNDBSchema.m`
- `db/schema/arlen_schema.json`

Generated table APIs expose:

- typed table-level builder entrypoints (`selectAll`, `selectColumns`, and
  write helpers only for writable reflected relations)
- typed column accessor methods (`columnX`, `qualifiedColumnX`)
- relation metadata helpers (`relationKind`, `isReadOnlyRelation`)
- typed decode helpers (`decodeTypedRow`, `decodeTypedFirstRowFromRows`, `decodeTypedRows`)

Consumers can include generated files in non-Arlen builds as long as `ALNSQLBuilder` is linked.

## 10. Typed Materialization and Result Helpers

PostgreSQL runtime materialization now aligns with the generated typed-contract
surface for the supported scalar baseline.

Bind values accepted by `ALNPg`:

- `NSString`
- `NSNumber` (`BOOL`, integer, float/numeric inputs)
- `NSDate`
- `NSData`
- `NSUUID`
- `ALNDatabaseJSONParameter(...)`
- `ALNDatabaseArrayParameter(...)`
- `NSArray` / `NSDictionary` (JSON-encoded)
- `NSNull`

Result values returned by `ALNPg` for supported PostgreSQL column types:

- `BOOL`, `smallint`, `integer`, `bigint`, `real`, `double precision`:
  `NSNumber`
- `numeric`: `NSDecimalNumber`
- `date`, `timestamp`, `timestamp with time zone`: `NSDate`
- `bytea`: `NSData`
- `json`, `jsonb`: Foundation collection/object decoded from JSON
- supported one-dimensional scalar arrays (`text[]`, `integer[]`, `numeric[]`,
  `uuid[]`, date/timestamp families, JSON arrays): `NSArray`
- text-like and unmapped runtime types: `NSString`

For mapped scalar types, decode failures now surface an explicit `NSError`
instead of silently returning a mismatched runtime class.

Generated write contracts use explicit wrapper parameters for collection-shaped
columns:

- array columns emit `ALNDatabaseArrayParameter(...)`
- `json` / `jsonb` columns emit `ALNDatabaseJSONParameter(...)`

That keeps PostgreSQL array-vs-JSON intent explicit instead of treating every
Foundation collection as implicit JSON.

Common fetch helpers:

```objc
NSError *error = nil;
NSArray<NSDictionary *> *rows =
    [db executeQuery:@"SELECT id, created_at FROM users WHERE id = $1"
          parameters:@[ @"u-1" ]
               error:&error];
NSDictionary *first = ALNDatabaseFirstRow(rows);
id total = ALNDatabaseScalarValueFromRows(@[ @{ @"count" : @3 } ], nil, &error);
```

Contract-aware typed decode from live rows:

```objc
NSError *error = nil;
NSArray<NSDictionary *> *rows =
    [db executeQuery:@"SELECT id, created_at FROM users WHERE id = $1"
          parameters:@[ @"u-1" ]
               error:&error];
ALNDBPublicUsersRow *user =
    [ALNDBPublicUsersRow decodeTypedFirstRowFromRows:rows error:&error];
```

Explicit scalar execution through a pooled connection:

```objc
NSError *error = nil;
ALNPgConnection *connection = [db acquireConnection:&error];
NSNumber *count =
    ALNDatabaseExecuteScalarQuery(connection,
                                  @"SELECT COUNT(*) AS count FROM users WHERE status = $1",
                                  @[ @"active" ],
                                  @"count",
                                  &error);
[db releaseConnection:connection];
```

Nested dialect compilation is also recursive now:

- `buildWithDialect:` applies the active dialect when compiling nested
  subqueries/CTEs/set-op fragments
- MSSQL fail-closed validation now catches unsupported nested constructs such
  as `ILIKE`, PostgreSQL pagination syntax, and related PostgreSQL-only forms
  inside subqueries instead of only at the root builder

## 11. Query Execution Diagnostics and Caching

`ALNPgConnection`/`ALNPg` now expose builder-driven execution helpers:

- `executeBuilderQuery:error:`
- `executeBuilderCommand:error:`
- `resetExecutionCaches`

Runtime controls:

- prepared statement reuse policy: `disabled`, `auto`, `always`
- cache limits:
  - `preparedStatementCacheLimit`
  - `builderCompilationCacheLimit`
- diagnostics controls:
  - `queryDiagnosticsListener` (stage events: `compile`, `execute`, `result`, `error`)
  - `emitDiagnosticsEventsToStderr`
  - `includeSQLInDiagnosticsEvents` (default off; redaction-safe metadata remains default)

## 12. Conformance and Migration Hardening

Conformance matrix:

- `docs/SQL_BUILDER_CONFORMANCE_MATRIX.md`
- `tests/fixtures/sql_builder/phase4e_conformance_matrix.json`
- `tests/unit/Phase4ETests.m`

Migration/deprecation docs:

- `docs/SQL_BUILDER_PHASE4_MIGRATION.md`

Regression coverage extends the data-layer contract with:

- `tests/unit/SchemaCodegenTests.m`
- `tests/unit/Phase17BTests.m`
- `tests/unit/PgTests.m`
- `tests/integration/PostgresIntegrationTests.m`
- `docs/RELEASE_PROCESS.md` (phase-4 transitional API lifecycle)

## 13. Multi-Database Runtime Routing

`ALNDatabaseRouter` provides operation-aware target selection on top of adapter contracts:

- read routes (`executeQuery`) default to a named read target
- write routes (`executeCommand`, transactions) default to a named write target
- optional read-after-write stickiness via bounded scope keys in routing context
- optional tenant/shard hook override via `routeTargetResolver`
- optional read fallback to write target on execution error
- structured route diagnostics via `routingDiagnosticsListener`

## 14. Target-Aware Migration and Codegen Tooling

CLI workflows now support explicit target selection:

- `arlen migrate --database <target>`
- `arlen schema-codegen --database <target>`

Target-aware defaults:

- migrations path: `db/migrations/<target>`
- migration state table: `arlen_schema_migrations__<target>`
- schema output dir: `src/Generated/<target>`
- schema manifest path: `db/schema/arlen_schema_<target>.json`

Adapter selection:

- `arlen migrate` / `arlen module migrate` select the configured adapter for
  the target (`postgresql`, `gdl2`, or optional `mssql`)
- `arlen schema-codegen` remains PostgreSQL-only in the current slice

Schema manifests include `database_target` metadata for deterministic per-target artifact tracking.

## 15. Typed Data Contracts and Typed SQL

Schema codegen now supports optional typed contract output:

- `arlen schema-codegen --typed-contracts`

When enabled, generated schema artifacts include:

- per-table `Row`, `Insert`, and `Update` classes
- table-level `insertContract` / `updateContract` helpers
- deterministic runtime decode helpers (`decodeTypedRow`, `decodeTypedRows`)
- generated decode error domain + error codes

Typed SQL helpers are available through:

- `arlen typed-sql-codegen`

This compiles SQL files with metadata comments into typed parameter/result helper APIs.

## 16. Hardening and Confidence Artifacts

The data layer ships explicit hardening and release-evidence workflows:

- soak/fault regression coverage in `tests/unit/PgTests.m`
  - connection interruption recovery
  - transaction abort rollback behavior
  - builder compile/execute cache churn under sustained loops
- deterministic confidence artifact generation:
  - `python3 tools/ci/generate_phase5e_confidence_artifacts.py`
  - output directory: `build/release_confidence/phase5e`

Key gates:

- `make ci-quality`
- `bash ./tools/ci/run_phase5e_sanitizers.sh`
- `make phase5e-confidence`

Soak loop count override:

- `ARLEN_PHASE5E_SOAK_ITERS` (default `120`)

## 17. Data-Layer Depth Pass

The current depth pass deepens the existing data layer without widening it
into ORM-style metadata or lifecycle behavior.

New internal seams and defaults:

- result/execution helpers now include:
  - `ALNDatabaseResult` / `ALNDatabaseRow`
  - stable select-list column ordering through `ALNDatabaseResult.columns`,
    `ALNDatabaseRow.columns`, and `ALNDatabaseRow.objectAtColumnIndex:`
  - `ALNDatabaseExecuteQueryResult`
  - `ALNDatabaseExecuteCommandBatch`
  - `ALNDatabaseWithSavepoint`
- reflection/codegen now go through `ALNDatabaseInspector`
  - PostgreSQL-first implementation: `ALNPostgresInspector`
  - normalized column fields:
    schema/table/column/ordinal/data type/nullability/PK/default-shape/relation kind/read-only
  - metadata surface:
    schemas / relations / columns / primary keys / unique constraints /
    foreign keys / indexes / check constraints / view definitions /
    relation comments / column comments
- generated schema manifests now include:
  - `reflection_contract_version`
  - `relation_kind`
  - `read_only`
  - `supports_write_contracts`
  - per-table `column_metadata`
- `ALNDatabaseRouter` now defaults read fallback to connectivity-only errors
  through `readFallbackPolicy`
- `ALNPg` now supports:
  - checkout liveness checks via `connectionLivenessChecksEnabled`
  - stale idle connection recycle behavior
  - prepared-statement cache eviction instead of permanent saturation
- `ALNMSSQL` now supports:
  - bounded batch execution on one acquired connection
  - explicit savepoints with no-op release normalization for SQL Server
  - optional checkout liveness checks when ODBC transport is present
  - native ODBC bind/fetch handling for the documented common scalar subset
    plus `NSData` / binary payloads when transport support is present
  - support-tier metadata that makes the subset-vs-unavailable distinction explicit
  - explicit fail-closed diagnostics for unsupported array-shaped parameters

Focused examples:

```objc
NSError *error = nil;
NSArray<NSDictionary<NSString *, id> *> *columns =
    [ALNDatabaseInspector inspectSchemaColumnsForAdapter:db error:&error];
NSDictionary *artifacts =
    [ALNSchemaCodegen renderArtifactsFromColumns:columns
                                      classPrefix:@"ALNDB"
                                   databaseTarget:@"default"
                            includeTypedContracts:YES
                                            error:&error];
```

```objc
NSError *error = nil;
NSDictionary<NSString *, id> *metadata =
    [ALNDatabaseInspector inspectSchemaMetadataForAdapter:db error:&error];
NSArray<NSDictionary<NSString *, id> *> *schemas = metadata[@"schemas"];
NSArray<NSDictionary<NSString *, id> *> *relations = metadata[@"relations"];
NSArray<NSDictionary<NSString *, id> *> *checkConstraints = metadata[@"check_constraints"];
```

```objc
router.readFallbackPolicy = ALNDatabaseReadFallbackPolicyConnectivityErrors;
db.connectionLivenessChecksEnabled = YES;
```

```objc
NSError *error = nil;
ALNDatabaseResult *result =
    ALNDatabaseExecuteQueryResult(connection,
                                  @"SELECT COUNT(*) AS count FROM users WHERE status = $1",
                                  @[ @"active" ],
                                  &error);
NSArray<NSString *> *projection = result.columns;
NSNumber *count = [result scalarValueForColumn:@"count" error:&error];
id firstValue = [[result first] objectAtColumnIndex:0];
BOOL ok = ALNDatabaseWithSavepoint(connection, @"phase20_inner", ^BOOL(NSError **blockError) {
  return ([connection executeCommand:@"INSERT INTO users (name) VALUES ($1)"
                          parameters:@[ @"hank" ]
                               error:blockError] >= 0);
}, &error);
```

Confidence pack:

- `make phase20-confidence`
- focused verification:
  - `make phase20-sql-builder-tests`
  - `make phase20-schema-tests`
  - `make phase20-routing-tests`
  - `make phase20-postgres-live-tests`
  - `make phase20-mssql-live-tests`
  - `make phase20-focused`
  - `bash tools/ci/run_phase20_focused.sh`
- output directory: `build/release_confidence/phase20`
- machine fixtures:
  - `tests/fixtures/phase20/postgres_reflection_contract.json`
  - `tests/fixtures/phase20/postgres_type_codec_contract.json`
  - `tests/fixtures/phase20/backend_support_matrix.json`
