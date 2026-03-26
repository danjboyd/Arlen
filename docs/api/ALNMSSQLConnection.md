# ALNMSSQLConnection

- Kind: `interface`
- Header: `src/Arlen/Data/ALNMSSQL.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `connectionString` | `NSString *` | `nonatomic, copy, readonly` | Public `connectionString` property available on `ALNMSSQLConnection`. |
| `open` | `BOOL` | `nonatomic, assign, readonly, getter=isOpen` | Public `open` property available on `ALNMSSQLConnection`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithConnectionString:error:` | `- (nullable instancetype)initWithConnectionString:(NSString *)connectionString error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNMSSQLConnection` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `close` | `- (void)close;` | Close the active resource/connection and release underlying handles. | Call for side effects; this method does not return a value. |
| `executeQueryResult:parameters:error:` | `- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql parameters:(NSArray *)parameters error:(NSError *_Nullable *_Nullable)error;` | Execute a read/query operation and return row dictionaries. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommandBatch:parameterSets:error:` | `- (NSInteger)executeCommandBatch:(NSString *)sql parameterSets:(NSArray<NSArray *> *)parameterSets error:(NSError *_Nullable *_Nullable)error;` | Execute a write/command operation and return affected row count. | Pass `NSError **` when you need detailed failure diagnostics. |
| `beginTransaction:` | `- (BOOL)beginTransaction:(NSError *_Nullable *_Nullable)error;` | Begin SQL transaction on current connection. | Always pair with the corresponding `end...` call to avoid leaked state. |
| `commitTransaction:` | `- (BOOL)commitTransaction:(NSError *_Nullable *_Nullable)error;` | Commit SQL transaction on current connection. | Check the return value to confirm the operation succeeded. |
| `rollbackTransaction:` | `- (BOOL)rollbackTransaction:(NSError *_Nullable *_Nullable)error;` | Roll back SQL transaction on current connection. | Check the return value to confirm the operation succeeded. |
| `createSavepointNamed:error:` | `- (BOOL)createSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;` | Perform `create savepoint named` for `ALNMSSQLConnection`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `rollbackToSavepointNamed:error:` | `- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;` | Perform `rollback to savepoint named` for `ALNMSSQLConnection`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `releaseSavepointNamed:error:` | `- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;` | Perform `release savepoint named` for `ALNMSSQLConnection`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `withSavepointNamed:usingBlock:error:` | `- (BOOL)withSavepointNamed:(NSString *)name usingBlock:(BOOL (^)(NSError *_Nullable *_Nullable error))block error:(NSError *_Nullable *_Nullable)error;` | Run a scoped callback with managed lifecycle semantics. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `executeBuilderQuery:error:` | `- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` query. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeBuilderCommand:error:` | `- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` command. | Pass `NSError **` when you need detailed failure diagnostics. |
