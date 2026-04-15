# ALNEventStreamReplayResult

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `streamID` | `NSString *` | `nonatomic, copy, readonly` | Public `streamID` property available on `ALNEventStreamReplayResult`. |
| `events` | `NSArray<ALNEventEnvelope *> *` | `nonatomic, copy, readonly` | Public `events` property available on `ALNEventStreamReplayResult`. |
| `latestCursor` | `ALNEventStreamCursor *` | `nonatomic, strong, readonly` | Public `latestCursor` property available on `ALNEventStreamReplayResult`. |
| `requestedAfterSequence` | `NSNumber *` | `nonatomic, strong, readonly, nullable` | Public `requestedAfterSequence` property available on `ALNEventStreamReplayResult`. |
| `replayLimit` | `NSUInteger` | `nonatomic, assign, readonly` | Public `replayLimit` property available on `ALNEventStreamReplayResult`. |
| `replayWindow` | `NSUInteger` | `nonatomic, assign, readonly` | Public `replayWindow` property available on `ALNEventStreamReplayResult`. |
| `resyncRequired` | `BOOL` | `nonatomic, assign, readonly` | Public `resyncRequired` property available on `ALNEventStreamReplayResult`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStreamID:events:latestCursor:requestedAfterSequence:replayLimit:replayWindow:resyncRequired:` | `- (instancetype)initWithStreamID:(NSString *)streamID events:(NSArray<ALNEventEnvelope *> *)events latestCursor:(ALNEventStreamCursor *)latestCursor requestedAfterSequence:(nullable NSNumber *)requestedAfterSequence replayLimit:(NSUInteger)replayLimit replayWindow:(NSUInteger)replayWindow resyncRequired:(BOOL)resyncRequired;` | Initialize and return a new `ALNEventStreamReplayResult` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
