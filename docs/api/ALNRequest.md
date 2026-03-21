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
| `httpVersion` | `NSString *` | `nonatomic, copy, readonly` | Public `httpVersion` property available on `ALNRequest`. |
| `headers` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNRequest`. |
| `body` | `NSData *` | `nonatomic, strong, readonly` | Public `body` property available on `ALNRequest`. |
| `queryParams` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `queryParams` property available on `ALNRequest`. |
| `formParams` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `formParams` property available on `ALNRequest`. |
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
| `headerValueForName:` | `- (NSString *)headerValueForName:(NSString *)name;` | Return a request header value by key. | Capture the returned value and propagate errors/validation as needed. |
| `queryValueForName:` | `- (nullable NSString *)queryValueForName:(NSString *)name;` | Return a query-string parameter by key. | Capture the returned value and propagate errors/validation as needed. |
| `initWithMethod:path:queryString:httpVersion:headers:body:` | `- (instancetype)initWithMethod:(NSString *)method path:(NSString *)path queryString:(NSString *)queryString httpVersion:(NSString *)httpVersion headers:(NSDictionary *)headers body:(NSData *)body;` | Initialize and return a new `ALNRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithMethod:path:queryString:headers:body:` | `- (instancetype)initWithMethod:(NSString *)method path:(NSString *)path queryString:(NSString *)queryString headers:(NSDictionary *)headers body:(NSData *)body;` | Initialize and return a new `ALNRequest` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `requestFromRawData:error:` | `+ (nullable ALNRequest *)requestFromRawData:(NSData *)data error:(NSError *_Nullable *_Nullable)error;` | Parse an HTTP request object from raw wire bytes. | Useful for parser tests and custom socket harnesses; validate that method/path/headers were parsed as expected. |
| `requestFromRawData:backend:error:` | `+ (nullable ALNRequest *)requestFromRawData:(NSData *)data backend:(ALNHTTPParserBackend)backend error:(NSError *_Nullable *_Nullable)error;` | Perform `request from raw data` for `ALNRequest`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `requestFromBufferedData:backend:consumedLength:headersComplete:contentLength:error:` | `+ (nullable ALNRequest *)requestFromBufferedData:(NSData *)data backend:(ALNHTTPParserBackend)backend consumedLength:(NSUInteger *_Nullable)consumedLength headersComplete:(BOOL *_Nullable)headersComplete contentLength:(NSInteger *_Nullable)contentLength error:(NSError *_Nullable *_Nullable)error;` | Perform `request from buffered data` for `ALNRequest`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `resolvedParserBackend` | `+ (ALNHTTPParserBackend)resolvedParserBackend;` | Perform `resolved parser backend` for `ALNRequest`. | Call on the class type, not on an instance. |
| `resolvedParserBackendName` | `+ (NSString *)resolvedParserBackendName;` | Perform `resolved parser backend name` for `ALNRequest`. | Call on the class type, not on an instance. |
| `parserBackendNameForBackend:` | `+ (NSString *)parserBackendNameForBackend:(ALNHTTPParserBackend)backend;` | Perform `parser backend name for backend` for `ALNRequest`. | Call on the class type, not on an instance. |
| `llhttpVersion` | `+ (NSString *)llhttpVersion;` | Perform `llhttp version` for `ALNRequest`. | Call on the class type, not on an instance. |
| `isLLHTTPAvailable` | `+ (BOOL)isLLHTTPAvailable;` | Return whether `ALNRequest` currently satisfies this condition. | Call on the class type, not on an instance. |
