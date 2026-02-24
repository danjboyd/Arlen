# ALNAuth

- Kind: `interface`
- Header: `src/Arlen/Support/ALNAuth.h`

Authentication and authorization helpers for bearer token extraction, JWT verification, and scope/role checks.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `bearerTokenFromAuthorizationHeader:error:` | `+ (nullable NSString *)bearerTokenFromAuthorizationHeader:(NSString *)authorizationHeader error:(NSError *_Nullable *_Nullable)error;` | Extract bearer token from an Authorization header value. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `verifyJWTToken:secret:issuer:audience:error:` | `+ (nullable NSDictionary *)verifyJWTToken:(NSString *)token secret:(NSString *)secret issuer:(nullable NSString *)issuer audience:(nullable NSString *)audience error:(NSError *_Nullable *_Nullable)error;` | Verify JWT signature and optional issuer/audience constraints. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `authenticateContext:authConfig:error:` | `+ (BOOL)authenticateContext:(ALNContext *)context authConfig:(NSDictionary *)authConfig error:(NSError *_Nullable *_Nullable)error;` | Authenticate request and populate auth claims/scopes/roles on context. | Call from auth middleware/guards before role/scope checks. |
| `applyClaims:toContext:` | `+ (void)applyClaims:(NSDictionary *)claims toContext:(ALNContext *)context;` | Copy verified auth claims onto request context. | Call on the class type, not on an instance. |
| `scopesFromClaims:` | `+ (NSArray *)scopesFromClaims:(NSDictionary *)claims;` | Extract scope list from claims payload. | Call on the class type, not on an instance. |
| `rolesFromClaims:` | `+ (NSArray *)rolesFromClaims:(NSDictionary *)claims;` | Extract role list from claims payload. | Call on the class type, not on an instance. |
| `context:hasRequiredScopes:` | `+ (BOOL)context:(ALNContext *)context hasRequiredScopes:(NSArray *)scopes;` | Return whether context claims satisfy required scope set. | Call on the class type, not on an instance. |
| `context:hasRequiredRoles:` | `+ (BOOL)context:(ALNContext *)context hasRequiredRoles:(NSArray *)roles;` | Return whether context claims satisfy required role set. | Call on the class type, not on an instance. |
