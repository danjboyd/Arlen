# ALNRateLimitMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNRateLimitMiddleware.h`

In-memory rate limiting middleware for per-window request throttling.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithMaxRequests:windowSeconds:` | `- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests windowSeconds:(NSUInteger)windowSeconds;` | Initialize and return a new `ALNRateLimitMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithMaxRequests:windowSeconds:ipv6PrefixLength:` | `- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests windowSeconds:(NSUInteger)windowSeconds ipv6PrefixLength:(NSUInteger)ipv6PrefixLength;` | Initialize and return a new `ALNRateLimitMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
