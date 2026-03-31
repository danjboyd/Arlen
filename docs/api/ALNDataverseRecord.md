# ALNDataverseRecord

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `values` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `values` property available on `ALNDataverseRecord`. |
| `formattedValues` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `formattedValues` property available on `ALNDataverseRecord`. |
| `annotations` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `annotations` property available on `ALNDataverseRecord`. |
| `rawDictionary` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `rawDictionary` property available on `ALNDataverseRecord`. |
| `etag` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `etag` property available on `ALNDataverseRecord`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `recordWithDictionary:error:` | `+ (nullable instancetype)recordWithDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError *_Nullable *_Nullable)error;` | Perform `record with dictionary` for `ALNDataverseRecord`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseRecord` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDictionary:error:` | `- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseRecord` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
