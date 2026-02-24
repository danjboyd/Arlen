# ALNRetryingAttachmentAdapter

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Retry-wrapper adapter implementation with deterministic retry semantics.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `maxAttempts` | `NSUInteger` | `nonatomic, assign` | Public `maxAttempts` property available on `ALNRetryingAttachmentAdapter`. |
| `retryDelaySeconds` | `NSTimeInterval` | `nonatomic, assign` | Public `retryDelaySeconds` property available on `ALNRetryingAttachmentAdapter`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithBaseAdapter:` | `- (instancetype)initWithBaseAdapter:(id<ALNAttachmentAdapter>)baseAdapter;` | Initialize and return a new `ALNRetryingAttachmentAdapter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
