# ALNRecoveryCodes

- Kind: `interface`
- Header: `src/Arlen/Support/ALNRecoveryCodes.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `generateCodesWithCount:error:` | `+ (nullable NSArray *)generateCodesWithCount:(NSUInteger)count error:(NSError *_Nullable *_Nullable)error;` | Perform `generate codes with count` for `ALNRecoveryCodes`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `generateCodesWithCount:segmentLength:error:` | `+ (nullable NSArray *)generateCodesWithCount:(NSUInteger)count segmentLength:(NSUInteger)segmentLength error:(NSError *_Nullable *_Nullable)error;` | Perform `generate codes with count` for `ALNRecoveryCodes`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `hashCodes:error:` | `+ (nullable NSArray *)hashCodes:(NSArray *)codes error:(NSError *_Nullable *_Nullable)error;` | Return whether `ALNRecoveryCodes` currently satisfies this condition. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `verifyCode:againstEncodedHash:error:` | `+ (BOOL)verifyCode:(NSString *)code againstEncodedHash:(NSString *)encodedHash error:(NSError *_Nullable *_Nullable)error;` | Verify and validate the input against configured rules. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `consumeCode:againstEncodedHashes:remainingEncodedHashes:error:` | `+ (BOOL)consumeCode:(NSString *)code againstEncodedHashes:(NSArray *)encodedHashes remainingEncodedHashes:(NSArray *_Nullable *_Nullable)remainingEncodedHashes error:(NSError *_Nullable *_Nullable)error;` | Perform `consume code` for `ALNRecoveryCodes`. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
