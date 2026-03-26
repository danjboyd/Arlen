# Getting Started: Data-Layer Track

This track focuses on SQL builder, PostgreSQL default usage, optional MSSQL
usage, and migration/codegen workflows.

## 1. Build and Verify Data Path

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make arlen-data-example
make test-data-layer
```

## 2. Configure Database

Set a connection string in config/environment and choose the adapter through
`database.adapter`.

Common values:

- `postgresql`: default path via `ALNPg`
- `gdl2`: compatibility wrapper over `ALNPg`
- `mssql`: optional SQL Server path via `ALNMSSQL` and an ODBC connection
  string

## 3. Run Migrations

Use migration runner through CLI flows:

```bash
/path/to/Arlen/bin/arlen db migrate
/path/to/Arlen/bin/arlen db migrate --dry-run
```

`arlen migrate` and `arlen module migrate` now use the configured adapter for
the selected database target. PostgreSQL remains the default-first path. MSSQL
requires an ODBC manager/runtime client at deployment time.

For target-aware environments use target-specific config keys and migration
state.

## 4. Compose Queries with ALNSQLBuilder

```objc
NSError *error = nil;
ALNSQLBuilder *builder = [[[ALNSQLBuilder selectFrom:@"users"
                                              columns:@[@"id", @"email"]]
                           whereField:@"status" equals:@"active"]
                           orderByField:@"id" descending:NO];
NSString *sql = [builder buildSQL:&error];
NSArray *params = [builder buildParameters:&error];
```

For non-default dialect compilation, use the explicit dialect seam:

```objc
NSError *error = nil;
NSDictionary *compiled =
    [builder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
NSString *sql = compiled[@"sql"];
NSArray *params = compiled[@"parameters"];
```

Nested subqueries now compile through the same active dialect context. That
means MSSQL rewrites and unsupported-feature checks apply inside nested
builders too, instead of only at the root statement.

## 5. Execute Through Adapter

```objc
NSArray<NSDictionary *> *rows = [db executeBuilderQuery:builder error:&error];
NSDictionary<NSString *, id> *firstRow = ALNDatabaseFirstRow(rows);
```

For scalar reads, prefer the explicit helper surface over open-coded
`rows[0][@"count"]` extraction:

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

PostgreSQL now materializes the supported scalar baseline as Objective-C
runtime values:

- `BOOL`, integer, float: `NSNumber`
- `numeric`: `NSDecimalNumber`
- `date`, `timestamp`, `timestamp with time zone`: `NSDate`
- `bytea`: `NSData`
- `json`, `jsonb`: Foundation objects decoded from JSON
- text-like and unmapped types: `NSString`

If you use schema codegen, decode live rows through the generated contract
instead of manually casting dictionaries:

```objc
NSError *error = nil;
NSArray<NSDictionary *> *rows =
    [db executeQuery:@"SELECT id, created_at FROM users WHERE id = $1"
          parameters:@[ @"u-1" ]
               error:&error];
ALNDBPublicUsersRow *user =
    [ALNDBPublicUsersRow decodeTypedFirstRowFromRows:rows error:&error];
```

Use transactions for write workflows:

- `withTransaction:error:`
- `withTransactionUsingBlock:error:`

Adapter examples:

- `ALNPg` for PostgreSQL
- `ALNMSSQL` for SQL Server over ODBC

## 6. Optional Standalone Reuse (`ArlenData`)

Use `src/ArlenData/ArlenData.h` when consuming the data layer in non-Arlen runtimes.

## 7. Recommended Follow-Up

1. Read [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md).
2. Read [ArlenData Reuse Guide](ARLEN_DATA.md).
3. Read [Phase 20 Roadmap](PHASE20_ROADMAP.md) for the current typed-codec, nested-dialect, and result-helper depth pass.
4. Read [Phase 17 Roadmap](PHASE17_ROADMAP.md) for the backend-neutral seam and optional MSSQL path.
5. Read [API Reference](API_REFERENCE.md) pages for `ALNSQLBuilder`, `ALNPg`, `ALNMSSQL`, and `ALNMigrationRunner`.

Schema codegen note:

- `arlen schema-codegen` remains PostgreSQL-only in the current Phase 17 slice.
