# ALNWebAuthn

- Kind: `interface`
- Header: `src/Arlen/Support/ALNWebAuthn.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `registrationOptionsForRelyingPartyID:relyingPartyName:origin:userIdentifier:userName:userDisplayName:requireUserVerification:timeoutSeconds:error:` | `+ (nullable NSDictionary *)registrationOptionsForRelyingPartyID:(NSString *)relyingPartyID relyingPartyName:(NSString *)relyingPartyName origin:(NSString *)origin userIdentifier:(NSString *)userIdentifier userName:(NSString *)userName userDisplayName:(nullable NSString *)userDisplayName requireUserVerification:(BOOL)requireUserVerification timeoutSeconds:(NSUInteger)timeoutSeconds error:(NSError *_Nullable *_Nullable)error;` | Perform `registration options for relying party id` for `ALNWebAuthn`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `assertionOptionsForRelyingPartyID:origin:allowedCredentialIDs:requireUserVerification:timeoutSeconds:error:` | `+ (nullable NSDictionary *)assertionOptionsForRelyingPartyID:(NSString *)relyingPartyID origin:(NSString *)origin allowedCredentialIDs:(nullable NSArray *)allowedCredentialIDs requireUserVerification:(BOOL)requireUserVerification timeoutSeconds:(NSUInteger)timeoutSeconds error:(NSError *_Nullable *_Nullable)error;` | Perform `assertion options for relying party id` for `ALNWebAuthn`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `verifyRegistrationResponse:expectedOptions:error:` | `+ (nullable NSDictionary *)verifyRegistrationResponse:(NSDictionary *)response expectedOptions:(NSDictionary *)expectedOptions error:(NSError *_Nullable *_Nullable)error;` | Verify and validate the input against configured rules. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `verifyAssertionResponse:expectedOptions:storedCredentialID:storedPublicKeyPEM:previousSignCount:error:` | `+ (nullable NSDictionary *)verifyAssertionResponse:(NSDictionary *)response expectedOptions:(NSDictionary *)expectedOptions storedCredentialID:(nullable NSString *)storedCredentialID storedPublicKeyPEM:(NSString *)storedPublicKeyPEM previousSignCount:(NSUInteger)previousSignCount error:(NSError *_Nullable *_Nullable)error;` | Verify and validate the input against configured rules. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
