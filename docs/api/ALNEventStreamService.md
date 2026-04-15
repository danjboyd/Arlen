# ALNEventStreamService

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `store` | `id<ALNEventStreamStore>` | `nonatomic, strong, readonly` | Public `store` property available on `ALNEventStreamService`. |
| `broker` | `id<ALNEventStreamBroker>` | `nonatomic, strong, readonly, nullable` | Public `broker` property available on `ALNEventStreamService`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStore:broker:` | `- (instancetype)initWithStore:(id<ALNEventStreamStore>)store broker:(nullable id<ALNEventStreamBroker>)broker;` | Initialize and return a new `ALNEventStreamService` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `appendEvent:toStream:error:` | `- (nullable ALNEventStreamAppendResult *)appendEvent:(NSDictionary *)event toStream:(NSString *)streamID error:(NSError *_Nullable *_Nullable)error;` | Perform `append event` for `ALNEventStreamService`. | Pass `NSError **` and treat a `nil` result as failure. |
| `replayStream:afterSequence:limit:replayWindow:error:` | `- (nullable ALNEventStreamReplayResult *)replayStream:(NSString *)streamID afterSequence:(nullable NSNumber *)sequence limit:(NSUInteger)limit replayWindow:(NSUInteger)replayWindow error:(NSError *_Nullable *_Nullable)error;` | Perform `replay stream` for `ALNEventStreamService`. | Pass `NSError **` and treat a `nil` result as failure. |
