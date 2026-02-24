# ALNSecurityHeadersMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNSecurityHeadersMiddleware.h`

Middleware that injects security-related response headers (including optional CSP).

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithContentSecurityPolicy:` | `- (instancetype)initWithContentSecurityPolicy:(nullable NSString *)contentSecurityPolicy;` | Initialize and return a new `ALNSecurityHeadersMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
