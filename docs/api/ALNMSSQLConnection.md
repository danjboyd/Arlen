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
| `beginTransaction:` | `- (BOOL)beginTransaction:(NSError *_Nullable *_Nullable)error;` | Begin SQL transaction on current connection. | Always pair with the corresponding `end...` call to avoid leaked state. |
| `commitTransaction:` | `- (BOOL)commitTransaction:(NSError *_Nullable *_Nullable)error;` | Commit SQL transaction on current connection. | Check the return value to confirm the operation succeeded. |
| `rollbackTransaction:` | `- (BOOL)rollbackTransaction:(NSError *_Nullable *_Nullable)error;` | Roll back SQL transaction on current connection. | Check the return value to confirm the operation succeeded. |
| `executeBuilderQuery:error:` | `- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` query. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeBuilderCommand:error:` | `- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Compile and execute an `ALNSQLBuilder` command. | Pass `NSError **` when you need detailed failure diagnostics. |
