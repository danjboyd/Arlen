# ALNEventEnvelope

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `streamID` | `NSString *` | `nonatomic, copy, readonly` | Public `streamID` property available on `ALNEventEnvelope`. |
| `sequence` | `NSUInteger` | `nonatomic, assign, readonly` | Public `sequence` property available on `ALNEventEnvelope`. |
| `eventID` | `NSString *` | `nonatomic, copy, readonly` | Public `eventID` property available on `ALNEventEnvelope`. |
| `eventType` | `NSString *` | `nonatomic, copy, readonly` | Public `eventType` property available on `ALNEventEnvelope`. |
| `occurredAt` | `NSString *` | `nonatomic, copy, readonly` | Public `occurredAt` property available on `ALNEventEnvelope`. |
| `payload` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `payload` property available on `ALNEventEnvelope`. |
| `idempotencyKey` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `idempotencyKey` property available on `ALNEventEnvelope`. |
| `actor` | `NSDictionary *` | `nonatomic, copy, readonly, nullable` | Public `actor` property available on `ALNEventEnvelope`. |
| `metadata` | `NSDictionary *` | `nonatomic, copy, readonly, nullable` | Public `metadata` property available on `ALNEventEnvelope`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithStreamID:sequence:eventID:eventType:occurredAt:payload:idempotencyKey:actor:metadata:` | `- (instancetype)initWithStreamID:(NSString *)streamID sequence:(NSUInteger)sequence eventID:(NSString *)eventID eventType:(NSString *)eventType occurredAt:(NSString *)occurredAt payload:(NSDictionary *)payload idempotencyKey:(nullable NSString *)idempotencyKey actor:(nullable NSDictionary *)actor metadata:(nullable NSDictionary *)metadata;` | Initialize and return a new `ALNEventEnvelope` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
