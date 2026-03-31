# ALNDataverseEntityPage

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `records` | `NSArray<ALNDataverseRecord *> *` | `nonatomic, copy, readonly` | Public `records` property available on `ALNDataverseEntityPage`. |
| `nextLinkURLString` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `nextLinkURLString` property available on `ALNDataverseEntityPage`. |
| `deltaLinkURLString` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `deltaLinkURLString` property available on `ALNDataverseEntityPage`. |
| `totalCount` | `NSNumber *` | `nonatomic, strong, readonly, nullable` | Public `totalCount` property available on `ALNDataverseEntityPage`. |
| `rawPayload` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `rawPayload` property available on `ALNDataverseEntityPage`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `pageWithPayload:error:` | `+ (nullable instancetype)pageWithPayload:(NSDictionary<NSString *, id> *)payload error:(NSError *_Nullable *_Nullable)error;` | Perform `page with payload` for `ALNDataverseEntityPage`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseEntityPage` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithPayload:error:` | `- (nullable instancetype)initWithPayload:(NSDictionary<NSString *, id> *)payload error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseEntityPage` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
