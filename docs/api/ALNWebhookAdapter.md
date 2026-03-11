# ALNWebhookAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Protocol contract for `ALNWebhookAdapter` adapter implementations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `deliverRequest:error:` | `- (nullable NSString *)deliverRequest:(NSDictionary *)request error:(NSError *_Nullable *_Nullable)error;` | Perform `deliver request` for `ALNWebhookAdapter`. | Pass `NSError **` and treat a `nil` result as failure. |
| `deliveriesSnapshot` | `- (NSArray *)deliveriesSnapshot;` | Return snapshot of delivered outbound messages. | Read this value when you need current runtime/request state. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
