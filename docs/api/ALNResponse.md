# ALNResponse

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNResponse.h`

Mutable HTTP response model for status, headers, buffered bodies, and preflighted file streaming into wire-format bytes.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `statusCode` | `NSInteger` | `nonatomic, assign` | Public `statusCode` property available on `ALNResponse`. |
| `headers` | `NSMutableDictionary *` | `nonatomic, strong, readonly` | Legacy dictionary of normalized names and first values. Use response header methods for validated mutations and repeated values. |
| `bodyData` | `NSMutableData *` | `nonatomic, strong, readonly` | Public `bodyData` property available on `ALNResponse`. |
| `committed` | `BOOL` | `nonatomic, assign` | Public `committed` property available on `ALNResponse`. |
| `fileBodyPath` | `NSString *` | `nonatomic, copy, nullable` | Existing regular file path to stream after Arlen preflights the descriptor before successful headers are sent. |
| `fileBodyLength` | `unsigned long long` | `nonatomic, assign` | Expected byte count for a file streaming response; also drives `Content-Length` for GET and HEAD. |
| `fileBodyDevice` | `unsigned long long` | `nonatomic, assign` | Optional device identity used to reject stale or replaced file streaming targets before headers are sent. |
| `fileBodyInode` | `unsigned long long` | `nonatomic, assign` | Optional inode identity used to reject stale or replaced file streaming targets before headers are sent. |
| `fileBodyMTimeSeconds` | `long long` | `nonatomic, assign` | Optional file modification timestamp seconds used to reject changed streaming targets before headers are sent. |
| `fileBodyMTimeNanoseconds` | `long` | `nonatomic, assign` | Optional file modification timestamp nanoseconds used to reject changed streaming targets before headers are sent. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `setHeader:value:` | `- (void)setHeader:(NSString *)name value:(NSString *)value;` | Replace all values for a case-insensitive response header name. | Use before transmission. Invalid names or CR/LF/NUL input leave the response unchanged; use appendHeader:value: to preserve other cookies. |
| `appendHeader:value:` | `- (BOOL)appendHeader:(NSString *)name value:(NSString *)value;` | Append a separate field line for an explicitly supported repeatable header. | Use for Set-Cookie, WWW-Authenticate, Proxy-Authenticate, Link, Warning, Vary, or Cache-Control. NO means invalid input or an unsupported name; state is unchanged. Framing headers cannot be appended. |
| `headerValuesForName:` | `- (NSArray<NSString *> *)headerValuesForName:(NSString *)name;` | Return all values for a case-insensitive header name in insertion order. | Use to inspect multiple cookies. The returned array is an immutable snapshot; an absent header returns an empty array. |
| `removeHeaderForName:` | `- (void)removeHeaderForName:(NSString *)name;` | Remove every value for a case-insensitive header name and invalidate serialization. | Use the response method instead of mutating headers directly. Default Content-Length and Content-Type may be regenerated during serialization. |
| `setHeadersIfMissing:` | `- (void)setHeadersIfMissing:(NSDictionary<NSString *, NSString *> *)headers;` | Set only response header names that have no current value. | Existing first and repeated values are preserved. Invalid header input is ignored. |
| `headerForName:` | `- (nullable NSString *)headerForName:(NSString *)name;` | Return the first response header value for a case-insensitive name, or nil. | Use headerValuesForName: when every repeated value is needed; this accessor does not combine values. |
| `appendData:` | `- (void)appendData:(NSData *)data;` | Append raw bytes to response body buffer. | Call for side effects; this method does not return a value. |
| `appendText:` | `- (void)appendText:(NSString *)text;` | Append UTF-8 text to response body buffer. | Call for side effects; this method does not return a value. |
| `clearBody` | `- (void)clearBody;` | Perform `clear body` for `ALNResponse`. | Call for side effects; this method does not return a value. |
| `bodyLength` | `- (NSUInteger)bodyLength;` | Perform `body length` for `ALNResponse`. | Read this value when you need current runtime/request state. |
| `bodyDataForTransmission` | `- (NSData *)bodyDataForTransmission;` | Perform `body data for transmission` for `ALNResponse`. | Read this value when you need current runtime/request state. |
| `setTextBody:` | `- (void)setTextBody:(NSString *)text;` | Replace response body with UTF-8 text and text content type. | Call before downstream behavior that depends on this updated value. |
| `setDataBody:contentType:` | `- (void)setDataBody:(NSData *)data contentType:(nullable NSString *)contentType;` | Set or override the current value for this concern. | Call before downstream behavior that depends on this updated value. |
| `setJSONBody:options:error:` | `- (BOOL)setJSONBody:(id)object options:(NSJSONWritingOptions)options error:(NSError *_Nullable *_Nullable)error;` | Serialize object as JSON response body using requested options. | Use options from `ALNController +jsonWritingOptions` unless you need custom formatting. |
| `serializedHeaderData` | `- (nullable NSData *)serializedHeaderData;` | Perform `serialized header data` for `ALNResponse`. | Read this value when you need current runtime/request state. |
| `serializedData` | `- (NSData *)serializedData;` | Return full HTTP response bytes ready for socket write. | Read this value when you need current runtime/request state. |
