# ALNController

- Kind: `interface`
- Header: `src/Arlen/MVC/Controller/ALNController.h`

Base controller with template/JSON rendering, parameter helpers, auth/session helpers, and envelope conventions.

## Typical Usage

```objc
- (void)showUser {
  NSString *userID = [self stringParamForName:@"id"];
  if (userID == nil) {
    [self addValidationErrorForField:@"id"
                                code:@"required"
                             message:@"id is required"];
    [self renderValidationErrors];
    return;
  }

  NSDictionary *payload = @{ @"id": userID, @"status": @"ok" };
  NSError *error = nil;
  [self renderJSONEnvelopeWithData:payload meta:nil error:&error];
}
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `context` | `ALNContext *` | `nonatomic, strong` | Public `context` property available on `ALNController`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `jsonWritingOptions` | `+ (NSJSONWritingOptions)jsonWritingOptions;` | Return JSON serializer options used by controller helpers. | Call on the class type, not on an instance. |
| `renderTemplate:context:error:` | `- (BOOL)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context error:(NSError *_Nullable *_Nullable)error;` | Render a template with explicit local context. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `renderTemplate:context:layout:error:` | `- (BOOL)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context layout:(nullable NSString *)layoutName error:(NSError *_Nullable *_Nullable)error;` | Render a template with explicit context and layout. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `renderTemplateWithoutLayout:context:error:` | `- (BOOL)renderTemplateWithoutLayout:(NSString *)templateName context:(nullable NSDictionary *)context error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `renderTemplate:error:` | `- (BOOL)renderTemplate:(NSString *)templateName error:(NSError *_Nullable *_Nullable)error;` | Render a template using current stash/context defaults. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `renderTemplate:layout:error:` | `- (BOOL)renderTemplate:(NSString *)templateName layout:(nullable NSString *)layoutName error:(NSError *_Nullable *_Nullable)error;` | Render a template with an explicit layout and default context. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `renderTemplateWithoutLayout:error:` | `- (BOOL)renderTemplateWithoutLayout:(NSString *)templateName error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `templateContext` | `- (NSDictionary *)templateContext;` | Perform `template context` for `ALNController`. | Read this value when you need current runtime/request state. |
| `useTemplateLayout:` | `- (void)useTemplateLayout:(nullable NSString *)layoutName;` | Perform `use template layout` for `ALNController`. | Call for side effects; this method does not return a value. |
| `disableTemplateLayout` | `- (void)disableTemplateLayout;` | Perform `disable template layout` for `ALNController`. | Call for side effects; this method does not return a value. |
| `clearTemplateLayoutPreference` | `- (void)clearTemplateLayoutPreference;` | Perform `clear template layout preference` for `ALNController`. | Call for side effects; this method does not return a value. |
| `stashValue:forKey:` | `- (void)stashValue:(nullable id)value forKey:(NSString *)key;` | Set one value in controller stash for template rendering. | Call for side effects; this method does not return a value. |
| `stashValues:` | `- (void)stashValues:(NSDictionary *)values;` | Merge multiple values into controller stash. | Call for side effects; this method does not return a value. |
| `stashValueForKey:` | `- (nullable id)stashValueForKey:(NSString *)key;` | Read one value from controller stash. | Capture the returned value and propagate errors/validation as needed. |
| `renderNegotiatedTemplate:context:jsonObject:error:` | `- (BOOL)renderNegotiatedTemplate:(NSString *)templateName context:(nullable NSDictionary *)context jsonObject:(nullable id)jsonObject error:(NSError *_Nullable *_Nullable)error;` | Render template or JSON based on negotiated request format. | Provide both template and JSON object so the controller can switch by `Accept` header automatically. |
| `renderJSON:error:` | `- (BOOL)renderJSON:(id)object error:(NSError *_Nullable *_Nullable)error;` | Serialize an object to JSON and set response body/content type. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `renderText:` | `- (void)renderText:(NSString *)text;` | Set plain-text response body. | Call from controller action paths after selecting response status/headers. |
| `renderData:contentType:` | `- (void)renderData:(NSData *)data contentType:(nullable NSString *)contentType;` | Render a response payload for the current request context. | Call from controller action paths after selecting response status/headers. |
| `renderSSEEvents:` | `- (void)renderSSEEvents:(NSArray *)events;` | Render server-sent event frames. | Set SSE-appropriate headers before calling when streaming manually; events should already be normalized dictionaries. |
| `acceptWebSocketEcho` | `- (void)acceptWebSocketEcho;` | Upgrade and run a websocket echo session. | Use from websocket-only routes. This method writes the websocket response directly. |
| `acceptWebSocketChannel:` | `- (void)acceptWebSocketChannel:(NSString *)channel;` | Upgrade and subscribe websocket connection to a realtime channel. | Pair with `ALNRealtimeHub` publish paths; channel value should be stable and tenant-safe. |
| `redirectTo:status:` | `- (void)redirectTo:(NSString *)location status:(NSInteger)statusCode;` | Set redirect status and `Location` header. | Call for side effects; this method does not return a value. |
| `setStatus:` | `- (void)setStatus:(NSInteger)statusCode;` | Set HTTP response status code. | Call before downstream behavior that depends on this updated value. |
| `hasRendered` | `- (BOOL)hasRendered;` | Return whether the controller already produced a response. | Check the return value to confirm the operation succeeded. |
| `session` | `- (NSMutableDictionary *)session;` | Return the mutable session map for the current request. | Read this value when you need current runtime/request state. |
| `csrfToken` | `- (nullable NSString *)csrfToken;` | Return the CSRF token associated with the current request/session. | Read this value when you need current runtime/request state. |
| `markSessionDirty` | `- (void)markSessionDirty;` | Mark session state as modified so middleware persists it. | Call for side effects; this method does not return a value. |
| `params` | `- (NSDictionary *)params;` | Return merged request parameters (route, query, and body). | Read this value when you need current runtime/request state. |
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
| `addValidationErrorForField:code:message:` | `- (void)addValidationErrorForField:(NSString *)field code:(NSString *)code message:(NSString *)message;` | Append a structured validation error to context state. | Call during bootstrap/setup before this behavior is exercised. |
| `validationErrors` | `- (NSArray *)validationErrors;` | Return collected validation errors for this request. | Read this value when you need current runtime/request state. |
| `renderValidationErrors` | `- (BOOL)renderValidationErrors;` | Render current validation errors using normalized error envelope. | Use after accumulating validation errors; this standardizes envelope shape and status behavior. |
| `normalizedEnvelopeWithData:meta:` | `- (NSDictionary *)normalizedEnvelopeWithData:(nullable id)data meta:(nullable NSDictionary *)meta;` | Build normalized response envelope `{data, meta}` structure. | Treat returned collection values as snapshots unless the API documents mutability. |
| `renderJSONEnvelopeWithData:meta:error:` | `- (BOOL)renderJSONEnvelopeWithData:(nullable id)data meta:(nullable NSDictionary *)meta error:(NSError *_Nullable *_Nullable)error;` | Serialize and render normalized `{data, meta}` JSON envelope. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call from controller action paths after selecting response status/headers. |
| `validatedParams` | `- (NSDictionary *)validatedParams;` | Return schema-validated and transformed parameter values. | Read this value when you need current runtime/request state. |
| `validatedValueForName:` | `- (nullable id)validatedValueForName:(NSString *)name;` | Return one validated parameter value by field key. | Capture the returned value and propagate errors/validation as needed. |
| `authClaims` | `- (nullable NSDictionary *)authClaims;` | Return authenticated JWT/API claims for the current request. | Read this value when you need current runtime/request state. |
| `authScopes` | `- (NSArray *)authScopes;` | Return authenticated scopes for authorization checks. | Read this value when you need current runtime/request state. |
| `authRoles` | `- (NSArray *)authRoles;` | Return authenticated roles for authorization checks. | Read this value when you need current runtime/request state. |
| `authSubject` | `- (nullable NSString *)authSubject;` | Return the authenticated subject identifier (`sub`). | Read this value when you need current runtime/request state. |
| `authProvider` | `- (nullable NSString *)authProvider;` | Perform `auth provider` for `ALNController`. | Read this value when you need current runtime/request state. |
| `authMethods` | `- (NSArray *)authMethods;` | Perform `auth methods` for `ALNController`. | Read this value when you need current runtime/request state. |
| `authAssuranceLevel` | `- (NSUInteger)authAssuranceLevel;` | Perform `auth assurance level` for `ALNController`. | Read this value when you need current runtime/request state. |
| `authPrimaryAuthenticatedAt` | `- (nullable NSDate *)authPrimaryAuthenticatedAt;` | Perform `auth primary authenticated at` for `ALNController`. | Read this value when you need current runtime/request state. |
| `authMFASatisfiedAt` | `- (nullable NSDate *)authMFASatisfiedAt;` | Perform `auth mfa satisfied at` for `ALNController`. | Read this value when you need current runtime/request state. |
| `authSessionIdentifier` | `- (nullable NSString *)authSessionIdentifier;` | Perform `auth session identifier` for `ALNController`. | Read this value when you need current runtime/request state. |
| `isMFAAuthenticated` | `- (BOOL)isMFAAuthenticated;` | Return whether `ALNController` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `startAuthenticatedSessionForSubject:provider:methods:error:` | `- (BOOL)startAuthenticatedSessionForSubject:(NSString *)subject provider:(nullable NSString *)provider methods:(nullable NSArray *)methods error:(NSError *_Nullable *_Nullable)error;` | Start runtime lifecycle processing and readiness checks. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `completeStepUpWithMethod:assuranceLevel:error:` | `- (BOOL)completeStepUpWithMethod:(NSString *)method assuranceLevel:(NSUInteger)assuranceLevel error:(NSError *_Nullable *_Nullable)error;` | Perform `complete step up with method` for `ALNController`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `clearAuthenticatedSession` | `- (void)clearAuthenticatedSession;` | Perform `clear authenticated session` for `ALNController`. | Call for side effects; this method does not return a value. |
| `jobsAdapter` | `- (nullable id<ALNJobAdapter>)jobsAdapter;` | Return the configured jobs adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `cacheAdapter` | `- (nullable id<ALNCacheAdapter>)cacheAdapter;` | Return the configured cache adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `localizationAdapter` | `- (nullable id<ALNLocalizationAdapter>)localizationAdapter;` | Return the configured localization adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `mailAdapter` | `- (nullable id<ALNMailAdapter>)mailAdapter;` | Return the configured mail adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `attachmentAdapter` | `- (nullable id<ALNAttachmentAdapter>)attachmentAdapter;` | Return the configured attachment adapter for the current application/context. | Read this value when you need current runtime/request state. |
| `localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:` | `- (NSString *)localizedStringForKey:(NSString *)key locale:(nullable NSString *)locale fallbackLocale:(nullable NSString *)fallbackLocale defaultValue:(nullable NSString *)defaultValue arguments:(nullable NSDictionary *)arguments;` | Resolve localized string with fallback/default and interpolation args. | Capture the returned value and propagate errors/validation as needed. |
| `pageStateForKey:` | `- (ALNPageState *)pageStateForKey:(NSString *)pageKey;` | Return a page-state helper bound to one logical page namespace. | Capture the returned value and propagate errors/validation as needed. |
