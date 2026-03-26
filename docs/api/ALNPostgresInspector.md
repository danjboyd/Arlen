# ALNPostgresInspector

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseInspector.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `inspectSchemaColumnsWithAdapter:error:` | `+ (nullable NSArray<NSDictionary<NSString *, id> *> *)inspectSchemaColumnsWithAdapter:(id<ALNDatabaseAdapter>)adapter error:(NSError *_Nullable *_Nullable)error;` | Perform `inspect schema columns with adapter` for `ALNPostgresInspector`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `normalizedColumnsFromInspectionRows:error:` | `+ (nullable NSArray<NSDictionary<NSString *, id> *> *)normalizedColumnsFromInspectionRows:(NSArray<NSDictionary *> *)rows error:(NSError *_Nullable *_Nullable)error;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `inspectSchemaMetadataWithAdapter:error:` | `+ (nullable NSDictionary<NSString *, id> *)inspectSchemaMetadataWithAdapter:(id<ALNDatabaseAdapter>)adapter error:(NSError *_Nullable *_Nullable)error;` | Perform `inspect schema metadata with adapter` for `ALNPostgresInspector`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
