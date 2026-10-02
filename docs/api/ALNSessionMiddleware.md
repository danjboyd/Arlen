# ALNSessionMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNSessionMiddleware.h`

Session middleware that signs/verifies cookie-backed session state for request context access.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `cookieName` | `NSString *` | `nonatomic, copy, readonly` | Public `cookieName` property available on `ALNSessionMiddleware`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithSecret:cookieName:maxAgeSeconds:secure:sameSite:` | `- (instancetype)initWithSecret:(NSString *)secret cookieName:(nullable NSString *)cookieName maxAgeSeconds:(NSUInteger)maxAgeSeconds secure:(BOOL)secure sameSite:(nullable NSString *)sameSite;` | Initialize and return a new `ALNSessionMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `encodeSessionDictionary:` | `- (nullable NSString *)encodeSessionDictionary:(NSDictionary *)session;` | Perform `encode session dictionary` for `ALNSessionMiddleware`. | Capture the returned value and propagate errors/validation as needed. |
| `sessionDictionaryFromCookieValue:` | `- (nullable NSDictionary *)sessionDictionaryFromCookieValue:(NSString *)value;` | Perform `session dictionary from cookie value` for `ALNSessionMiddleware`. | Treat returned collection values as snapshots unless the API documents mutability. |
