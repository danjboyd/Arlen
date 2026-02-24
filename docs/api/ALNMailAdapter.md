# ALNMailAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Mail adapter protocol for outbound delivery and delivery snapshot diagnostics.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `deliverMessage:error:` | `- (nullable NSString *)deliverMessage:(ALNMailMessage *)message error:(NSError *_Nullable *_Nullable)error;` | Deliver one outbound mail message. | Prefer immutable message objects and include metadata for downstream auditing. |
| `deliveriesSnapshot` | `- (NSArray *)deliveriesSnapshot;` | Return snapshot of delivered outbound messages. | Read this value when you need current runtime/request state. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
