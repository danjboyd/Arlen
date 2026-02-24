# ALNCSRFMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNCSRFMiddleware.h`

CSRF validation middleware for state-changing requests using token headers/query params.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithHeaderName:queryParamName:` | `- (instancetype)initWithHeaderName:(nullable NSString *)headerName queryParamName:(nullable NSString *)queryParamName;` | Initialize and return a new `ALNCSRFMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
