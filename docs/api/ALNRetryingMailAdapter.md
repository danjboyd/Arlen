# ALNRetryingMailAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Retry-wrapper adapter implementation with deterministic retry semantics.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `maxAttempts` | `NSUInteger` | `nonatomic, assign` | Public `maxAttempts` property available on `ALNRetryingMailAdapter`. |
| `retryDelaySeconds` | `NSTimeInterval` | `nonatomic, assign` | Public `retryDelaySeconds` property available on `ALNRetryingMailAdapter`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithBaseAdapter:` | `- (instancetype)initWithBaseAdapter:(id<ALNMailAdapter>)baseAdapter;` | Initialize and return a new `ALNRetryingMailAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
