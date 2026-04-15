# ALNEventStreamBrokerSubscription

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `streamID` | `NSString *` | `nonatomic, copy, readonly` | Public `streamID` property available on `ALNEventStreamBrokerSubscription`. |
| `subscriber` | `id<ALNEventStreamLiveSubscriber>` | `nonatomic, strong, readonly` | Public `subscriber` property available on `ALNEventStreamBrokerSubscription`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStreamID:subscriber:` | `- (instancetype)initWithStreamID:(NSString *)streamID subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber;` | Initialize and return a new `ALNEventStreamBrokerSubscription` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
