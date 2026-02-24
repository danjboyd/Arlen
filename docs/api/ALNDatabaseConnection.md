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
