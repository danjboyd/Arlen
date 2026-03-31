# ALNDataverseBatchRequest

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `method` | `NSString *` | `nonatomic, copy, readonly` | Public `method` property available on `ALNDataverseBatchRequest`. |
| `relativePath` | `NSString *` | `nonatomic, copy, readonly` | Public `relativePath` property available on `ALNDataverseBatchRequest`. |
| `headers` | `NSDictionary<NSString *, NSString *> *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNDataverseBatchRequest`. |
| `bodyObject` | `id` | `nonatomic, strong, readonly, nullable` | Public `bodyObject` property available on `ALNDataverseBatchRequest`. |
| `contentID` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `contentID` property available on `ALNDataverseBatchRequest`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `requestWithMethod:relativePath:headers:bodyObject:contentID:` | `+ (instancetype)requestWithMethod:(NSString *)method relativePath:(NSString *)relativePath headers:(nullable NSDictionary<NSString *, NSString *> *)headers bodyObject:(nullable id)bodyObject contentID:(nullable NSString *)contentID;` | Perform `request with method` for `ALNDataverseBatchRequest`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseBatchRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithMethod:relativePath:headers:bodyObject:contentID:` | `- (instancetype)initWithMethod:(NSString *)method relativePath:(NSString *)relativePath headers:(nullable NSDictionary<NSString *, NSString *> *)headers bodyObject:(nullable id)bodyObject contentID:(nullable NSString *)contentID NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseBatchRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
