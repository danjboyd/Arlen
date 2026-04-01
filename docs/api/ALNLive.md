# ALNLive

- Kind: `interface`
- Header: `src/Arlen/Support/ALNLive.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `contentType` | `+ (NSString *)contentType;` | Perform `content type` for `ALNLive`. | Call on the class type, not on an instance. |
| `acceptContentType` | `+ (NSString *)acceptContentType;` | Accept and handle an upgraded realtime connection. | Call on the class type, not on an instance. |
| `protocolVersion` | `+ (NSString *)protocolVersion;` | Perform `protocol version` for `ALNLive`. | Call on the class type, not on an instance. |
| `replaceOperationForTarget:html:` | `+ (NSDictionary *)replaceOperationForTarget:(NSString *)target html:(NSString *)html;` | Perform `replace operation for target` for `ALNLive`. | Call on the class type, not on an instance. |
| `updateOperationForTarget:html:` | `+ (NSDictionary *)updateOperationForTarget:(NSString *)target html:(NSString *)html;` | Perform `update operation for target` for `ALNLive`. | Call on the class type, not on an instance. |
| `appendOperationForTarget:html:` | `+ (NSDictionary *)appendOperationForTarget:(NSString *)target html:(NSString *)html;` | Perform `append operation for target` for `ALNLive`. | Call on the class type, not on an instance. |
| `prependOperationForTarget:html:` | `+ (NSDictionary *)prependOperationForTarget:(NSString *)target html:(NSString *)html;` | Perform `prepend operation for target` for `ALNLive`. | Call on the class type, not on an instance. |
| `removeOperationForTarget:` | `+ (NSDictionary *)removeOperationForTarget:(NSString *)target;` | Perform `remove operation for target` for `ALNLive`. | Call on the class type, not on an instance. |
| `navigateOperationForLocation:replace:` | `+ (NSDictionary *)navigateOperationForLocation:(NSString *)location replace:(BOOL)replace;` | Perform `navigate operation for location` for `ALNLive`. | Call on the class type, not on an instance. |
| `dispatchOperationForEvent:detail:target:` | `+ (NSDictionary *)dispatchOperationForEvent:(NSString *)eventName detail:(nullable NSDictionary *)detail target:(nullable NSString *)target;` | Dispatch the current request through routing and controller handling. | Call on the class type, not on an instance. |
| `requestIsLive:` | `+ (BOOL)requestIsLive:(nullable ALNRequest *)request;` | Perform `request is live` for `ALNLive`. | Call on the class type, not on an instance. |
| `requestMetadataForRequest:` | `+ (NSDictionary *)requestMetadataForRequest:(nullable ALNRequest *)request;` | Perform `request metadata for request` for `ALNLive`. | Call on the class type, not on an instance. |
| `validatedPayloadWithOperations:meta:error:` | `+ (nullable NSDictionary *)validatedPayloadWithOperations:(NSArray *)operations meta:(nullable NSDictionary *)meta error:(NSError *_Nullable *_Nullable)error;` | Perform `validated payload with operations` for `ALNLive`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `renderResponse:operations:meta:error:` | `+ (BOOL)renderResponse:(ALNResponse *)response operations:(NSArray *)operations meta:(nullable NSDictionary *)meta error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `runtimeJavaScript` | `+ (NSString *)runtimeJavaScript;` | Perform `runtime java script` for `ALNLive`. | Call on the class type, not on an instance. |
