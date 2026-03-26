# ALNDatabaseInspector

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseInspector.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `inspectSchemaColumnsForAdapter:error:` | `+ (nullable NSArray<NSDictionary<NSString *, id> *> *)inspectSchemaColumnsForAdapter:(id<ALNDatabaseAdapter>)adapter error:(NSError *_Nullable *_Nullable)error;` | Perform `inspect schema columns for adapter` for `ALNDatabaseInspector`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
