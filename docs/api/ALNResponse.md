# ALNResponse

- Kind: `interface`
- Header: `src/Arlen/Support/ALNTestClient.h`

Mutable HTTP response model for status, headers, buffered bodies, and preflighted file streaming into wire-format bytes.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `bodyText` | `- (NSString *)bodyText;` | Perform `body text` for `ALNResponse`. | Read this value when you need current runtime/request state. |
| `JSONObject` | `- (nullable id)JSONObject;` | Perform `json object` for `ALNResponse`. | Read this value when you need current runtime/request state. |
