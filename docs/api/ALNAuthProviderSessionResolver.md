# ALNAuthProviderSessionResolver

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNAuthProviderSessionBridge.h`

Protocol contract exported as part of the `ALNAuthProviderSessionResolver` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `resolveSessionDescriptorForNormalizedIdentity:providerConfiguration:error:` | `- (nullable NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity providerConfiguration:(NSDictionary *)providerConfiguration error:(NSError *_Nullable *_Nullable)error;` | Perform `resolve session descriptor for normalized identity` for `ALNAuthProviderSessionResolver`. | Pass `NSError **` and treat a `nil` result as failure. |
| `accountLinkingDescriptorForNormalizedIdentity:providerConfiguration:error:` | `- (nullable NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity providerConfiguration:(NSDictionary *)providerConfiguration error:(NSError *_Nullable *_Nullable)error;` | Perform `account linking descriptor for normalized identity` for `ALNAuthProviderSessionResolver`. | Pass `NSError **` and treat a `nil` result as failure. |
| `providerSessionEstablishedForDescriptor:context:error:` | `- (BOOL)providerSessionEstablishedForDescriptor:(NSDictionary *)sessionDescriptor context:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;` | Perform `provider session established for descriptor` for `ALNAuthProviderSessionResolver`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `refreshSessionDescriptorForSubject:provider:error:` | `- (nullable NSDictionary *)refreshSessionDescriptorForSubject:(NSString *)subject provider:(NSString *)provider error:(NSError *_Nullable *_Nullable)error;` | Perform `refresh session descriptor for subject` for `ALNAuthProviderSessionResolver`. | Pass `NSError **` and treat a `nil` result as failure. |
