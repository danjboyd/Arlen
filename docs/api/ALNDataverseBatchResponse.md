# ALNDataverseBatchResponse

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `statusCode` | `NSInteger` | `nonatomic, assign, readonly` | Public `statusCode` property available on `ALNDataverseBatchResponse`. |
| `headers` | `NSDictionary<NSString *, NSString *> *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNDataverseBatchResponse`. |
| `bodyObject` | `id` | `nonatomic, strong, readonly, nullable` | Public `bodyObject` property available on `ALNDataverseBatchResponse`. |
| `bodyText` | `NSString *` | `nonatomic, copy, readonly` | Public `bodyText` property available on `ALNDataverseBatchResponse`. |
| `contentID` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `contentID` property available on `ALNDataverseBatchResponse`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseBatchResponse` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithStatusCode:headers:bodyObject:bodyText:contentID:` | `- (instancetype)initWithStatusCode:(NSInteger)statusCode headers:(nullable NSDictionary<NSString *, NSString *> *)headers bodyObject:(nullable id)bodyObject bodyText:(nullable NSString *)bodyText contentID:(nullable NSString *)contentID NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseBatchResponse` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
