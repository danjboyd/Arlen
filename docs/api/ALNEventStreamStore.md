# ALNEventStreamStore

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNEventStream.h`

Protocol contract exported as part of the `ALNEventStreamStore` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `appendEvent:toStream:error:` | `- (nullable ALNEventEnvelope *)appendEvent:(NSDictionary *)event toStream:(NSString *)streamID error:(NSError *_Nullable *_Nullable)error;` | Perform `append event` for `ALNEventStreamStore`. | Pass `NSError **` and treat a `nil` result as failure. |
| `eventsForStream:afterSequence:limit:error:` | `- (nullable NSArray<ALNEventEnvelope *> *)eventsForStream:(NSString *)streamID afterSequence:(nullable NSNumber *)sequence limit:(NSUInteger)limit error:(NSError *_Nullable *_Nullable)error;` | Perform `events for stream` for `ALNEventStreamStore`. | Pass `NSError **` and treat a `nil` result as failure. |
| `latestCursorForStream:error:` | `- (nullable ALNEventStreamCursor *)latestCursorForStream:(NSString *)streamID error:(NSError *_Nullable *_Nullable)error;` | Perform `latest cursor for stream` for `ALNEventStreamStore`. | Pass `NSError **` and treat a `nil` result as failure. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
