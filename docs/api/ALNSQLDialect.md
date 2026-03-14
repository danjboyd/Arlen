# ALNSQLDialect

- Kind: `protocol`
- Header: `src/Arlen/Data/ALNSQLDialect.h`

Protocol contract exported as part of the `ALNSQLDialect` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `dialectName` | `- (NSString *)dialectName;` | Perform `dialect name` for `ALNSQLDialect`. | Read this value when you need current runtime/request state. |
| `capabilityMetadata` | `- (NSDictionary<NSString *, id> *)capabilityMetadata;` | Return machine-readable capability metadata for this adapter/runtime. | Read this value when you need current runtime/request state. |
| `compileBuilder:error:` | `- (nullable NSDictionary *)compileBuilder:(ALNSQLBuilder *)builder error:(NSError *_Nullable *_Nullable)error;` | Perform `compile builder` for `ALNSQLDialect`. | Pass `NSError **` and treat a `nil` result as failure. |
| `migrationStateTableCreateSQLForTableName:error:` | `- (nullable NSString *)migrationStateTableCreateSQLForTableName:(NSString *)tableName error:(NSError *_Nullable *_Nullable)error;` | Perform `migration state table create sql for table name` for `ALNSQLDialect`. | Pass `NSError **` and treat a `nil` result as failure. |
| `migrationVersionsSelectSQLForTableName:error:` | `- (nullable NSString *)migrationVersionsSelectSQLForTableName:(NSString *)tableName error:(NSError *_Nullable *_Nullable)error;` | Perform `migration versions select sql for table name` for `ALNSQLDialect`. | Pass `NSError **` and treat a `nil` result as failure. |
| `migrationVersionInsertSQLForTableName:error:` | `- (nullable NSString *)migrationVersionInsertSQLForTableName:(NSString *)tableName error:(NSError *_Nullable *_Nullable)error;` | Perform `migration version insert sql for table name` for `ALNSQLDialect`. | Pass `NSError **` and treat a `nil` result as failure. |
