# ALNRequest

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNRequest.h`

Immutable HTTP request model containing method/path/query/headers/body and parsed parameter helpers.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `method` | `NSString *` | `nonatomic, copy, readonly` | Public `method` property available on `ALNRequest`. |
| `path` | `NSString *` | `nonatomic, copy, readonly` | Public `path` property available on `ALNRequest`. |
| `queryString` | `NSString *` | `nonatomic, copy, readonly` | Public `queryString` property available on `ALNRequest`. |
| `headers` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNRequest`. |
| `body` | `NSData *` | `nonatomic, strong, readonly` | Public `body` property available on `ALNRequest`. |
| `queryParams` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `queryParams` property available on `ALNRequest`. |
| `cookies` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `cookies` property available on `ALNRequest`. |
| `routeParams` | `NSDictionary *` | `nonatomic, copy` | Public `routeParams` property available on `ALNRequest`. |
| `remoteAddress` | `NSString *` | `nonatomic, copy` | Public `remoteAddress` property available on `ALNRequest`. |
| `effectiveRemoteAddress` | `NSString *` | `nonatomic, copy` | Public `effectiveRemoteAddress` property available on `ALNRequest`. |
| `scheme` | `NSString *` | `nonatomic, copy` | Public `scheme` property available on `ALNRequest`. |
| `parseDurationMilliseconds` | `double` | `nonatomic, assign` | Public `parseDurationMilliseconds` property available on `ALNRequest`. |
| `responseWriteDurationMilliseconds` | `double` | `nonatomic, assign` | Public `responseWriteDurationMilliseconds` property available on `ALNRequest`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithMethod:path:queryString:headers:body:` | `- (instancetype)initWithMethod:(NSString *)method path:(NSString *)path queryString:(NSString *)queryString headers:(NSDictionary *)headers body:(NSData *)body;` | Initialize and return a new `ALNRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `requestFromRawData:error:` | `+ (nullable ALNRequest *)requestFromRawData:(NSData *)data error:(NSError *_Nullable *_Nullable)error;` | Parse an HTTP request object from raw wire bytes. | Useful for parser tests and custom socket harnesses; validate that method/path/headers were parsed as expected. |
