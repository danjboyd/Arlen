# ALNDataverseMetadata

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseMetadata.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `normalizedMetadataFromPayload:error:` | `+ (nullable NSDictionary<NSString *, id> *)normalizedMetadataFromPayload:(id)payload error:(NSError *_Nullable *_Nullable)error;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `fetchNormalizedMetadataWithClient:logicalNames:error:` | `+ (nullable NSDictionary<NSString *, id> *)fetchNormalizedMetadataWithClient:(ALNDataverseClient *)client logicalNames:(nullable NSArray<NSString *> *)logicalNames error:(NSError *_Nullable *_Nullable)error;` | Perform `fetch normalized metadata with client` for `ALNDataverseMetadata`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
