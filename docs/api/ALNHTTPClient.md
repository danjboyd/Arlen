# ALNHTTPClient

- Kind: `interface`
- Header: `src/Arlen/Support/ALNHTTPClient.h`

Outbound HTTP client for third-party APIs: a host allowlist fixed at construction, one total deadline, a response size limit, redirects off by default and never for credential-bearing requests, and errors and logs without headers, bodies or query strings. See [HTTP client](../HTTP_CLIENT.md).

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
| `logger` | `ALNLogger *` | `nonatomic, strong, nullable` | Runtime `logger` component configured for this application instance. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithConfiguration:error:` | `- (nullable instancetype)initWithConfiguration:(NSDictionary *)configuration error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNHTTPClient` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNHTTPClient` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `performRequest:error:` | `- (nullable ALNHTTPClientResult *)performRequest:(NSURLRequest *)request error:(NSError *_Nullable *_Nullable)error;` | Perform `perform request` for `ALNHTTPClient`. | Pass `NSError **` and treat a `nil` result as failure. |
| `GETURL:headers:error:` | `- (nullable ALNHTTPClientResult *)GETURL:(NSURL *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers error:(NSError *_Nullable *_Nullable)error;` | Perform `geturl` for `ALNHTTPClient`. | Pass `NSError **` and treat a `nil` result as failure. |
| `POSTJSONObject:toURL:headers:error:` | `- (nullable ALNHTTPClientResult *)POSTJSONObject:(id)object toURL:(NSURL *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers error:(NSError *_Nullable *_Nullable)error;` | Perform `postjson object` for `ALNHTTPClient`. | Pass `NSError **` and treat a `nil` result as failure. |
