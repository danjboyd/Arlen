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
| `configureLimitsWithMaxTotalSubscribers:maxSubscribersPerChannel:` | `- (void)configureLimitsWithMaxTotalSubscribers:(NSUInteger)maxTotalSubscribers maxSubscribersPerChannel:(NSUInteger)maxSubscribersPerChannel;` | Configure behavior for an already-registered runtime element. | Call for side effects; this method does not return a value. |
| `subscribeChannel:subscriber:` | `- (nullable ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel subscriber:(id<ALNRealtimeSubscriber>)subscriber;` | Subscribe one subscriber to a realtime channel. | Capture the returned value and propagate errors/validation as needed. |
| `subscribeChannel:subscriber:rejectionReason:` | `- (nullable ALNRealtimeSubscription *) subscribeChannel:(NSString *)channel subscriber:(id<ALNRealtimeSubscriber>)subscriber rejectionReason:(NSString * _Nullable * _Nullable)rejectionReason;` | Register a subscriber for channel messages. | Capture the returned value and propagate errors/validation as needed. |
| `unsubscribe:` | `- (void)unsubscribe:(nullable ALNRealtimeSubscription *)subscription;` | Unsubscribe a prior realtime subscription. | Call for side effects; this method does not return a value. |
| `publishMessage:onChannel:` | `- (NSUInteger)publishMessage:(NSString *)message onChannel:(NSString *)channel;` | Publish message to all subscribers for a channel. | Capture the returned value and propagate errors/validation as needed. |
| `subscriberCountForChannel:` | `- (NSUInteger)subscriberCountForChannel:(NSString *)channel;` | Return current subscriber count for a channel. | Capture the returned value and propagate errors/validation as needed. |
| `metricsSnapshot` | `- (NSDictionary *)metricsSnapshot;` | Perform `metrics snapshot` for `ALNRealtimeHub`. | Read this value when you need current runtime/request state. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
