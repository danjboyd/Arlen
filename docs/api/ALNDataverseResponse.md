# ALNDataverseResponse

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `statusCode` | `NSInteger` | `nonatomic, assign, readonly` | Public `statusCode` property available on `ALNDataverseResponse`. |
| `headers` | `NSDictionary<NSString *, NSString *> *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNDataverseResponse`. |
| `bodyData` | `NSData *` | `nonatomic, copy, readonly` | Public `bodyData` property available on `ALNDataverseResponse`. |
| `bodyText` | `NSString *` | `nonatomic, copy, readonly` | Public `bodyText` property available on `ALNDataverseResponse`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseResponse` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithStatusCode:headers:bodyData:` | `- (instancetype)initWithStatusCode:(NSInteger)statusCode headers:(nullable NSDictionary<NSString *, NSString *> *)headers bodyData:(nullable NSData *)bodyData NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseResponse` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `headerValueForName:` | `- (nullable NSString *)headerValueForName:(NSString *)name;` | Return a request header value by key. | Capture the returned value and propagate errors/validation as needed. |
| `JSONObject:` | `- (nullable id)JSONObject:(NSError *_Nullable *_Nullable)error;` | Perform `json object` for `ALNDataverseResponse`. | Capture the returned value and propagate errors/validation as needed. |
