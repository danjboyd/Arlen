# ALNFileResponse

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNFileResponse.h`

Filesystem-backed adapter implementation for durable local environments.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `prepareResponse:forRequest:filePath:contentType:options:` | `+ (BOOL)prepareResponse:(ALNResponse *)response forRequest:(ALNRequest *)request filePath:(NSString *)filePath contentType:(nullable NSString *)contentType options:(nullable NSDictionary *)options;` | Perform `prepare response` for `ALNFileResponse`. | Call on the class type, not on an instance. |
