# ALNAuthProviderSessionBridge

- Kind: `interface`
- Header: `src/Arlen/Support/ALNAuthProviderSessionBridge.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `completeLoginWithCallbackParameters:callbackState:tokenResponse:userInfoResponse:providerConfiguration:jwksDocument:resolver:context:error:` | `+ (nullable NSDictionary *)completeLoginWithCallbackParameters:(NSDictionary *)callbackParameters callbackState:(NSDictionary *)callbackState tokenResponse:(NSDictionary *)tokenResponse userInfoResponse:(nullable NSDictionary *)userInfoResponse providerConfiguration:(NSDictionary *)providerConfiguration jwksDocument:(nullable NSDictionary *)jwksDocument resolver:(id<ALNAuthProviderSessionResolver>)resolver context:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;` | Perform `complete login with callback parameters` for `ALNAuthProviderSessionBridge`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `accountLinkingDescriptorForNormalizedIdentity:providerConfiguration:resolver:error:` | `+ (nullable NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity providerConfiguration:(NSDictionary *)providerConfiguration resolver:(id<ALNAuthProviderSessionResolver>)resolver error:(NSError *_Nullable *_Nullable)error;` | Perform `account linking descriptor for normalized identity` for `ALNAuthProviderSessionBridge`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
