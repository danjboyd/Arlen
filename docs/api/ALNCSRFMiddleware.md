# ALNCSRFMiddleware

- Kind: `interface`
- Header: `src/Arlen/MVC/Middleware/ALNCSRFMiddleware.h`

CSRF validation middleware for state-changing requests using token headers/query params.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithHeaderName:queryParamName:` | `- (instancetype)initWithHeaderName:(nullable NSString *)headerName queryParamName:(nullable NSString *)queryParamName;` | Initialize and return a new `ALNCSRFMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithHeaderName:queryParamName:allowQueryParamFallback:` | `- (instancetype)initWithHeaderName:(nullable NSString *)headerName queryParamName:(nullable NSString *)queryParamName allowQueryParamFallback:(BOOL)allowQueryParamFallback;` | Initialize and return a new `ALNCSRFMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithHeaderName:queryParamName:allowQueryParamFallback:exemptPathPrefixes:` | `- (instancetype)initWithHeaderName:(nullable NSString *)headerName queryParamName:(nullable NSString *)queryParamName allowQueryParamFallback:(BOOL)allowQueryParamFallback exemptPathPrefixes:(nullable NSArray<NSString *> *)exemptPathPrefixes;` | Initialize and return a new `ALNCSRFMiddleware` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `normalizedExemptPathPrefixes:problem:` | `+ (nullable NSArray<NSString *> *)normalizedExemptPathPrefixes:(nullable id)value problem:(NSString *_Nullable *_Nullable)problem;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. |
