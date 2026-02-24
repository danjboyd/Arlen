# ALNGDL2Adapter

- Kind: `interface`
- Header: `src/Arlen/Data/ALNGDL2Adapter.h`

Optional GDL2 compatibility adapter with fallback behavior when native GDL2 runtime is unavailable.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `fallbackAdapter` | `ALNPg *` | `nonatomic, strong, readonly` | Adapter used by this runtime for the corresponding service concern. |
| `migrationMode` | `NSString *` | `nonatomic, copy, readonly` | Public `migrationMode` property available on `ALNGDL2Adapter`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `capabilityMetadata` | `+ (NSDictionary<NSString *, id> *)capabilityMetadata;` | Return machine-readable capability metadata for this adapter/runtime. | Call on the class type, not on an instance. |
| `initWithConnectionString:maxConnections:error:` | `- (nullable instancetype)initWithConnectionString:(NSString *)connectionString maxConnections:(NSUInteger)maxConnections error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNGDL2Adapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithFallbackAdapter:` | `- (instancetype)initWithFallbackAdapter:(ALNPg *)fallbackAdapter;` | Initialize and return a new `ALNGDL2Adapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `isNativeGDL2RuntimeAvailable` | `+ (BOOL)isNativeGDL2RuntimeAvailable;` | Return whether native GDL2 runtime support is available. | Call on the class type, not on an instance. |
