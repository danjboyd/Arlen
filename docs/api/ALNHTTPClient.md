# ALNHTTPClient

- Kind: `interface`
- Header: `src/Arlen/Support/ALNHTTPClient.h`

Outbound HTTP client with buffered and opt-in incremental delivery, cancellation, idle/total deadlines, a fixed host allowlist, cumulative streaming byte limits, credential-safe redirects, and sanitized logging. See [HTTP client](../HTTP_CLIENT.md).

## Typical Usage

```objc
NSError *error = nil;
ALNHTTPClient *client = [[ALNHTTPClient alloc] initWithConfiguration:@{
  @"allowedHosts" : @[ @"api.vendor.example" ],
  @"timeoutSeconds" : @10,
} error:&error];
ALNHTTPClientResult *result = [client POSTJSONObject:@{ @"ticket" : @42 }
    toURL:[NSURL URLWithString:@"https://api.vendor.example/v1/events"]
    headers:@{ @"Authorization" : @"Bearer ..." } error:&error];
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `allowedHosts` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `allowedHosts` property available on `ALNHTTPClient`. |
| `timeout` | `NSTimeInterval` | `nonatomic, assign, readonly` | Public `timeout` property available on `ALNHTTPClient`. |
| `maxResponseBytes` | `NSUInteger` | `nonatomic, assign, readonly` | Public `maxResponseBytes` property available on `ALNHTTPClient`. |
| `maxRedirects` | `NSUInteger` | `nonatomic, assign, readonly` | Public `maxRedirects` property available on `ALNHTTPClient`. |
| `allowHTTP` | `BOOL` | `nonatomic, assign, readonly` | Public `allowHTTP` property available on `ALNHTTPClient`. |
| `idleTimeout` | `NSTimeInterval` | `nonatomic, assign, readonly` | Streaming-only incoming-byte idle deadline in seconds; default 30, configured with idleTimeoutSeconds. |
| `streamingTimeout` | `NSTimeInterval` | `nonatomic, assign, readonly` | Streaming-only total deadline across redirects in seconds; default 900, configured with streamingTimeoutSeconds. |
| `logger` | `ALNLogger *` | `nonatomic, strong, nullable` | Runtime `logger` component configured for this application instance. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithConfiguration:error:` | `- (nullable instancetype)initWithConfiguration:(NSDictionary *)configuration error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNHTTPClient` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNHTTPClient` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `performRequest:error:` | `- (nullable ALNHTTPClientResult *)performRequest:(NSURLRequest *)request error:(NSError *_Nullable *_Nullable)error;` | Perform `perform request` for `ALNHTTPClient`. | Pass `NSError **` and treat a `nil` result as failure. |
| `streamRequest:cancellation:onResponse:onData:error:` | `- (BOOL)streamRequest:(NSURLRequest *)request cancellation:(nullable ALNHTTPClientCancellation *)cancellation onResponse:(ALNHTTPClientResponseHandler)onResponse onData:(ALNHTTPClientDataHandler)onData error:(NSError *_Nullable *_Nullable)error;` | Deliver the final response headers and arbitrary body byte chunks synchronously, without buffering the response body. | Run on an application worker. Both callbacks run serially on that thread and may return NO to cancel. Use the token to cancel during silence. On NO inspect the sanitized error; earlier bytes remain partial output and are not a successful response. |
| `GETURL:headers:error:` | `- (nullable ALNHTTPClientResult *)GETURL:(NSURL *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers error:(NSError *_Nullable *_Nullable)error;` | Perform `geturl` for `ALNHTTPClient`. | Pass `NSError **` and treat a `nil` result as failure. |
| `POSTJSONObject:toURL:headers:error:` | `- (nullable ALNHTTPClientResult *)POSTJSONObject:(id)object toURL:(NSURL *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers error:(NSError *_Nullable *_Nullable)error;` | Perform `postjson object` for `ALNHTTPClient`. | Pass `NSError **` and treat a `nil` result as failure. |
