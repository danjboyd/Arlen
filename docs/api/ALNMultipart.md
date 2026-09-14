# ALNMultipart

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNMultipart.h`

HTTP request/response and server runtime primitives.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `defaultLimits` | `+ (NSDictionary *)defaultLimits;` | Perform `default limits` for `ALNMultipart`. | Call on the class type, not on an instance. |
| `parseBody:contentType:limits:error:` | `+ (nullable NSArray<ALNMultipartPart *> *)parseBody:(NSData *)body contentType:(NSString *)contentType limits:(NSDictionary *)limits error:(NSError *_Nullable *_Nullable)error;` | Perform `parse body` for `ALNMultipart`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
