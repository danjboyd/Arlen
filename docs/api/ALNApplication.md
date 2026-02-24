# ALNApplication

- Kind: `interface`
- Header: `src/Arlen/Core/ALNApplication.h`

Primary runtime container for route registration, middleware/plugins, service adapters, lifecycle hooks, and OpenAPI metadata.

## Typical Usage

```objc
NSError *error = nil;
ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:@"development"
                                                     configRoot:@"config"
                                                          error:&error];
if (app == nil) {
  NSLog(@"startup config failed: %@", error);
  return;
}

[app registerRouteMethod:@"GET"
                    path:@"/healthz"
                    name:@"healthz"
         controllerClass:[HealthController class]
                  action:@"show"];

if (![app startWithError:&error]) {
  NSLog(@"app startup failed: %@", error);
}
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `router` | `ALNRouter *` | `nonatomic, strong, readonly` | Router instance that owns route registration and path matching for this app. |
| `config` | `NSDictionary *` | `nonatomic, copy, readonly` | Resolved application configuration dictionary used at runtime. |
| `environment` | `NSString *` | `nonatomic, copy, readonly` | Current runtime environment name (`development`, `test`, `production`, etc.). |
| `logger` | `ALNLogger *` | `nonatomic, strong, readonly` | Application-wide structured logger used by controllers/middleware/runtime internals. |
| `metrics` | `ALNMetricsRegistry *` | `nonatomic, strong, readonly` | Application-wide metrics registry used for counters/gauges/timings and `/metrics` export. |
| `middlewares` | `NSArray *` | `nonatomic, copy, readonly` | Ordered middleware list executed for request pre/post processing. |
| `plugins` | `NSArray *` | `nonatomic, copy, readonly` | Registered plugin instances that extended this app during bootstrap. |
| `lifecycleHooks` | `NSArray *` | `nonatomic, copy, readonly` | Registered lifecycle hooks invoked around startup and shutdown. |
| `staticMounts` | `NSArray *` | `nonatomic, copy, readonly` | Configured static mount definitions used by the HTTP server static-file path. |
| `jobsAdapter` | `id<ALNJobAdapter>` | `nonatomic, strong, readonly` | Adapter used by this runtime for the corresponding service concern. |
| `cacheAdapter` | `id<ALNCacheAdapter>` | `nonatomic, strong, readonly` | Adapter used by this runtime for the corresponding service concern. |
| `localizationAdapter` | `id<ALNLocalizationAdapter>` | `nonatomic, strong, readonly` | Adapter used by this runtime for the corresponding service concern. |
| `mailAdapter` | `id<ALNMailAdapter>` | `nonatomic, strong, readonly` | Adapter used by this runtime for the corresponding service concern. |
| `attachmentAdapter` | `id<ALNAttachmentAdapter>` | `nonatomic, strong, readonly` | Adapter used by this runtime for the corresponding service concern. |
| `clusterEnabled` | `BOOL` | `nonatomic, assign, readonly` | Cluster/runtime metadata exposed for diagnostics and routing behavior. |
| `clusterName` | `NSString *` | `nonatomic, copy, readonly` | Cluster identifier used for distributed-runtime diagnostics and headers. |
| `clusterNodeID` | `NSString *` | `nonatomic, copy, readonly` | Node identifier used for distributed-runtime diagnostics and headers. |
| `clusterExpectedNodes` | `NSUInteger` | `nonatomic, assign, readonly` | Cluster/runtime metadata exposed for diagnostics and routing behavior. |
| `clusterObservedNodes` | `NSUInteger` | `nonatomic, assign, readonly` | Cluster/runtime metadata exposed for diagnostics and routing behavior. |
| `clusterEmitHeaders` | `BOOL` | `nonatomic, assign, readonly` | Cluster/runtime metadata exposed for diagnostics and routing behavior. |
| `started` | `BOOL` | `nonatomic, assign, readonly, getter=isStarted` | Lifecycle flag that indicates whether startup has completed. |
| `traceExporter` | `id<ALNTraceExporter>` | `nonatomic, strong, nullable` | Optional request-trace exporter invoked after route dispatch. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithEnvironment:configRoot:error:` | `- (nullable instancetype)initWithEnvironment:(NSString *)environment configRoot:(NSString *)configRoot error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNApplication` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithConfig:` | `- (instancetype)initWithConfig:(NSDictionary *)config;` | Initialize and return a new `ALNApplication` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `registerRouteMethod:path:name:controllerClass:action:` | `- (ALNRoute *)registerRouteMethod:(NSString *)method path:(NSString *)path name:(nullable NSString *)name controllerClass:(Class)controllerClass action:(NSString *)actionName;` | Register this component so it participates in runtime behavior. | Call during bootstrap/setup before this behavior is exercised. |
| `registerRouteMethod:path:name:formats:controllerClass:guardAction:action:` | `- (ALNRoute *)registerRouteMethod:(NSString *)method path:(NSString *)path name:(nullable NSString *)name formats:(nullable NSArray *)formats controllerClass:(Class)controllerClass guardAction:(nullable NSString *)guardAction action:(NSString *)actionName;` | Register this component so it participates in runtime behavior. | Call during bootstrap/setup before this behavior is exercised. |
| `beginRouteGroupWithPrefix:guardAction:formats:` | `- (void)beginRouteGroupWithPrefix:(NSString *)prefix guardAction:(nullable NSString *)guardAction formats:(nullable NSArray *)formats;` | Begin a scoped operation that must be closed by a matching end call. | Call once for a grouped route section, then register routes, then call `endRouteGroup`. |
| `endRouteGroup` | `- (void)endRouteGroup;` | Close a previously started scoped operation. | Always pair with `beginRouteGroupWithPrefix:guardAction:formats:` to avoid leaking group settings. |
| `mountApplication:atPrefix:` | `- (BOOL)mountApplication:(ALNApplication *)application atPrefix:(NSString *)prefix;` | Mount or attach this component into the active application tree. | Mount child app at a fixed URL prefix before startup. |
| `mountStaticDirectory:atPrefix:allowExtensions:` | `- (BOOL)mountStaticDirectory:(NSString *)directory atPrefix:(NSString *)prefix allowExtensions:(nullable NSArray *)allowExtensions;` | Mount or attach this component into the active application tree. | Prefer explicit extension allowlists in production to reduce accidental file exposure. |
| `addMiddleware:` | `- (void)addMiddleware:(id<ALNMiddleware>)middleware;` | Add this item to the current runtime collection. | Call during bootstrap/setup before this behavior is exercised. |
| `setJobsAdapter:` | `- (void)setJobsAdapter:(id<ALNJobAdapter>)adapter;` | Set or override the current value for this concern. | Call before downstream behavior that depends on this updated value. |
| `setCacheAdapter:` | `- (void)setCacheAdapter:(id<ALNCacheAdapter>)adapter;` | Set or override the current value for this concern. | Call before downstream behavior that depends on this updated value. |
| `setLocalizationAdapter:` | `- (void)setLocalizationAdapter:(id<ALNLocalizationAdapter>)adapter;` | Set or override the current value for this concern. | Call before downstream behavior that depends on this updated value. |
| `setMailAdapter:` | `- (void)setMailAdapter:(id<ALNMailAdapter>)adapter;` | Set or override the current value for this concern. | Call before downstream behavior that depends on this updated value. |
| `setAttachmentAdapter:` | `- (void)setAttachmentAdapter:(id<ALNAttachmentAdapter>)adapter;` | Set or override the current value for this concern. | Call before downstream behavior that depends on this updated value. |
| `localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:` | `- (NSString *)localizedStringForKey:(NSString *)key locale:(nullable NSString *)locale fallbackLocale:(nullable NSString *)fallbackLocale defaultValue:(nullable NSString *)defaultValue arguments:(nullable NSDictionary *)arguments;` | Resolve localized string with fallback/default and interpolation args. | Capture the returned value and propagate errors/validation as needed. |
| `registerLifecycleHook:` | `- (BOOL)registerLifecycleHook:(id<ALNLifecycleHook>)hook;` | Register this component so it participates in runtime behavior. | Call during bootstrap/setup before this behavior is exercised. |
| `registerPlugin:error:` | `- (BOOL)registerPlugin:(id<ALNPlugin>)plugin error:(NSError *_Nullable *_Nullable)error;` | Register this component so it participates in runtime behavior. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call during bootstrap/setup before this behavior is exercised. |
| `registerPluginClassNamed:error:` | `- (BOOL)registerPluginClassNamed:(NSString *)className error:(NSError *_Nullable *_Nullable)error;` | Register this component so it participates in runtime behavior. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call during bootstrap/setup before this behavior is exercised. |
| `configureRouteNamed:requestSchema:responseSchema:summary:operationID:tags:requiredScopes:requiredRoles:includeInOpenAPI:error:` | `- (BOOL)configureRouteNamed:(NSString *)routeName requestSchema:(nullable NSDictionary *)requestSchema responseSchema:(nullable NSDictionary *)responseSchema summary:(nullable NSString *)summary operationID:(nullable NSString *)operationID tags:(nullable NSArray *)tags requiredScopes:(nullable NSArray *)requiredScopes requiredRoles:(nullable NSArray *)requiredRoles includeInOpenAPI:(BOOL)includeInOpenAPI error:(NSError *_Nullable *_Nullable)error;` | Configure behavior for an already-registered runtime element. | Call after route registration and before startup so compile-on-start checks can validate schemas/scopes/roles. |
| `dispatchRequest:` | `- (ALNResponse *)dispatchRequest:(ALNRequest *)request;` | Dispatch the current request through routing and controller handling. | Used by HTTP server internals; app code typically calls higher-level server APIs. |
| `routeTable` | `- (NSArray *)routeTable;` | Return route metadata table for diagnostics and route inspection. | Read this value when you need current runtime/request state. |
| `openAPISpecification` | `- (NSDictionary *)openAPISpecification;` | Build OpenAPI document from registered routes and schema metadata. | Read this value when you need current runtime/request state. |
| `writeOpenAPISpecToPath:pretty:error:` | `- (BOOL)writeOpenAPISpecToPath:(NSString *)path pretty:(BOOL)pretty error:(NSError *_Nullable *_Nullable)error;` | Write OpenAPI document to disk for tooling/publishing. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `startWithError:` | `- (BOOL)startWithError:(NSError *_Nullable *_Nullable)error;` | Start runtime lifecycle processing and readiness checks. | Call once before accepting traffic. On failure, inspect startup compile/security diagnostics in `error`. |
| `shutdown` | `- (void)shutdown;` | Shut down runtime processing and release resources. | Call during graceful stop to execute lifecycle hooks and flush runtime state. |
