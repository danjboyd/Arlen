# ALNRoute

- Kind: `interface`
- Header: `src/Arlen/MVC/Routing/ALNRoute.h`

Single route descriptor containing method/path pattern/controller/action and matching helpers.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `method` | `NSString *` | `nonatomic, copy, readonly` | Public `method` property available on `ALNRoute`. |
| `pathPattern` | `NSString *` | `nonatomic, copy, readonly` | Public `pathPattern` property available on `ALNRoute`. |
| `name` | `NSString *` | `nonatomic, copy, readonly` | Public `name` property available on `ALNRoute`. |
| `controllerClass` | `Class` | `nonatomic, assign, readonly` | Public `controllerClass` property available on `ALNRoute`. |
| `actionSelector` | `SEL` | `nonatomic, assign, readonly` | Public `actionSelector` property available on `ALNRoute`. |
| `actionName` | `NSString *` | `nonatomic, copy, readonly` | Public `actionName` property available on `ALNRoute`. |
| `guardSelector` | `SEL` | `nonatomic, assign, readonly` | Public `guardSelector` property available on `ALNRoute`. |
| `guardActionName` | `NSString *` | `nonatomic, copy, readonly` | Public `guardActionName` property available on `ALNRoute`. |
| `formats` | `NSArray *` | `nonatomic, copy, readonly` | Public `formats` property available on `ALNRoute`. |
| `registrationIndex` | `NSUInteger` | `nonatomic, assign, readonly` | Public `registrationIndex` property available on `ALNRoute`. |
| `kind` | `ALNRouteKind` | `nonatomic, assign, readonly` | Public `kind` property available on `ALNRoute`. |
| `staticSegmentCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `staticSegmentCount` property available on `ALNRoute`. |
| `requestSchema` | `NSDictionary *` | `nonatomic, copy` | Public `requestSchema` property available on `ALNRoute`. |
| `responseSchema` | `NSDictionary *` | `nonatomic, copy` | Public `responseSchema` property available on `ALNRoute`. |
| `summary` | `NSString *` | `nonatomic, copy` | Public `summary` property available on `ALNRoute`. |
| `operationID` | `NSString *` | `nonatomic, copy` | Public `operationID` property available on `ALNRoute`. |
| `tags` | `NSArray *` | `nonatomic, copy` | Public `tags` property available on `ALNRoute`. |
| `requiredScopes` | `NSArray *` | `nonatomic, copy` | Public `requiredScopes` property available on `ALNRoute`. |
| `requiredRoles` | `NSArray *` | `nonatomic, copy` | Public `requiredRoles` property available on `ALNRoute`. |
| `includeInOpenAPI` | `BOOL` | `nonatomic, assign` | Public `includeInOpenAPI` property available on `ALNRoute`. |
| `compiledActionSignature` | `NSMethodSignature *` | `nonatomic, strong, nullable` | Public `compiledActionSignature` property available on `ALNRoute`. |
| `compiledGuardSignature` | `NSMethodSignature *` | `nonatomic, strong, nullable` | Public `compiledGuardSignature` property available on `ALNRoute`. |
| `compiledInvocationMetadata` | `BOOL` | `nonatomic, assign` | Public `compiledInvocationMetadata` property available on `ALNRoute`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithMethod:pathPattern:name:controllerClass:actionName:registrationIndex:` | `- (instancetype)initWithMethod:(NSString *)method pathPattern:(NSString *)pathPattern name:(nullable NSString *)name controllerClass:(Class)controllerClass actionName:(NSString *)actionName registrationIndex:(NSUInteger)registrationIndex;` | Initialize and return a new `ALNRoute` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithMethod:pathPattern:name:formats:controllerClass:guardActionName:actionName:registrationIndex:` | `- (instancetype)initWithMethod:(NSString *)method pathPattern:(NSString *)pathPattern name:(nullable NSString *)name formats:(nullable NSArray *)formats controllerClass:(Class)controllerClass guardActionName:(nullable NSString *)guardActionName actionName:(NSString *)actionName registrationIndex:(NSUInteger)registrationIndex;` | Initialize and return a new `ALNRoute` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `matchPath:` | `- (nullable NSDictionary *)matchPath:(NSString *)path;` | Match one path against this route pattern and return extracted params. | Treat returned collection values as snapshots unless the API documents mutability. |
| `matchesFormat:` | `- (BOOL)matchesFormat:(nullable NSString *)format;` | Return whether route allows this negotiated/requested format. | Check the return value to confirm the operation succeeded. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
