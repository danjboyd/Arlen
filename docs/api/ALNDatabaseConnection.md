# ALNDatabaseConnection

- Kind: `protocol`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Database-connection protocol defining query/command primitives used by adapters and routers.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `executeQuery:parameters:error:` | `- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return zero or more result rows. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeQueryOne:parameters:error:` | `- (nullable NSDictionary *)executeQueryOne:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return at most one row. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommand:parameters:error:` | `- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL command and return affected-row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `executeQueryResult:parameters:error:` | `- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute a read/query operation and return row dictionaries. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommandBatch:parameterSets:error:` | `- (NSInteger)executeCommandBatch:(NSString *)sql parameterSets:(NSArray<NSArray *> *)parameterSets error:(NSError *_Nullable *_Nullable)error;` | Execute a write/command operation and return affected row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `createSavepointNamed:error:` | `- (BOOL)createSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;` | Perform `create savepoint named` for `ALNDatabaseConnection`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `rollbackToSavepointNamed:error:` | `- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;` | Perform `rollback to savepoint named` for `ALNDatabaseConnection`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `releaseSavepointNamed:error:` | `- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;` | Perform `release savepoint named` for `ALNDatabaseConnection`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `withSavepointNamed:usingBlock:error:` | `- (BOOL)withSavepointNamed:(NSString *)name usingBlock:(BOOL (^)(NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a scoped callback with managed lifecycle semantics. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
