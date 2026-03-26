# ALNDatabaseAdapter

- Kind: `protocol`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Database-adapter protocol defining connection lifecycle, query primitives, transactions, and capability metadata.

## Helper Functions

`src/Arlen/Data/ALNDatabaseAdapter.h` also exposes small result helpers that
preserve the dictionary-row contract while removing common scalar/first-row
boilerplate:

| Symbol | Signature | Purpose |
| --- | --- | --- |
| `ALNDatabaseFirstRow` | `NSDictionary<NSString *, id> *_Nullable ALNDatabaseFirstRow(NSArray<NSDictionary *> *_Nullable rows);` | Return the first dictionary row or `nil`. |
| `ALNDatabaseScalarValueFromRow` | `id _Nullable ALNDatabaseScalarValueFromRow(NSDictionary<NSString *, id> *_Nullable row, NSString *_Nullable columnName, NSError *_Nullable *_Nullable error);` | Extract a scalar from one row, with explicit diagnostics when the row is empty, ambiguous, or missing the requested column. |
| `ALNDatabaseScalarValueFromRows` | `id _Nullable ALNDatabaseScalarValueFromRows(NSArray<NSDictionary *> *_Nullable rows, NSString *_Nullable columnName, NSError *_Nullable *_Nullable error);` | Extract a scalar from the first row of a result set. |
| `ALNDatabaseExecuteScalarQuery` | `id _Nullable ALNDatabaseExecuteScalarQuery(id<ALNDatabaseConnection> connection, NSString *sql, NSArray *_Nullable parameters, NSString *_Nullable columnName, NSError *_Nullable *_Nullable error);` | Execute a query through a connection and return a single scalar value. |

Additional adapter-helper diagnostics use `ALNDatabaseAdapterErrorInvalidResult`
when a row shape cannot honestly satisfy the requested scalar contract.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `acquireAdapterConnection:` | `- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;` | Acquire a protocol-typed adapter connection instance. | Capture the returned value and propagate errors/validation as needed. |
| `releaseAdapterConnection:` | `- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;` | Release a protocol-typed adapter connection instance. | Call for side effects; this method does not return a value. |
| `executeQuery:parameters:error:` | `- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return zero or more result rows. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommand:parameters:error:` | `- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL command and return affected-row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `withTransactionUsingBlock:error:` | `- (BOOL)withTransactionUsingBlock: (BOOL (^)(id<ALNDatabaseConnection> connection, NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a callback inside a managed transaction. | Return `YES` from block to commit; return `NO` or set `error` to trigger rollback. |
| `sqlDialect` | `- (nullable id<ALNSQLDialect>)sqlDialect;` | Perform `sql dialect` for `ALNDatabaseAdapter`. | Read this value when you need current runtime/request state. |
| `capabilityMetadata` | `- (NSDictionary<NSString *, id> *)capabilityMetadata;` | Return machine-readable capability metadata for this adapter/runtime. | Read this value when you need current runtime/request state. |
