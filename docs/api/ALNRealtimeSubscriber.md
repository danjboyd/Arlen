# ALNRealtimeSubscriber

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNRealtime.h`

Realtime callback protocol implemented by websocket/session subscribers.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `receiveRealtimeMessage:onChannel:` | `- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel;` | Realtime subscriber callback for one published channel message. | Call for side effects; this method does not return a value. |
