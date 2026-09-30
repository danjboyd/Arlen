# ALNRealtimeFanout

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNRealtime.h`

Protocol contract exported as part of the `ALNRealtimeFanout` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `hub:didPublishMessage:onChannel:` | `- (void)hub:(ALNRealtimeHub *)hub didPublishMessage:(NSString *)message onChannel:(NSString *)channel;` | Perform `hub` for `ALNRealtimeFanout`. | Call for side effects; this method does not return a value. |
| `stop` | `- (void)stop;` | Perform `stop` for `ALNRealtimeFanout`. | Call for side effects; this method does not return a value. |
