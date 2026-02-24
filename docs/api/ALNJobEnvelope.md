# ALNJobEnvelope

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Immutable leased-job envelope containing identity, payload, attempt counters, and schedule metadata.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `jobID` | `NSString *` | `nonatomic, copy, readonly` | Public `jobID` property available on `ALNJobEnvelope`. |
| `name` | `NSString *` | `nonatomic, copy, readonly` | Public `name` property available on `ALNJobEnvelope`. |
| `payload` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `payload` property available on `ALNJobEnvelope`. |
| `attempt` | `NSUInteger` | `nonatomic, assign, readonly` | Public `attempt` property available on `ALNJobEnvelope`. |
| `maxAttempts` | `NSUInteger` | `nonatomic, assign, readonly` | Public `maxAttempts` property available on `ALNJobEnvelope`. |
| `notBefore` | `NSDate *` | `nonatomic, strong, readonly` | Public `notBefore` property available on `ALNJobEnvelope`. |
| `createdAt` | `NSDate *` | `nonatomic, strong, readonly` | Public `createdAt` property available on `ALNJobEnvelope`. |
| `sequence` | `NSUInteger` | `nonatomic, assign, readonly` | Public `sequence` property available on `ALNJobEnvelope`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithJobID:name:payload:attempt:maxAttempts:notBefore:createdAt:sequence:` | `- (instancetype)initWithJobID:(NSString *)jobID name:(NSString *)name payload:(NSDictionary *)payload attempt:(NSUInteger)attempt maxAttempts:(NSUInteger)maxAttempts notBefore:(NSDate *)notBefore createdAt:(NSDate *)createdAt sequence:(NSUInteger)sequence;` | Initialize and return a new `ALNJobEnvelope` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
