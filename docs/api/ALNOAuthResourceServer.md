# ALNOAuthResourceServer

- Kind: `interface`
- Header: `src/Arlen/Support/ALNOAuthResourceServer.h`

Opt-in OAuth access-token verifier, verified principal, protected-resource discovery and shared REST/MCP authorization middleware.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `configuration` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `configuration` property available on `ALNOAuthResourceServer`. |
| `metadataPath` | `NSString *` | `nonatomic, copy, readonly` | Public `metadataPath` property available on `ALNOAuthResourceServer`. |
| `metadataURL` | `NSString *` | `nonatomic, copy, readonly` | Public `metadataURL` property available on `ALNOAuthResourceServer`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithConfiguration:documentLoader:authorizationPolicy:error:` | `- (nullable instancetype)initWithConfiguration:(NSDictionary *)configuration documentLoader:(nullable ALNOAuthDocumentLoader)loader authorizationPolicy:(nullable ALNOAuthAuthorizationPolicy)policy error:(NSError *_Nullable *_Nullable)error;` | Validate and freeze resource-server trust configuration and application policy. | Pass nil documentLoader for bounded Foundation HTTPS fetching; inject a controlled loader for tests. Register the instance as a plugin, or assign it to MCP before installing. A nil result indicates invalid configuration. |
| `entraConfigurationForTenant:tokenVersion:audience:resourceURL:scopes:error:` | `+ (nullable NSDictionary *)entraConfigurationForTenant:(NSString *)tenant tokenVersion:(NSString *)version audience:(NSString *)audience resourceURL:(NSString *)resourceURL scopes:(NSArray *)scopes error:(NSError *_Nullable *_Nullable)error;` | Perform `entra configuration for tenant` for `ALNOAuthResourceServer`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `principalForAccessToken:error:` | `- (nullable NSDictionary *)principalForAccessToken:(nullable NSString *)token error:(NSError *_Nullable *_Nullable)error;` | Validate access-token signature and claims and return an immutable normalized principal. | This cryptographic method does not invoke request policy. Use the installed middleware for authorization and suspension checks; do not log the token. |
| `protectedResourceMetadata` | `- (NSDictionary *)protectedResourceMetadata;` | Perform `protected resource metadata` for `ALNOAuthResourceServer`. | Read this value when you need current runtime/request state. |
| `challengeForError:` | `- (NSString *)challengeForError:(nullable NSString *)error;` | Perform `challenge for error` for `ALNOAuthResourceServer`. | Capture the returned value and propagate errors/validation as needed. |
| `protectsPath:` | `- (BOOL)protectsPath:(NSString *)path;` | Perform `protects path` for `ALNOAuthResourceServer`. | Check the return value to confirm the operation succeeded. |
