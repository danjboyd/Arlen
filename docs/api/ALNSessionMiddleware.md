# ALNSessionMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNSessionMiddleware.h`

Session middleware that signs/verifies cookie-backed session state for request context access.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithSecret:cookieName:maxAgeSeconds:secure:sameSite:` | `- (instancetype)initWithSecret:(NSString *)secret cookieName:(nullable NSString *)cookieName maxAgeSeconds:(NSUInteger)maxAgeSeconds secure:(BOOL)secure sameSite:(nullable NSString *)sameSite;` | Initialize and return a new `ALNSessionMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
