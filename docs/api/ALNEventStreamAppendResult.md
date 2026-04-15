# ALNEventStreamAppendResult

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `committedEvent` | `ALNEventEnvelope *` | `nonatomic, strong, readonly` | Public `committedEvent` property available on `ALNEventStreamAppendResult`. |
| `livePublishAttempted` | `BOOL` | `nonatomic, assign, readonly` | Public `livePublishAttempted` property available on `ALNEventStreamAppendResult`. |
| `livePublishSucceeded` | `BOOL` | `nonatomic, assign, readonly` | Public `livePublishSucceeded` property available on `ALNEventStreamAppendResult`. |
| `livePublishError` | `NSError *` | `nonatomic, strong, readonly, nullable` | Public `livePublishError` property available on `ALNEventStreamAppendResult`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithCommittedEvent:livePublishAttempted:livePublishSucceeded:livePublishError:` | `- (instancetype)initWithCommittedEvent:(ALNEventEnvelope *)committedEvent livePublishAttempted:(BOOL)livePublishAttempted livePublishSucceeded:(BOOL)livePublishSucceeded livePublishError:(nullable NSError *)livePublishError;` | Initialize and return a new `ALNEventStreamAppendResult` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
