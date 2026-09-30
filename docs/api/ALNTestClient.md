# ALNTestClient

- Kind: `interface`
- Header: `src/Arlen/Support/ALNTestClient.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `application` | `ALNApplication *` | `nonatomic, strong, readonly` | Public `application` property available on `ALNTestClient`. |
| `cookies` | `NSDictionary<NSString *, NSString *> *` | `nonatomic, copy, readonly` | Public `cookies` property available on `ALNTestClient`. |
| `automaticCSRF` | `BOOL` | `nonatomic, assign` | Public `automaticCSRF` property available on `ALNTestClient`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `setAppMain:` | `+ (void)setAppMain:(nullable ALNAppMainFunction)appMain;` | Set or override the current value for this concern. | Call on the class type, not on an instance. Call before downstream behavior that depends on this updated value. |
| `clientWithEnvironment:configOverrides:error:` | `+ (nullable instancetype)clientWithEnvironment:(nullable NSString *)environment configOverrides:(nullable NSDictionary *)configOverrides error:(NSError *_Nullable *_Nullable)error;` | Perform `client with environment` for `ALNTestClient`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `clientWithAppRoot:environment:configOverrides:registerRoutes:error:` | `+ (nullable instancetype)clientWithAppRoot:(nullable NSString *)appRoot environment:(nullable NSString *)environment configOverrides:(nullable NSDictionary *)configOverrides registerRoutes:(nullable ALNRouteRegistrationCallback)registerRoutes error:(NSError *_Nullable *_Nullable)error;` | Perform `client with app root` for `ALNTestClient`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithApplication:error:` | `- (nullable instancetype)initWithApplication:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNTestClient` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `get:` | `- (ALNResponse *)get:(NSString *)path;` | Perform `get` for `ALNTestClient`. | Capture the returned value and propagate errors/validation as needed. |
| `get:query:headers:` | `- (ALNResponse *)get:(NSString *)path query:(nullable NSDictionary<NSString *, NSString *> *)query headers:(nullable NSDictionary<NSString *, NSString *> *)headers;` | Perform `get` for `ALNTestClient`. | Capture the returned value and propagate errors/validation as needed. |
| `post:form:` | `- (ALNResponse *)post:(NSString *)path form:(nullable NSDictionary<NSString *, NSString *> *)form;` | Perform `post` for `ALNTestClient`. | Capture the returned value and propagate errors/validation as needed. |
| `post:JSON:` | `- (ALNResponse *)post:(NSString *)path JSON:(nullable id)object;` | Perform `post` for `ALNTestClient`. | Capture the returned value and propagate errors/validation as needed. |
| `post:multipartFields:files:` | `- (ALNResponse *)post:(NSString *)path multipartFields:(nullable NSDictionary<NSString *, NSString *> *)fields files:(nullable NSArray<NSDictionary *> *)files;` | Perform `post` for `ALNTestClient`. | Capture the returned value and propagate errors/validation as needed. |
| `requestWithMethod:path:query:headers:body:` | `- (ALNResponse *)requestWithMethod:(NSString *)method path:(NSString *)path query:(nullable NSString *)query headers:(nullable NSDictionary<NSString *, NSString *> *)headers body:(nullable NSData *)body;` | Perform `request with method` for `ALNTestClient`. | Capture the returned value and propagate errors/validation as needed. |
| `session` | `- (nullable NSDictionary *)session;` | Return the mutable session map for the current request. | Read this value when you need current runtime/request state. |
| `updateSession:error:` | `- (BOOL)updateSession:(void (^)(NSMutableDictionary *session))update error:(NSError *_Nullable *_Nullable)error;` | Perform `update session` for `ALNTestClient`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `csrfToken` | `- (nullable NSString *)csrfToken;` | Return the CSRF token associated with the current request/session. | Read this value when you need current runtime/request state. |
| `signInAsSubject:roles:scopes:error:` | `- (BOOL)signInAsSubject:(NSString *)subject roles:(nullable NSArray<NSString *> *)roles scopes:(nullable NSArray<NSString *> *)scopes error:(NSError *_Nullable *_Nullable)error;` | Perform `sign in as subject` for `ALNTestClient`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `clearCookies` | `- (void)clearCookies;` | Perform `clear cookies` for `ALNTestClient`. | Call for side effects; this method does not return a value. |
