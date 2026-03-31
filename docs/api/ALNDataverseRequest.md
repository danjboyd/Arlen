# ALNDataverseRequest

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `method` | `NSString *` | `nonatomic, copy, readonly` | Public `method` property available on `ALNDataverseRequest`. |
| `URLString` | `NSString *` | `nonatomic, copy, readonly` | Public `URLString` property available on `ALNDataverseRequest`. |
| `headers` | `NSDictionary<NSString *, NSString *> *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNDataverseRequest`. |
| `bodyData` | `NSData *` | `nonatomic, copy, readonly, nullable` | Public `bodyData` property available on `ALNDataverseRequest`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithMethod:URLString:headers:bodyData:` | `- (instancetype)initWithMethod:(NSString *)method URLString:(NSString *)URLString headers:(nullable NSDictionary<NSString *, NSString *> *)headers bodyData:(nullable NSData *)bodyData NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
