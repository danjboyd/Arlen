# ALNDataverseCurlTransport

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `timeoutInterval` | `NSTimeInterval` | `nonatomic, assign, readonly` | Public `timeoutInterval` property available on `ALNDataverseCurlTransport`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init;` | Initialize and return a new `ALNDataverseCurlTransport` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithTimeoutInterval:` | `- (instancetype)initWithTimeoutInterval:(NSTimeInterval)timeoutInterval NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseCurlTransport` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
