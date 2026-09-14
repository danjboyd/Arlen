# ALNUpload

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNMultipart.h`

HTTP request/response and server runtime primitives.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `writeToFile:error:` | `- (BOOL)writeToFile:(NSString *)path error:(NSError *_Nullable *_Nullable)error;` | Write a serialized representation to disk. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
