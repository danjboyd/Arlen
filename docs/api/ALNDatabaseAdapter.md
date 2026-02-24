# ALNDatabaseAdapter

- Kind: `protocol`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Database-adapter protocol defining connection lifecycle, query primitives, transactions, and capability metadata.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `acquireAdapterConnection:` | `- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;` | Acquire a protocol-typed adapter connection instance. | Capture the returned value and propagate errors/validation as needed. |
| `releaseAdapterConnection:` | `- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;` | Release a protocol-typed adapter connection instance. | Call for side effects; this method does not return a value. |
| `executeQuery:parameters:error:` | `- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return zero or more result rows. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommand:parameters:error:` | `- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL command and return affected-row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `withTransactionUsingBlock:error:` | `- (BOOL)withTransactionUsingBlock: (BOOL (^)(id<ALNDatabaseConnection> connection, NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a callback inside a managed transaction. | Return `YES` from block to commit; return `NO` or set `error` to trigger rollback. |
| `capabilityMetadata` | `- (NSDictionary<NSString *, id> *)capabilityMetadata;` | Return machine-readable capability metadata for this adapter/runtime. | Read this value when you need current runtime/request state. |
