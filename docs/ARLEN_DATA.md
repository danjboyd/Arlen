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
- safety/IR regressions in `tests/unit/Phase4ATests.m`
- PostgreSQL execution regression for identifier-bound templates in `tests/unit/PgTests.m`

## 8. Expression Template Safety Contracts

Expression-capable builder APIs now route through a trusted-template IR (`trusted-template-v1`) with explicit contracts:

- Identifier slots use `{{token}}` and must be satisfied by `identifierBindings`.
- Identifier bindings must resolve to identifier paths/wildcards (for example `d.state_code`, `d.*`, `*`, or `d."Unit Name"`). Paths accept only ordinary or double-quoted components separated by dots, never SQL fragments. Use `ALNSQLDialectIdentifierComponent` to encode a physical component from trusted metadata; embedded quotes are doubled. Aliases remain ordinary identifiers.
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
- `json`, `jsonb`: Foundation value decoded from JSON: `NSDictionary`/`NSArray`
  for objects and arrays; `NSString`, `NSNumber` or `NSNull` for scalar documents
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

- `docs/internal/SQL_BUILDER_PHASE4_MIGRATION.md`

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
  - checkout liveness checks via `connectionLivenessChecksEnabled`, limited
    to connections idle for `connectionLivenessCheckIdleThreshold` seconds
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

## PostgreSQL timestamp precision

`ALNPg` binds `NSDate` scalar and array parameters with six fractional digits,
rounded to the nearest microsecond with carry into the next second. The decoder
and encoder preserve PostgreSQL microseconds for dates from 1900-01-01 through
2100-12-31 on the supported GNUstep and Apple double-precision `NSDate` runtimes.
This is a database round-trip guarantee; binary floating-point does not represent
every decimal fraction exactly. Negative epochs and offsets are supported.

Dates use the proleptic Gregorian calendar, as PostgreSQL does, for every year
from 1 through 9999. Decoded `date`, `timestamp` and `timestamptz` values give
the same instant as PostgreSQL's `extract(epoch ...)`, including dates before
the 1582 Gregorian reform. An `NSDate` parameter before year 1 is sent with
PostgreSQL's ` BC` suffix.

`timestamptz` becomes an instant: received offsets are normalized and parameters
are emitted in UTC. The original offset/zone name is not retained. PostgreSQL
`timestamp without time zone` is interpreted as UTC wall-clock components, and
binding that date back to `timestamp` preserves those components; it does not
attach the session or machine timezone. Use explicit SQL casts for parameter
intent. An application-supplied date is rounded, not truncated.

Outside this guaranteed range, or for PostgreSQL infinity/BC/extended-year
values, use the lossless text path instead of converting through `NSDate`:

```objc
NSDictionary *row = [connection executeQueryOne:
    @"SELECT audit_time::text AS value FROM events WHERE id = $1"
    parameters:@[eventID] error:&error];
[connection executeCommand:
    @"UPDATE prospects SET changed_at = $1::timestamptz WHERE id = $2"
    parameters:@[row[@"value"], prospectID] error:&error];
```

Keep a deterministic PostgreSQL `DateStyle` (`ISO, YMD`) for text interchange.
For timestamps without a timezone, use `::timestamp` instead. Text values and
`ALNDatabaseArrayParameter` containing timestamp strings bypass `NSDate` and
retain all six digits. NSDate conversion outside the supported range can lose
precision or fail decoding and is not the lossless alternative. PostgreSQL's
original zone spelling is not stored even when text is used.

## Connection pool acquire timeout

`ALNPg` and `ALNMSSQL` keep at most `maxConnections` connections. When all of
them are checked out, `acquireConnection:` (and every helper built on it, such
as `executeQuery:parameters:error:`) fails straight away with
`ALNPgErrorPoolExhausted` / `ALNMSSQLErrorPoolExhausted`. That is the default.

Set `acquireTimeout` to let a borrower wait for a connection to come back
instead. This absorbs short bursts, for example several webhooks arriving
within a few milliseconds, without holding more database backends open:

```objc
ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn
                                            maxConnections:4
                                                     error:&error];
database.acquireTimeout = 2.0;  // seconds; 0 (default) fails immediately
```

- A waiter wakes when a connection is released, or when a dead connection is
  discarded and its slot freed. It then reuses the idle connection or opens a
  replacement.
- If the wait runs out, the error is the same pool-exhausted code, with the
  message `connection pool exhausted after waiting <seconds>s`. Its
  `ALNPgErrorDiagnosticsKey` / `ALNMSSQLErrorDiagnosticsKey` dictionary holds
  `max_connections`, `acquire_timeout_seconds` and `acquire_wait_seconds`.
- Waiters are not served first-come-first-served.
- Connects, checkout liveness checks and release-time rollbacks run outside
  the pool lock, so one slow checkout does not hold up other borrowers.
- Code that holds one connection while acquiring a second can stall when every
  borrower does the same: each waits for a connection none of them will
  release. With a timeout this ends in pool-exhausted errors after
  `acquireTimeout` rather than hanging, but keep the timeout short (a few
  seconds) and avoid nested acquisition.
- `poolDiagnostics` returns `max_connections`, `in_use_connections`,
  `idle_connections`, `acquire_timeout_seconds`, `acquire_wait_count`,
  `acquire_wait_seconds_total`, `pool_exhausted_count` and
  `connection_retry_count` (see below). A rising
  `pool_exhausted_count` or `acquire_wait_seconds_total` means the pool is too
  small for the load.
- `acquireTimeout` is an optional `ALNDatabaseAdapter` property; `ALNGDL2Adapter`
  forwards it to its PostgreSQL fallback adapter.

Size `maxConnections` to at least the number of requests that use the
database concurrently (`runtimeLimits.maxConcurrentHTTPWorkers`, default 8,
per worker process) when you can afford the backends; use `acquireTimeout`
for bursts beyond that.

Apps that build adapters from configuration can read
`database.poolAcquireTimeoutSeconds` (default `0`, env override
`ARLEN_DB_POOL_ACQUIRE_TIMEOUT_SECONDS`) alongside `database.poolSize`. See
the [Configuration Reference](CONFIGURATION_REFERENCE.md).

## Connection pool liveness checks

`ALNPg` checks a pooled connection before handing it out again:

- Every reused connection gets libpq's connection status check, which costs
  no round trip. A connection libpq already knows is dead is closed, and the
  pool opens a replacement.
- With `connectionLivenessChecksEnabled` (default `YES`), a connection that
  has sat idle for at least `connectionLivenessCheckIdleThreshold` seconds
  (default `30`) also runs `SELECT 1` first. This catches a connection the
  server or a firewall dropped during a quiet period.
- A connection returned less than the threshold ago skips the `SELECT 1`, so
  back-to-back pooled statements don't pay an extra round trip each.

```objc
database.connectionLivenessCheckIdleThreshold = 10.0;  // probe after 10 s idle
database.connectionLivenessCheckIdleThreshold = 0;     // probe on every reuse
database.connectionLivenessChecksEnabled = NO;         // never probe
```

Before the threshold existed, every reuse ran `SELECT 1`. Set the threshold to
`0` to get that back.

If the server ends a session that was used within the threshold (a restart,
failover, idle timeout or `pg_terminate_backend` in the middle of traffic),
the next statement on that connection fails. `ALNPg` reports that as
`ALNPgErrorConnectionFailed` with `ALNPgErrorConnectionLostKey = YES` in
`userInfo`, whatever the last result said, and closes the connection, so a
dead connection is never handed out again.

Before each statement is sent, `ALNPg` reads whatever the server has already
sent on the connection (without waiting). A session the server ended while
the connection sat idle shows up there as a FATAL message or a closed
socket; the statement is then not sent at all, and the error also carries
`ALNPgErrorStatementNotSentKey = YES`. `ALNPg` sends with libpq's
synchronous calls, which cannot tell a failed send from a failure while
waiting for the result, so this check before sending is what decides that a
statement never reached the server.

Retry policy for the pool's own convenience methods (a statement is retried
at most once, only when the connection came from the idle list, and the
other idle connections are closed first):

- Reads (`executeQuery`, `executeQueryResult` and `executeBuilderQuery` whose
  SQL is a plain read): retried when the connection was lost at any point. A
  plain read starts with `SELECT`, `WITH`, `VALUES`, `TABLE`, `SHOW` or
  `EXPLAIN` (without `ANALYZE`) and contains no word that writes, locks or
  changes session state (`INSERT`, `UPDATE`, `DELETE`, `MERGE`, `INTO`,
  `LOCK`, `FOR SHARE`, `NEXTVAL`, `pg_advisory_*`, and so on). An
  `INSERT ... RETURNING` through `executeQuery` is a write. A `SELECT` that
  calls a function with side effects is still classified as a read; run it
  with `executeCommand`.
- Writes (`executeCommand`, `executeBuilderCommand`, and every statement
  that is not a plain read): retried only when the statement was not sent
  (`ALNPgErrorStatementNotSentKey`). If it was sent and the connection
  failed while waiting for the result, the server may have run it, so the
  connection-lost error is returned and the caller decides. Running a write
  twice is worse than one failed request.
- Never when a transaction is open on the connection, whether started with
  `beginTransaction:` or by sending `BEGIN` by hand: the earlier statements
  were rolled back, so running the failed one on its own would apply only
  part of the transaction. A connection released with a hand-opened
  transaction still open is closed, not reused.
- `withTransaction:` restarts the transaction once on a new connection only
  when `BEGIN` itself failed on a connection from the idle list (nothing has
  run). When the connection is lost inside the block or at `COMMIT`, the
  server rolled back what had run and the connection-lost error is returned.
- `withTransactionReplayingOnConnectionLoss:` additionally runs the whole
  block again from `BEGIN` on a new connection, once, when the connection is
  lost inside the block or at `COMMIT`. Use it only for blocks that are safe
  to run twice (idempotent, or guarded by compare-and-set), since a
  connection lost at `COMMIT` may follow a successful commit.

`connection_retry_count` in `poolDiagnostics` counts retries and restarts.
`executeCommandBatch` and statements on a connection you acquired yourself
are not retried. The instance `capabilityMetadata` reports the setting as
`connection_liveness_check_idle_threshold_seconds`.

## Connection pool session reset

`ALNPg` resets a connection's session state when it goes back to the pool, so
one request's settings never reach the next borrower. This matters most for
row-level security or tenancy implemented with
`set_config('app.tenant_id', ...)`: without a reset, a request that skips the
`set_config` would run as the previous request's tenant.

- A connection still inside a transaction when it is released, whether
  started with `beginTransaction:` or by sending `BEGIN` by hand, is closed
  rather than reused. Closing it rolls the transaction back on the server.
  `released_in_transaction_count` in `poolDiagnostics` counts these.
- A connection is reset only if the borrower could have changed its session.
  It is marked when it runs SQL the pool did not generate itself: any
  `executeQuery`, `executeQueryResult`, `executeCommand`, batch, script or
  `prepareStatementNamed:` with caller SQL, a transaction, and also a builder
  statement that contains a trusted expression (`selectExpression:`,
  `whereExpression:`, `orderByExpression:`, join `onExpression:` and the
  other expression APIs splice app SQL text, which can call `set_config`,
  `pg_advisory_lock` or `nextval` inside a plain `SELECT`). A connection that
  only ran generated builder statements is reused without a reset. ORM
  repositories run their SQL through `executeQuery`/`executeCommand`, so they
  mark the connection too.
- For a marked connection, `sessionResetPolicy` decides what is reset:
  - `ALNPgSessionResetPolicySession` (default): one round trip running
    `RESET ALL`, `SET SESSION AUTHORIZATION DEFAULT`, `CLOSE ALL`,
    `DISCARD TEMP`, `DISCARD SEQUENCES`, `UNLISTEN *` and
    `pg_advisory_unlock_all()`, and reading `pg_prepared_statements`.
    Settings (including `search_path` and `SET ROLE`), cursors, temporary
    tables, `currval`/`lastval` state, `LISTEN`s and session advisory locks
    are cleared. The pool's cached prepared statements are kept only if every
    one is still the statement the pool prepared: a statement the cache does
    not know, one made with SQL `PREPARE`, or one whose text differs (a
    borrower can `DEALLOCATE` a cached name and `PREPARE` other SQL under it)
    makes the pool run `DEALLOCATE ALL` and clear its cache.
  - `ALNPgSessionResetPolicyDiscardAll`: `DISCARD ALL`, which also drops
    every prepared statement; the pool's statement cache is cleared and
    statements are prepared again on next use.
  - `ALNPgSessionResetPolicyNone`: no reset, for code that manages session
    state itself.
- Under every policy, notifications still queued for the borrower's
  `LISTEN`s are read and dropped, so the next borrower's
  `waitForNotificationsWithTimeout:` cannot see them.
- If the reset fails, the connection is closed instead of reused
  (`session_reset_failure_count`). `session_reset_count` counts releases that
  ran the reset.

Cost, measured on a local socket over 2,000 pooled requests: a connection that
ran only generated builder statements pays nothing extra. A marked connection
pays one round trip, about 95 µs per request (49 µs → 142 µs for a pooled
`executeQuery`), for the reset, the prepared-statement check and the
notification drain.

```objc
database.sessionResetPolicy = ALNPgSessionResetPolicyDiscardAll;
```

## Text parameters and NUL

PostgreSQL `text` cannot hold U+0000, and libpq reads text parameters as C
strings. `ALNPg` therefore refuses a string parameter that contains U+0000
with `ALNPgErrorInvalidArgument` instead of letting it be cut short at the NUL
(which would make the database see a different value than the one the app
validated). Send binary data as `NSData`; it is bound as `bytea`.

`ALNMSSQL` binds text parameters with their full byte length, so a value with
an embedded U+0000 reaches SQL Server unchanged (SQL Server stores NUL inside
`(n)varchar`).

Both adapters also refuse SQL text (and `ALNPg` statement names) that contain
U+0000 with an invalid-argument error. The drivers take statement text as a C
string, so the statement would otherwise end silently at the NUL.

The PostgreSQL builder cache retains SQL shapes, keyed by SQL and parameter
count, rather than builder snapshots or bound values. Each call compiles its
current parameters and reuses the matching SQL shape/prepared statement.
Changing only values therefore reports a compile-cache hit without retaining
another request's values. Trusted expressions are checked on each compilation
and still trigger session cleanup on release.

For large PostgreSQL SELECT results, use
`-[ALNPg enumerateQuery:parameters:batchSize:usingBlock:error:]`. It holds one
pooled connection and a transaction-local cursor, fetches 1–10,000 rows per
batch, and drains an autorelease pool between batches. Set `*stop = YES` in the
callback for successful early termination. Errors roll back; callback
exceptions clean up and propagate. Callbacks are never replayed. Retaining rows
in your callback increases memory use; `executeQuery:` still buffers its full
result. The cursor API does not change the SQL or limit its server-side cost.

ORM-generated PostgreSQL statements that contain no raw or trusted expression
skip session reset when released. Compiler provenance is carried internally;
public raw-SQL APIs still mark the connection dirty. Raw predicates such as
`set_config(..., false)` still trigger reset. Transactions and previously dirty
connections continue to reset even if their last statement was generated.
