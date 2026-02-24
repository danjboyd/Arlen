# ALNPg

- Kind: `interface`
- Header: `src/Arlen/Data/ALNPg.h`

PostgreSQL adapter with pooled connections and adapter-compatible query/command/transaction APIs.

## Typical Usage

```objc
NSError *error = nil;
ALNPg *db = [[ALNPg alloc] initWithConnectionString:@"postgres://localhost/arlen"
                                     maxConnections:4
                                              error:&error];
NSArray *rows = [db executeQuery:@"SELECT now() AS ts"
                      parameters:@[]
                           error:&error];
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `connectionString` | `NSString *` | `nonatomic, copy, readonly` | Public `connectionString` property available on `ALNPg`. |
| `maxConnections` | `NSUInteger` | `nonatomic, assign, readonly` | Public `maxConnections` property available on `ALNPg`. |
| `preparedStatementReusePolicy` | `ALNPgPreparedStatementReusePolicy` | `nonatomic, assign` | Public `preparedStatementReusePolicy` property available on `ALNPg`. |
| `preparedStatementCacheLimit` | `NSUInteger` | `nonatomic, assign` | Public `preparedStatementCacheLimit` property available on `ALNPg`. |
| `builderCompilationCacheLimit` | `NSUInteger` | `nonatomic, assign` | Public `builderCompilationCacheLimit` property available on `ALNPg`. |
| `includeSQLInDiagnosticsEvents` | `BOOL` | `nonatomic, assign` | Public `includeSQLInDiagnosticsEvents` property available on `ALNPg`. |
| `emitDiagnosticsEventsToStderr` | `BOOL` | `nonatomic, assign` | Public `emitDiagnosticsEventsToStderr` property available on `ALNPg`. |
| `queryDiagnosticsListener` | `ALNPgQueryDiagnosticsListener` | `nonatomic, copy, nullable` | Public `queryDiagnosticsListener` property available on `ALNPg`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `capabilityMetadata` | `+ (NSDictionary<NSString *, id> *)capabilityMetadata;` | Return machine-readable capability metadata for this adapter/runtime. | Call on the class type, not on an instance. |
| `initWithConnectionString:maxConnections:error:` | `- (nullable instancetype)initWithConnectionString:(NSString *)connectionString maxConnections:(NSUInteger)maxConnections error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNPg` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `acquireConnection:` | `- (nullable ALNPgConnection *)acquireConnection:(NSError *_Nullable *_Nullable)error;` | Acquire a pooled database connection instance. | Capture the returned value and propagate errors/validation as needed. |
| `releaseConnection:` | `- (void)releaseConnection:(ALNPgConnection *)connection;` | Release a pooled database connection back to the adapter. | Call for side effects; this method does not return a value. |
| `acquireAdapterConnection:` | `- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;` | Acquire a protocol-typed adapter connection instance. | Capture the returned value and propagate errors/validation as needed. |
| `releaseAdapterConnection:` | `- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;` | Release a protocol-typed adapter connection instance. | Call for side effects; this method does not return a value. |
| `executeQuery:parameters:error:` | `- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return zero or more result rows. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeBuilderQuery:error:` | `- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` query. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommand:parameters:error:` | `- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL command and return affected-row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `executeBuilderCommand:error:` | `- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` command. | Pass `NSError **` when you need detailed failure diagnostics. |
| `withTransaction:error:` | `- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection, NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a scoped callback with managed lifecycle semantics. | Return `YES` from block to commit; return `NO` or set `error` to trigger rollback. |
| `withTransactionUsingBlock:error:` | `- (BOOL)withTransactionUsingBlock: (BOOL (^)(id<ALNDatabaseConnection> connection, NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a callback inside a managed transaction. | Return `YES` from block to commit; return `NO` or set `error` to trigger rollback. |
