# ALNJobLease

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Immutable job claim carrying an ownership token, initial expiration, and heartbeat duration.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `leaseToken` | `NSString *` | `nonatomic, copy, readonly` | Public `leaseToken` property available on `ALNJobLease`. |
| `leaseExpiresAt` | `NSDate *` | `nonatomic, strong, readonly` | Public `leaseExpiresAt` property available on `ALNJobLease`. |
| `leaseDurationSeconds` | `NSTimeInterval` | `nonatomic, assign, readonly` | Public `leaseDurationSeconds` property available on `ALNJobLease`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithEnvelope:leaseToken:leaseExpiresAt:leaseDurationSeconds:` | `- (instancetype)initWithEnvelope:(ALNJobEnvelope *)envelope leaseToken:(NSString *)leaseToken leaseExpiresAt:(NSDate *)leaseExpiresAt leaseDurationSeconds:(NSTimeInterval)leaseDurationSeconds;` | Initialize and return a new `ALNJobLease` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
