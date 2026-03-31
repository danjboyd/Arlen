# ALNDataverseClientCredentialsTokenProvider

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init;` | Initialize and return a new `ALNDataverseClientCredentialsTokenProvider` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
