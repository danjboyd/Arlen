# ALNDataverseTokenProvider

- Kind: `protocol`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Protocol contract exported as part of the `ALNDataverseTokenProvider` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `accessTokenForTarget:transport:error:` | `- (nullable NSString *)accessTokenForTarget:(ALNDataverseTarget *)target transport:(id<ALNDataverseTransport>)transport error:(NSError *_Nullable *_Nullable)error;` | Perform `access token for target` for `ALNDataverseTokenProvider`. | Pass `NSError **` and treat a `nil` result as failure. |
