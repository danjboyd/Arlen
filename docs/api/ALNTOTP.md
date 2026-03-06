# ALNTOTP

- Kind: `interface`
- Header: `src/Arlen/Support/ALNTOTP.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `generateSecretWithError:` | `+ (nullable NSString *)generateSecretWithError:(NSError *_Nullable *_Nullable)error;` | Perform `generate secret with error` for `ALNTOTP`. | Call on the class type, not on an instance. |
| `generateSecretWithLength:error:` | `+ (nullable NSString *)generateSecretWithLength:(NSUInteger)length error:(NSError *_Nullable *_Nullable)error;` | Perform `generate secret with length` for `ALNTOTP`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `provisioningURIForSecret:accountName:issuer:error:` | `+ (nullable NSString *)provisioningURIForSecret:(NSString *)secret accountName:(NSString *)accountName issuer:(nullable NSString *)issuer error:(NSError *_Nullable *_Nullable)error;` | Perform `provisioning uri for secret` for `ALNTOTP`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `codeForSecret:atDate:error:` | `+ (nullable NSString *)codeForSecret:(NSString *)secret atDate:(NSDate *)date error:(NSError *_Nullable *_Nullable)error;` | Perform `code for secret` for `ALNTOTP`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `codeForSecret:atDate:digits:period:error:` | `+ (nullable NSString *)codeForSecret:(NSString *)secret atDate:(NSDate *)date digits:(NSUInteger)digits period:(NSUInteger)period error:(NSError *_Nullable *_Nullable)error;` | Perform `code for secret` for `ALNTOTP`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `verifyCode:secret:atDate:error:` | `+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret atDate:(NSDate *)date error:(NSError *_Nullable *_Nullable)error;` | Verify and validate the input against configured rules. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `verifyCode:secret:atDate:digits:period:allowedPastIntervals:allowedFutureIntervals:error:` | `+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret atDate:(NSDate *)date digits:(NSUInteger)digits period:(NSUInteger)period allowedPastIntervals:(NSUInteger)allowedPastIntervals allowedFutureIntervals:(NSUInteger)allowedFutureIntervals error:(NSError *_Nullable *_Nullable)error;` | Verify and validate the input against configured rules. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
