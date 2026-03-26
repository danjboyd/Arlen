# ALNMSSQL

- Kind: `interface`
- Header: `src/Arlen/Data/ALNMSSQL.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `connectionString` | `NSString *` | `nonatomic, copy, readonly` | Public `connectionString` property available on `ALNMSSQL`. |
| `maxConnections` | `NSUInteger` | `nonatomic, assign, readonly` | Public `maxConnections` property available on `ALNMSSQL`. |
| `connectionLivenessChecksEnabled` | `BOOL` | `nonatomic, assign` | Public `connectionLivenessChecksEnabled` property available on `ALNMSSQL`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `capabilityMetadata` | `+ (NSDictionary<NSString *, id> *)capabilityMetadata;` | Return machine-readable capability metadata for this adapter/runtime. | Call on the class type, not on an instance. |
| `initWithConnectionString:maxConnections:error:` | `- (nullable instancetype)initWithConnectionString:(NSString *)connectionString maxConnections:(NSUInteger)maxConnections error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNMSSQL` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `acquireConnection:` | `- (nullable ALNMSSQLConnection *)acquireConnection:(NSError *_Nullable *_Nullable)error;` | Acquire a pooled database connection instance. | Capture the returned value and propagate errors/validation as needed. |
| `releaseConnection:` | `- (void)releaseConnection:(ALNMSSQLConnection *)connection;` | Release a pooled database connection back to the adapter. | Call for side effects; this method does not return a value. |
| `executeQueryResult:parameters:error:` | `- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute a read/query operation and return row dictionaries. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommandBatch:parameterSets:error:` | `- (NSInteger)executeCommandBatch:(NSString *)sql parameterSets:(NSArray<NSArray *> *)parameterSets error:(NSError *_Nullable *_Nullable)error;` | Execute a write/command operation and return affected row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `executeBuilderQuery:error:` | `- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` query. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeBuilderCommand:error:` | `- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` command. | Pass `NSError **` when you need detailed failure diagnostics. |
| `withTransaction:error:` | `- (BOOL)withTransaction:(BOOL (^)(ALNMSSQLConnection *connection, NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a scoped callback with managed lifecycle semantics. | Return `YES` from block to commit; return `NO` or set `error` to trigger rollback. |
