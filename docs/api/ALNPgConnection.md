# ALNPgConnection

- Kind: `interface`
- Header: `src/Arlen/Data/ALNPg.h`

PostgreSQL connection wrapper with SQL execution, prepared statements, transactions, and builder execution helpers.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `connectionString` | `NSString *` | `nonatomic, copy, readonly` | Public `connectionString` property available on `ALNPgConnection`. |
| `open` | `BOOL` | `nonatomic, assign, readonly, getter=isOpen` | Public `open` property available on `ALNPgConnection`. |
| `preparedStatementReusePolicy` | `ALNPgPreparedStatementReusePolicy` | `nonatomic, assign` | Public `preparedStatementReusePolicy` property available on `ALNPgConnection`. |
| `preparedStatementCacheLimit` | `NSUInteger` | `nonatomic, assign` | Public `preparedStatementCacheLimit` property available on `ALNPgConnection`. |
| `builderCompilationCacheLimit` | `NSUInteger` | `nonatomic, assign` | Public `builderCompilationCacheLimit` property available on `ALNPgConnection`. |
| `includeSQLInDiagnosticsEvents` | `BOOL` | `nonatomic, assign` | Public `includeSQLInDiagnosticsEvents` property available on `ALNPgConnection`. |
| `emitDiagnosticsEventsToStderr` | `BOOL` | `nonatomic, assign` | Public `emitDiagnosticsEventsToStderr` property available on `ALNPgConnection`. |
| `queryDiagnosticsListener` | `ALNPgQueryDiagnosticsListener` | `nonatomic, copy, nullable` | Public `queryDiagnosticsListener` property available on `ALNPgConnection`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithConnectionString:error:` | `- (nullable instancetype)initWithConnectionString:(NSString *)connectionString error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNPgConnection` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `close` | `- (void)close;` | Close the active resource/connection and release underlying handles. | Call for side effects; this method does not return a value. |
| `prepareStatementNamed:sql:parameterCount:error:` | `- (BOOL)prepareStatementNamed:(NSString *)name sql:(NSString *)sql parameterCount:(NSInteger)parameterCount error:(NSError *_Nullable *_Nullable)error;` | Prepare a named SQL statement on the active connection. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `executeQuery:parameters:error:` | `- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return zero or more result rows. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeQueryOne:parameters:error:` | `- (nullable NSDictionary *)executeQueryOne:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL query and return at most one row. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommand:parameters:error:` | `- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute SQL command and return affected-row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `executePreparedQueryNamed:parameters:error:` | `- (nullable NSArray<NSDictionary *> *)executePreparedQueryNamed:(NSString *)name parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute a prepared query statement by name. | Pass `NSError **` and treat a `nil` result as failure. |
| `executePreparedCommandNamed:parameters:error:` | `- (NSInteger)executePreparedCommandNamed:(NSString *)name parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute a prepared command statement by name. | Pass `NSError **` when you need detailed failure diagnostics. |
| `beginTransaction:` | `- (BOOL)beginTransaction:(NSError *_Nullable *_Nullable)error;` | Begin SQL transaction on current connection. | Always pair with the corresponding `end...` call to avoid leaked state. |
| `commitTransaction:` | `- (BOOL)commitTransaction:(NSError *_Nullable *_Nullable)error;` | Commit SQL transaction on current connection. | Check the return value to confirm the operation succeeded. |
| `rollbackTransaction:` | `- (BOOL)rollbackTransaction:(NSError *_Nullable *_Nullable)error;` | Roll back SQL transaction on current connection. | Check the return value to confirm the operation succeeded. |
| `executeBuilderQuery:error:` | `- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` query. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeBuilderCommand:error:` | `- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` command. | Pass `NSError **` when you need detailed failure diagnostics. |
| `resetExecutionCaches` | `- (void)resetExecutionCaches;` | Reset prepared-statement and builder compilation caches. | Call for side effects; this method does not return a value. |
