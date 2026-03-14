# ALNMSSQLSQLBuilder

- Kind: `interface`
- Header: `src/Arlen/Data/ALNMSSQLSQLBuilder.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `buildForMSSQL:` | `- (nullable NSDictionary *)buildForMSSQL:(NSError *_Nullable *_Nullable)error;` | Build a deterministic compiled representation. | Treat returned collection values as snapshots unless the API documents mutability. |
| `buildMSSQLSQL:` | `- (nullable NSString *)buildMSSQLSQL:(NSError *_Nullable *_Nullable)error;` | Build a deterministic compiled representation. | Capture the returned value and propagate errors/validation as needed. |
| `buildMSSQLParameters:` | `- (NSArray *)buildMSSQLParameters:(NSError *_Nullable *_Nullable)error;` | Build a deterministic compiled representation. | Treat returned collection values as snapshots unless the API documents mutability. |
