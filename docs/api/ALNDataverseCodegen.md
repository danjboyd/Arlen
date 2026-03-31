# ALNDataverseCodegen

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseCodegen.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `renderArtifactsFromMetadata:classPrefix:dataverseTarget:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromMetadata:(NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix dataverseTarget:(nullable NSString *)dataverseTarget error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
