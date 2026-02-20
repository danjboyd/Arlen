#import "ALNApplication.h"

#import "ALNConfig.h"
#import "ALNOpenAPI.h"
#import "ALNSchemaContract.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNCSRFMiddleware.h"
#import "ALNRateLimitMiddleware.h"
#import "ALNResponseEnvelopeMiddleware.h"
#import "ALNRouter.h"
#import "ALNRoute.h"
#import "ALNSecurityHeadersMiddleware.h"
#import "ALNSessionMiddleware.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNMetrics.h"
#import "ALNAuth.h"

#include <unistd.h>

NSString *const ALNApplicationErrorDomain = @"Arlen.Application.Error";

static BOOL ALNRequestPrefersJSON(ALNRequest *request, BOOL apiOnly);
static void ALNSetStructuredErrorResponse(ALNResponse *response,
                                          NSInteger statusCode,
                                          NSDictionary *payload);

@interface ALNApplication ()

@property(nonatomic, strong, readwrite) ALNRouter *router;
@property(nonatomic, copy, readwrite) NSDictionary *config;
@property(nonatomic, copy, readwrite) NSString *environment;
@property(nonatomic, strong, readwrite) ALNLogger *logger;
@property(nonatomic, strong, readwrite) ALNMetricsRegistry *metrics;
@property(nonatomic, strong) NSMutableArray *mutableMiddlewares;
@property(nonatomic, strong) NSMutableArray *mutablePlugins;
@property(nonatomic, strong) NSMutableArray *mutableLifecycleHooks;
@property(nonatomic, strong) NSMutableArray *mutableMounts;
@property(nonatomic, strong) NSMutableArray *mutableStaticMounts;
@property(nonatomic, strong, readwrite) id<ALNJobAdapter> jobsAdapter;
@property(nonatomic, strong, readwrite) id<ALNCacheAdapter> cacheAdapter;
@property(nonatomic, strong, readwrite) id<ALNLocalizationAdapter> localizationAdapter;
@property(nonatomic, strong, readwrite) id<ALNMailAdapter> mailAdapter;
@property(nonatomic, strong, readwrite) id<ALNAttachmentAdapter> attachmentAdapter;
@property(nonatomic, assign, readwrite) BOOL clusterEnabled;
@property(nonatomic, copy, readwrite) NSString *clusterName;
@property(nonatomic, copy, readwrite) NSString *clusterNodeID;
@property(nonatomic, assign, readwrite) NSUInteger clusterExpectedNodes;
@property(nonatomic, assign, readwrite) BOOL clusterEmitHeaders;
@property(nonatomic, copy) NSString *i18nDefaultLocale;
@property(nonatomic, copy) NSString *i18nFallbackLocale;
@property(nonatomic, assign, readwrite, getter=isStarted) BOOL started;

- (void)loadConfiguredPlugins;
- (void)loadConfiguredStaticMounts;
- (nullable NSDictionary *)mountedEntryForPath:(NSString *)requestPath
                                   rewrittenPath:(NSString *_Nullable *_Nullable)rewrittenPath;

@end

@implementation ALNApplication

- (instancetype)initWithEnvironment:(NSString *)environment
                         configRoot:(NSString *)configRoot
                              error:(NSError **)error {
  NSError *configError = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:configRoot
                                        environment:environment
                                              error:&configError];
  if (config == nil) {
    if (error != NULL) {
      *error = configError;
    }
    return nil;
  }
  return [self initWithConfig:config];
}

- (instancetype)initWithConfig:(NSDictionary *)config {
  self = [super init];
  if (self) {
    _config = [config copy] ?: @{};
    _environment = [_config[@"environment"] copy] ?: @"development";
    _router = [[ALNRouter alloc] init];
    _logger = [[ALNLogger alloc] initWithFormat:_config[@"logFormat"] ?: @"text"];
    _metrics = [[ALNMetricsRegistry alloc] init];
    _mutableMiddlewares = [NSMutableArray array];
    _mutablePlugins = [NSMutableArray array];
    _mutableLifecycleHooks = [NSMutableArray array];
    _mutableMounts = [NSMutableArray array];
    _mutableStaticMounts = [NSMutableArray array];
    _jobsAdapter = [[ALNInMemoryJobAdapter alloc] init];
    _cacheAdapter = [[ALNInMemoryCacheAdapter alloc] init];
    _localizationAdapter = [[ALNInMemoryLocalizationAdapter alloc] init];
    _mailAdapter = [[ALNInMemoryMailAdapter alloc] init];
    _attachmentAdapter = [[ALNInMemoryAttachmentAdapter alloc] init];
    NSDictionary *services = [_config[@"services"] isKindOfClass:[NSDictionary class]] ? _config[@"services"] : @{};
    NSDictionary *i18nConfig =
        [services[@"i18n"] isKindOfClass:[NSDictionary class]] ? services[@"i18n"] : @{};
    NSString *defaultLocale =
        [i18nConfig[@"defaultLocale"] isKindOfClass:[NSString class]] ? i18nConfig[@"defaultLocale"] : @"en";
    if ([defaultLocale length] == 0) {
      defaultLocale = @"en";
    }
    defaultLocale = [defaultLocale lowercaseString];
    NSString *fallbackLocale = [i18nConfig[@"fallbackLocale"] isKindOfClass:[NSString class]]
                                   ? i18nConfig[@"fallbackLocale"]
                                   : defaultLocale;
    if ([fallbackLocale length] == 0) {
      fallbackLocale = defaultLocale;
    }
    fallbackLocale = [fallbackLocale lowercaseString];
    _i18nDefaultLocale = [defaultLocale copy];
    _i18nFallbackLocale = [fallbackLocale copy];
    NSDictionary *cluster = [_config[@"cluster"] isKindOfClass:[NSDictionary class]]
                                ? _config[@"cluster"]
                                : @{};
    id clusterEnabledValue = cluster[@"enabled"];
    _clusterEnabled = [clusterEnabledValue respondsToSelector:@selector(boolValue)]
                          ? [clusterEnabledValue boolValue]
                          : NO;
    NSString *clusterNameValue = [cluster[@"name"] isKindOfClass:[NSString class]]
                                     ? cluster[@"name"]
                                     : @"default";
    if ([clusterNameValue length] == 0) {
      clusterNameValue = @"default";
    }
    _clusterName = [clusterNameValue copy];
    NSString *clusterNodeIDValue = [cluster[@"nodeID"] isKindOfClass:[NSString class]]
                                       ? cluster[@"nodeID"]
                                       : @"node";
    if ([clusterNodeIDValue length] == 0) {
      clusterNodeIDValue = @"node";
    }
    _clusterNodeID = [clusterNodeIDValue copy];
    id expectedNodesValue = cluster[@"expectedNodes"];
    NSUInteger expectedNodes =
        [expectedNodesValue respondsToSelector:@selector(unsignedIntegerValue)]
            ? [expectedNodesValue unsignedIntegerValue]
            : (NSUInteger)1;
    _clusterExpectedNodes = (expectedNodes < 1) ? 1 : expectedNodes;
    id emitHeadersValue = cluster[@"emitHeaders"];
    _clusterEmitHeaders = [emitHeadersValue respondsToSelector:@selector(boolValue)]
                              ? [emitHeadersValue boolValue]
                              : YES;
    _started = NO;
    if ([_environment isEqualToString:@"development"]) {
      _logger.minimumLevel = ALNLogLevelDebug;
    }
    [self registerBuiltInMiddlewares];
    [self loadConfiguredStaticMounts];
    [self loadConfiguredPlugins];
  }
  return self;
}

- (ALNRoute *)registerRouteMethod:(NSString *)method
                             path:(NSString *)path
                             name:(NSString *)name
                  controllerClass:(Class)controllerClass
                           action:(NSString *)actionName {
  return [self registerRouteMethod:method
                              path:path
                              name:name
                           formats:nil
                   controllerClass:controllerClass
                       guardAction:nil
                            action:actionName];
}

- (ALNRoute *)registerRouteMethod:(NSString *)method
                             path:(NSString *)path
                             name:(NSString *)name
                          formats:(NSArray *)formats
                  controllerClass:(Class)controllerClass
                      guardAction:(NSString *)guardAction
                           action:(NSString *)actionName {
  return [self.router addRouteMethod:method
                                path:path
                                name:name
                             formats:formats
                     controllerClass:controllerClass
                         guardAction:guardAction
                              action:actionName];
}

- (void)beginRouteGroupWithPrefix:(NSString *)prefix
                      guardAction:(NSString *)guardAction
                          formats:(NSArray *)formats {
  [self.router beginRouteGroupWithPrefix:prefix
                             guardAction:guardAction
                                 formats:formats];
}

- (void)endRouteGroup {
  [self.router endRouteGroup];
}

- (BOOL)mountApplication:(ALNApplication *)application atPrefix:(NSString *)prefix {
  if (application == nil || application == self) {
    return NO;
  }

  NSString *normalizedPrefix = ALNNormalizeMountPrefix(prefix);
  if ([normalizedPrefix length] == 0) {
    return NO;
  }

  for (NSDictionary *entry in self.mutableMounts) {
    NSString *existingPrefix = [entry[@"prefix"] isKindOfClass:[NSString class]] ? entry[@"prefix"] : @"";
    if ([existingPrefix isEqualToString:normalizedPrefix]) {
      return NO;
    }
  }

  [self.mutableMounts addObject:@{
    @"prefix" : normalizedPrefix,
    @"application" : application
  }];
  return YES;
}

- (NSArray *)staticMounts {
  return [NSArray arrayWithArray:self.mutableStaticMounts];
}

- (BOOL)mountStaticDirectory:(NSString *)directory
                    atPrefix:(NSString *)prefix
             allowExtensions:(NSArray *)allowExtensions {
  NSString *normalizedPrefix = ALNNormalizeMountPrefix(prefix);
  if ([normalizedPrefix length] == 0) {
    return NO;
  }

  NSString *normalizedDirectory = [directory isKindOfClass:[NSString class]]
                                      ? [directory stringByStandardizingPath]
                                      : @"";
  normalizedDirectory = [normalizedDirectory stringByTrimmingCharactersInSet:
                                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalizedDirectory length] == 0) {
    return NO;
  }

  for (NSDictionary *entry in self.mutableStaticMounts) {
    NSString *existingPrefix = [entry[@"prefix"] isKindOfClass:[NSString class]] ? entry[@"prefix"] : @"";
    if ([existingPrefix isEqualToString:normalizedPrefix]) {
      return NO;
    }
  }

  NSArray *extensions = ALNNormalizedStaticExtensions(allowExtensions);
  [self.mutableStaticMounts addObject:@{
    @"prefix" : normalizedPrefix,
    @"directory" : normalizedDirectory,
    @"allowExtensions" : extensions ?: @[],
  }];
  return YES;
}

- (NSArray *)routeTable {
  return [self.router routeTable];
}

- (NSArray *)middlewares {
  return [NSArray arrayWithArray:self.mutableMiddlewares];
}

- (void)addMiddleware:(id<ALNMiddleware>)middleware {
  if (middleware == nil) {
    return;
  }
  [self.mutableMiddlewares addObject:middleware];
}

- (void)setJobsAdapter:(id<ALNJobAdapter>)adapter {
  if (adapter == nil) {
    return;
  }
  _jobsAdapter = adapter;
}

- (void)setCacheAdapter:(id<ALNCacheAdapter>)adapter {
  if (adapter == nil) {
    return;
  }
  _cacheAdapter = adapter;
}

- (void)setLocalizationAdapter:(id<ALNLocalizationAdapter>)adapter {
  if (adapter == nil) {
    return;
  }
  _localizationAdapter = adapter;
}

- (void)setMailAdapter:(id<ALNMailAdapter>)adapter {
  if (adapter == nil) {
    return;
  }
  _mailAdapter = adapter;
}

- (void)setAttachmentAdapter:(id<ALNAttachmentAdapter>)adapter {
  if (adapter == nil) {
    return;
  }
  _attachmentAdapter = adapter;
}

- (NSString *)localizedStringForKey:(NSString *)key
                             locale:(NSString *)locale
                     fallbackLocale:(NSString *)fallbackLocale
                       defaultValue:(NSString *)defaultValue
                          arguments:(NSDictionary *)arguments {
  if (self.localizationAdapter == nil) {
    return defaultValue ?: @"";
  }
  return [self.localizationAdapter localizedStringForKey:key ?: @""
                                                  locale:locale ?: @""
                                          fallbackLocale:fallbackLocale ?: @""
                                            defaultValue:defaultValue ?: @""
                                               arguments:arguments ?: @{}];
}

- (NSArray *)plugins {
  return [NSArray arrayWithArray:self.mutablePlugins];
}

- (NSArray *)lifecycleHooks {
  return [NSArray arrayWithArray:self.mutableLifecycleHooks];
}

- (BOOL)registerLifecycleHook:(id<ALNLifecycleHook>)hook {
  if (hook == nil) {
    return NO;
  }
  [self.mutableLifecycleHooks addObject:hook];
  return YES;
}

- (BOOL)registerPlugin:(id<ALNPlugin>)plugin error:(NSError **)error {
  if (plugin == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:300
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"plugin is required"
                               }];
    }
    return NO;
  }

  NSString *name = [plugin pluginName];
  if ([name length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:301
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"pluginName must not be empty"
                               }];
    }
    return NO;
  }

  for (id<ALNPlugin> existing in self.mutablePlugins) {
    if ([[existing pluginName] isEqualToString:name]) {
      return YES;
    }
  }

  if (![plugin registerWithApplication:self error:error]) {
    return NO;
  }

  if ([plugin respondsToSelector:@selector(middlewaresForApplication:)]) {
    NSArray *middlewares = [plugin middlewaresForApplication:self];
    for (id middleware in middlewares ?: @[]) {
      if ([middleware conformsToProtocol:@protocol(ALNMiddleware)]) {
        [self addMiddleware:middleware];
      }
    }
  }

  if ([plugin conformsToProtocol:@protocol(ALNLifecycleHook)]) {
    [self registerLifecycleHook:(id<ALNLifecycleHook>)plugin];
  }

  [self.mutablePlugins addObject:plugin];
  [self.logger info:@"plugin registered"
             fields:@{
               @"plugin" : name ?: @"",
             }];
  return YES;
}

- (BOOL)registerPluginClassNamed:(NSString *)className error:(NSError **)error {
  if ([className length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:302
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"plugin class name is required"
                               }];
    }
    return NO;
  }

  Class klass = NSClassFromString(className);
  if (klass == Nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:303
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"plugin class not found: %@", className]
                               }];
    }
    return NO;
  }

  id instance = [[klass alloc] init];
  if (![instance conformsToProtocol:@protocol(ALNPlugin)]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:304
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"%@ does not conform to ALNPlugin", className]
                               }];
    }
    return NO;
  }

  return [self registerPlugin:instance error:error];
}

static BOOL ALNResponseHasBody(ALNResponse *response) {
  return [response.bodyData length] > 0;
}

static NSDictionary *ALNDictionaryConfigValue(NSDictionary *config, NSString *key) {
  id value = config[key];
  if ([value isKindOfClass:[NSDictionary class]]) {
    return value;
  }
  return @{};
}

static BOOL ALNBoolConfigValue(id value, BOOL defaultValue) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return defaultValue;
}

static NSUInteger ALNUIntConfigValue(id value, NSUInteger defaultValue, NSUInteger minimum) {
  if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
    NSUInteger parsed = [value unsignedIntegerValue];
    if (parsed >= minimum) {
      return parsed;
    }
  }
  return defaultValue;
}

static NSString *ALNStringConfigValue(id value, NSString *defaultValue) {
  if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
    return value;
  }
  return defaultValue;
}

static NSString *ALNNormalizeMountPrefix(NSString *prefix) {
  if (![prefix isKindOfClass:[NSString class]] || [prefix length] == 0) {
    return nil;
  }
  NSString *normalized =
      [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  while ([normalized containsString:@"//"]) {
    normalized = [normalized stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
  }
  if (![normalized hasPrefix:@"/"]) {
    normalized = [@"/" stringByAppendingString:normalized];
  }
  while ([normalized length] > 1 && [normalized hasSuffix:@"/"]) {
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  if ([normalized length] == 0 || [normalized isEqualToString:@"/"]) {
    return nil;
  }
  return normalized;
}

static NSString *ALNRewriteMountedPath(NSString *requestPath, NSString *prefix) {
  NSString *path = [requestPath isKindOfClass:[NSString class]] ? requestPath : @"/";
  if ([path length] == 0) {
    path = @"/";
  }
  if (![path hasPrefix:@"/"]) {
    path = [@"/" stringByAppendingString:path];
  }

  if ([path isEqualToString:prefix]) {
    return @"/";
  }

  NSString *prefixWithSlash = [prefix stringByAppendingString:@"/"];
  if ([path hasPrefix:prefixWithSlash]) {
    NSString *trimmed = [path substringFromIndex:[prefix length]];
    return ([trimmed length] > 0) ? trimmed : @"/";
  }
  return nil;
}

static NSArray *ALNNormalizedStaticExtensions(NSArray *allowExtensions) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in allowExtensions ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *extension = [[(NSString *)value lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([extension hasPrefix:@"."]) {
      extension = [extension substringFromIndex:1];
    }
    if ([extension length] == 0) {
      continue;
    }
    if ([normalized containsObject:extension]) {
      continue;
    }
    [normalized addObject:extension];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray *ALNNormalizedUniqueStrings(NSArray *values) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0 || [normalized containsObject:trimmed]) {
      continue;
    }
    [normalized addObject:trimmed];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSDictionary *ALNValidationFailurePayload(NSString *requestID, NSArray *errors) {
  return @{
    @"error" : @{
      @"code" : @"validation_failed",
      @"message" : @"Validation failed",
      @"status" : @(422),
      @"request_id" : requestID ?: @"",
      @"correlation_id" : requestID ?: @"",
    },
    @"details" : errors ?: @[]
  };
}

static void ALNApplyValidationFailureResponse(ALNApplication *application,
                                              ALNRequest *request,
                                              ALNResponse *response,
                                              NSString *requestID,
                                              NSArray *errors) {
  BOOL apiOnly = ALNBoolConfigValue(application.config[@"apiOnly"], NO);
  if (apiOnly || ALNRequestPrefersJSON(request, apiOnly)) {
    ALNSetStructuredErrorResponse(response, 422,
                                  ALNValidationFailurePayload(requestID, errors));
    return;
  }
  response.statusCode = 422;
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [response setTextBody:@"validation failed\n"];
  response.committed = YES;
}

static NSDictionary *ALNAuthConfig(NSDictionary *config) {
  return ALNDictionaryConfigValue(config, @"auth");
}

static NSDictionary *ALNOpenAPIConfig(NSDictionary *config) {
  return ALNDictionaryConfigValue(config, @"openapi");
}

static BOOL ALNOpenAPIEnabled(ALNApplication *application) {
  NSDictionary *openapi = ALNOpenAPIConfig(application.config);
  return ALNBoolConfigValue(openapi[@"enabled"], YES);
}

static BOOL ALNOpenAPIDocsUIEnabled(ALNApplication *application) {
  NSDictionary *openapi = ALNOpenAPIConfig(application.config);
  BOOL defaultEnabled = ![application.environment isEqualToString:@"production"];
  return ALNBoolConfigValue(openapi[@"docsUIEnabled"], defaultEnabled);
}

static NSString *ALNOpenAPIDocsUIStyle(ALNApplication *application) {
  NSDictionary *openapi = ALNOpenAPIConfig(application.config);
  NSString *style = [openapi[@"docsUIStyle"] isKindOfClass:[NSString class]]
                        ? [openapi[@"docsUIStyle"] lowercaseString]
                        : @"interactive";
  if (![style isEqualToString:@"interactive"] &&
      ![style isEqualToString:@"viewer"] &&
      ![style isEqualToString:@"swagger"]) {
    style = @"interactive";
  }
  return style;
}

static NSString *ALNOpenAPIBasicViewerHTML(void) {
  return @"<!doctype html><html><head><meta charset='utf-8'>"
         "<title>Arlen OpenAPI Viewer</title>"
         "<style>body{font-family:Menlo,Consolas,monospace;padding:18px;background:#0f172a;color:#e2e8f0;}h1{margin-top:0;}pre{white-space:pre-wrap;background:#111827;padding:14px;border:1px solid #334155;border-radius:6px;}a{color:#38bdf8;}</style>"
         "</head><body><h1>Arlen OpenAPI Viewer</h1>"
         "<p>Spec source: <a href='/openapi.json'>/openapi.json</a> · <a href='/openapi'>Interactive explorer</a> · <a href='/openapi/swagger'>Swagger UI</a></p>"
         "<pre id='spec'>Loading...</pre>"
         "<script>fetch('/openapi.json').then(r=>r.json()).then(j=>{document.getElementById('spec').textContent=JSON.stringify(j,null,2);}).catch(e=>{document.getElementById('spec').textContent='Failed to load /openapi.json: '+e;});</script>"
         "</body></html>";
}

static NSString *ALNOpenAPIInteractiveDocsHTML(void) {
  return @"<!doctype html><html><head><meta charset='utf-8'>"
         "<title>Arlen OpenAPI Explorer</title>"
         "<style>"
         "body{font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif;margin:0;background:#0b1220;color:#e2e8f0;}"
         "header{padding:16px 22px;border-bottom:1px solid #1f2a44;background:#101a2d;}"
         "h1{margin:0;font-size:22px;}main{padding:18px;display:grid;gap:12px;max-width:960px;}"
         ".row{display:grid;gap:8px;}label{font-size:12px;color:#93a3c5;}"
         "select,input,textarea,button{font:inherit;padding:10px;border-radius:8px;border:1px solid #2a3a5f;background:#0f172a;color:#e2e8f0;}"
         "button{background:#0ea5e9;border-color:#0284c7;color:#071226;font-weight:700;cursor:pointer;}"
         "button:hover{background:#38bdf8;}pre{margin:0;white-space:pre-wrap;background:#0f172a;border:1px solid #2a3a5f;border-radius:8px;padding:12px;}"
         ".muted{color:#9fb0d0;font-size:13px;}a{color:#67e8f9;}#params .param{display:grid;gap:6px;margin-bottom:8px;}"
         "</style></head><body>"
         "<header><h1>Arlen OpenAPI Explorer</h1>"
         "<div class='muted'>FastAPI-style try-it-out flow for generated OpenAPI specs.</div>"
         "<div class='muted'><a href='/openapi.json'>Raw OpenAPI JSON</a> · <a href='/openapi/viewer'>Lightweight viewer</a> · <a href='/openapi/swagger'>Swagger UI</a></div>"
         "</header>"
         "<main>"
         "<div class='row'><label for='operation'>Operation</label><select id='operation'></select></div>"
         "<div id='operationMeta' class='muted'></div>"
         "<div id='params' class='row'></div>"
         "<div class='row'><label for='requestBody'>JSON Request Body (optional)</label><textarea id='requestBody' rows='8' placeholder='{\"example\":true}'></textarea></div>"
         "<div><button id='tryBtn'>Try It Out</button></div>"
         "<div class='row'><label>Response</label><pre id='response'>Select an operation and click Try It Out.</pre></div>"
         "</main>"
         "<script>"
         "const opSelect=document.getElementById('operation');"
         "const opMeta=document.getElementById('operationMeta');"
         "const paramsRoot=document.getElementById('params');"
         "const reqBody=document.getElementById('requestBody');"
         "const responsePre=document.getElementById('response');"
         "const tryBtn=document.getElementById('tryBtn');"
         "let operations=[];"
         "function opId(path,method){return method.toUpperCase()+' '+path;}"
         "function clearParams(){while(paramsRoot.firstChild){paramsRoot.removeChild(paramsRoot.firstChild);}}"
         "function renderParams(op){clearParams();(op.parameters||[]).forEach((p,idx)=>{"
         "const wrap=document.createElement('div');wrap.className='param';"
         "const lbl=document.createElement('label');lbl.textContent=(p.in||'param')+': '+p.name+(p.required?' *':'');"
         "const input=document.createElement('input');input.type='text';input.dataset.paramIndex=String(idx);input.placeholder=p.description||'';"
         "wrap.appendChild(lbl);wrap.appendChild(input);paramsRoot.appendChild(wrap);});"
         "}"
         "function selectedOp(){const idx=Number(opSelect.value||'-1');return (idx>=0&&idx<operations.length)?operations[idx]:null;}"
         "function renderSelection(){const op=selectedOp();if(!op){opMeta.textContent='';clearParams();return;}"
         "opMeta.textContent=(op.summary||op.description||'')+' ['+op.method.toUpperCase()+' '+op.path+']';"
         "renderParams(op);}"
         "async function loadSpec(){"
         "const res=await fetch('/openapi.json');if(!res.ok){throw new Error('HTTP '+res.status);}"
         "const spec=await res.json();const paths=spec.paths||{};operations=[];"
         "Object.keys(paths).sort().forEach(path=>{const item=paths[path]||{};"
         "Object.keys(item).forEach(method=>{const lower=method.toLowerCase();"
         "if(!['get','post','put','patch','delete','head','options'].includes(lower)){return;}"
         "const op=item[method]||{};operations.push({path,method:lower,summary:op.summary||'',description:op.description||'',parameters:op.parameters||[],requestBody:op.requestBody||null});"
         "});});"
         "opSelect.innerHTML='';operations.forEach((op,idx)=>{const opt=document.createElement('option');opt.value=String(idx);opt.textContent=opId(op.path,op.method)+(op.summary?' - '+op.summary:'');opSelect.appendChild(opt);});"
         "if(operations.length===0){responsePre.textContent='No operations found in /openapi.json';}"
         "renderSelection();}"
         "function applyParams(op){let path=op.path;const query=[];const paramInputs=paramsRoot.querySelectorAll('input[data-param-index]');"
         "paramInputs.forEach(input=>{const idx=Number(input.dataset.paramIndex);const def=op.parameters[idx]||{};const val=input.value||'';"
         "if((def.in||'')==='path'){path=path.replace('{'+def.name+'}',encodeURIComponent(val));}"
         "else if((def.in||'')==='query'&&val.length>0){query.push(encodeURIComponent(def.name)+'='+encodeURIComponent(val));}"
         "});if(query.length>0){path+=(path.includes('?')?'&':'?')+query.join('&');}return path;}"
         "async function tryOperation(){const op=selectedOp();if(!op){return;}const url=applyParams(op);const init={method:op.method.toUpperCase(),headers:{}};"
         "const bodyRaw=reqBody.value.trim();if(bodyRaw.length>0&&op.method!=='get'&&op.method!=='head'){init.headers['Content-Type']='application/json';init.body=bodyRaw;}"
         "let resText='';try{const res=await fetch(url,init);const text=await res.text();resText='HTTP '+res.status+' '+res.statusText+'\\n\\n'+text;}"
         "catch(err){resText='Request failed: '+err;}responsePre.textContent=resText;}"
         "opSelect.addEventListener('change',renderSelection);tryBtn.addEventListener('click',tryOperation);"
         "loadSpec().catch(err=>{responsePre.textContent='Failed to load /openapi.json: '+err;});"
         "</script>"
         "</body></html>";
}

static NSString *ALNOpenAPISwaggerDocsHTML(void) {
  return @"<!doctype html><html><head><meta charset='utf-8'>"
         "<title>Arlen Swagger UI</title>"
         "<style>"
         "body{font-family:Arial,Helvetica,sans-serif;margin:0;background:#f8fafc;color:#0f172a;}"
         "header{padding:14px 20px;background:#0ea5e9;color:#06243a;box-shadow:0 1px 3px rgba(2,6,23,0.14);}"
         "h1{margin:0;font-size:24px;font-weight:700;}"
         ".sub{margin-top:4px;font-size:13px;color:#08314d;}"
         "main{max-width:1080px;margin:16px auto;padding:0 16px 28px;display:grid;gap:14px;}"
         ".panel{background:#fff;border:1px solid #cbd5e1;border-radius:8px;padding:14px;box-shadow:0 1px 2px rgba(2,6,23,0.06);}"
         ".row{display:grid;gap:8px;}"
         "label{font-size:12px;font-weight:700;color:#334155;}"
         "select,input,textarea{width:100%;box-sizing:border-box;padding:9px;border:1px solid #94a3b8;border-radius:6px;font:inherit;}"
         "button{padding:10px 14px;background:#16a34a;border:1px solid #15803d;color:#fff;border-radius:6px;font-weight:700;cursor:pointer;}"
         "button:hover{background:#22c55e;}"
         "a{color:#0369a1;text-decoration:none;}a:hover{text-decoration:underline;}"
         "pre{margin:0;white-space:pre-wrap;background:#0f172a;color:#e2e8f0;padding:12px;border-radius:6px;}"
         ".opmeta{font-size:13px;color:#475569;}"
         "#params .param{display:grid;gap:6px;margin-bottom:8px;}"
         "</style></head><body>"
         "<header><h1>Arlen Swagger UI</h1><div class='sub'>Self-hosted Swagger-style docs wired to generated /openapi.json.</div></header>"
         "<main>"
         "<div class='panel'><a href='/openapi.json'>Raw OpenAPI JSON</a> · <a href='/openapi'>Interactive explorer</a> · <a href='/openapi/viewer'>Lightweight viewer</a></div>"
         "<div class='panel row'><label for='operation'>Operation</label><select id='operation'></select><div id='operationMeta' class='opmeta'></div><div id='params' class='row'></div></div>"
         "<div class='panel row'><label for='requestBody'>JSON Request Body (optional)</label><textarea id='requestBody' rows='8' placeholder='{\"example\":true}'></textarea><div><button id='tryBtn'>Try It Out</button></div></div>"
         "<div class='panel row'><label>Response</label><pre id='response'>Select an operation and click Try It Out.</pre></div>"
         "</main>"
         "<script>"
         "const opSelect=document.getElementById('operation');"
         "const opMeta=document.getElementById('operationMeta');"
         "const paramsRoot=document.getElementById('params');"
         "const reqBody=document.getElementById('requestBody');"
         "const responsePre=document.getElementById('response');"
         "const tryBtn=document.getElementById('tryBtn');"
         "let operations=[];"
         "function clearParams(){while(paramsRoot.firstChild){paramsRoot.removeChild(paramsRoot.firstChild);}}"
         "function selectedOp(){const idx=Number(opSelect.value||'-1');return (idx>=0&&idx<operations.length)?operations[idx]:null;}"
         "function renderParams(op){clearParams();(op.parameters||[]).forEach((p,idx)=>{"
         "const wrap=document.createElement('div');wrap.className='param';"
         "const lbl=document.createElement('label');lbl.textContent=(p.in||'param')+': '+p.name+(p.required?' *':'');"
         "const input=document.createElement('input');input.type='text';input.dataset.paramIndex=String(idx);input.placeholder=p.description||'';"
         "wrap.appendChild(lbl);wrap.appendChild(input);paramsRoot.appendChild(wrap);});}"
         "function renderSelection(){const op=selectedOp();if(!op){opMeta.textContent='';clearParams();return;}"
         "opMeta.textContent=(op.summary||op.description||'')+' ['+op.method.toUpperCase()+' '+op.path+']';renderParams(op);}"
         "function applyParams(op){let path=op.path;const query=[];const paramInputs=paramsRoot.querySelectorAll('input[data-param-index]');"
         "paramInputs.forEach(input=>{const idx=Number(input.dataset.paramIndex);const def=op.parameters[idx]||{};const val=input.value||'';"
         "if((def.in||'')==='path'){path=path.replace('{'+def.name+'}',encodeURIComponent(val));}"
         "else if((def.in||'')==='query'&&val.length>0){query.push(encodeURIComponent(def.name)+'='+encodeURIComponent(val));}"
         "});if(query.length>0){path+=(path.includes('?')?'&':'?')+query.join('&');}return path;}"
         "async function loadSpec(){const res=await fetch('/openapi.json');if(!res.ok){throw new Error('HTTP '+res.status);}"
         "const spec=await res.json();const paths=spec.paths||{};operations=[];"
         "Object.keys(paths).sort().forEach(path=>{const item=paths[path]||{};Object.keys(item).forEach(method=>{const lower=method.toLowerCase();"
         "if(!['get','post','put','patch','delete','head','options'].includes(lower)){return;}"
         "const op=item[method]||{};operations.push({path,method:lower,summary:op.summary||'',description:op.description||'',parameters:op.parameters||[]});});});"
         "opSelect.innerHTML='';operations.forEach((op,idx)=>{const opt=document.createElement('option');opt.value=String(idx);opt.textContent=op.method.toUpperCase()+' '+op.path+(op.summary?' - '+op.summary:'');opSelect.appendChild(opt);});"
         "if(operations.length===0){responsePre.textContent='No operations found in /openapi.json';}renderSelection();}"
         "async function tryOperation(){const op=selectedOp();if(!op){return;}const url=applyParams(op);const init={method:op.method.toUpperCase(),headers:{}};"
         "const bodyRaw=reqBody.value.trim();if(bodyRaw.length>0&&op.method!=='get'&&op.method!=='head'){init.headers['Content-Type']='application/json';init.body=bodyRaw;}"
         "let resText='';try{const res=await fetch(url,init);const text=await res.text();resText='HTTP '+res.status+' '+res.statusText+'\\n\\n'+text;}catch(err){resText='Request failed: '+err;}responsePre.textContent=resText;}"
         "opSelect.addEventListener('change',renderSelection);tryBtn.addEventListener('click',tryOperation);"
         "loadSpec().catch(err=>{responsePre.textContent='Failed to load /openapi.json: '+err;});"
         "</script>"
         "</body></html>";
}

static void ALNRecordRequestMetrics(ALNApplication *application,
                                    ALNResponse *response,
                                    ALNPerfTrace *trace) {
  [application.metrics incrementCounter:@"http_requests_total"];
  [application.metrics incrementCounter:[NSString stringWithFormat:@"http_status_%ld_total", (long)response.statusCode]];
  if (response.statusCode >= 500) {
    [application.metrics incrementCounter:@"http_errors_total"];
  }

  NSNumber *totalMs = [trace durationMillisecondsForStage:@"total"];
  if (totalMs != nil) {
    [application.metrics recordTiming:@"http_request_duration_ms"
                         milliseconds:[totalMs doubleValue]];
  }
  NSNumber *routeMs = [trace durationMillisecondsForStage:@"route"];
  if (routeMs != nil) {
    [application.metrics recordTiming:@"http_route_duration_ms"
                         milliseconds:[routeMs doubleValue]];
  }
  NSNumber *controllerMs = [trace durationMillisecondsForStage:@"controller"];
  if (controllerMs != nil) {
    [application.metrics recordTiming:@"http_controller_duration_ms"
                         milliseconds:[controllerMs doubleValue]];
  }
}

static NSString *ALNGenerateRequestID(void) {
  return [[NSUUID UUID] UUIDString];
}

static BOOL ALNPathLooksLikeAPI(NSString *path) {
  if (![path isKindOfClass:[NSString class]]) {
    return NO;
  }
  return [path hasPrefix:@"/api/"] || [path isEqualToString:@"/api"];
}

static NSString *ALNExtractPathFormat(NSString *path, NSString **strippedPath) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    if (strippedPath != NULL) {
      *strippedPath = @"/";
    }
    return nil;
  }

  NSString *normalized = path;
  NSRange queryRange = [normalized rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    normalized = [normalized substringToIndex:queryRange.location];
  }
  if ([normalized length] == 0) {
    normalized = @"/";
  }

  NSString *trimmed = normalized;
  while ([trimmed length] > 1 && [trimmed hasSuffix:@"/"]) {
    trimmed = [trimmed substringToIndex:[trimmed length] - 1];
  }

  NSRange lastSlash = [trimmed rangeOfString:@"/" options:NSBackwardsSearch];
  NSRange lastDot = [trimmed rangeOfString:@"." options:NSBackwardsSearch];
  BOOL hasExtension = (lastDot.location != NSNotFound &&
                       (lastSlash.location == NSNotFound || lastDot.location > lastSlash.location));
  if (!hasExtension) {
    if (strippedPath != NULL) {
      *strippedPath = trimmed;
    }
    return nil;
  }

  NSString *extension = [[trimmed substringFromIndex:lastDot.location + 1] lowercaseString];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([extension length] == 0 ||
      [[extension stringByTrimmingCharactersInSet:allowed] length] > 0) {
    if (strippedPath != NULL) {
      *strippedPath = trimmed;
    }
    return nil;
  }

  if (strippedPath != NULL) {
    NSString *withoutExt = [trimmed substringToIndex:lastDot.location];
    *strippedPath = ([withoutExt length] > 0) ? withoutExt : @"/";
  }
  return extension;
}

static NSString *ALNRequestPreferredFormat(ALNRequest *request, BOOL apiOnly, NSString **strippedPath) {
  NSString *path = request.path ?: @"/";
  NSString *pathFormat = ALNExtractPathFormat(path, strippedPath);
  if ([pathFormat length] > 0) {
    return pathFormat;
  }

  NSString *accept = [request.headers[@"accept"] isKindOfClass:[NSString class]]
                         ? [request.headers[@"accept"] lowercaseString]
                         : @"";
  if ([accept containsString:@"application/json"] || [accept containsString:@"text/json"]) {
    return @"json";
  }
  if ([accept containsString:@"text/html"] || [accept containsString:@"application/xhtml+xml"]) {
    return @"html";
  }

  NSString *resolvedPath = (strippedPath != NULL && [*strippedPath length] > 0)
                               ? *strippedPath
                               : (request.path ?: @"/");
  if (apiOnly || ALNPathLooksLikeAPI(resolvedPath)) {
    return @"json";
  }

  return @"html";
}

static BOOL ALNRequestPrefersJSON(ALNRequest *request, BOOL apiOnly) {
  NSString *format = ALNRequestPreferredFormat(request, apiOnly, NULL);
  return [format isEqualToString:@"json"];
}

static NSString *ALNEscapeHTML(NSString *value) {
  NSString *safe = value ?: @"";
  safe = [safe stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  safe = [safe stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  safe = [safe stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  safe = [safe stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  return [safe stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
}

static NSString *ALNBuiltInHealthBodyForPath(NSString *path) {
  if ([path isEqualToString:@"/healthz"]) {
    return @"ok\n";
  }
  if ([path isEqualToString:@"/readyz"]) {
    return @"ready\n";
  }
  if ([path isEqualToString:@"/livez"]) {
    return @"live\n";
  }
  return nil;
}

static NSDictionary *ALNClusterStatusPayload(ALNApplication *application) {
  NSDictionary *session = ALNDictionaryConfigValue(application.config, @"session");
  BOOL sessionEnabled = ALNBoolConfigValue(session[@"enabled"], NO);
  BOOL sessionSecretConfigured =
      [ALNStringConfigValue(session[@"secret"], @"") length] > 0;

  return @{
    @"ok" : @(YES),
    @"cluster" : @{
      @"enabled" : @(application.clusterEnabled),
      @"name" : application.clusterName ?: @"default",
      @"node_id" : application.clusterNodeID ?: @"node",
      @"expected_nodes" : @(application.clusterExpectedNodes),
      @"worker_pid" : @((NSInteger)getpid()),
      @"mode" : application.clusterEnabled ? @"multi_node" : @"single_node",
    },
    @"contracts" : @{
      @"session" : @{
        @"enabled" : @(sessionEnabled),
        @"mode" : @"cookie_signed",
        @"shared_secret_required" : @(sessionEnabled),
        @"shared_secret_configured" : @(sessionSecretConfigured),
      },
      @"realtime" : @{
        @"mode" : @"node_local_pubsub",
        @"cluster_broadcast" : @"external_broker_required",
      }
    }
  };
}

static BOOL ALNRequestMethodIsReadOnly(ALNRequest *request) {
  return [request.method isEqualToString:@"GET"] ||
         [request.method isEqualToString:@"HEAD"];
}

static BOOL ALNHeaderPrefersJSON(ALNRequest *request) {
  NSString *accept = [request.headers[@"accept"] isKindOfClass:[NSString class]]
                         ? [request.headers[@"accept"] lowercaseString]
                         : @"";
  return [accept containsString:@"application/json"] ||
         [accept containsString:@"text/json"];
}

static BOOL ALNApplyBuiltInResponse(ALNApplication *application,
                                    ALNRequest *request,
                                    ALNResponse *response,
                                    NSString *routePath) {
  BOOL headRequest = [request.method isEqualToString:@"HEAD"];
  NSString *requestPath = request.path ?: routePath ?: @"/";
  NSRange queryRange = [requestPath rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    requestPath = [requestPath substringToIndex:queryRange.location];
  }
  if (!ALNRequestMethodIsReadOnly(request)) {
    return NO;
  }

  NSString *healthBody = ALNBuiltInHealthBodyForPath(routePath);
  if ([healthBody length] > 0) {
    response.statusCode = 200;
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    if (!headRequest) {
      [response setTextBody:healthBody];
    }
    response.committed = YES;
    return YES;
  }

  if ([routePath isEqualToString:@"/clusterz"] || [requestPath isEqualToString:@"/clusterz"]) {
    response.statusCode = 200;
    NSError *jsonError = nil;
    BOOL ok = [response setJSONBody:ALNClusterStatusPayload(application)
                            options:0
                              error:&jsonError];
    if (!ok) {
      response.statusCode = 500;
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      [response setTextBody:@"cluster status serialization failed\n"];
    } else if (headRequest) {
      [response setTextBody:@""];
    }
    response.committed = YES;
    return YES;
  }

  if ([routePath isEqualToString:@"/metrics"] || [requestPath isEqualToString:@"/metrics"]) {
    response.statusCode = 200;
    if (ALNHeaderPrefersJSON(request)) {
      NSError *jsonError = nil;
      BOOL ok = [response setJSONBody:[application.metrics snapshot]
                              options:0
                                error:&jsonError];
      if (!ok) {
        response.statusCode = 500;
        [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
        [response setTextBody:@"metrics serialization failed\n"];
      }
    } else {
      [response setHeader:@"Content-Type" value:@"text/plain; version=0.0.4; charset=utf-8"];
      if (!headRequest) {
        [response setTextBody:[application.metrics prometheusText]];
      }
    }
    response.committed = YES;
    return YES;
  }

  BOOL openapiPath = [routePath isEqualToString:@"/openapi.json"] ||
                     [routePath isEqualToString:@"/.well-known/openapi.json"] ||
                     [requestPath isEqualToString:@"/openapi.json"] ||
                     [requestPath isEqualToString:@"/.well-known/openapi.json"];
  if (openapiPath && ALNOpenAPIEnabled(application)) {
    NSError *jsonError = nil;
    BOOL ok = [response setJSONBody:[application openAPISpecification]
                            options:0
                              error:&jsonError];
    if (!ok) {
      response.statusCode = 500;
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      [response setTextBody:@"openapi serialization failed\n"];
    } else {
      response.statusCode = 200;
      if (headRequest) {
        [response setTextBody:@""];
      }
    }
    response.committed = YES;
    return YES;
  }

  BOOL docsPath = [routePath isEqualToString:@"/openapi"] ||
                  [routePath isEqualToString:@"/docs/openapi"] ||
                  [requestPath isEqualToString:@"/openapi"] ||
                  [requestPath isEqualToString:@"/docs/openapi"];
  BOOL viewerPath = [routePath isEqualToString:@"/openapi/viewer"] ||
                    [routePath isEqualToString:@"/docs/openapi/viewer"] ||
                    [requestPath isEqualToString:@"/openapi/viewer"] ||
                    [requestPath isEqualToString:@"/docs/openapi/viewer"];
  BOOL swaggerPath = [routePath isEqualToString:@"/openapi/swagger"] ||
                     [routePath isEqualToString:@"/docs/openapi/swagger"] ||
                     [requestPath isEqualToString:@"/openapi/swagger"] ||
                     [requestPath isEqualToString:@"/docs/openapi/swagger"];

  if ((docsPath || viewerPath || swaggerPath) && ALNOpenAPIEnabled(application) &&
      ALNOpenAPIDocsUIEnabled(application)) {
    NSString *docsStyle = [[ALNOpenAPIDocsUIStyle(application) lowercaseString] copy];
    BOOL preferViewer = [docsStyle isEqualToString:@"viewer"];
    BOOL preferSwagger = [docsStyle isEqualToString:@"swagger"];
    response.statusCode = 200;
    [response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
    if (!headRequest) {
      BOOL renderViewer = viewerPath || (docsPath && preferViewer);
      BOOL renderSwagger = swaggerPath || (docsPath && preferSwagger);
      if (renderViewer) {
        [response setTextBody:ALNOpenAPIBasicViewerHTML()];
      } else if (renderSwagger) {
        [response setTextBody:ALNOpenAPISwaggerDocsHTML()];
      } else {
        [response setTextBody:ALNOpenAPIInteractiveDocsHTML()];
      }
    }
    response.committed = YES;
    return YES;
  }

  return NO;
}

static NSDictionary *ALNErrorDetailsFromNSError(NSError *error) {
  if (error == nil) {
    return @{};
  }

  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[@"domain"] = error.domain ?: @"";
  details[@"code"] = @([error code]);
  details[@"description"] = error.localizedDescription ?: @"";

  id file = error.userInfo[@"ALNEOCErrorPath"] ?: error.userInfo[@"path"];
  id line = error.userInfo[@"ALNEOCErrorLine"] ?: error.userInfo[@"line"];
  id column = error.userInfo[@"ALNEOCErrorColumn"] ?: error.userInfo[@"column"];
  if ([file isKindOfClass:[NSString class]]) {
    details[@"file"] = file;
  }
  if ([line respondsToSelector:@selector(integerValue)]) {
    details[@"line"] = @([line integerValue]);
  }
  if ([column respondsToSelector:@selector(integerValue)]) {
    details[@"column"] = @([column integerValue]);
  }
  return details;
}

static NSDictionary *ALNErrorDetailsFromException(NSException *exception) {
  if (exception == nil) {
    return @{};
  }

  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[@"name"] = exception.name ?: @"";
  details[@"reason"] = exception.reason ?: @"";
  NSArray *stack = exception.callStackSymbols ?: @[];
  if ([stack count] > 0) {
    details[@"stack"] = stack;
  }
  return details;
}

static NSString *ALNDevelopmentErrorPageHTML(NSString *requestID,
                                             NSString *errorCode,
                                             NSString *message,
                                             NSDictionary *details) {
  NSMutableString *html = [NSMutableString string];
  [html appendString:@"<!doctype html><html><head><meta charset='utf-8'>"];
  [html appendString:@"<title>Arlen Development Exception</title>"];
  [html appendString:@"<style>body{font-family:Menlo,Consolas,monospace;background:#111;color:#eee;padding:24px;}h1{margin-top:0;}pre{background:#1b1b1b;border:1px solid #333;padding:12px;overflow:auto;}code{background:#1b1b1b;padding:2px 4px;}table{border-collapse:collapse;width:100%;}td{border:1px solid #333;padding:6px;vertical-align:top;} .muted{color:#aaa;}</style>"];
  [html appendString:@"</head><body>"];
  [html appendString:@"<h1>Arlen Development Exception</h1>"];
  [html appendFormat:@"<p><strong>Request ID:</strong> <code>%@</code></p>", ALNEscapeHTML(requestID)];
  [html appendFormat:@"<p><strong>Error Code:</strong> <code>%@</code></p>", ALNEscapeHTML(errorCode)];
  [html appendFormat:@"<p><strong>Message:</strong> %@</p>", ALNEscapeHTML(message)];

  if ([details count] > 0) {
    [html appendString:@"<h2>Details</h2><table>"];
    NSArray *keys = [[details allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
      id value = details[key];
      NSString *rendered = nil;
      if ([value isKindOfClass:[NSArray class]]) {
        rendered = [[(NSArray *)value componentsJoinedByString:@"\n"] copy];
      } else {
        rendered = [value description] ?: @"";
      }
      [html appendFormat:@"<tr><td><strong>%@</strong></td><td><pre>%@</pre></td></tr>",
                         ALNEscapeHTML(key), ALNEscapeHTML(rendered)];
    }
    [html appendString:@"</table>"];
  } else {
    [html appendString:@"<p class='muted'>No additional details were captured.</p>"];
  }

  [html appendString:@"</body></html>"];
  return html;
}

static NSDictionary *ALNStructuredErrorPayload(NSInteger statusCode,
                                               NSString *errorCode,
                                               NSString *message,
                                               NSString *requestID,
                                               NSDictionary *details) {
  NSMutableDictionary *errorObject = [NSMutableDictionary dictionary];
  errorObject[@"code"] = errorCode ?: @"internal_error";
  errorObject[@"message"] = message ?: @"Internal Server Error";
  errorObject[@"status"] = @(statusCode);
  errorObject[@"correlation_id"] = requestID ?: @"";
  errorObject[@"request_id"] = requestID ?: @"";

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"error"] = errorObject;
  if ([details count] > 0) {
    payload[@"details"] = details;
  }
  return payload;
}

static void ALNSetStructuredErrorResponse(ALNResponse *response,
                                          NSInteger statusCode,
                                          NSDictionary *payload) {
  NSError *jsonError = nil;
  BOOL ok = [response setJSONBody:payload options:0 error:&jsonError];
  if (!ok) {
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [response setTextBody:@"internal server error\n"];
  }
  response.statusCode = statusCode;
  response.committed = YES;
}

static void ALNApplyInternalErrorResponse(ALNApplication *application,
                                          ALNRequest *request,
                                          ALNResponse *response,
                                          NSString *requestID,
                                          NSInteger statusCode,
                                          NSString *errorCode,
                                          NSString *publicMessage,
                                          NSString *developerMessage,
                                          NSDictionary *details) {
  BOOL production = [application.environment isEqualToString:@"production"];
  BOOL apiOnly = ALNBoolConfigValue(application.config[@"apiOnly"], NO);
  BOOL prefersJSON = ALNRequestPrefersJSON(request, apiOnly);

  if (production || prefersJSON) {
    NSDictionary *payload = ALNStructuredErrorPayload(statusCode,
                                                      errorCode,
                                                      publicMessage,
                                                      requestID,
                                                      production ? @{} : (details ?: @{}));
    ALNSetStructuredErrorResponse(response, statusCode, payload);
    return;
  }

  NSString *html = ALNDevelopmentErrorPageHTML(requestID,
                                               errorCode ?: @"internal_error",
                                               developerMessage ?: publicMessage,
                                               details ?: @{});
  response.statusCode = statusCode;
  [response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
  [response setTextBody:html ?: @"internal server error\n"];
  response.committed = YES;
}

static BOOL ALNApplyRequestContractIfNeeded(ALNApplication *application,
                                            ALNRequest *request,
                                            ALNResponse *response,
                                            ALNContext *context,
                                            ALNRoute *route,
                                            NSString *requestID) {
  NSDictionary *requestSchema = [route.requestSchema isKindOfClass:[NSDictionary class]]
                                    ? route.requestSchema
                                    : @{};
  if ([requestSchema count] == 0) {
    return YES;
  }

  NSArray *validationErrors = nil;
  NSDictionary *coerced = ALNSchemaCoerceRequestValues(requestSchema,
                                                       request,
                                                       request.routeParams ?: @{},
                                                       &validationErrors);
  if ([validationErrors count] > 0) {
    context.stash[ALNContextValidationErrorsStashKey] = validationErrors;
    ALNApplyValidationFailureResponse(application,
                                      request,
                                      response,
                                      requestID,
                                      validationErrors);
    return NO;
  }

  context.stash[ALNContextValidatedParamsStashKey] = coerced ?: @{};
  return YES;
}

static void ALNApplyUnauthorizedResponse(ALNApplication *application,
                                         ALNRequest *request,
                                         ALNResponse *response,
                                         NSString *requestID,
                                         NSString *message,
                                         NSArray *requiredScopes) {
  BOOL apiOnly = ALNBoolConfigValue(application.config[@"apiOnly"], NO);
  if (apiOnly || ALNRequestPrefersJSON(request, apiOnly)) {
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    NSArray *scopes = ALNNormalizedUniqueStrings(requiredScopes);
    if ([scopes count] > 0) {
      details[@"required_scopes"] = scopes;
    }
    NSDictionary *payload = ALNStructuredErrorPayload(401,
                                                      @"unauthorized",
                                                      message ?: @"Unauthorized",
                                                      requestID,
                                                      details);
    ALNSetStructuredErrorResponse(response, 401, payload);
  } else {
    response.statusCode = 401;
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [response setTextBody:@"unauthorized\n"];
    response.committed = YES;
  }

  NSMutableArray *authenticate = [NSMutableArray arrayWithObject:@"Bearer"];
  NSArray *scopes = ALNNormalizedUniqueStrings(requiredScopes);
  if ([scopes count] > 0) {
    [authenticate addObject:[NSString stringWithFormat:@"scope=\"%@\"",
                             [scopes componentsJoinedByString:@" "]]];
  }
  [response setHeader:@"WWW-Authenticate" value:[authenticate componentsJoinedByString:@", "]];
}

static void ALNApplyForbiddenResponse(ALNApplication *application,
                                      ALNRequest *request,
                                      ALNResponse *response,
                                      NSString *requestID,
                                      NSString *message,
                                      NSDictionary *details) {
  BOOL apiOnly = ALNBoolConfigValue(application.config[@"apiOnly"], NO);
  if (apiOnly || ALNRequestPrefersJSON(request, apiOnly)) {
    NSDictionary *payload = ALNStructuredErrorPayload(403,
                                                      @"forbidden",
                                                      message ?: @"Forbidden",
                                                      requestID,
                                                      details ?: @{});
    ALNSetStructuredErrorResponse(response, 403, payload);
  } else {
    response.statusCode = 403;
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [response setTextBody:@"forbidden\n"];
    response.committed = YES;
  }
}

static BOOL ALNApplyAuthContractIfNeeded(ALNApplication *application,
                                         ALNRequest *request,
                                         ALNResponse *response,
                                         ALNContext *context,
                                         ALNRoute *route,
                                         NSString *requestID) {
  NSArray *requiredScopes = ALNNormalizedUniqueStrings(route.requiredScopes);
  NSArray *requiredRoles = ALNNormalizedUniqueStrings(route.requiredRoles);
  if ([requiredScopes count] == 0 && [requiredRoles count] == 0) {
    return YES;
  }

  NSDictionary *authConfig = ALNAuthConfig(application.config);
  NSError *authError = nil;
  BOOL authenticated = [ALNAuth authenticateContext:context
                                         authConfig:authConfig
                                              error:&authError];
  if (!authenticated) {
    [application.logger warn:@"request auth rejected"
                      fields:@{
                        @"request_id" : requestID ?: @"",
                        @"error" : authError.localizedDescription ?: @"missing bearer token",
                        @"route" : route.name ?: @"",
                      }];
    ALNApplyUnauthorizedResponse(application,
                                 request,
                                 response,
                                 requestID,
                                 @"Unauthorized",
                                 requiredScopes);
    return NO;
  }

  if (![ALNAuth context:context hasRequiredScopes:requiredScopes]) {
    ALNApplyForbiddenResponse(application,
                              request,
                              response,
                              requestID,
                              @"Missing required scope",
                              @{
                                @"required_scopes" : requiredScopes,
                                @"granted_scopes" : [context authScopes] ?: @[],
                              });
    return NO;
  }
  if (![ALNAuth context:context hasRequiredRoles:requiredRoles]) {
    ALNApplyForbiddenResponse(application,
                              request,
                              response,
                              requestID,
                              @"Missing required role",
                              @{
                                @"required_roles" : requiredRoles,
                                @"granted_roles" : [context authRoles] ?: @[],
                              });
    return NO;
  }
  return YES;
}

static BOOL ALNValidateResponseContractIfNeeded(ALNApplication *application,
                                                ALNRequest *request,
                                                ALNResponse *response,
                                                ALNRoute *route,
                                                id returnValue,
                                                NSString *requestID) {
  NSDictionary *responseSchema = [route.responseSchema isKindOfClass:[NSDictionary class]]
                                     ? route.responseSchema
                                     : @{};
  if ([responseSchema count] == 0) {
    return YES;
  }
  if (response.statusCode >= 400) {
    return YES;
  }

  id payload = nil;
  if ([returnValue isKindOfClass:[NSDictionary class]] ||
      [returnValue isKindOfClass:[NSArray class]]) {
    payload = returnValue;
  } else {
    NSString *contentType = [[response headerForName:@"Content-Type"] lowercaseString] ?: @"";
    BOOL jsonLike = [contentType containsString:@"application/json"] ||
                    [contentType containsString:@"text/json"];
    if (jsonLike && [response.bodyData length] > 0) {
      NSError *jsonError = nil;
      payload = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                options:0
                                                  error:&jsonError];
      if (jsonError != nil) {
        NSDictionary *details = ALNErrorDetailsFromNSError(jsonError);
        ALNApplyInternalErrorResponse(application,
                                      request,
                                      response,
                                      requestID,
                                      500,
                                      @"response_contract_failed",
                                      @"Internal Server Error",
                                      @"Failed parsing response payload for contract validation",
                                      details);
        return NO;
      }
    }
  }

  NSArray *validationErrors = nil;
  BOOL valid = ALNSchemaValidateResponseValue(payload, responseSchema, &validationErrors);
  if (!valid) {
    ALNApplyInternalErrorResponse(application,
                                  request,
                                  response,
                                  requestID,
                                  500,
                                  @"response_contract_failed",
                                  @"Internal Server Error",
                                  @"Response payload failed schema contract",
                                  @{
                                    @"contract_errors" : validationErrors ?: @[],
                                    @"route" : route.name ?: @"",
                                  });
    return NO;
  }
  return YES;
}

static void ALNFinalizeResponse(ALNApplication *application,
                                ALNResponse *response,
                                ALNPerfTrace *trace,
                                ALNRequest *request,
                                NSString *requestID,
                                BOOL performanceLogging) {
  if (performanceLogging && [trace isEnabled]) {
    [trace setStage:@"parse" durationMilliseconds:request.parseDurationMilliseconds >= 0.0
                                           ? request.parseDurationMilliseconds
                                           : 0.0];

    NSNumber *writeStage = [trace durationMillisecondsForStage:@"response_write"];
    if (writeStage == nil) {
      double writeMs = request.responseWriteDurationMilliseconds;
      if (writeMs < 0.0) {
        writeMs = 0.0;
      }
      [trace setStage:@"response_write" durationMilliseconds:writeMs];
    }

    [trace endStage:@"total"];
    NSNumber *total = [trace durationMillisecondsForStage:@"total"] ?: @(0);
    NSNumber *parse = [trace durationMillisecondsForStage:@"parse"] ?: @(0);
    NSNumber *responseWrite = [trace durationMillisecondsForStage:@"response_write"] ?: @(0);

    [response setHeader:@"X-Arlen-Total-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [total doubleValue]]];
    [response setHeader:@"X-Mojo-Total-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [total doubleValue]]];
    [response setHeader:@"X-Arlen-Parse-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [parse doubleValue]]];
    [response setHeader:@"X-Arlen-Response-Write-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [responseWrite doubleValue]]];
  }

  if ([requestID length] > 0) {
    [response setHeader:@"X-Request-Id" value:requestID];
  }
  if (application.clusterEmitHeaders) {
    [response setHeader:@"X-Arlen-Cluster" value:application.clusterName ?: @"default"];
    [response setHeader:@"X-Arlen-Node" value:application.clusterNodeID ?: @"node"];
    [response setHeader:@"X-Arlen-Worker-Pid"
                  value:[NSString stringWithFormat:@"%d", (int)getpid()]];
  }
}

- (void)loadConfiguredPlugins {
  NSDictionary *plugins = ALNDictionaryConfigValue(self.config, @"plugins");
  NSArray *classNames = [plugins[@"classes"] isKindOfClass:[NSArray class]]
                            ? plugins[@"classes"]
                            : @[];
  for (id value in classNames) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
      continue;
    }
    NSError *error = nil;
    BOOL ok = [self registerPluginClassNamed:value error:&error];
    if (!ok) {
      [self.logger warn:@"plugin load skipped"
                 fields:@{
                   @"plugin_class" : value ?: @"",
                   @"error" : error.localizedDescription ?: @"unknown",
                 }];
    }
  }
}

- (void)loadConfiguredStaticMounts {
  NSArray *mounts = [self.config[@"staticMounts"] isKindOfClass:[NSArray class]]
                        ? self.config[@"staticMounts"]
                        : @[];
  for (id value in mounts) {
    if (![value isKindOfClass:[NSDictionary class]]) {
      continue;
    }

    NSDictionary *entry = (NSDictionary *)value;
    NSString *prefix = [entry[@"prefix"] isKindOfClass:[NSString class]] ? entry[@"prefix"] : @"";
    NSString *directory = [entry[@"directory"] isKindOfClass:[NSString class]] ? entry[@"directory"] : @"";
    NSArray *allowExtensions = [entry[@"allowExtensions"] isKindOfClass:[NSArray class]]
                                   ? entry[@"allowExtensions"]
                                   : @[];
    if ([prefix length] == 0 || [directory length] == 0) {
      [self.logger warn:@"static mount skipped"
                 fields:@{
                   @"reason" : @"staticMounts entry requires prefix + directory",
                 }];
      continue;
    }

    if (![self mountStaticDirectory:directory atPrefix:prefix allowExtensions:allowExtensions]) {
      [self.logger warn:@"static mount skipped"
                 fields:@{
                   @"prefix" : prefix ?: @"",
                   @"directory" : directory ?: @"",
                   @"reason" : @"duplicate/invalid static mount entry",
                 }];
    }
  }
}

- (NSDictionary *)mountedEntryForPath:(NSString *)requestPath
                         rewrittenPath:(NSString **)rewrittenPath {
  NSString *path = [requestPath isKindOfClass:[NSString class]] ? requestPath : @"/";
  if ([path length] == 0) {
    path = @"/";
  }

  NSDictionary *best = nil;
  NSString *bestRewritten = nil;
  NSUInteger bestPrefixLength = 0;
  for (NSDictionary *entry in self.mutableMounts) {
    NSString *prefix = [entry[@"prefix"] isKindOfClass:[NSString class]] ? entry[@"prefix"] : @"";
    if ([prefix length] == 0) {
      continue;
    }
    NSString *rewritten = ALNRewriteMountedPath(path, prefix);
    if ([rewritten length] == 0) {
      continue;
    }
    if ([prefix length] > bestPrefixLength) {
      best = entry;
      bestRewritten = rewritten;
      bestPrefixLength = [prefix length];
    }
  }

  if (rewrittenPath != NULL) {
    *rewrittenPath = [bestRewritten copy];
  }
  return best;
}

- (BOOL)configureRouteNamed:(NSString *)routeName
             requestSchema:(NSDictionary *)requestSchema
            responseSchema:(NSDictionary *)responseSchema
                   summary:(NSString *)summary
               operationID:(NSString *)operationID
                      tags:(NSArray *)tags
             requiredScopes:(NSArray *)requiredScopes
              requiredRoles:(NSArray *)requiredRoles
            includeInOpenAPI:(BOOL)includeInOpenAPI
                      error:(NSError **)error {
  ALNRoute *route = [self.router routeNamed:routeName];
  if (route == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:305
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"route not found: %@", routeName ?: @""]
                               }];
    }
    return NO;
  }

  route.requestSchema = [requestSchema isKindOfClass:[NSDictionary class]] ? requestSchema : @{};
  route.responseSchema = [responseSchema isKindOfClass:[NSDictionary class]] ? responseSchema : @{};
  route.summary = [summary copy] ?: @"";
  route.operationID = [operationID copy] ?: @"";
  route.tags = ALNNormalizedUniqueStrings(tags);
  route.requiredScopes = ALNNormalizedUniqueStrings(requiredScopes);
  route.requiredRoles = ALNNormalizedUniqueStrings(requiredRoles);
  route.includeInOpenAPI = includeInOpenAPI;
  return YES;
}

- (NSDictionary *)openAPISpecification {
  return ALNBuildOpenAPISpecification([self.router allRoutes], self.config ?: @{});
}

- (BOOL)writeOpenAPISpecToPath:(NSString *)path
                        pretty:(BOOL)pretty
                         error:(NSError **)error {
  if ([path length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                   code:306
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"output path is required"
                               }];
    }
    return NO;
  }

  NSJSONWritingOptions options = pretty ? NSJSONWritingPrettyPrinted : 0;
  NSData *json = [NSJSONSerialization dataWithJSONObject:[self openAPISpecification]
                                                 options:options
                                                   error:error];
  if (json == nil) {
    return NO;
  }
  return [json writeToFile:path options:NSDataWritingAtomic error:error];
}

- (BOOL)startWithError:(NSError **)error {
  if (self.isStarted) {
    return YES;
  }

  for (NSDictionary *entry in self.mutableMounts) {
    ALNApplication *mounted =
        [entry[@"application"] isKindOfClass:[ALNApplication class]] ? entry[@"application"] : nil;
    if (mounted == nil) {
      continue;
    }
    NSError *mountedError = nil;
    BOOL mountedStarted = [mounted startWithError:&mountedError];
    if (!mountedStarted) {
      if (error != NULL) {
        NSString *prefix = [entry[@"prefix"] isKindOfClass:[NSString class]] ? entry[@"prefix"] : @"";
        NSString *message =
            [NSString stringWithFormat:@"mounted application failed to start at %@: %@",
                                       prefix,
                                       mountedError.localizedDescription ?: @"unknown"];
        *error = [NSError errorWithDomain:ALNApplicationErrorDomain
                                     code:308
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : message
                                 }];
      }
      return NO;
    }
  }

  for (id<ALNLifecycleHook> hook in self.mutableLifecycleHooks) {
    if (![hook respondsToSelector:@selector(applicationWillStart:error:)]) {
      continue;
    }
    NSError *hookError = nil;
    BOOL ok = [hook applicationWillStart:self error:&hookError];
    if (!ok) {
      if (error != NULL) {
        *error = hookError ?: [NSError errorWithDomain:ALNApplicationErrorDomain
                                                  code:307
                                              userInfo:@{
                                                NSLocalizedDescriptionKey : @"startup hook rejected startup"
                                              }];
      }
      return NO;
    }
  }

  self.started = YES;
  for (id<ALNLifecycleHook> hook in self.mutableLifecycleHooks) {
    if ([hook respondsToSelector:@selector(applicationDidStart:)]) {
      [hook applicationDidStart:self];
    }
  }
  return YES;
}

- (void)shutdown {
  if (!self.isStarted) {
    return;
  }

  for (NSInteger idx = (NSInteger)[self.mutableLifecycleHooks count] - 1; idx >= 0; idx--) {
    id<ALNLifecycleHook> hook = self.mutableLifecycleHooks[(NSUInteger)idx];
    if ([hook respondsToSelector:@selector(applicationWillStop:)]) {
      [hook applicationWillStop:self];
    }
  }

  for (NSInteger idx = (NSInteger)[self.mutableLifecycleHooks count] - 1; idx >= 0; idx--) {
    id<ALNLifecycleHook> hook = self.mutableLifecycleHooks[(NSUInteger)idx];
    if ([hook respondsToSelector:@selector(applicationDidStop:)]) {
      [hook applicationDidStop:self];
    }
  }
  self.started = NO;

  for (NSInteger idx = (NSInteger)[self.mutableMounts count] - 1; idx >= 0; idx--) {
    NSDictionary *entry = self.mutableMounts[(NSUInteger)idx];
    ALNApplication *mounted =
        [entry[@"application"] isKindOfClass:[ALNApplication class]] ? entry[@"application"] : nil;
    if (mounted != nil) {
      [mounted shutdown];
    }
  }
}

- (void)registerBuiltInMiddlewares {
  NSDictionary *securityHeaders = ALNDictionaryConfigValue(self.config, @"securityHeaders");
  BOOL securityHeadersEnabled = ALNBoolConfigValue(securityHeaders[@"enabled"], YES);
  if (securityHeadersEnabled) {
    NSString *csp =
        ALNStringConfigValue(securityHeaders[@"contentSecurityPolicy"], @"default-src 'self'");
    [self addMiddleware:[[ALNSecurityHeadersMiddleware alloc] initWithContentSecurityPolicy:csp]];
  }

  NSDictionary *rateLimit = ALNDictionaryConfigValue(self.config, @"rateLimit");
  BOOL rateLimitEnabled = ALNBoolConfigValue(rateLimit[@"enabled"], NO);
  if (rateLimitEnabled) {
    NSUInteger requests = ALNUIntConfigValue(rateLimit[@"requests"], 120, 1);
    NSUInteger windowSeconds = ALNUIntConfigValue(rateLimit[@"windowSeconds"], 60, 1);
    [self addMiddleware:[[ALNRateLimitMiddleware alloc] initWithMaxRequests:requests
                                                               windowSeconds:windowSeconds]];
  }

  NSDictionary *session = ALNDictionaryConfigValue(self.config, @"session");
  BOOL sessionEnabled = ALNBoolConfigValue(session[@"enabled"], NO);
  if (sessionEnabled) {
    NSString *secret = ALNStringConfigValue(session[@"secret"], nil);
    if ([secret length] == 0) {
      [self.logger warn:@"session middleware disabled"
                 fields:@{
                   @"reason" : @"missing session.secret",
                 }];
    } else {
      NSString *cookieName = ALNStringConfigValue(session[@"cookieName"], @"arlen_session");
      NSUInteger maxAge = ALNUIntConfigValue(session[@"maxAgeSeconds"], 1209600, 1);
      BOOL secureDefault = [self.environment isEqualToString:@"production"];
      BOOL secure = ALNBoolConfigValue(session[@"secure"], secureDefault);
      NSString *sameSite = ALNStringConfigValue(session[@"sameSite"], @"Lax");
      [self addMiddleware:[[ALNSessionMiddleware alloc] initWithSecret:secret
                                                             cookieName:cookieName
                                                          maxAgeSeconds:maxAge
                                                                 secure:secure
                                                               sameSite:sameSite]];
    }
  }

  NSDictionary *csrf = ALNDictionaryConfigValue(self.config, @"csrf");
  BOOL csrfEnabled = ALNBoolConfigValue(csrf[@"enabled"], sessionEnabled);
  if (csrfEnabled) {
    if (!sessionEnabled) {
      [self.logger warn:@"csrf middleware disabled"
                 fields:@{
                   @"reason" : @"csrf requires session middleware",
                 }];
    } else {
      NSString *headerName = ALNStringConfigValue(csrf[@"headerName"], @"x-csrf-token");
      NSString *queryParam = ALNStringConfigValue(csrf[@"queryParamName"], @"csrf_token");
      [self addMiddleware:[[ALNCSRFMiddleware alloc] initWithHeaderName:headerName
                                                         queryParamName:queryParam]];
    }
  }

  NSDictionary *apiHelpers = ALNDictionaryConfigValue(self.config, @"apiHelpers");
  BOOL responseEnvelopeEnabled = ALNBoolConfigValue(apiHelpers[@"responseEnvelopeEnabled"], NO);
  if (responseEnvelopeEnabled) {
    [self addMiddleware:[[ALNResponseEnvelopeMiddleware alloc] init]];
  }
}

- (ALNResponse *)dispatchRequest:(ALNRequest *)request {
  NSString *rewrittenPath = nil;
  NSDictionary *mountedEntry = [self mountedEntryForPath:request.path rewrittenPath:&rewrittenPath];
  if (mountedEntry != nil) {
    ALNApplication *mountedApp =
        [mountedEntry[@"application"] isKindOfClass:[ALNApplication class]]
            ? mountedEntry[@"application"]
            : nil;
    NSString *prefix = [mountedEntry[@"prefix"] isKindOfClass:[NSString class]]
                           ? mountedEntry[@"prefix"]
                           : @"";
    if (mountedApp != nil && [rewrittenPath length] > 0) {
      ALNRequest *forwarded =
          [[ALNRequest alloc] initWithMethod:request.method
                                        path:rewrittenPath
                                 queryString:request.queryString
                                     headers:request.headers
                                        body:request.body];
      forwarded.routeParams = request.routeParams ?: @{};
      forwarded.remoteAddress = request.remoteAddress ?: @"";
      forwarded.effectiveRemoteAddress = request.effectiveRemoteAddress ?: @"";
      forwarded.scheme = request.scheme ?: @"http";
      forwarded.parseDurationMilliseconds = request.parseDurationMilliseconds;
      forwarded.responseWriteDurationMilliseconds = request.responseWriteDurationMilliseconds;

      ALNResponse *forwardedResponse = [mountedApp dispatchRequest:forwarded];
      if ([prefix length] > 0 && [forwardedResponse headerForName:@"X-Arlen-Mount-Prefix"] == nil) {
        [forwardedResponse setHeader:@"X-Arlen-Mount-Prefix" value:prefix];
      }
      return forwardedResponse;
    }
  }

  ALNResponse *response = [[ALNResponse alloc] init];
  NSString *requestID = ALNGenerateRequestID();
  [response setHeader:@"X-Request-Id" value:requestID];

  BOOL performanceLogging = ALNBoolConfigValue(self.config[@"performanceLogging"], YES);
  BOOL apiOnly = ALNBoolConfigValue(self.config[@"apiOnly"], NO);
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:performanceLogging];
  [trace startStage:@"total"];
  [self.metrics addGauge:@"http_requests_active" delta:1.0];

  NSString *routePath = nil;
  NSString *requestFormat = ALNRequestPreferredFormat(request, apiOnly, &routePath);
  if ([routePath length] == 0) {
    routePath = request.path ?: @"/";
  }

  [trace startStage:@"route"];
  ALNRouteMatch *match =
      [self.router matchMethod:request.method ?: @"GET"
                          path:routePath
                        format:requestFormat];
  [trace endStage:@"route"];

  if (match == nil) {
    BOOL handledBuiltIn = ALNApplyBuiltInResponse(self, request, response, routePath);
    if (!handledBuiltIn && (apiOnly || ALNRequestPrefersJSON(request, apiOnly))) {
      NSDictionary *payload = ALNStructuredErrorPayload(404,
                                                        @"not_found",
                                                        @"Not Found",
                                                        requestID,
                                                        @{});
      ALNSetStructuredErrorResponse(response, 404, payload);
    } else if (!handledBuiltIn) {
      response.statusCode = 404;
      [response setTextBody:@"not found\n"];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
    }
    ALNFinalizeResponse(self, response, trace, request, requestID, performanceLogging);
    ALNRecordRequestMetrics(self, response, trace);
    [self.metrics addGauge:@"http_requests_active" delta:-1.0];

    if (self.traceExporter != nil) {
      @try {
        [self.traceExporter exportTrace:[trace dictionaryRepresentation]
                                request:request
                               response:response
                              routeName:@""
                         controllerName:@""
                             actionName:@""];
      } @catch (NSException *exception) {
        [self.logger warn:@"trace exporter failed"
                   fields:@{
                     @"request_id" : requestID ?: @"",
                     @"exception" : exception.reason ?: @"",
                   }];
      }
    }

    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    fields[@"method"] = request.method ?: @"";
    fields[@"path"] = request.path ?: @"";
    fields[@"status"] = @(response.statusCode);
    fields[@"request_id"] = requestID ?: @"";
    if (performanceLogging) {
      fields[@"timings"] = [trace dictionaryRepresentation];
    }
    [self.logger info:@"request" fields:fields];
    return response;
  }

  NSMutableDictionary *stash = [NSMutableDictionary dictionary];
  stash[@"request_id"] = requestID ?: @"";
  stash[ALNContextRequestFormatStashKey] = requestFormat ?: @"";
  if (self.jobsAdapter != nil) {
    stash[ALNContextJobsAdapterStashKey] = self.jobsAdapter;
  }
  if (self.cacheAdapter != nil) {
    stash[ALNContextCacheAdapterStashKey] = self.cacheAdapter;
  }
  if (self.localizationAdapter != nil) {
    stash[ALNContextLocalizationAdapterStashKey] = self.localizationAdapter;
  }
  if (self.mailAdapter != nil) {
    stash[ALNContextMailAdapterStashKey] = self.mailAdapter;
  }
  if (self.attachmentAdapter != nil) {
    stash[ALNContextAttachmentAdapterStashKey] = self.attachmentAdapter;
  }

  stash[ALNContextI18nDefaultLocaleStashKey] = self.i18nDefaultLocale ?: @"en";
  stash[ALNContextI18nFallbackLocaleStashKey] =
      self.i18nFallbackLocale ?: self.i18nDefaultLocale ?: @"en";

  NSDictionary *eoc = ALNDictionaryConfigValue(self.config, @"eoc");
  NSDictionary *compatibility = ALNDictionaryConfigValue(self.config, @"compatibility");
  stash[ALNContextEOCStrictLocalsStashKey] =
      @(ALNBoolConfigValue(eoc[@"strictLocals"], NO));
  stash[ALNContextEOCStrictStringifyStashKey] =
      @(ALNBoolConfigValue(eoc[@"strictStringify"], NO));
  stash[ALNContextPageStateEnabledStashKey] =
      @(ALNBoolConfigValue(compatibility[@"pageStateEnabled"], NO));
  request.routeParams = match.params ?: @{};
  ALNContext *context = [[ALNContext alloc] initWithRequest:request
                                                   response:response
                                                     params:request.routeParams
                                                      stash:stash
                                                     logger:self.logger
                                                  perfTrace:trace
                                                  routeName:match.route.name ?: @""
                                             controllerName:NSStringFromClass(match.route.controllerClass)
                                                 actionName:match.route.actionName ?: @""];

  id returnValue = nil;
  BOOL shouldDispatchController =
      ALNApplyRequestContractIfNeeded(self, request, response, context, match.route, requestID);
  NSMutableArray *executedMiddlewares = [NSMutableArray array];
  if (shouldDispatchController && [self.mutableMiddlewares count] > 0) {
    [trace startStage:@"middleware"];
    for (id<ALNMiddleware> middleware in self.mutableMiddlewares) {
      NSError *middlewareError = nil;
      BOOL shouldContinue = [middleware processContext:context error:&middlewareError];
      [executedMiddlewares addObject:middleware];
      if (!shouldContinue) {
        shouldDispatchController = NO;
        if (!response.committed) {
          if (middlewareError != nil) {
            NSDictionary *details = ALNErrorDetailsFromNSError(middlewareError);
            ALNApplyInternalErrorResponse(self,
                                          request,
                                          response,
                                          requestID,
                                          500,
                                          @"middleware_failure",
                                          @"Internal Server Error",
                                          middlewareError.localizedDescription ?: @"middleware failure",
                                          details);
          } else {
            response.statusCode = 400;
            [response setTextBody:@"request halted by middleware\n"];
            [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
            response.committed = YES;
          }
        }
        if (middlewareError != nil) {
          [self.logger error:@"middleware failure"
                      fields:@{
                        @"request_id" : requestID ?: @"",
                        @"controller" : context.controllerName ?: @"",
                        @"action" : context.actionName ?: @"",
                        @"error" : middlewareError.localizedDescription ?: @""
                      }];
        }
        break;
      }
    }
    [trace endStage:@"middleware"];
  }

  if (shouldDispatchController && !response.committed) {
    shouldDispatchController =
        ALNApplyAuthContractIfNeeded(self, request, response, context, match.route, requestID);
  }

  if (shouldDispatchController) {
    [trace startStage:@"controller"];
    @try {
      id controller = [[match.route.controllerClass alloc] init];
      if ([controller isKindOfClass:[ALNController class]]) {
        ((ALNController *)controller).context = context;
      }
      BOOL guardPassed = YES;
      if (match.route.guardSelector != NULL) {
        NSMethodSignature *guardSignature =
            [controller methodSignatureForSelector:match.route.guardSelector];
        if (guardSignature == nil || [guardSignature numberOfArguments] != 3) {
          NSDictionary *details = @{
            @"controller" : context.controllerName ?: @"",
            @"guard" : match.route.guardActionName ?: @"",
            @"reason" : @"Guard must accept exactly one ALNContext * parameter"
          };
          ALNApplyInternalErrorResponse(self,
                                        request,
                                        response,
                                        requestID,
                                        500,
                                        @"invalid_guard_signature",
                                        @"Internal Server Error",
                                        @"Invalid route guard signature",
                                        details);
          guardPassed = NO;
        } else {
          NSInvocation *guardInvocation =
              [NSInvocation invocationWithMethodSignature:guardSignature];
          [guardInvocation setTarget:controller];
          [guardInvocation setSelector:match.route.guardSelector];
          ALNContext *arg = context;
          [guardInvocation setArgument:&arg atIndex:2];
          [guardInvocation invoke];

          const char *guardReturnType = [guardSignature methodReturnType];
          if (strcmp(guardReturnType, @encode(void)) == 0) {
            guardPassed = !response.committed;
          } else if (strcmp(guardReturnType, @encode(BOOL)) == 0 ||
                     strcmp(guardReturnType, @encode(bool)) == 0 ||
                     strcmp(guardReturnType, "c") == 0) {
            BOOL value = NO;
            [guardInvocation getReturnValue:&value];
            guardPassed = value;
          } else {
            __unsafe_unretained id guardResult = nil;
            [guardInvocation getReturnValue:&guardResult];
            if ([guardResult respondsToSelector:@selector(boolValue)]) {
              guardPassed = [guardResult boolValue];
            } else {
              guardPassed = (guardResult != nil);
            }
          }
        }
      }

      if (!guardPassed && !response.committed) {
        if (apiOnly || ALNRequestPrefersJSON(request, apiOnly)) {
          NSDictionary *payload = ALNStructuredErrorPayload(403,
                                                            @"forbidden",
                                                            @"Forbidden",
                                                            requestID,
                                                            @{});
          ALNSetStructuredErrorResponse(response, 403, payload);
        } else {
          response.statusCode = 403;
          [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
          [response setTextBody:@"forbidden\n"];
          response.committed = YES;
        }
      }

      if (guardPassed && !response.committed) {
        NSMethodSignature *signature =
            [controller methodSignatureForSelector:match.route.actionSelector];
        if (signature == nil || [signature numberOfArguments] != 3) {
          NSDictionary *details = @{
            @"controller" : context.controllerName ?: @"",
            @"action" : context.actionName ?: @"",
            @"reason" : @"Action must accept exactly one ALNContext * parameter"
          };
          ALNApplyInternalErrorResponse(self,
                                        request,
                                        response,
                                        requestID,
                                        500,
                                        @"invalid_action_signature",
                                        @"Internal Server Error",
                                        @"Invalid controller action signature",
                                        details);
        } else {
          NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
          [invocation setTarget:controller];
          [invocation setSelector:match.route.actionSelector];
          ALNContext *arg = context;
          [invocation setArgument:&arg atIndex:2];
          [invocation invoke];

          const char *returnType = [signature methodReturnType];
          if (strcmp(returnType, @encode(void)) != 0) {
            __unsafe_unretained id temp = nil;
            [invocation getReturnValue:&temp];
            returnValue = temp;
          }
        }
      }
    } @catch (NSException *exception) {
      NSDictionary *details = ALNErrorDetailsFromException(exception);
      ALNApplyInternalErrorResponse(self,
                                    request,
                                    response,
                                    requestID,
                                    500,
                                    @"controller_exception",
                                    @"Internal Server Error",
                                    exception.reason ?: @"controller exception",
                                    details);
      [self.logger error:@"controller exception"
                  fields:@{
                    @"request_id" : requestID ?: @"",
                    @"controller" : context.controllerName ?: @"",
                    @"action" : context.actionName ?: @"",
                    @"exception" : exception.description ?: @""
                  }];
    }
    [trace endStage:@"controller"];
  }

  if (!response.committed) {
    if ([returnValue isKindOfClass:[NSDictionary class]] ||
        [returnValue isKindOfClass:[NSArray class]]) {
      Class controllerClass = match.route.controllerClass;
      NSJSONWritingOptions options = 0;
      if ([controllerClass respondsToSelector:@selector(jsonWritingOptions)]) {
        options = (NSJSONWritingOptions)[controllerClass jsonWritingOptions];
      }

      NSError *jsonError = nil;
      BOOL ok = [response setJSONBody:returnValue options:options error:&jsonError];
      if (!ok) {
        NSDictionary *details = ALNErrorDetailsFromNSError(jsonError);
        ALNApplyInternalErrorResponse(self,
                                      request,
                                      response,
                                      requestID,
                                      500,
                                      @"json_serialization_failed",
                                      @"Internal Server Error",
                                      jsonError.localizedDescription ?: @"json serialization failed",
                                      details);
        [self.logger error:@"implicit json serialization failed"
                    fields:@{
                      @"request_id" : requestID ?: @"",
                      @"controller" : context.controllerName ?: @"",
                      @"action" : context.actionName ?: @"",
                      @"error" : jsonError.localizedDescription ?: @""
                    }];
      } else {
        if (response.statusCode == 0) {
          response.statusCode = 200;
        }
        response.committed = YES;
      }
    } else if ([returnValue isKindOfClass:[NSString class]]) {
      [response setTextBody:returnValue];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
    } else if (returnValue != nil) {
      [response setTextBody:[returnValue description]];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
    } else if (!ALNResponseHasBody(response)) {
      response.statusCode = 204;
      response.committed = YES;
    }
  }

  for (NSInteger idx = (NSInteger)[executedMiddlewares count] - 1; idx >= 0; idx--) {
    id<ALNMiddleware> middleware = executedMiddlewares[(NSUInteger)idx];
    if (![middleware respondsToSelector:@selector(didProcessContext:)]) {
      continue;
    }
    @try {
      [middleware didProcessContext:context];
    } @catch (NSException *exception) {
      if (!response.committed) {
        NSDictionary *details = ALNErrorDetailsFromException(exception);
        ALNApplyInternalErrorResponse(self,
                                      request,
                                      response,
                                      requestID,
                                      500,
                                      @"middleware_finalize_failure",
                                      @"Internal Server Error",
                                      exception.reason ?: @"middleware finalize failure",
                                      details);
      }
      [self.logger error:@"middleware finalize failure"
                  fields:@{
                    @"request_id" : requestID ?: @"",
                    @"controller" : context.controllerName ?: @"",
                    @"action" : context.actionName ?: @"",
                    @"exception" : exception.description ?: @""
                  }];
    }
  }

  (void)ALNValidateResponseContractIfNeeded(self,
                                            request,
                                            response,
                                            match.route,
                                            returnValue,
                                            requestID);

  ALNFinalizeResponse(self, response, trace, request, requestID, performanceLogging);
  ALNRecordRequestMetrics(self, response, trace);
  [self.metrics addGauge:@"http_requests_active" delta:-1.0];

  if (self.traceExporter != nil) {
    @try {
      [self.traceExporter exportTrace:[trace dictionaryRepresentation]
                              request:request
                             response:response
                            routeName:context.routeName ?: @""
                       controllerName:context.controllerName ?: @""
                           actionName:context.actionName ?: @""];
    } @catch (NSException *exception) {
      [self.logger warn:@"trace exporter failed"
                 fields:@{
                   @"request_id" : requestID ?: @"",
                   @"exception" : exception.reason ?: @"",
                 }];
    }
  }

  NSMutableDictionary *logFields = [NSMutableDictionary dictionary];
  logFields[@"method"] = request.method ?: @"";
  logFields[@"path"] = request.path ?: @"";
  logFields[@"status"] = @(response.statusCode);
  logFields[@"request_id"] = requestID ?: @"";
  logFields[@"controller"] = context.controllerName ?: @"";
  logFields[@"action"] = context.actionName ?: @"";
  if (performanceLogging) {
    logFields[@"timings"] = [trace dictionaryRepresentation];
  }
  [self.logger info:@"request" fields:logFields];

  return response;
}

@end
