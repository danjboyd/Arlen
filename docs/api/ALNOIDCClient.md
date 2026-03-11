# ALNOIDCClient

- Kind: `interface`
- Header: `src/Arlen/Support/ALNOIDCClient.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `authorizationRequestForProviderConfiguration:redirectURI:scopes:referenceDate:error:` | `+ (nullable NSDictionary *)authorizationRequestForProviderConfiguration:(NSDictionary *)providerConfiguration redirectURI:(NSString *)redirectURI scopes:(nullable NSArray *)scopes referenceDate:(nullable NSDate *)referenceDate error:(NSError *_Nullable *_Nullable)error;` | Perform `authorization request for provider configuration` for `ALNOIDCClient`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `validateAuthorizationCallbackParameters:expectedState:issuedAtDate:maxAgeSeconds:error:` | `+ (nullable NSDictionary *)validateAuthorizationCallbackParameters:(NSDictionary *)parameters expectedState:(NSString *)expectedState issuedAtDate:(nullable NSDate *)issuedAtDate maxAgeSeconds:(NSUInteger)maxAgeSeconds error:(NSError *_Nullable *_Nullable)error;` | Perform `validate authorization callback parameters` for `ALNOIDCClient`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `tokenExchangeRequestForProviderConfiguration:authorizationCode:redirectURI:codeVerifier:error:` | `+ (nullable NSDictionary *)tokenExchangeRequestForProviderConfiguration:(NSDictionary *)providerConfiguration authorizationCode:(NSString *)authorizationCode redirectURI:(NSString *)redirectURI codeVerifier:(NSString *)codeVerifier error:(NSError *_Nullable *_Nullable)error;` | Perform `token exchange request for provider configuration` for `ALNOIDCClient`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `parseTokenResponseData:error:` | `+ (nullable NSDictionary *)parseTokenResponseData:(NSData *)data error:(NSError *_Nullable *_Nullable)error;` | Perform `parse token response data` for `ALNOIDCClient`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `verifyIDToken:providerConfiguration:expectedNonce:jwksDocument:referenceDate:error:` | `+ (nullable NSDictionary *)verifyIDToken:(NSString *)idToken providerConfiguration:(NSDictionary *)providerConfiguration expectedNonce:(nullable NSString *)expectedNonce jwksDocument:(nullable NSDictionary *)jwksDocument referenceDate:(nullable NSDate *)referenceDate error:(NSError *_Nullable *_Nullable)error;` | Verify and validate the input against configured rules. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `normalizedIdentityFromVerifiedClaims:tokenResponse:userInfoResponse:providerConfiguration:error:` | `+ (nullable NSDictionary *)normalizedIdentityFromVerifiedClaims:(nullable NSDictionary *)verifiedClaims tokenResponse:(nullable NSDictionary *)tokenResponse userInfoResponse:(nullable NSDictionary *)userInfoResponse providerConfiguration:(NSDictionary *)providerConfiguration error:(NSError *_Nullable *_Nullable)error;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `redactedProviderConfiguration:` | `+ (NSDictionary *)redactedProviderConfiguration:(NSDictionary *)providerConfiguration;` | Perform `redacted provider configuration` for `ALNOIDCClient`. | Call on the class type, not on an instance. |
