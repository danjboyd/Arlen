# ALNEventStreamLiveSubscriber

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNEventStream.h`

Protocol contract exported as part of the `ALNEventStreamLiveSubscriber` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `receiveCommittedEvent:onStream:` | `- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID;` | Perform `receive committed event` for `ALNEventStreamLiveSubscriber`. | Call for side effects; this method does not return a value. |
