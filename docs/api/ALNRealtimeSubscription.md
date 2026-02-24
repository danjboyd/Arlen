# ALNRealtimeSubscription

- Kind: `interface`
- Header: `src/Arlen/Support/ALNRealtime.h`

Subscription token returned by realtime hub subscribe calls and used for unsubscribe operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `channel` | `NSString *` | `nonatomic, copy, readonly` | Public `channel` property available on `ALNRealtimeSubscription`. |
| `subscriber` | `id<ALNRealtimeSubscriber>` | `nonatomic, strong, readonly` | Public `subscriber` property available on `ALNRealtimeSubscription`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithChannel:subscriber:` | `- (instancetype)initWithChannel:(NSString *)channel subscriber:(id<ALNRealtimeSubscriber>)subscriber;` | Initialize and return a new `ALNRealtimeSubscription` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
