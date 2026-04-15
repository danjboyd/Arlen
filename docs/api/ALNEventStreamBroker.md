# ALNEventStreamBroker

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNEventStream.h`

Protocol contract exported as part of the `ALNEventStreamBroker` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `publishCommittedEvent:onStream:error:` | `- (BOOL)publishCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID error:(NSError *_Nullable *_Nullable)error;` | Publish a message to channel subscribers. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `subscribeToStream:subscriber:error:` | `- (nullable ALNEventStreamBrokerSubscription *)subscribeToStream:(NSString *)streamID subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber error:(NSError *_Nullable *_Nullable)error;` | Register a subscriber for channel messages. | Pass `NSError **` and treat a `nil` result as failure. |
| `unsubscribe:` | `- (void)unsubscribe:(nullable ALNEventStreamBrokerSubscription *)subscription;` | Unsubscribe a prior realtime subscription. | Call for side effects; this method does not return a value. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
