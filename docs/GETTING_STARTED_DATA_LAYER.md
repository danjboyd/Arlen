# Getting Started: Data-Layer Track

This track focuses on SQL builder, PostgreSQL adapter usage, and migration/codegen workflows.

## 1. Build and Verify Data Path

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make arlen-data-example
make test-data-layer
```

## 2. Configure Database

Set connection string in config/environment and initialize `ALNPg` with a pool size appropriate for your runtime profile.

## 3. Run Migrations

Use migration runner through CLI flows:

```bash
/path/to/Arlen/bin/arlen db migrate
/path/to/Arlen/bin/arlen db migrate --dry-run
```

For target-aware environments use target-specific config keys and migration state.

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

## 5. Execute Through Adapter

```objc
NSArray *rows = [db executeBuilderQuery:builder error:&error];
```

Use transactions for write workflows:

- `withTransaction:error:`
- `withTransactionUsingBlock:error:`

## 6. Optional Standalone Reuse (`ArlenData`)

Use `src/ArlenData/ArlenData.h` when consuming the data layer in non-Arlen runtimes.

## 7. Recommended Follow-Up

1. Read [SQL Builder Conformance Matrix](SQL_BUILDER_CONFORMANCE_MATRIX.md).
2. Read [ArlenData Reuse Guide](ARLEN_DATA.md).
3. Read [API Reference](API_REFERENCE.md) pages for `ALNSQLBuilder`, `ALNPg`, and `ALNMigrationRunner`.
