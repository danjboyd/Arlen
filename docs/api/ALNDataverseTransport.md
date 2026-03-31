# ALNDataverseTransport

- Kind: `protocol`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Protocol contract exported as part of the `ALNDataverseTransport` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `executeRequest:error:` | `- (nullable ALNDataverseResponse *)executeRequest:(ALNDataverseRequest *)request error:(NSError *_Nullable *_Nullable)error;` | Execute the operation against the active backend. | Pass `NSError **` and treat a `nil` result as failure. |
