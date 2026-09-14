# ALNMultipartPart

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNMultipart.h`

HTTP request/response and server runtime primitives.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `fieldName` | `NSString *` | `nonatomic, copy, readonly` | Public `fieldName` property available on `ALNMultipartPart`. |
| `originalFilename` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `originalFilename` property available on `ALNMultipartPart`. |
| `contentType` | `NSString *` | `nonatomic, copy, readonly` | Public `contentType` property available on `ALNMultipartPart`. |
| `data` | `NSData *` | `nonatomic, copy, readonly` | Public `data` property available on `ALNMultipartPart`. |
| `size` | `NSUInteger` | `nonatomic, assign, readonly` | Public `size` property available on `ALNMultipartPart`. |
| `text` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `text` property available on `ALNMultipartPart`. |
