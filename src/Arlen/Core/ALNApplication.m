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
#import "ALNJSONSerialization.h"
#import "ALNPerf.h"
#import "ALNMetrics.h"
#import "ALNAuth.h"

#include <ctype.h>
#include <math.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

NSString *const ALNApplicationErrorDomain = @"Arlen.Application.Error";

typedef id (*ALNContextObjectIMP)(id target, SEL selector, ALNContext *context);
typedef void (*ALNContextVoidIMP)(id target, SEL selector, ALNContext *context);
typedef BOOL (*ALNContextBoolIMP)(id target, SEL selector, ALNContext *context);

typedef NS_ENUM(NSUInteger, ALNRuntimeInvocationMode) {
  ALNRuntimeInvocationModeCachedIMP = 0,
  ALNRuntimeInvocationModeSelector = 1,
};

typedef struct {
  BOOL enabled;
  BOOL hasTraceID;
  BOOL hasParentSpanID;
  char traceID[33];
  char spanID[17];
  char parentSpanID[17];
  char flags[3];
  char traceparent[56];
} ALNRequestTraceContext;

static BOOL ALNRequestPrefersJSON(ALNRequest *request, BOOL apiOnly);
static void ALNSetStructuredErrorResponse(ALNResponse *response,
                                          NSInteger statusCode,
                                          NSDictionary *payload);

static const char *ALNObjCTypeWithoutQualifiers(const char *typeEncoding) {
  if (typeEncoding == NULL) {
    return "";
  }
  const char *cursor = typeEncoding;
  while (*cursor == 'r' || *cursor == 'n' || *cursor == 'N' || *cursor == 'o' ||
         *cursor == 'O' || *cursor == 'R' || *cursor == 'V') {
    cursor++;
  }
  return cursor;
}

static ALNRouteInvocationReturnKind ALNReturnKindForSignature(NSMethodSignature *signature) {
  if (signature == nil) {
    return ALNRouteInvocationReturnKindUnknown;
  }

  const char *returnType = ALNObjCTypeWithoutQualifiers([signature methodReturnType]);
  if (strcmp(returnType, @encode(void)) == 0) {
    return ALNRouteInvocationReturnKindVoid;
  }
  if (returnType[0] == '@') {
    return ALNRouteInvocationReturnKindObject;
  }
  if (strcmp(returnType, @encode(BOOL)) == 0 || strcmp(returnType, @encode(bool)) == 0 ||
      strcmp(returnType, "c") == 0 || strcmp(returnType, "B") == 0) {
    return ALNRouteInvocationReturnKindBool;
  }
  return ALNRouteInvocationReturnKindUnknown;
}

static ALNRuntimeInvocationMode ALNInvocationModeFromString(NSString *rawValue,
                                                            ALNRuntimeInvocationMode defaultMode) {
  if (![rawValue isKindOfClass:[NSString class]]) {
    return defaultMode;
  }
  NSString *normalized = [[rawValue lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"selector"] ||
      [normalized isEqualToString:@"objc_msgsend"] ||
      [normalized isEqualToString:@"legacy"]) {
    return ALNRuntimeInvocationModeSelector;
  }
  if ([normalized isEqualToString:@"cached_imp"] ||
      [normalized isEqualToString:@"cached"] ||
      [normalized isEqualToString:@"imp"]) {
    return ALNRuntimeInvocationModeCachedIMP;
  }
  return defaultMode;
}

static ALNRuntimeInvocationMode ALNResolvedRuntimeInvocationMode(NSDictionary *config) {
  ALNRuntimeInvocationMode mode =
      ALNInvocationModeFromString(config[@"runtimeInvocationMode"], ALNRuntimeInvocationModeCachedIMP);
  const char *rawEnv = getenv("ARLEN_RUNTIME_INVOCATION_MODE");
  if (rawEnv != NULL && rawEnv[0] != '\0') {
    NSString *envValue = [NSString stringWithUTF8String:rawEnv];
    mode = ALNInvocationModeFromString(envValue, mode);
  }
  return mode;
}

static NSString *ALNRuntimeInvocationModeName(ALNRuntimeInvocationMode mode) {
  if (mode == ALNRuntimeInvocationModeSelector) {
    return @"selector";
  }
  return @"cached_imp";
}

static BOOL ALNRouteInvocationResultToBool(id value) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return (value != nil);
}

static BOOL ALNInvokeRouteGuard(id controller,
                                ALNRoute *route,
                                ALNContext *context,
                                ALNResponse *response,
                                ALNRuntimeInvocationMode mode,
                                BOOL *guardPassedOut) {
  if (controller == nil || route == nil || context == nil || response == nil || guardPassedOut == NULL) {
    return NO;
  }

  ALNRouteInvocationReturnKind guardReturnKind = route.compiledGuardReturnKind;
  if (guardReturnKind == ALNRouteInvocationReturnKindUnknown) {
    return NO;
  }

  IMP guardIMP = route.compiledGuardIMP;
  BOOL guardPassed = YES;
  if (mode == ALNRuntimeInvocationModeSelector) {
    if (guardReturnKind == ALNRouteInvocationReturnKindVoid) {
      ((ALNContextVoidIMP)objc_msgSend)(controller, route.guardSelector, context);
      guardPassed = !response.committed;
    } else if (guardReturnKind == ALNRouteInvocationReturnKindBool) {
      guardPassed = ((ALNContextBoolIMP)objc_msgSend)(controller, route.guardSelector, context);
    } else if (guardReturnKind == ALNRouteInvocationReturnKindObject) {
      id guardResult = ((ALNContextObjectIMP)objc_msgSend)(controller, route.guardSelector, context);
      guardPassed = ALNRouteInvocationResultToBool(guardResult);
    } else {
      return NO;
    }
    *guardPassedOut = guardPassed;
    return YES;
  }

  if (guardIMP == NULL) {
    return NO;
  }
  if (guardReturnKind == ALNRouteInvocationReturnKindVoid) {
    ((ALNContextVoidIMP)guardIMP)(controller, route.guardSelector, context);
    guardPassed = !response.committed;
  } else if (guardReturnKind == ALNRouteInvocationReturnKindBool) {
    guardPassed = ((ALNContextBoolIMP)guardIMP)(controller, route.guardSelector, context);
  } else if (guardReturnKind == ALNRouteInvocationReturnKindObject) {
    id guardResult = ((ALNContextObjectIMP)guardIMP)(controller, route.guardSelector, context);
    guardPassed = ALNRouteInvocationResultToBool(guardResult);
  } else {
    return NO;
  }
  *guardPassedOut = guardPassed;
  return YES;
}

static BOOL ALNInvokeRouteAction(id controller,
                                 ALNRoute *route,
                                 ALNContext *context,
                                 ALNRuntimeInvocationMode mode,
                                 id *returnValueOut) {
  if (controller == nil || route == nil || context == nil) {
    return NO;
  }

  ALNRouteInvocationReturnKind actionReturnKind = route.compiledActionReturnKind;
  if (actionReturnKind == ALNRouteInvocationReturnKindUnknown) {
    return NO;
  }

  id returnValue = nil;
  IMP actionIMP = route.compiledActionIMP;
  if (mode == ALNRuntimeInvocationModeSelector) {
    if (actionReturnKind == ALNRouteInvocationReturnKindVoid) {
      ((ALNContextVoidIMP)objc_msgSend)(controller, route.actionSelector, context);
    } else if (actionReturnKind == ALNRouteInvocationReturnKindObject) {
      returnValue = ((ALNContextObjectIMP)objc_msgSend)(controller, route.actionSelector, context);
    } else {
      return NO;
    }
    if (returnValueOut != NULL) {
      *returnValueOut = returnValue;
    }
    return YES;
  }

  if (actionIMP == NULL) {
    return NO;
  }
  if (actionReturnKind == ALNRouteInvocationReturnKindVoid) {
    ((ALNContextVoidIMP)actionIMP)(controller, route.actionSelector, context);
  } else if (actionReturnKind == ALNRouteInvocationReturnKindObject) {
    returnValue = ((ALNContextObjectIMP)actionIMP)(controller, route.actionSelector, context);
  } else {
    return NO;
  }
  if (returnValueOut != NULL) {
    *returnValueOut = returnValue;
  }
  return YES;
}

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
@property(nonatomic, assign, readwrite) NSUInteger clusterObservedNodes;
@property(nonatomic, assign, readwrite) BOOL clusterEmitHeaders;
@property(nonatomic, assign) BOOL metricsEnabled;
@property(nonatomic, assign) BOOL tracePropagationEnabled;
@property(nonatomic, assign) BOOL apiOnly;
@property(nonatomic, assign) BOOL performanceLoggingEnabled;
@property(nonatomic, assign) BOOL eocStrictLocalsEnabled;
@property(nonatomic, assign) BOOL eocStrictStringifyEnabled;
@property(nonatomic, assign) BOOL pageStateEnabled;
@property(nonatomic, copy) NSString *i18nDefaultLocale;
@property(nonatomic, copy) NSString *i18nFallbackLocale;
@property(nonatomic, copy, readwrite) NSString *runtimeInvocationMode;
@property(nonatomic, assign) ALNRuntimeInvocationMode runtimeInvocationModeKind;
@property(nonatomic, strong) NSDate *bootedAt;
@property(nonatomic, strong) NSDate *startedAt;
@property(nonatomic, assign, readwrite, getter=isStarted) BOOL started;
@property(nonatomic, strong) NSLock *routeCompilationLock;

- (void)loadConfiguredPlugins;
- (void)loadConfiguredStaticMounts;
- (BOOL)compileRegisteredRoutesWithWarningsAsErrors:(BOOL)warningsAsErrors
                                              error:(NSError *_Nullable *_Nullable)error;
- (BOOL)compileRoute:(ALNRoute *)route
       controllerMap:(NSMutableDictionary *)controllerMap
    warningsAsErrors:(BOOL)warningsAsErrors
               error:(NSError *_Nullable *_Nullable)error;
- (BOOL)routingCompileOnStartEnabled;
- (BOOL)routingRouteCompileWarningsAsErrorsEnabled;
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
    id observedNodesValue = cluster[@"observedNodes"];
    NSUInteger observedNodes =
        [observedNodesValue respondsToSelector:@selector(unsignedIntegerValue)]
            ? [observedNodesValue unsignedIntegerValue]
            : _clusterExpectedNodes;
    _clusterObservedNodes = observedNodes;
    id emitHeadersValue = cluster[@"emitHeaders"];
    _clusterEmitHeaders = [emitHeadersValue respondsToSelector:@selector(boolValue)]
                              ? [emitHeadersValue boolValue]
                              : YES;
    NSDictionary *observability =
        [_config[@"observability"] isKindOfClass:[NSDictionary class]]
            ? _config[@"observability"]
            : @{};
    id metricsEnabledValue = observability[@"metricsEnabled"];
    _metricsEnabled = [metricsEnabledValue respondsToSelector:@selector(boolValue)]
                          ? [metricsEnabledValue boolValue]
                          : YES;
    id tracePropagationEnabledValue = observability[@"tracePropagationEnabled"];
    _tracePropagationEnabled = [tracePropagationEnabledValue respondsToSelector:@selector(boolValue)]
                                   ? [tracePropagationEnabledValue boolValue]
                                   : YES;
    id apiOnlyValue = _config[@"apiOnly"];
    _apiOnly = [apiOnlyValue respondsToSelector:@selector(boolValue)]
                   ? [apiOnlyValue boolValue]
                   : NO;
    id performanceLoggingValue = _config[@"performanceLogging"];
    _performanceLoggingEnabled = [performanceLoggingValue respondsToSelector:@selector(boolValue)]
                                     ? [performanceLoggingValue boolValue]
                                     : YES;
    NSDictionary *eoc = [_config[@"eoc"] isKindOfClass:[NSDictionary class]]
                            ? _config[@"eoc"]
                            : @{};
    id strictLocalsValue = eoc[@"strictLocals"];
    _eocStrictLocalsEnabled = [strictLocalsValue respondsToSelector:@selector(boolValue)]
                                  ? [strictLocalsValue boolValue]
                                  : NO;
    id strictStringifyValue = eoc[@"strictStringify"];
    _eocStrictStringifyEnabled = [strictStringifyValue respondsToSelector:@selector(boolValue)]
                                     ? [strictStringifyValue boolValue]
                                     : NO;
    NSDictionary *compatibility =
        [_config[@"compatibility"] isKindOfClass:[NSDictionary class]]
            ? _config[@"compatibility"]
            : @{};
    id pageStateEnabledValue = compatibility[@"pageStateEnabled"];
    _pageStateEnabled = [pageStateEnabledValue respondsToSelector:@selector(boolValue)]
                            ? [pageStateEnabledValue boolValue]
                            : NO;
    _runtimeInvocationModeKind = ALNResolvedRuntimeInvocationMode(_config);
    _runtimeInvocationMode = [ALNRuntimeInvocationModeName(_runtimeInvocationModeKind) copy];
    _bootedAt = [NSDate date];
    _startedAt = nil;
    _started = NO;
    _routeCompilationLock = [[NSLock alloc] init];
    ALNLogLevel defaultLogLevel =
        [_environment isEqualToString:@"development"] ? ALNLogLevelDebug : ALNLogLevelInfo;
    _logger.minimumLevel = ALNLogLevelFromConfigValue(_config[@"logLevel"], defaultLogLevel);
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

static ALNLogLevel ALNLogLevelFromConfigValue(id value, ALNLogLevel defaultValue) {
  if (![value isKindOfClass:[NSString class]]) {
    return defaultValue;
  }
  NSString *normalized = [[(NSString *)value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"debug"]) {
    return ALNLogLevelDebug;
  }
  if ([normalized isEqualToString:@"info"]) {
    return ALNLogLevelInfo;
  }
  if ([normalized isEqualToString:@"warn"]) {
    return ALNLogLevelWarn;
  }
  if ([normalized isEqualToString:@"error"]) {
    return ALNLogLevelError;
  }
  return defaultValue;
}

static NSDictionary *ALNRouteCompileContext(ALNRoute *route) {
  if (route == nil) {
    return @{};
  }
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"route_name"] = [route.name isKindOfClass:[NSString class]] ? route.name : @"";
  context[@"route_method"] = [route.method isKindOfClass:[NSString class]] ? route.method : @"";
  context[@"route_path"] = [route.pathPattern isKindOfClass:[NSString class]] ? route.pathPattern : @"";
  context[@"controller"] = NSStringFromClass(route.controllerClass ?: [NSObject class]);
  context[@"action"] = [route.actionName isKindOfClass:[NSString class]] ? route.actionName : @"";
  context[@"guard"] = [route.guardActionName isKindOfClass:[NSString class]] ? route.guardActionName : @"";
  return context;
}

static NSError *ALNRouteCompileError(NSInteger code,
                                     NSString *compileCode,
                                     NSString *responseErrorCode,
                                     NSString *message,
                                     ALNRoute *route,
                                     NSArray *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"route compile failed";
  if ([compileCode length] > 0) {
    userInfo[@"compile_code"] = compileCode;
  }
  if ([responseErrorCode length] > 0) {
    userInfo[@"response_error_code"] = responseErrorCode;
  }
  [userInfo addEntriesFromDictionary:ALNRouteCompileContext(route)];
  if ([details isKindOfClass:[NSArray class]] && [details count] > 0) {
    userInfo[@"details"] = details;
  }
  return [NSError errorWithDomain:ALNApplicationErrorDomain
                             code:code
                         userInfo:userInfo];
}

static NSString *ALNRouteCompileResponseErrorCode(NSError *error) {
  if (![error.userInfo isKindOfClass:[NSDictionary class]]) {
    return @"route_compile_failed";
  }
  NSString *code = [error.userInfo[@"response_error_code"] isKindOfClass:[NSString class]]
                       ? error.userInfo[@"response_error_code"]
                       : @"";
  if ([code length] > 0) {
    return code;
  }
  return @"route_compile_failed";
}

static NSDictionary *ALNRouteCompileRuntimeDetails(NSError *error) {
  if (![error.userInfo isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  NSDictionary *userInfo = error.userInfo;
  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  NSArray *keys = @[
    @"compile_code",
    @"route_name",
    @"route_method",
    @"route_path",
    @"controller",
    @"action",
    @"guard",
  ];
  for (NSString *key in keys) {
    id value = userInfo[key];
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
      details[key] = value;
    }
  }
  NSArray *diagnostics = [userInfo[@"details"] isKindOfClass:[NSArray class]]
                             ? userInfo[@"details"]
                             : @[];
  if ([diagnostics count] > 0) {
    details[@"route_compile_diagnostics"] = diagnostics;
  }
  return details;
}

static NSDictionary *ALNNormalizedSchemaCompileDiagnostic(NSDictionary *entry,
                                                          NSString *schemaName) {
  NSString *field = [entry[@"field"] isKindOfClass:[NSString class]] ? entry[@"field"] : @"";
  NSString *severity = [entry[@"severity"] isKindOfClass:[NSString class]]
                           ? [entry[@"severity"] lowercaseString]
                           : @"error";
  if (![severity isEqualToString:@"warning"] && ![severity isEqualToString:@"error"]) {
    severity = @"error";
  }
  NSString *code = [entry[@"code"] isKindOfClass:[NSString class]] ? entry[@"code"] : @"invalid_schema";
  NSString *message =
      [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"invalid schema descriptor";

  NSMutableDictionary *diagnostic = [NSMutableDictionary dictionary];
  if ([field length] > 0) {
    diagnostic[@"field"] = [NSString stringWithFormat:@"%@.%@", schemaName ?: @"schema", field];
  } else {
    diagnostic[@"field"] = schemaName ?: @"schema";
  }
  diagnostic[@"severity"] = severity;
  diagnostic[@"code"] = code;
  diagnostic[@"message"] = message;

  NSMutableDictionary *meta = [NSMutableDictionary dictionary];
  NSDictionary *rawMeta = [entry[@"meta"] isKindOfClass:[NSDictionary class]] ? entry[@"meta"] : @{};
  if ([rawMeta count] > 0) {
    [meta addEntriesFromDictionary:rawMeta];
  }
  if ([schemaName length] > 0) {
    meta[@"schema"] = schemaName;
  }
  if ([meta count] > 0) {
    diagnostic[@"meta"] = meta;
  }
  return diagnostic;
}

static NSDictionary *ALNSchemaShapeCompileWarning(NSString *schemaName, id rawSchema) {
  NSString *label = [schemaName length] > 0 ? schemaName : @"schema";
  NSString *schemaClass = (rawSchema != nil) ? NSStringFromClass([rawSchema class]) : @"";
  return @{
    @"field" : label,
    @"severity" : @"warning",
    @"code" : @"schema_not_dictionary",
    @"message" : @"Route schema should be a dictionary descriptor",
    @"meta" : @{
      @"schema" : label,
      @"schema_class" : schemaClass ?: @"",
    }
  };
}

static BOOL ALNCompileDiagnosticIsError(NSDictionary *diagnostic) {
  NSString *severity = [diagnostic[@"severity"] isKindOfClass:[NSString class]]
                           ? [diagnostic[@"severity"] lowercaseString]
                           : @"error";
  return ![severity isEqualToString:@"warning"];
}

static NSArray *ALNRouteSchemaDiagnosticsForSchema(id rawSchema, NSString *schemaName) {
  NSMutableArray *diagnostics = [NSMutableArray array];
  if (rawSchema == nil) {
    return diagnostics;
  }
  if (![rawSchema isKindOfClass:[NSDictionary class]]) {
    [diagnostics addObject:ALNSchemaShapeCompileWarning(schemaName, rawSchema)];
    return diagnostics;
  }

  NSArray *schemaDiagnostics = ALNSchemaReadinessDiagnostics((NSDictionary *)rawSchema);
  for (id value in schemaDiagnostics) {
    if (![value isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [diagnostics addObject:ALNNormalizedSchemaCompileDiagnostic((NSDictionary *)value, schemaName)];
  }
  return diagnostics;
}

static NSDictionary *ALNRoutingConfig(NSDictionary *config) {
  return ALNDictionaryConfigValue(config, @"routing");
}

static NSString *ALNTrimmedStringConfigValue(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSError *ALNSecurityConfigValidationError(NSInteger code,
                                                 NSString *message,
                                                 NSString *configKey,
                                                 NSString *reason,
                                                 NSString *securityProfile) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"invalid security configuration";
  if ([configKey length] > 0) {
    userInfo[@"config_key"] = configKey;
  }
  if ([reason length] > 0) {
    userInfo[@"reason"] = reason;
  }
  if ([securityProfile length] > 0) {
    userInfo[@"security_profile"] = securityProfile;
  }
  return [NSError errorWithDomain:ALNApplicationErrorDomain code:code userInfo:userInfo];
}

static NSError *ALNValidateSecurityConfiguration(NSDictionary *config) {
  NSDictionary *session = ALNDictionaryConfigValue(config, @"session");
  NSDictionary *csrf = ALNDictionaryConfigValue(config, @"csrf");
  NSDictionary *auth = ALNDictionaryConfigValue(config, @"auth");
  NSString *securityProfile = ALNStringConfigValue(config[@"securityProfile"], @"balanced");

  BOOL sessionEnabled = ALNBoolConfigValue(session[@"enabled"], NO);
  NSString *sessionSecret = ALNTrimmedStringConfigValue(session[@"secret"]);
  if (sessionEnabled && [sessionSecret length] == 0) {
    return ALNSecurityConfigValidationError(
        330,
        @"Invalid security configuration: session.enabled requires session.secret",
        @"session.secret",
        @"missing_required_secret",
        securityProfile);
  }

  BOOL csrfEnabled = ALNBoolConfigValue(csrf[@"enabled"], sessionEnabled);
  if (csrfEnabled && !sessionEnabled) {
    return ALNSecurityConfigValidationError(
        331,
        @"Invalid security configuration: csrf.enabled requires session.enabled",
        @"csrf.enabled",
        @"missing_session_dependency",
        securityProfile);
  }

  BOOL authEnabled = ALNBoolConfigValue(auth[@"enabled"], NO);
  NSString *authBearerSecret = ALNTrimmedStringConfigValue(auth[@"bearerSecret"]);
  if (authEnabled && [authBearerSecret length] == 0) {
    return ALNSecurityConfigValidationError(
        332,
        @"Invalid security configuration: auth.enabled requires auth.bearerSecret",
        @"auth.bearerSecret",
        @"missing_required_secret",
        securityProfile);
  }

  return nil;
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

static NSDictionary *ALNErrorDetailEntry(NSString *field,
                                         NSString *code,
                                         NSString *message,
                                         NSDictionary *meta) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionary];
  entry[@"field"] = [field isKindOfClass:[NSString class]] ? field : @"";
  entry[@"code"] = [code isKindOfClass:[NSString class]] && [code length] > 0 ? code : @"invalid";
  entry[@"message"] = [message isKindOfClass:[NSString class]] && [message length] > 0
                          ? message
                          : @"invalid value";
  if ([meta isKindOfClass:[NSDictionary class]] && [meta count] > 0) {
    entry[@"meta"] = meta;
  }
  return entry;
}

static NSArray *ALNNormalizedErrorDetailsArray(id rawDetails) {
  if ([rawDetails isKindOfClass:[NSArray class]]) {
    NSMutableArray *normalized = [NSMutableArray array];
    for (id value in (NSArray *)rawDetails) {
      if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *entry = (NSDictionary *)value;
        NSString *field = [entry[@"field"] isKindOfClass:[NSString class]] ? entry[@"field"] : @"";
        NSString *code = [entry[@"code"] isKindOfClass:[NSString class]] ? entry[@"code"] : @"invalid";
        NSString *message =
            [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"invalid value";
        NSMutableDictionary *meta = [NSMutableDictionary dictionary];
        NSDictionary *entryMeta = [entry[@"meta"] isKindOfClass:[NSDictionary class]] ? entry[@"meta"] : @{};
        if ([entryMeta count] > 0) {
          [meta addEntriesFromDictionary:entryMeta];
        }
        for (id key in entry) {
          if (![key isKindOfClass:[NSString class]]) {
            continue;
          }
          NSString *name = (NSString *)key;
          if ([name isEqualToString:@"field"] || [name isEqualToString:@"code"] ||
              [name isEqualToString:@"message"] || [name isEqualToString:@"meta"]) {
            continue;
          }
          meta[name] = entry[key] ?: [NSNull null];
        }
        [normalized addObject:ALNErrorDetailEntry(field,
                                                  code,
                                                  message,
                                                  [meta count] > 0 ? meta : nil)];
      } else {
        [normalized addObject:ALNErrorDetailEntry(@"",
                                                  @"invalid",
                                                  [value description] ?: @"invalid value",
                                                  nil)];
      }
    }
    return [NSArray arrayWithArray:normalized];
  }

  if ([rawDetails isKindOfClass:[NSDictionary class]] &&
      [(NSDictionary *)rawDetails count] > 0) {
    return @[ ALNErrorDetailEntry(@"",
                                  @"internal_error_details",
                                  @"Additional error details",
                                  (NSDictionary *)rawDetails) ];
  }

  return @[];
}

static NSDictionary *ALNValidationFailurePayload(NSString *requestID, NSArray *errors) {
  NSArray *details = ALNNormalizedErrorDetailsArray(errors);
  return @{
    @"error" : @{
      @"code" : @"validation_failed",
      @"message" : @"Validation failed",
      @"status" : @(422),
      @"request_id" : requestID ?: @"",
      @"correlation_id" : requestID ?: @"",
    },
    @"details" : details ?: @[]
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
  if (!application.metricsEnabled) {
    return;
  }
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

static ALNPerfTrace *ALNDisabledPerfTrace(void) {
  static ALNPerfTrace *trace = nil;
  if (trace == nil) {
    @synchronized([ALNPerfTrace class]) {
      if (trace == nil) {
        trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
      }
    }
  }
  return trace;
}

static NSString *ALNFastRandomHexString(NSUInteger length) {
  if (length == 0) {
    return @"";
  }

  static const char hexDigits[] = "0123456789abcdef";
  NSUInteger byteCount = (length + 1) / 2;

  uint8_t stackRandomBytes[32];
  uint8_t *randomBytes = stackRandomBytes;
  BOOL randomBytesNeedsFree = NO;
  if (byteCount > sizeof(stackRandomBytes)) {
    randomBytes = calloc(byteCount, sizeof(uint8_t));
    if (randomBytes == NULL) {
      return @"";
    }
    randomBytesNeedsFree = YES;
  }
  arc4random_buf(randomBytes, byteCount);

  char stackHexChars[64];
  char *hexChars = stackHexChars;
  BOOL hexCharsNeedsFree = NO;
  if (length > sizeof(stackHexChars)) {
    hexChars = calloc(length, sizeof(char));
    if (hexChars == NULL) {
      if (randomBytesNeedsFree) {
        free(randomBytes);
      }
      return @"";
    }
    hexCharsNeedsFree = YES;
  }

  for (NSUInteger idx = 0; idx < length; idx++) {
    uint8_t byte = randomBytes[idx / 2];
    uint8_t nibble = (idx % 2 == 0) ? (uint8_t)((byte >> 4) & 0x0F) : (uint8_t)(byte & 0x0F);
    hexChars[idx] = hexDigits[nibble];
  }

  NSString *result = nil;
  if (hexCharsNeedsFree) {
    result = [[NSString alloc] initWithBytesNoCopy:hexChars
                                            length:length
                                          encoding:NSASCIIStringEncoding
                                      freeWhenDone:YES];
  } else {
    result = [[NSString alloc] initWithBytes:hexChars length:length encoding:NSASCIIStringEncoding];
  }

  if (randomBytesNeedsFree) {
    free(randomBytes);
  }
  return result ?: @"";
}

static NSString *ALNGenerateRequestID(void) {
  return ALNFastRandomHexString(32);
}

static NSString *ALNISO8601Now(void) {
  struct timeval tv;
  if (gettimeofday(&tv, NULL) != 0) {
    return @"1970-01-01T00:00:00.000Z";
  }

  time_t seconds = tv.tv_sec;
  struct tm utc;
  if (gmtime_r(&seconds, &utc) == NULL) {
    return @"1970-01-01T00:00:00.000Z";
  }

  int milliseconds = (int)(tv.tv_usec / 1000);
  char buffer[32];
  int written = snprintf(buffer,
                         sizeof(buffer),
                         "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                         utc.tm_year + 1900,
                         utc.tm_mon + 1,
                         utc.tm_mday,
                         utc.tm_hour,
                         utc.tm_min,
                         utc.tm_sec,
                         milliseconds);
  if (written <= 0 || written >= (int)sizeof(buffer)) {
    return @"1970-01-01T00:00:00.000Z";
  }

  NSString *formatted = [NSString stringWithUTF8String:buffer];
  return [formatted length] > 0 ? formatted : @"1970-01-01T00:00:00.000Z";
}

static BOOL ALNIsASCIIWhitespace(unsigned char byte) {
  return byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n' ||
         byte == '\f' || byte == '\v';
}

static BOOL ALNIsASCIIHexCharacter(unsigned char byte) {
  return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f') ||
         (byte >= 'A' && byte <= 'F');
}

static char ALNLowerASCIIHexCharacter(unsigned char byte) {
  if (byte >= 'A' && byte <= 'F') {
    return (char)(byte - 'A' + 'a');
  }
  return (char)byte;
}

static BOOL ALNAllHexCharactersAreZero(const char *value, size_t expectedLength) {
  if (value == NULL) {
    return YES;
  }
  for (size_t idx = 0; idx < expectedLength; idx++) {
    if (value[idx] != '0') {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNParseLowerHexSegment(const char *input,
                                    size_t inputLength,
                                    size_t *offset,
                                    size_t segmentLength,
                                    char *output) {
  if (input == NULL || offset == NULL || output == NULL) {
    return NO;
  }
  if (*offset + segmentLength > inputLength) {
    return NO;
  }
  for (size_t idx = 0; idx < segmentLength; idx++) {
    unsigned char byte = (unsigned char)input[*offset + idx];
    if (!ALNIsASCIIHexCharacter(byte)) {
      return NO;
    }
    output[idx] = ALNLowerASCIIHexCharacter(byte);
  }
  output[segmentLength] = '\0';
  *offset += segmentLength;
  return YES;
}

static BOOL ALNParseTraceparentMember(const char *memberStart,
                                      size_t memberLength,
                                      char traceIDOut[33],
                                      char parentSpanIDOut[17],
                                      char flagsOut[3]) {
  if (memberStart == NULL || memberLength == 0 ||
      traceIDOut == NULL || parentSpanIDOut == NULL || flagsOut == NULL) {
    return NO;
  }

  size_t offset = 0;
  char version[3] = {0};
  if (!ALNParseLowerHexSegment(memberStart, memberLength, &offset, 2, version)) {
    return NO;
  }
  if (offset >= memberLength || memberStart[offset] != '-') {
    return NO;
  }
  offset += 1;

  if (!ALNParseLowerHexSegment(memberStart, memberLength, &offset, 32, traceIDOut)) {
    return NO;
  }
  if (offset >= memberLength || memberStart[offset] != '-') {
    return NO;
  }
  offset += 1;

  if (!ALNParseLowerHexSegment(memberStart, memberLength, &offset, 16, parentSpanIDOut)) {
    return NO;
  }
  if (offset >= memberLength || memberStart[offset] != '-') {
    return NO;
  }
  offset += 1;

  if (!ALNParseLowerHexSegment(memberStart, memberLength, &offset, 2, flagsOut)) {
    return NO;
  }
  if (offset != memberLength) {
    return NO;
  }
  if (ALNAllHexCharactersAreZero(traceIDOut, 32) ||
      ALNAllHexCharactersAreZero(parentSpanIDOut, 16)) {
    return NO;
  }
  return YES;
}

static BOOL ALNParseTraceparentHeader(NSString *headerValue,
                                      char traceIDOut[33],
                                      char parentSpanIDOut[17],
                                      char flagsOut[3]) {
  if (![headerValue isKindOfClass:[NSString class]] || [headerValue length] == 0 ||
      traceIDOut == NULL || parentSpanIDOut == NULL || flagsOut == NULL) {
    return NO;
  }
  const char *raw = [headerValue UTF8String];
  if (raw == NULL || raw[0] == '\0') {
    return NO;
  }

  const char *cursor = raw;
  while (*cursor != '\0' && ALNIsASCIIWhitespace((unsigned char)*cursor)) {
    cursor++;
  }
  const char *memberStart = cursor;
  while (*cursor != '\0' && *cursor != ',') {
    cursor++;
  }
  const char *memberEnd = cursor;
  while (memberEnd > memberStart &&
         ALNIsASCIIWhitespace((unsigned char)*(memberEnd - 1))) {
    memberEnd--;
  }
  if (memberEnd <= memberStart) {
    return NO;
  }
  size_t memberLength = (size_t)(memberEnd - memberStart);
  return ALNParseTraceparentMember(memberStart,
                                   memberLength,
                                   traceIDOut,
                                   parentSpanIDOut,
                                   flagsOut);
}

static BOOL ALNNormalizeTraceIDCandidate(NSString *value, char traceIDOut[33]) {
  if (traceIDOut == NULL) {
    return NO;
  }
  traceIDOut[0] = '\0';
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }

  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return NO;
  }

  const char *raw = [trimmed UTF8String];
  if (raw == NULL || raw[0] == '\0') {
    return NO;
  }

  size_t writeIndex = 0;
  const unsigned char *cursor = (const unsigned char *)raw;
  while (*cursor != '\0' && writeIndex < 32) {
    if (ALNIsASCIIHexCharacter(*cursor)) {
      traceIDOut[writeIndex++] = ALNLowerASCIIHexCharacter(*cursor);
    }
    cursor++;
  }
  if (writeIndex != 32) {
    traceIDOut[0] = '\0';
    return NO;
  }
  traceIDOut[32] = '\0';
  if (ALNAllHexCharactersAreZero(traceIDOut, 32)) {
    traceIDOut[0] = '\0';
    return NO;
  }
  return YES;
}

static void ALNFillRandomLowerHex(char *output, size_t hexLength) {
  if (output == NULL || hexLength == 0) {
    return;
  }

  size_t byteLength = (hexLength + 1) / 2;
  unsigned char randomBytes[32];
  if (byteLength > sizeof(randomBytes)) {
    output[0] = '\0';
    return;
  }
  arc4random_buf(randomBytes, byteLength);

  static const char *kHex = "0123456789abcdef";
  for (size_t idx = 0; idx < hexLength; idx++) {
    unsigned char byte = randomBytes[idx / 2];
    unsigned char nibble = (idx % 2 == 0) ? (unsigned char)((byte >> 4) & 0x0F)
                                          : (unsigned char)(byte & 0x0F);
    output[idx] = kHex[nibble];
  }
  output[hexLength] = '\0';
}

static NSString *ALNStringFromTraceBuffer(const char *value) {
  if (value == NULL || value[0] == '\0') {
    return @"";
  }
  NSString *stringValue = [NSString stringWithUTF8String:value];
  return [stringValue isKindOfClass:[NSString class]] ? stringValue : @"";
}

static ALNRequestTraceContext ALNBuildRequestTraceContext(ALNRequest *request,
                                                          BOOL tracePropagationEnabled) {
  ALNRequestTraceContext context;
  memset(&context, 0, sizeof(context));
  if (!tracePropagationEnabled) {
    return context;
  }

  context.enabled = YES;
  context.flags[0] = '0';
  context.flags[1] = '1';
  context.flags[2] = '\0';

  NSString *traceparentHeader = [request headerValueForName:@"traceparent"];
  if (ALNParseTraceparentHeader(traceparentHeader,
                                context.traceID,
                                context.parentSpanID,
                                context.flags)) {
    context.hasTraceID = YES;
    context.hasParentSpanID = YES;
  }

  if (!context.hasTraceID) {
    context.hasTraceID = ALNNormalizeTraceIDCandidate([request headerValueForName:@"x-trace-id"],
                                                      context.traceID);
  }

  if (!context.hasTraceID) {
    ALNFillRandomLowerHex(context.traceID, 32);
    context.hasTraceID = (context.traceID[0] != '\0');
  }

  ALNFillRandomLowerHex(context.spanID, 16);
  const char *flags = (context.flags[0] != '\0') ? context.flags : "01";
  (void)snprintf(context.traceparent,
                 sizeof(context.traceparent),
                 "00-%s-%s-%s",
                 context.traceID,
                 context.spanID,
                 flags);
  return context;
}

static BOOL ALNTraceContextHasTraceID(const ALNRequestTraceContext *context) {
  return (context != NULL && context->enabled && context->traceID[0] != '\0');
}

static BOOL ALNTraceContextHasParentSpanID(const ALNRequestTraceContext *context) {
  return (context != NULL && context->enabled && context->parentSpanID[0] != '\0');
}

static NSDictionary *ALNObservabilityConfig(ALNApplication *application) {
  return ALNDictionaryConfigValue(application.config, @"observability");
}

static BOOL ALNHealthDetailsEnabled(ALNApplication *application) {
  NSDictionary *observability = ALNObservabilityConfig(application);
  return ALNBoolConfigValue(observability[@"healthDetailsEnabled"], YES);
}

static BOOL ALNReadinessRequiresStartup(ALNApplication *application) {
  NSDictionary *observability = ALNObservabilityConfig(application);
  return ALNBoolConfigValue(observability[@"readinessRequiresStartup"], NO);
}

static BOOL ALNReadinessRequiresClusterQuorum(ALNApplication *application) {
  NSDictionary *observability = ALNObservabilityConfig(application);
  return ALNBoolConfigValue(observability[@"readinessRequiresClusterQuorum"], NO);
}

static NSString *ALNClusterCoordinationStatus(ALNApplication *application) {
  if (!application.clusterEnabled) {
    return @"single_node";
  }
  NSUInteger expectedNodes = (application.clusterExpectedNodes < 1) ? 1 : application.clusterExpectedNodes;
  NSUInteger observedNodes = application.clusterObservedNodes;
  if (observedNodes == 0) {
    return @"partitioned";
  }
  if (observedNodes < expectedNodes) {
    return @"degraded";
  }
  return @"nominal";
}

static BOOL ALNClusterQuorumMet(ALNApplication *application) {
  if (!application.clusterEnabled) {
    return YES;
  }
  NSUInteger expectedNodes = (application.clusterExpectedNodes < 1) ? 1 : application.clusterExpectedNodes;
  return application.clusterObservedNodes >= expectedNodes;
}

static NSDictionary *ALNClusterQuorumSummary(ALNApplication *application) {
  NSUInteger expectedNodes = (application.clusterExpectedNodes < 1) ? 1 : application.clusterExpectedNodes;
  NSUInteger observedNodes = application.clusterObservedNodes;
  return @{
    @"status" : ALNClusterCoordinationStatus(application),
    @"met" : @(ALNClusterQuorumMet(application)),
    @"observed_nodes" : @(observedNodes),
    @"expected_nodes" : @(expectedNodes),
  };
}

static NSDictionary *ALNTraceExportPayload(ALNPerfTrace *trace,
                                           NSString *requestID,
                                           const ALNRequestTraceContext *traceContext,
                                           ALNRequest *request,
                                           ALNResponse *response,
                                           NSString *routeName,
                                           NSString *controllerName,
                                           NSString *actionName) {
  NSMutableDictionary *payload =
      [NSMutableDictionary dictionaryWithDictionary:[trace dictionaryRepresentation] ?: @{}];
  payload[@"event"] = @"http.request.trace";
  payload[@"method"] = request.method ?: @"";
  payload[@"path"] = request.path ?: @"";
  payload[@"status"] = @(response.statusCode);
  payload[@"request_id"] = requestID ?: @"";
  payload[@"correlation_id"] = requestID ?: @"";
  payload[@"route"] = routeName ?: @"";
  payload[@"controller"] = controllerName ?: @"";
  payload[@"action"] = actionName ?: @"";

  if (ALNTraceContextHasTraceID(traceContext)) {
    payload[@"trace_id"] = ALNStringFromTraceBuffer(traceContext->traceID);
    if (traceContext->spanID[0] != '\0') {
      payload[@"span_id"] = ALNStringFromTraceBuffer(traceContext->spanID);
    }
    if (ALNTraceContextHasParentSpanID(traceContext)) {
      payload[@"parent_span_id"] = ALNStringFromTraceBuffer(traceContext->parentSpanID);
    }
    if (traceContext->traceparent[0] != '\0') {
      payload[@"traceparent"] = ALNStringFromTraceBuffer(traceContext->traceparent);
    }
  }
  return payload;
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

static NSString *ALNRequestPreferredFormatWithoutPathExtension(ALNRequest *request,
                                                               BOOL apiOnly,
                                                               NSString *resolvedPath) {
  NSString *accept = [[request headerValueForName:@"accept"] lowercaseString];
  if ([accept containsString:@"application/json"] || [accept containsString:@"text/json"]) {
    return @"json";
  }
  if ([accept containsString:@"text/html"] || [accept containsString:@"application/xhtml+xml"]) {
    return @"html";
  }

  NSString *path = ([resolvedPath isKindOfClass:[NSString class]] && [resolvedPath length] > 0)
                       ? resolvedPath
                       : (request.path ?: @"/");
  if (apiOnly || ALNPathLooksLikeAPI(path)) {
    return @"json";
  }
  return @"html";
}

static NSString *ALNRequestPreferredFormat(ALNRequest *request, BOOL apiOnly, NSString **strippedPath) {
  NSString *path = request.path ?: @"/";
  NSString *pathFormat = ALNExtractPathFormat(path, strippedPath);
  if ([pathFormat length] > 0) {
    return pathFormat;
  }
  NSString *resolvedPath = (strippedPath != NULL && [*strippedPath length] > 0)
                               ? *strippedPath
                               : path;
  return ALNRequestPreferredFormatWithoutPathExtension(request, apiOnly, resolvedPath);
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

static NSString *ALNHealthSignalNameForPath(NSString *path) {
  if ([path isEqualToString:@"/readyz"]) {
    return @"ready";
  }
  if ([path isEqualToString:@"/livez"]) {
    return @"live";
  }
  return @"health";
}

static NSDictionary *ALNOperationalSignalPayload(ALNApplication *application,
                                                 NSString *signal,
                                                 BOOL ok,
                                                 BOOL startupReady,
                                                 BOOL readinessRequiresStartup,
                                                 BOOL readinessRequiresClusterQuorum) {
  NSDictionary *metricsSnapshot = application.metricsEnabled ? [application.metrics snapshot] : @{};
  NSDictionary *gauges = [metricsSnapshot[@"gauges"] isKindOfClass:[NSDictionary class]]
                             ? metricsSnapshot[@"gauges"]
                             : @{};
  double activeRequests = [gauges[@"http_requests_active"] respondsToSelector:@selector(doubleValue)]
                              ? [gauges[@"http_requests_active"] doubleValue]
                              : 0.0;

  NSDate *uptimeAnchor = application.startedAt ?: application.bootedAt ?: [NSDate date];
  NSTimeInterval uptimeSeconds = [[NSDate date] timeIntervalSinceDate:uptimeAnchor];
  if (uptimeSeconds < 0.0) {
    uptimeSeconds = 0.0;
  }

  NSMutableDictionary *checks = [NSMutableDictionary dictionary];
  checks[@"request_dispatch"] = @{
    @"ok" : @(YES),
    @"mode" : @"in_process",
  };
  checks[@"metrics_registry"] = @{
    @"ok" : @(YES),
    @"source" : @"ALNMetricsRegistry",
    @"enabled" : @(application.metricsEnabled),
  };
  checks[@"active_requests"] = @{
    @"ok" : @(activeRequests >= 0.0),
    @"value" : @(activeRequests),
  };
  checks[@"startup"] = @{
    @"ok" : @(startupReady || !readinessRequiresStartup),
    @"started" : @(startupReady),
    @"required_for_readyz" : @(readinessRequiresStartup),
  };
  NSDictionary *quorumSummary = ALNClusterQuorumSummary(application);
  BOOL quorumMet = [quorumSummary[@"met"] respondsToSelector:@selector(boolValue)]
                       ? [quorumSummary[@"met"] boolValue]
                       : YES;
  BOOL quorumRequired = readinessRequiresClusterQuorum && application.clusterEnabled;
  checks[@"cluster_quorum"] = @{
    @"ok" : @(quorumMet || !quorumRequired),
    @"required_for_readyz" : @(quorumRequired),
    @"status" : quorumSummary[@"status"] ?: @"single_node",
    @"observed_nodes" : quorumSummary[@"observed_nodes"] ?: @(application.clusterObservedNodes),
    @"expected_nodes" : quorumSummary[@"expected_nodes"] ?: @(application.clusterExpectedNodes),
  };

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"ok"] = @(ok);
  payload[@"signal"] = signal ?: @"health";
  payload[@"status"] = ok ? ([signal isEqualToString:@"ready"] ? @"ready" : @"ok") : @"not_ready";
  payload[@"timestamp_utc"] = ALNISO8601Now();
  payload[@"uptime_seconds"] = @((NSInteger)floor(uptimeSeconds));
  payload[@"checks"] = checks;
  if ([signal isEqualToString:@"ready"]) {
    payload[@"ready"] = @(ok);
  }
  return payload;
}

static NSDictionary *ALNClusterStatusPayload(ALNApplication *application) {
  NSDictionary *session = ALNDictionaryConfigValue(application.config, @"session");
  BOOL sessionEnabled = ALNBoolConfigValue(session[@"enabled"], NO);
  BOOL sessionSecretConfigured =
      [ALNStringConfigValue(session[@"secret"], @"") length] > 0;
  NSDictionary *quorumSummary = ALNClusterQuorumSummary(application);

  return @{
    @"ok" : @(YES),
    @"cluster" : @{
      @"enabled" : @(application.clusterEnabled),
      @"name" : application.clusterName ?: @"default",
      @"node_id" : application.clusterNodeID ?: @"node",
      @"expected_nodes" : @(application.clusterExpectedNodes),
      @"observed_nodes" : @(application.clusterObservedNodes),
      @"worker_pid" : @((NSInteger)getpid()),
      @"mode" : application.clusterEnabled ? @"multi_node" : @"single_node",
      @"quorum" : quorumSummary,
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
    },
    @"coordination" : @{
      @"membership_source" : @"static_config",
      @"state" : quorumSummary[@"status"] ?: @"single_node",
      @"capability_matrix" : @{
        @"cross_node_request_routing" : @"external_load_balancer_required",
        @"cross_node_realtime_fanout" : @"external_broker_required",
        @"cross_node_jobs_deduplication" : @"external_queue_required",
        @"cross_node_cache_coherence" : @"external_cache_required",
      }
    }
  };
}

static BOOL ALNRequestMethodIsReadOnly(ALNRequest *request) {
  return [request.method isEqualToString:@"GET"] ||
         [request.method isEqualToString:@"HEAD"];
}

static BOOL ALNHeaderPrefersJSON(ALNRequest *request) {
  NSString *accept = [[request headerValueForName:@"accept"] lowercaseString];
  return [accept containsString:@"application/json"] ||
         [accept containsString:@"text/json"];
}

static BOOL ALNBuiltInEndpointPrefersJSON(ALNRequest *request) {
  if (ALNHeaderPrefersJSON(request)) {
    return YES;
  }
  NSString *format = [request.queryParams[@"format"] isKindOfClass:[NSString class]]
                         ? [request.queryParams[@"format"] lowercaseString]
                         : @"";
  return [format isEqualToString:@"json"];
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

  NSString *healthPath = routePath;
  NSString *healthBody = ALNBuiltInHealthBodyForPath(routePath);
  if ([healthBody length] == 0) {
    healthBody = ALNBuiltInHealthBodyForPath(requestPath);
    if ([healthBody length] > 0) {
      healthPath = requestPath;
    }
  }
  if ([healthBody length] > 0) {
    BOOL healthDetailsEnabled = ALNHealthDetailsEnabled(application);
    BOOL readinessRequiresStartup = ALNReadinessRequiresStartup(application);
    BOOL readinessRequiresClusterQuorum = ALNReadinessRequiresClusterQuorum(application);
    BOOL clusterQuorumMet = ALNClusterQuorumMet(application);
    NSString *signal = ALNHealthSignalNameForPath(healthPath);
    BOOL startupReady = application.isStarted;
    BOOL ready = YES;
    if ([signal isEqualToString:@"ready"]) {
      if (readinessRequiresStartup && !startupReady) {
        ready = NO;
      }
      if (ready && readinessRequiresClusterQuorum && application.clusterEnabled && !clusterQuorumMet) {
        ready = NO;
      }
    }
    response.statusCode = ready ? 200 : 503;

    BOOL prefersJSON = ALNBuiltInEndpointPrefersJSON(request);
    if (prefersJSON && healthDetailsEnabled) {
      NSDictionary *payload = ALNOperationalSignalPayload(application,
                                                          signal,
                                                          ready,
                                                          startupReady,
                                                          readinessRequiresStartup,
                                                          readinessRequiresClusterQuorum);
      NSError *jsonError = nil;
      BOOL ok = [response setJSONBody:payload options:0 error:&jsonError];
      if (!ok) {
        response.statusCode = 500;
        [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
        [response setTextBody:@"health status serialization failed\n"];
      } else if (headRequest) {
        [response.bodyData setLength:0];
      }
    } else {
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      if (!headRequest) {
        NSString *body = ready ? healthBody : @"not_ready\n";
        [response setTextBody:body];
      }
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
                                               id details) {
  NSMutableDictionary *errorObject = [NSMutableDictionary dictionary];
  errorObject[@"code"] = errorCode ?: @"internal_error";
  errorObject[@"message"] = message ?: @"Internal Server Error";
  errorObject[@"status"] = @(statusCode);
  errorObject[@"correlation_id"] = requestID ?: @"";
  errorObject[@"request_id"] = requestID ?: @"";

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"error"] = errorObject;
  NSArray *normalizedDetails = ALNNormalizedErrorDetailsArray(details);
  if ([normalizedDetails count] > 0) {
    payload[@"details"] = normalizedDetails;
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
    id structuredDetails = @[];
    if (!production && [details count] > 0) {
      structuredDetails = @[ ALNErrorDetailEntry(@"",
                                                 errorCode ?: @"internal_error",
                                                 developerMessage ?: publicMessage,
                                                 details ?: @{}) ];
    }
    NSDictionary *payload = ALNStructuredErrorPayload(statusCode,
                                                      errorCode,
                                                      publicMessage,
                                                      requestID,
                                                      structuredDetails);
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
    NSArray *scopes = ALNNormalizedUniqueStrings(requiredScopes);
    NSDictionary *meta = ([scopes count] > 0) ? @{ @"required_scopes" : scopes } : @{};
    NSArray *details = ([meta count] > 0)
                           ? @[ ALNErrorDetailEntry(@"auth",
                                                    @"unauthorized",
                                                    message ?: @"Unauthorized",
                                                    meta) ]
                           : @[];
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
    NSArray *structuredDetails =
        ([details count] > 0) ? @[ ALNErrorDetailEntry(@"auth",
                                                       @"forbidden",
                                                       message ?: @"Forbidden",
                                                       details ?: @{}) ]
                              : @[];
    NSDictionary *payload = ALNStructuredErrorPayload(403,
                                                      @"forbidden",
                                                      message ?: @"Forbidden",
                                                      requestID,
                                                      structuredDetails);
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
      payload = [ALNJSONSerialization JSONObjectWithData:response.bodyData
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
                                const ALNRequestTraceContext *traceContext,
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
    [response setHeader:@"X-Correlation-Id" value:requestID];
  }

  if (ALNTraceContextHasTraceID(traceContext)) {
    [response setHeader:@"X-Trace-Id" value:ALNStringFromTraceBuffer(traceContext->traceID)];
    if (traceContext->traceparent[0] != '\0') {
      [response setHeader:@"traceparent"
                    value:ALNStringFromTraceBuffer(traceContext->traceparent)];
    }
  }

  if (application.clusterEnabled && application.clusterEmitHeaders) {
    NSDictionary *quorumSummary = ALNClusterQuorumSummary(application);
    NSString *clusterStatus = [quorumSummary[@"status"] isKindOfClass:[NSString class]]
                                  ? quorumSummary[@"status"]
                                  : @"single_node";
    NSString *observedNodes =
        [quorumSummary[@"observed_nodes"] respondsToSelector:@selector(stringValue)]
            ? [quorumSummary[@"observed_nodes"] stringValue]
            : [NSString stringWithFormat:@"%lu", (unsigned long)application.clusterObservedNodes];
    NSString *expectedNodes =
        [quorumSummary[@"expected_nodes"] respondsToSelector:@selector(stringValue)]
            ? [quorumSummary[@"expected_nodes"] stringValue]
            : [NSString stringWithFormat:@"%lu", (unsigned long)application.clusterExpectedNodes];
    [response setHeader:@"X-Arlen-Cluster" value:application.clusterName ?: @"default"];
    [response setHeader:@"X-Arlen-Node" value:application.clusterNodeID ?: @"node"];
    [response setHeader:@"X-Arlen-Worker-Pid"
                  value:[NSString stringWithFormat:@"%d", (int)getpid()]];
    [response setHeader:@"X-Arlen-Cluster-Status" value:clusterStatus];
    [response setHeader:@"X-Arlen-Cluster-Observed-Nodes" value:observedNodes];
    [response setHeader:@"X-Arlen-Cluster-Expected-Nodes" value:expectedNodes];
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
  route.compiledActionSignature = nil;
  route.compiledGuardSignature = nil;
  route.compiledActionIMP = NULL;
  route.compiledGuardIMP = NULL;
  route.compiledActionReturnKind = ALNRouteInvocationReturnKindUnknown;
  route.compiledGuardReturnKind = ALNRouteInvocationReturnKindUnknown;
  route.compiledInvocationMetadata = NO;
  return YES;
}

- (BOOL)routingCompileOnStartEnabled {
  NSDictionary *routing = ALNRoutingConfig(self.config);
  return ALNBoolConfigValue(routing[@"compileOnStart"], YES);
}

- (BOOL)routingRouteCompileWarningsAsErrorsEnabled {
  NSDictionary *routing = ALNRoutingConfig(self.config);
  return ALNBoolConfigValue(routing[@"routeCompileWarningsAsErrors"], NO);
}

- (BOOL)compileRoute:(ALNRoute *)route
       controllerMap:(NSMutableDictionary *)controllerMap
    warningsAsErrors:(BOOL)warningsAsErrors
               error:(NSError **)error {
  if (route == nil) {
    return YES;
  }
  if (route.compiledInvocationMetadata) {
    return YES;
  }

  route.compiledActionSignature = nil;
  route.compiledGuardSignature = nil;
  route.compiledActionIMP = NULL;
  route.compiledGuardIMP = NULL;
  route.compiledActionReturnKind = ALNRouteInvocationReturnKindUnknown;
  route.compiledGuardReturnKind = ALNRouteInvocationReturnKindUnknown;
  route.compiledInvocationMetadata = NO;

  if (route.controllerClass == Nil) {
    if (error != NULL) {
      *error = ALNRouteCompileError(337,
                                    @"route_controller_invalid",
                                    @"route_compile_failed",
                                    @"Invalid route controller class",
                                    route,
                                    @[]);
    }
    return NO;
  }

  NSMutableDictionary *controllers = [controllerMap isKindOfClass:[NSMutableDictionary class]]
                                         ? controllerMap
                                         : [NSMutableDictionary dictionary];
  NSString *controllerKey = NSStringFromClass(route.controllerClass);
  id controller = controllers[controllerKey];
  if (controller == nil) {
    controller = [[route.controllerClass alloc] init];
    if (controller == nil) {
      if (error != NULL) {
        *error = ALNRouteCompileError(337,
                                      @"route_controller_uninstantiable",
                                      @"route_compile_failed",
                                      @"Controller could not be instantiated",
                                      route,
                                      @[]);
      }
      return NO;
    }
    controllers[controllerKey] = controller;
  }

  NSMethodSignature *actionSignature = [controller methodSignatureForSelector:route.actionSelector];
  Method actionMethod = class_getInstanceMethod(route.controllerClass, route.actionSelector);
  IMP actionIMP = (actionMethod != NULL) ? method_getImplementation(actionMethod) : NULL;
  ALNRouteInvocationReturnKind actionReturnKind = ALNReturnKindForSignature(actionSignature);
  BOOL actionSignatureValid = (actionSignature != nil &&
                               [actionSignature numberOfArguments] == 3 &&
                               actionIMP != NULL &&
                               (actionReturnKind == ALNRouteInvocationReturnKindVoid ||
                                actionReturnKind == ALNRouteInvocationReturnKindObject));
  if (!actionSignatureValid) {
    if (error != NULL) {
      *error = ALNRouteCompileError(333,
                                    @"route_action_signature_invalid",
                                    @"invalid_action_signature",
                                    @"Action must accept exactly one ALNContext * parameter and return object/void",
                                    route,
                                    @[]);
    }
    return NO;
  }

  NSMethodSignature *guardSignature = nil;
  IMP guardIMP = NULL;
  ALNRouteInvocationReturnKind guardReturnKind = ALNRouteInvocationReturnKindUnknown;
  if (route.guardSelector != NULL) {
    guardSignature = [controller methodSignatureForSelector:route.guardSelector];
    Method guardMethod = class_getInstanceMethod(route.controllerClass, route.guardSelector);
    guardIMP = (guardMethod != NULL) ? method_getImplementation(guardMethod) : NULL;
    guardReturnKind = ALNReturnKindForSignature(guardSignature);
    BOOL guardSignatureValid = (guardSignature != nil &&
                                [guardSignature numberOfArguments] == 3 &&
                                guardIMP != NULL &&
                                (guardReturnKind == ALNRouteInvocationReturnKindVoid ||
                                 guardReturnKind == ALNRouteInvocationReturnKindObject ||
                                 guardReturnKind == ALNRouteInvocationReturnKindBool));
    if (!guardSignatureValid) {
      if (error != NULL) {
        *error = ALNRouteCompileError(334,
                                      @"route_guard_signature_invalid",
                                      @"invalid_guard_signature",
                                      @"Guard must accept exactly one ALNContext * parameter and return bool/object/void",
                                      route,
                                      @[]);
      }
      return NO;
    }
  }

  NSMutableArray *diagnostics = [NSMutableArray array];
  [diagnostics addObjectsFromArray:ALNRouteSchemaDiagnosticsForSchema(route.requestSchema, @"request")];
  [diagnostics addObjectsFromArray:ALNRouteSchemaDiagnosticsForSchema(route.responseSchema, @"response")];

  NSMutableArray *errors = [NSMutableArray array];
  NSMutableArray *warnings = [NSMutableArray array];
  for (id value in diagnostics) {
    if (![value isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *diagnostic = (NSDictionary *)value;
    if (ALNCompileDiagnosticIsError(diagnostic)) {
      [errors addObject:diagnostic];
    } else {
      [warnings addObject:diagnostic];
    }
  }

  if ([errors count] > 0) {
    if (error != NULL) {
      *error = ALNRouteCompileError(335,
                                    @"route_schema_invalid",
                                    @"route_schema_not_ready",
                                    @"Route schema readiness validation failed",
                                    route,
                                    errors);
    }
    return NO;
  }

  if (warningsAsErrors && [warnings count] > 0) {
    if (error != NULL) {
      *error = ALNRouteCompileError(336,
                                    @"route_compile_warning",
                                    @"route_compile_warning",
                                    @"Route compile warning treated as error",
                                    route,
                                    warnings);
    }
    return NO;
  }

  if ([warnings count] > 0) {
    [self.logger warn:@"route compile warning"
               fields:@{
                 @"route_name" : route.name ?: @"",
                 @"route_path" : route.pathPattern ?: @"",
                 @"controller" : NSStringFromClass(route.controllerClass ?: [NSObject class]),
                 @"diagnostics" : warnings,
               }];
  }

  route.compiledActionSignature = actionSignature;
  route.compiledGuardSignature = guardSignature;
  route.compiledActionIMP = actionIMP;
  route.compiledGuardIMP = guardIMP;
  route.compiledActionReturnKind = actionReturnKind;
  route.compiledGuardReturnKind = guardReturnKind;
  route.compiledInvocationMetadata = YES;
  return YES;
}

- (BOOL)compileRegisteredRoutesWithWarningsAsErrors:(BOOL)warningsAsErrors
                                              error:(NSError **)error {
  NSMutableDictionary *controllerMap = [NSMutableDictionary dictionary];
  for (id value in [self.router allRoutes]) {
    if (![value isKindOfClass:[ALNRoute class]]) {
      continue;
    }
    NSError *routeError = nil;
    BOOL ok = [self compileRoute:(ALNRoute *)value
                    controllerMap:controllerMap
                 warningsAsErrors:warningsAsErrors
                            error:&routeError];
    if (!ok) {
      if (error != NULL) {
        *error = routeError;
      }
      return NO;
    }
  }
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
  NSData *json = [ALNJSONSerialization dataWithJSONObject:[self openAPISpecification]
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

  NSError *securityConfigError = ALNValidateSecurityConfiguration(self.config);
  if (securityConfigError != nil) {
    if (error != NULL) {
      *error = securityConfigError;
    }
    return NO;
  }

  if ([self routingCompileOnStartEnabled]) {
    NSError *routeCompileError = nil;
    BOOL compiled = [self compileRegisteredRoutesWithWarningsAsErrors:
                              [self routingRouteCompileWarningsAsErrorsEnabled]
                                                               error:&routeCompileError];
    if (!compiled) {
      if (error != NULL) {
        *error = routeCompileError;
      }
      return NO;
    }
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
  self.startedAt = [NSDate date];
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
  self.startedAt = nil;

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
  BOOL sessionMiddlewareActive = NO;
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
      sessionMiddlewareActive = YES;
    }
  }

  NSDictionary *csrf = ALNDictionaryConfigValue(self.config, @"csrf");
  BOOL csrfEnabled = ALNBoolConfigValue(csrf[@"enabled"], sessionEnabled);
  if (csrfEnabled) {
    if (!sessionMiddlewareActive) {
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

  BOOL performanceLogging = self.performanceLoggingEnabled;
  BOOL metricsEnabled = self.metricsEnabled;
  BOOL infoLoggingEnabled = [self.logger shouldLogLevel:ALNLogLevelInfo];
  ALNRequestTraceContext traceContext =
      ALNBuildRequestTraceContext(request, self.tracePropagationEnabled);
  BOOL apiOnly = self.apiOnly;
  ALNPerfTrace *trace =
      performanceLogging ? [[ALNPerfTrace alloc] initWithEnabled:YES] : ALNDisabledPerfTrace();
  if (performanceLogging) {
    [trace startStage:@"total"];
  }
  if (metricsEnabled) {
    [self.metrics addGauge:@"http_requests_active" delta:1.0];
  }

  NSString *routePath = request.path ?: @"/";
  NSString *requestFormat = nil;
  BOOL routerNeedsFormatExtraction = self.router.hasFormatConstrainedRoutes;
  if (routerNeedsFormatExtraction) {
    requestFormat = ALNRequestPreferredFormat(request, apiOnly, &routePath);
    if ([routePath length] == 0) {
      routePath = request.path ?: @"/";
    }
  }

  if (performanceLogging) {
    [trace startStage:@"route"];
  }
  NSString *retryStrippedPath = nil;
  NSString *retryPathFormat = nil;
  ALNRouteMatch *match =
      [self.router matchMethod:request.method ?: @"GET"
                          path:routePath
                        format:requestFormat];
  if (match == nil && !routerNeedsFormatExtraction) {
    retryPathFormat = ALNExtractPathFormat(routePath, &retryStrippedPath);
    if ([retryStrippedPath length] > 0 && ![retryStrippedPath isEqualToString:routePath]) {
      match = [self.router matchMethod:request.method ?: @"GET"
                                  path:retryStrippedPath
                                format:nil];
      if (match != nil) {
        routePath = retryStrippedPath;
        requestFormat = retryPathFormat;
      }
    }
  }
  if (performanceLogging) {
    [trace endStage:@"route"];
  }

  if (match == nil) {
    NSString *builtInPath = routePath;
    if (!routerNeedsFormatExtraction && [retryStrippedPath length] > 0) {
      builtInPath = retryStrippedPath;
    }
    if ([requestFormat length] == 0 && [retryPathFormat length] > 0) {
      requestFormat = retryPathFormat;
    }
    if ([requestFormat length] == 0) {
      requestFormat =
          ALNRequestPreferredFormatWithoutPathExtension(request, apiOnly, builtInPath);
    }
    BOOL prefersJSON = [requestFormat isEqualToString:@"json"];
    BOOL handledBuiltIn = ALNApplyBuiltInResponse(self, request, response, builtInPath);
    if (!handledBuiltIn && (apiOnly || prefersJSON)) {
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
    ALNFinalizeResponse(self,
                        response,
                        trace,
                        request,
                        requestID,
                        &traceContext,
                        performanceLogging);
    ALNRecordRequestMetrics(self, response, trace);
    if (metricsEnabled) {
      [self.metrics addGauge:@"http_requests_active" delta:-1.0];
    }

    if (self.traceExporter != nil) {
      @try {
        [self.traceExporter exportTrace:ALNTraceExportPayload(trace,
                                                              requestID,
                                                              &traceContext,
                                                              request,
                                                              response,
                                                              @"",
                                                              @"",
                                                              @"")
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

    if (infoLoggingEnabled) {
      NSMutableDictionary *fields = [NSMutableDictionary dictionary];
      fields[@"method"] = request.method ?: @"";
      fields[@"path"] = request.path ?: @"";
      fields[@"status"] = @(response.statusCode);
      fields[@"event"] = @"http.request.completed";
      fields[@"request_id"] = requestID ?: @"";
      fields[@"correlation_id"] = requestID ?: @"";
      if (ALNTraceContextHasTraceID(&traceContext)) {
        fields[@"trace_id"] = ALNStringFromTraceBuffer(traceContext.traceID);
        fields[@"span_id"] = ALNStringFromTraceBuffer(traceContext.spanID);
        if (ALNTraceContextHasParentSpanID(&traceContext)) {
          fields[@"parent_span_id"] = ALNStringFromTraceBuffer(traceContext.parentSpanID);
        }
        fields[@"traceparent"] = ALNStringFromTraceBuffer(traceContext.traceparent);
      }
      if (performanceLogging) {
        fields[@"timings"] = [trace dictionaryRepresentation];
      }
      [self.logger info:@"request" fields:fields];
    }
    return response;
  }

  if ([requestFormat length] == 0) {
    requestFormat = ALNRequestPreferredFormatWithoutPathExtension(request, apiOnly, routePath);
  }
  BOOL prefersJSON = [requestFormat isEqualToString:@"json"];

  NSMutableDictionary *stash = [NSMutableDictionary dictionaryWithCapacity:12];
  stash[@"request_id"] = requestID ?: @"";
  if (ALNTraceContextHasTraceID(&traceContext)) {
    stash[@"aln.trace_id"] = ALNStringFromTraceBuffer(traceContext.traceID);
    stash[@"aln.span_id"] = ALNStringFromTraceBuffer(traceContext.spanID);
    if (ALNTraceContextHasParentSpanID(&traceContext)) {
      stash[@"aln.parent_span_id"] = ALNStringFromTraceBuffer(traceContext.parentSpanID);
    }
    stash[@"aln.traceparent"] = ALNStringFromTraceBuffer(traceContext.traceparent);
  }
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
  stash[ALNContextEOCStrictLocalsStashKey] = @(self.eocStrictLocalsEnabled);
  stash[ALNContextEOCStrictStringifyStashKey] = @(self.eocStrictStringifyEnabled);
  stash[ALNContextPageStateEnabledStashKey] = @(self.pageStateEnabled);
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
  NSError *routeCompileError = nil;
  BOOL routeReady = YES;
  if (!match.route.compiledInvocationMetadata) {
    [self.routeCompilationLock lock];
    @try {
      routeReady = [self compileRoute:match.route
                         controllerMap:nil
                      warningsAsErrors:[self routingRouteCompileWarningsAsErrorsEnabled]
                                 error:&routeCompileError];
    } @finally {
      [self.routeCompilationLock unlock];
    }
  }
  if (!routeReady) {
    NSDictionary *details = ALNRouteCompileRuntimeDetails(routeCompileError);
    ALNApplyInternalErrorResponse(self,
                                  request,
                                  response,
                                  requestID,
                                  500,
                                  ALNRouteCompileResponseErrorCode(routeCompileError),
                                  @"Internal Server Error",
                                  routeCompileError.localizedDescription ?: @"route compile failed",
                                  details);
  }
  BOOL shouldDispatchController =
      routeReady &&
      ALNApplyRequestContractIfNeeded(self, request, response, context, match.route, requestID);
  NSMutableArray *executedMiddlewares = nil;
  if (shouldDispatchController && [self.mutableMiddlewares count] > 0) {
    executedMiddlewares = [NSMutableArray arrayWithCapacity:[self.mutableMiddlewares count]];
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
        BOOL guardInvocationOK = ALNInvokeRouteGuard(controller,
                                                     match.route,
                                                     context,
                                                     response,
                                                     self.runtimeInvocationModeKind,
                                                     &guardPassed);
        if (!guardInvocationOK) {
          NSDictionary *details = @{
            @"controller" : context.controllerName ?: @"",
            @"guard" : match.route.guardActionName ?: @"",
            @"reason" : @"Guard must accept exactly one ALNContext * parameter and return bool/object/void"
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
        }
      }

      if (!guardPassed && !response.committed) {
        if (apiOnly || prefersJSON) {
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
        BOOL actionInvocationOK = ALNInvokeRouteAction(controller,
                                                       match.route,
                                                       context,
                                                       self.runtimeInvocationModeKind,
                                                       &returnValue);
        if (!actionInvocationOK) {
          NSDictionary *details = @{
            @"controller" : context.controllerName ?: @"",
            @"action" : context.actionName ?: @"",
            @"reason" : @"Action must accept exactly one ALNContext * parameter and return object/void"
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
    } else if ([returnValue isKindOfClass:[NSData class]]) {
      if (response.statusCode == 0) {
        response.statusCode = 200;
      }
      NSString *existingContentType = [response headerForName:@"Content-Type"];
      [response setDataBody:returnValue
                contentType:[existingContentType length] > 0 ? existingContentType
                                                              : @"application/octet-stream"];
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

  ALNFinalizeResponse(self,
                      response,
                      trace,
                      request,
                      requestID,
                      &traceContext,
                      performanceLogging);
  ALNRecordRequestMetrics(self, response, trace);
  if (metricsEnabled) {
    [self.metrics addGauge:@"http_requests_active" delta:-1.0];
  }

  if (self.traceExporter != nil) {
    @try {
      [self.traceExporter exportTrace:ALNTraceExportPayload(trace,
                                                            requestID,
                                                            &traceContext,
                                                            request,
                                                            response,
                                                            context.routeName ?: @"",
                                                            context.controllerName ?: @"",
                                                            context.actionName ?: @"")
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

  if (infoLoggingEnabled) {
    NSMutableDictionary *logFields = [NSMutableDictionary dictionary];
    logFields[@"method"] = request.method ?: @"";
    logFields[@"path"] = request.path ?: @"";
    logFields[@"status"] = @(response.statusCode);
    logFields[@"event"] = @"http.request.completed";
    logFields[@"request_id"] = requestID ?: @"";
    logFields[@"correlation_id"] = requestID ?: @"";
    if (ALNTraceContextHasTraceID(&traceContext)) {
      logFields[@"trace_id"] = ALNStringFromTraceBuffer(traceContext.traceID);
      logFields[@"span_id"] = ALNStringFromTraceBuffer(traceContext.spanID);
      if (ALNTraceContextHasParentSpanID(&traceContext)) {
        logFields[@"parent_span_id"] = ALNStringFromTraceBuffer(traceContext.parentSpanID);
      }
      logFields[@"traceparent"] = ALNStringFromTraceBuffer(traceContext.traceparent);
    }
    logFields[@"route"] = context.routeName ?: @"";
    logFields[@"controller"] = context.controllerName ?: @"";
    logFields[@"action"] = context.actionName ?: @"";
    if (performanceLogging) {
      logFields[@"timings"] = [trace dictionaryRepresentation];
    }
    [self.logger info:@"request" fields:logFields];
  }

  return response;
}

@end
