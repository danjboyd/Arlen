# ALNRealtimeHub

- Kind: `interface`
- Header: `src/Arlen/Support/ALNRealtime.h`

In-process pub/sub hub used for websocket channel fanout and simple realtime event routing.

## Typical Usage

```objc
ALNRealtimeHub *hub = [ALNRealtimeHub sharedHub];
NSUInteger delivered = [hub publishMessage:@"status:ok" onChannel:@"system"];
NSLog(@"delivered to %lu subscribers", (unsigned long)delivered);
```

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `sharedHub` | `+ (instancetype)sharedHub;` | Return process-wide `ALNRealtimeHub` singleton. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `subscribeChannel:subscriber:` | `- (nullable ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel subscriber:(id<ALNRealtimeSubscriber>)subscriber;` | Subscribe one subscriber to a realtime channel. | Capture the returned value and propagate errors/validation as needed. |
| `unsubscribe:` | `- (void)unsubscribe:(nullable ALNRealtimeSubscription *)subscription;` | Unsubscribe a prior realtime subscription. | Call for side effects; this method does not return a value. |
| `publishMessage:onChannel:` | `- (NSUInteger)publishMessage:(NSString *)message onChannel:(NSString *)channel;` | Publish message to all subscribers for a channel. | Capture the returned value and propagate errors/validation as needed. |
| `subscriberCountForChannel:` | `- (NSUInteger)subscriberCountForChannel:(NSString *)channel;` | Return current subscriber count for a channel. | Capture the returned value and propagate errors/validation as needed. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
