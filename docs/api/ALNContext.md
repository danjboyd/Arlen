# ALNContext

- Kind: `interface`
- Header: `src/Arlen/MVC/Controller/ALNContext.h`

Per-request execution context shared across middleware and controllers, including params/auth/session/services.

## Typical Usage

```objc
NSString *userID = [context stringParamForName:@"id"];
if (userID == nil) {
  [context addValidationErrorForField:@"id"
                                 code:@"required"
                              message:@"id is required"];
}
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `request` | `ALNRequest *` | `nonatomic, strong, readonly` | Public `request` property available on `ALNContext`. |
| `response` | `ALNResponse *` | `nonatomic, strong, readonly` | Public `response` property available on `ALNContext`. |
| `params` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `params` property available on `ALNContext`. |
| `stash` | `NSMutableDictionary *` | `nonatomic, strong, readonly` | Public `stash` property available on `ALNContext`. |
| `logger` | `ALNLogger *` | `nonatomic, strong, readonly` | Runtime `logger` component configured for this application instance. |
| `perfTrace` | `ALNPerfTrace *` | `nonatomic, strong, readonly` | Public `perfTrace` property available on `ALNContext`. |
| `routeName` | `NSString *` | `nonatomic, copy, readonly` | Public `routeName` property available on `ALNContext`. |
| `controllerName` | `NSString *` | `nonatomic, copy, readonly` | Public `controllerName` property available on `ALNContext`. |
| `actionName` | `NSString *` | `nonatomic, copy, readonly` | Public `actionName` property available on `ALNContext`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithRequest:response:params:stash:logger:perfTrace:routeName:controllerName:actionName:` | `- (instancetype)initWithRequest:(ALNRequest *)request response:(ALNResponse *)response params:(NSDictionary *)params stash:(NSMutableDictionary *)stash logger:(ALNLogger *)logger perfTrace:(ALNPerfTrace *)perfTrace routeName:(NSString *)routeName controllerName:(NSString *)controllerName actionName:(NSString *)actionName;` | Initialize and return a new `ALNContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `session` | `- (NSMutableDictionary *)session;` | Return the mutable session map for the current request. | Read this value when you need current runtime/request state. |
| `markSessionDirty` | `- (void)markSessionDirty;` | Mark session state as modified so middleware persists it. | Call for side effects; this method does not return a value. |
| `csrfToken` | `- (nullable NSString *)csrfToken;` | Return the CSRF token associated with the current request/session. | Read this value when you need current runtime/request state. |
| `allParams` | `- (NSDictionary *)allParams;` | Return merged request parameters (route, query, and body). | Read this value when you need current runtime/request state. |
| `paramValueForName:` | `- (nullable id)paramValueForName:(NSString *)name;` | Return a raw parameter value by key. | Capture the returned value and propagate errors/validation as needed. |
| `stringParamForName:` | `- (nullable NSString *)stringParamForName:(NSString *)name;` | Return a parameter coerced to string when possible. | Capture the returned value and propagate errors/validation as needed. |
| `queryValueForName:` | `- (nullable NSString *)queryValueForName:(NSString *)name;` | Return a query-string parameter by key. | Capture the returned value and propagate errors/validation as needed. |
| `headerValueForName:` | `- (nullable NSString *)headerValueForName:(NSString *)name;` | Return a request header value by key. | Capture the returned value and propagate errors/validation as needed. |
| `queryIntegerForName:` | `- (nullable NSNumber *)queryIntegerForName:(NSString *)name;` | Return a query parameter parsed as an integer. | Prefer this over manual parsing to avoid repeated validation boilerplate. |
| `queryBooleanForName:` | `- (nullable NSNumber *)queryBooleanForName:(NSString *)name;` | Return a query parameter parsed as a boolean. | Accepts common boolean forms; check for `nil` when parameter is absent or invalid. |
| `headerIntegerForName:` | `- (nullable NSNumber *)headerIntegerForName:(NSString *)name;` | Return a header parsed as an integer. | Use for numeric custom headers; returns `nil` when parsing fails. |
| `headerBooleanForName:` | `- (nullable NSNumber *)headerBooleanForName:(NSString *)name;` | Return a header parsed as a boolean. | Use for feature-flag style headers; returns `nil` when parsing fails. |
| `requireStringParam:value:` | `- (BOOL)requireStringParam:(NSString *)name value:(NSString *_Nullable *_Nullable)value;` | Require a string parameter and copy it to the out-parameter. | If this returns `NO`, add/return validation errors immediately rather than continuing handler logic. |
| `requireIntegerParam:value:` | `- (BOOL)requireIntegerParam:(NSString *)name value:(NSInteger *_Nullable)value;` | Require an integer parameter and copy it to the out-parameter. | If this returns `NO`, add/return validation errors immediately rather than continuing handler logic. |
| `applyETagAndReturnNotModifiedIfMatch:` | `- (BOOL)applyETagAndReturnNotModifiedIfMatch:(NSString *)etag;` | Apply this helper to context and update response state. | Call before expensive render/DB work; if it returns `YES`, exit action early. |
| `requestFormat` | `- (NSString *)requestFormat;` | Resolve request format from explicit route format or Accept negotiation. | Read this value when you need current runtime/request state. |
| `wantsJSON` | `- (BOOL)wantsJSON;` | Return whether request negotiation prefers JSON. | Check the return value to confirm the operation succeeded. |
| `addValidationErrorForField:code:message:` | `- (void)addValidationErrorForField:(NSString *)field code:(NSString *)code message:(NSString *)message;` | Append a structured validation error to context state. | Call during bootstrap/setup before this behavior is exercised. |
| `validationErrors` | `- (NSArray *)validationErrors;` | Return collected validation errors for this request. | Read this value when you need current runtime/request state. |
| `validatedParams` | `- (NSDictionary *)validatedParams;` | Return schema-validated and transformed parameter values. | Read this value when you need current runtime/request state. |
| `validatedValueForName:` | `- (nullable id)validatedValueForName:(NSString *)name;` | Return one validated parameter value by field key. | Capture the returned value and propagate errors/validation as needed. |
| `authClaims` | `- (nullable NSDictionary *)authClaims;` | Return authenticated JWT/API claims for the current request. | Read this value when you need current runtime/request state. |
| `authScopes` | `- (NSArray *)authScopes;` | Return authenticated scopes for authorization checks. | Read this value when you need current runtime/request state. |
| `authRoles` | `- (NSArray *)authRoles;` | Return authenticated roles for authorization checks. | Read this value when you need current runtime/request state. |
| `authSubject` | `- (nullable NSString *)authSubject;` | Return the authenticated subject identifier (`sub`). | Read this value when you need current runtime/request state. |
| `jobsAdapter` | `- (nullable id<ALNJobAdapter>)jobsAdapter;` | Return the configured jobs adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `cacheAdapter` | `- (nullable id<ALNCacheAdapter>)cacheAdapter;` | Return the configured cache adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `localizationAdapter` | `- (nullable id<ALNLocalizationAdapter>)localizationAdapter;` | Return the configured localization adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `mailAdapter` | `- (nullable id<ALNMailAdapter>)mailAdapter;` | Return the configured mail adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `attachmentAdapter` | `- (nullable id<ALNAttachmentAdapter>)attachmentAdapter;` | Return the configured attachment adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:` | `- (NSString *)localizedStringForKey:(NSString *)key locale:(nullable NSString *)locale fallbackLocale:(nullable NSString *)fallbackLocale defaultValue:(nullable NSString *)defaultValue arguments:(nullable NSDictionary *)arguments;` | Resolve localized string with fallback/default and interpolation args. | Capture the returned value and propagate errors/validation as needed. |
| `pageStateForKey:` | `- (ALNPageState *)pageStateForKey:(NSString *)pageKey;` | Return a page-state helper bound to one logical page namespace. | Capture the returned value and propagate errors/validation as needed. |
