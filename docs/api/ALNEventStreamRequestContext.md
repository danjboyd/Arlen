# ALNEventStreamRequestContext

- Kind: `interface`
- Header: `src/Arlen/Support/ALNEventStream.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `requestMethod` | `NSString *` | `nonatomic, copy, readonly` | Public `requestMethod` property available on `ALNEventStreamRequestContext`. |
| `requestPath` | `NSString *` | `nonatomic, copy, readonly` | Public `requestPath` property available on `ALNEventStreamRequestContext`. |
| `requestQueryString` | `NSString *` | `nonatomic, copy, readonly` | Public `requestQueryString` property available on `ALNEventStreamRequestContext`. |
| `routeName` | `NSString *` | `nonatomic, copy, readonly` | Public `routeName` property available on `ALNEventStreamRequestContext`. |
| `controllerName` | `NSString *` | `nonatomic, copy, readonly` | Public `controllerName` property available on `ALNEventStreamRequestContext`. |
| `actionName` | `NSString *` | `nonatomic, copy, readonly` | Public `actionName` property available on `ALNEventStreamRequestContext`. |
| `authSubject` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `authSubject` property available on `ALNEventStreamRequestContext`. |
| `authScopes` | `NSArray *` | `nonatomic, copy, readonly` | Public `authScopes` property available on `ALNEventStreamRequestContext`. |
| `authRoles` | `NSArray *` | `nonatomic, copy, readonly` | Public `authRoles` property available on `ALNEventStreamRequestContext`. |
| `authClaims` | `NSDictionary *` | `nonatomic, copy, readonly, nullable` | Public `authClaims` property available on `ALNEventStreamRequestContext`. |
| `authSessionIdentifier` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `authSessionIdentifier` property available on `ALNEventStreamRequestContext`. |
| `liveRequest` | `BOOL` | `nonatomic, assign, readonly` | Public `liveRequest` property available on `ALNEventStreamRequestContext`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `requestContextWithContext:` | `+ (instancetype)requestContextWithContext:(ALNContext *)context;` | Perform `request context with context` for `ALNEventStreamRequestContext`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithRequestMethod:requestPath:requestQueryString:routeName:controllerName:actionName:authSubject:authScopes:authRoles:authClaims:authSessionIdentifier:liveRequest:` | `- (instancetype)initWithRequestMethod:(NSString *)requestMethod requestPath:(NSString *)requestPath requestQueryString:(nullable NSString *)requestQueryString routeName:(nullable NSString *)routeName controllerName:(nullable NSString *)controllerName actionName:(nullable NSString *)actionName authSubject:(nullable NSString *)authSubject authScopes:(nullable NSArray *)authScopes authRoles:(nullable NSArray *)authRoles authClaims:(nullable NSDictionary *)authClaims authSessionIdentifier:(nullable NSString *)authSessionIdentifier liveRequest:(BOOL)liveRequest;` | Initialize and return a new `ALNEventStreamRequestContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
