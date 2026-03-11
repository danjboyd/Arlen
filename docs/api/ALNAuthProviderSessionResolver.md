# ALNAuthProviderSessionResolver

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNAuthProviderSessionBridge.h`

Protocol contract exported as part of the `ALNAuthProviderSessionResolver` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `resolveSessionDescriptorForNormalizedIdentity:providerConfiguration:error:` | `- (nullable NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity providerConfiguration:(NSDictionary *)providerConfiguration error:(NSError *_Nullable *_Nullable)error;` | Perform `resolve session descriptor for normalized identity` for `ALNAuthProviderSessionResolver`. | Pass `NSError **` and treat a `nil` result as failure. |
| `accountLinkingDescriptorForNormalizedIdentity:providerConfiguration:error:` | `- (nullable NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity providerConfiguration:(NSDictionary *)providerConfiguration error:(NSError *_Nullable *_Nullable)error;` | Perform `account linking descriptor for normalized identity` for `ALNAuthProviderSessionResolver`. | Pass `NSError **` and treat a `nil` result as failure. |
