# ALNAuthSession

- Kind: `interface`
- Header: `src/Arlen/Support/ALNAuthSession.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `subjectFromContext:` | `+ (nullable NSString *)subjectFromContext:(ALNContext *)context;` | Perform `subject from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `providerFromContext:` | `+ (nullable NSString *)providerFromContext:(ALNContext *)context;` | Perform `provider from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `authenticationMethodsFromContext:` | `+ (NSArray *)authenticationMethodsFromContext:(ALNContext *)context;` | Perform `authentication methods from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `scopesFromContext:` | `+ (NSArray *)scopesFromContext:(ALNContext *)context;` | Perform `scopes from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `rolesFromContext:` | `+ (NSArray *)rolesFromContext:(ALNContext *)context;` | Perform `roles from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `assuranceLevelFromContext:` | `+ (NSUInteger)assuranceLevelFromContext:(ALNContext *)context;` | Perform `assurance level from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `primaryAuthenticatedAtFromContext:` | `+ (nullable NSDate *)primaryAuthenticatedAtFromContext:(ALNContext *)context;` | Perform `primary authenticated at from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `mfaAuthenticatedAtFromContext:` | `+ (nullable NSDate *)mfaAuthenticatedAtFromContext:(ALNContext *)context;` | Perform `mfa authenticated at from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `sessionIdentifierFromContext:` | `+ (nullable NSString *)sessionIdentifierFromContext:(ALNContext *)context;` | Perform `session identifier from context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `isMFAAuthenticatedForContext:` | `+ (BOOL)isMFAAuthenticatedForContext:(ALNContext *)context;` | Return whether `ALNAuthSession` currently satisfies this condition. | Call on the class type, not on an instance. |
| `context:satisfiesMinimumAssuranceLevel:maximumAuthenticationAgeSeconds:referenceDate:` | `+ (BOOL)context:(ALNContext *)context satisfiesMinimumAssuranceLevel:(NSUInteger)minimumAssuranceLevel maximumAuthenticationAgeSeconds:(NSUInteger)maximumAuthenticationAgeSeconds referenceDate:(nullable NSDate *)referenceDate;` | Perform `context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
| `establishAuthenticatedSessionForSubject:provider:methods:scopes:roles:assuranceLevel:authenticatedAt:context:error:` | `+ (BOOL)establishAuthenticatedSessionForSubject:(NSString *)subject provider:(nullable NSString *)provider methods:(nullable NSArray *)methods scopes:(nullable NSArray *)scopes roles:(nullable NSArray *)roles assuranceLevel:(NSUInteger)assuranceLevel authenticatedAt:(nullable NSDate *)authenticatedAt context:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;` | Perform `establish authenticated session for subject` for `ALNAuthSession`. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `establishAuthenticatedSessionForSubject:provider:methods:assuranceLevel:authenticatedAt:context:error:` | `+ (BOOL)establishAuthenticatedSessionForSubject:(NSString *)subject provider:(nullable NSString *)provider methods:(nullable NSArray *)methods assuranceLevel:(NSUInteger)assuranceLevel authenticatedAt:(nullable NSDate *)authenticatedAt context:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;` | Perform `establish authenticated session for subject` for `ALNAuthSession`. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `elevateAuthenticatedSessionForMethod:assuranceLevel:authenticatedAt:context:error:` | `+ (BOOL)elevateAuthenticatedSessionForMethod:(NSString *)method assuranceLevel:(NSUInteger)assuranceLevel authenticatedAt:(nullable NSDate *)authenticatedAt context:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;` | Perform `elevate authenticated session for method` for `ALNAuthSession`. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `clearAuthenticatedSessionForContext:` | `+ (void)clearAuthenticatedSessionForContext:(ALNContext *)context;` | Perform `clear authenticated session for context` for `ALNAuthSession`. | Call on the class type, not on an instance. |
