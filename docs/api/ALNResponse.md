# ALNResponse

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNResponse.h`

Mutable HTTP response model for status, headers, and body serialization into wire-format bytes.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `statusCode` | `NSInteger` | `nonatomic, assign` | Public `statusCode` property available on `ALNResponse`. |
| `headers` | `NSMutableDictionary *` | `nonatomic, strong, readonly` | Public `headers` property available on `ALNResponse`. |
| `bodyData` | `NSMutableData *` | `nonatomic, strong, readonly` | Public `bodyData` property available on `ALNResponse`. |
| `committed` | `BOOL` | `nonatomic, assign` | Public `committed` property available on `ALNResponse`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `setHeader:value:` | `- (void)setHeader:(NSString *)name value:(NSString *)value;` | Set/replace one response header. | Call before downstream behavior that depends on this updated value. |
| `headerForName:` | `- (nullable NSString *)headerForName:(NSString *)name;` | Return response header value by name. | Capture the returned value and propagate errors/validation as needed. |
| `appendData:` | `- (void)appendData:(NSData *)data;` | Append raw bytes to response body buffer. | Call for side effects; this method does not return a value. |
| `appendText:` | `- (void)appendText:(NSString *)text;` | Append UTF-8 text to response body buffer. | Call for side effects; this method does not return a value. |
| `setTextBody:` | `- (void)setTextBody:(NSString *)text;` | Replace response body with UTF-8 text and text content type. | Call before downstream behavior that depends on this updated value. |
| `setJSONBody:options:error:` | `- (BOOL)setJSONBody:(id)object options:(NSJSONWritingOptions)options error:(NSError *_Nullable *_Nullable)error;` | Serialize object as JSON response body using requested options. | Use options from `ALNController +jsonWritingOptions` unless you need custom formatting. |
| `serializedData` | `- (NSData *)serializedData;` | Return full HTTP response bytes ready for socket write. | Read this value when you need current runtime/request state. |
