# ALNResponseEnvelopeMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNResponseEnvelopeMiddleware.h`

Middleware that normalizes JSON API responses into a consistent envelope shape.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init;` | Initialize and return a new `ALNResponseEnvelopeMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithIncludeRequestID:` | `- (instancetype)initWithIncludeRequestID:(BOOL)includeRequestID;` | Initialize and return a new `ALNResponseEnvelopeMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
