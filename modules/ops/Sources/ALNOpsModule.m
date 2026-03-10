#import "ALNOpsModule.h"

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNMetrics.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNStorageModule.h"

NSString *const ALNOpsModuleErrorDomain = @"Arlen.Modules.Ops.Error";

static NSString *OTTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OTLowerTrimmedString(id value) {
  return [[OTTrimmedString(value) lowercaseString] copy];
}

static NSString *OTPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = OTTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/ops";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = OTTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *OTConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = OTTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/ops";
  }
  NSString *override = OTTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return OTPathJoin(prefix, override);
  }
  return OTPathJoin(prefix, defaultSuffix);
}

static NSError *OTError(ALNOpsModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"ops module error";
  return [NSError errorWithDomain:ALNOpsModuleErrorDomain code:code userInfo:userInfo];
}

static NSDictionary *OTJSONObjectFromData(NSData *data) {
  if ([data length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSString *OTPercentEncodedQueryComponent(NSString *value) {
  NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
  NSMutableCharacterSet *blocked = [allowed mutableCopy];
  [blocked removeCharactersInString:@"=&+?"];
  return [OTTrimmedString(value) stringByAddingPercentEncodingWithAllowedCharacters:blocked] ?: @"";
}

static NSArray *OTTailArray(NSArray *values, NSUInteger limit) {
  if (![values isKindOfClass:[NSArray class]] || [values count] == 0) {
    return @[];
  }
  if ([values count] <= limit) {
    return values;
  }
  return [values subarrayWithRange:NSMakeRange([values count] - limit, limit)];
}

static NSNumber *OTNumberValue(id value) {
  if ([value respondsToSelector:@selector(doubleValue)]) {
    return @([value doubleValue]);
  }
  return @0;
}

static BOOL OTRolesAllowAccess(NSArray *grantedRoles, NSArray *configuredRoles) {
  NSSet *granted = [NSSet setWithArray:[grantedRoles isKindOfClass:[NSArray class]] ? grantedRoles : @[]];
  for (NSString *role in [configuredRoles isKindOfClass:[NSArray class]] ? configuredRoles : @[]) {
    if ([granted containsObject:role]) {
      return YES;
    }
  }
  return NO;
}

@interface ALNOpsModuleRuntime ()

@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *accessRoles;
@property(nonatomic, assign, readwrite) NSUInteger minimumAuthAssuranceLevel;
@property(nonatomic, strong, readwrite, nullable) ALNApplication *application;
@property(nonatomic, copy) NSDictionary *moduleConfig;

@end

@interface ALNOpsModuleController : ALNController

@property(nonatomic, strong) ALNOpsModuleRuntime *runtime;
@property(nonatomic, strong) ALNAuthModuleRuntime *authRuntime;

@end

@implementation ALNOpsModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNOpsModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNOpsModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _prefix = @"/ops";
    _apiPrefix = @"/ops/api";
    _accessRoles = @[ @"operator", @"admin" ];
    _minimumAuthAssuranceLevel = 2;
    _moduleConfig = @{};
  }
  return self;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  if (application == nil) {
    if (error != NULL) {
      *error = OTError(ALNOpsModuleErrorInvalidConfiguration, @"ops module requires an application", nil);
    }
    return NO;
  }

  NSDictionary *moduleConfig =
      [application.config[@"opsModule"] isKindOfClass:[NSDictionary class]] ? application.config[@"opsModule"] : @{};
  NSDictionary *access = [moduleConfig[@"access"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"access"] : @{};
  NSArray *rawRoles = [access[@"roles"] isKindOfClass:[NSArray class]] ? access[@"roles"] : @[ @"operator", @"admin" ];
  NSMutableArray *roles = [NSMutableArray array];
  for (id value in rawRoles) {
    NSString *role = OTLowerTrimmedString(value);
    if ([role length] == 0 || [roles containsObject:role]) {
      continue;
    }
    [roles addObject:role];
  }
  if ([roles count] == 0) {
    [roles addObjectsFromArray:@[ @"operator", @"admin" ]];
  }

  self.application = application;
  self.moduleConfig = moduleConfig;
  self.prefix = OTConfiguredPath(moduleConfig, @"prefix", @"");
  self.apiPrefix = OTConfiguredPath(moduleConfig, @"apiPrefix", @"api");
  self.accessRoles = [NSArray arrayWithArray:roles];
  self.minimumAuthAssuranceLevel =
      [access[@"minimumAuthAssuranceLevel"] respondsToSelector:@selector(unsignedIntegerValue)]
          ? [access[@"minimumAuthAssuranceLevel"] unsignedIntegerValue]
          : 2;
  if (self.minimumAuthAssuranceLevel == 0) {
    self.minimumAuthAssuranceLevel = 2;
  }
  return YES;
}

- (NSDictionary *)resolvedConfigSummary {
  return @{
    @"prefix" : self.prefix ?: @"/ops",
    @"apiPrefix" : self.apiPrefix ?: @"/ops/api",
    @"accessRoles" : self.accessRoles ?: @[ @"operator", @"admin" ],
    @"minimumAuthAssuranceLevel" : @(self.minimumAuthAssuranceLevel),
  };
}

- (NSDictionary *)signalSummaryForPath:(NSString *)path {
  if (self.application == nil) {
    return @{
      @"path" : OTTrimmedString(path),
      @"statusCode" : @503,
      @"ok" : @NO,
      @"body" : @{ @"error" : @"application unavailable" },
    };
  }
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:OTTrimmedString(path)
                                               queryString:@""
                                                   headers:@{ @"Accept" : @"application/json", @"X-Arlen-Ops-Internal" : @"1" }
                                                      body:[NSData data]];
  ALNResponse *response = [self.application dispatchRequest:request];
  NSDictionary *body = OTJSONObjectFromData(response.bodyData);
  BOOL ok = (response.statusCode >= 200 && response.statusCode < 400);
  return @{
    @"path" : OTTrimmedString(path),
    @"statusCode" : @(response.statusCode),
    @"ok" : @(ok),
    @"body" : body ?: @{},
  };
}

- (NSDictionary *)metricsSummary {
  NSDictionary *snapshot = [self.application.metrics snapshot];
  NSDictionary *counters = [snapshot[@"counters"] isKindOfClass:[NSDictionary class]] ? snapshot[@"counters"] : @{};
  NSDictionary *gauges = [snapshot[@"gauges"] isKindOfClass:[NSDictionary class]] ? snapshot[@"gauges"] : @{};
  NSDictionary *timings = [snapshot[@"timings"] isKindOfClass:[NSDictionary class]] ? snapshot[@"timings"] : @{};

  double requestCount = [counters[@"http_requests_total"] respondsToSelector:@selector(doubleValue)]
                            ? [counters[@"http_requests_total"] doubleValue]
                            : 0.0;
  double errorCount = [counters[@"http_errors_total"] respondsToSelector:@selector(doubleValue)]
                          ? [counters[@"http_errors_total"] doubleValue]
                          : 0.0;
  double errorRate = (requestCount > 0.0) ? (errorCount / requestCount) : 0.0;
  NSDictionary *requestDuration = [timings[@"http_request_duration_ms"] isKindOfClass:[NSDictionary class]]
                                      ? timings[@"http_request_duration_ms"]
                                      : @{};

  return @{
    @"requestsTotal" : @(requestCount),
    @"errorsTotal" : @(errorCount),
    @"errorRate" : @(errorRate),
    @"requestDuration" : requestDuration ?: @{},
    @"countersCount" : @([counters count]),
    @"gaugesCount" : @([gauges count]),
    @"timingsCount" : @([timings count]),
    @"counterKeys" : [[counters allKeys] sortedArrayUsingSelector:@selector(compare:)] ?: @[],
  };
}

- (NSDictionary *)jobsSummary {
  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  if (runtime.application == nil) {
    return @{ @"available" : @NO };
  }
  NSDictionary *summary = [runtime dashboardSummary];
  return @{
    @"available" : @YES,
    @"totals" : [summary[@"totals"] isKindOfClass:[NSDictionary class]] ? summary[@"totals"] : @{},
    @"queues" : [summary[@"queues"] isKindOfClass:[NSArray class]] ? summary[@"queues"] : @[],
    @"recentRuns" : OTTailArray(summary[@"recentRuns"], 5),
  };
}

- (NSDictionary *)notificationsSummary {
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  if (runtime.application == nil) {
    return @{ @"available" : @NO };
  }
  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *cards = [summary[@"cards"] isKindOfClass:[NSArray class]] ? summary[@"cards"] : @[];
  NSArray *recent = [summary[@"recentOutbox"] isKindOfClass:[NSArray class]] ? summary[@"recentOutbox"] : @[];
  return @{
    @"available" : @YES,
    @"cards" : cards,
    @"recentOutbox" : OTTailArray(recent, 5),
  };
}

- (NSDictionary *)storageSummary {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  if (runtime.application == nil) {
    return @{ @"available" : @NO };
  }
  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *collections = [summary[@"collections"] isKindOfClass:[NSArray class]] ? summary[@"collections"] : @[];
  NSArray *recent = [summary[@"recentObjects"] isKindOfClass:[NSArray class]] ? summary[@"recentObjects"] : @[];
  return @{
    @"available" : @YES,
    @"cards" : [summary[@"cards"] isKindOfClass:[NSArray class]] ? summary[@"cards"] : @[],
    @"collections" : collections,
    @"recentObjects" : OTTailArray(recent, 5),
  };
}

- (NSDictionary *)searchSummary {
  Class runtimeClass = NSClassFromString(@"ALNSearchModuleRuntime");
  if (runtimeClass == Nil || ![runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    return @{ @"available" : @NO };
  }
  id (*sharedRuntimeIMP)(id, SEL) = (id (*)(id, SEL))[runtimeClass methodForSelector:@selector(sharedRuntime)];
  id runtime = sharedRuntimeIMP(runtimeClass, @selector(sharedRuntime));
  if (![runtime respondsToSelector:@selector(application)] || [runtime valueForKey:@"application"] == nil) {
    return @{ @"available" : @NO };
  }
  if (![runtime respondsToSelector:@selector(dashboardSummary)]) {
    return @{ @"available" : @NO };
  }
  NSDictionary *(*dashboardIMP)(id, SEL) = (NSDictionary *(*)(id, SEL))[runtime methodForSelector:@selector(dashboardSummary)];
  NSDictionary *summary = dashboardIMP(runtime, @selector(dashboardSummary));
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:summary ?: @{}];
  result[@"available"] = @YES;
  return result;
}

- (NSDictionary *)automationSummary {
  NSDictionary *spec = [self.application openAPISpecification];
  NSDictionary *paths = [spec[@"paths"] isKindOfClass:[NSDictionary class]] ? spec[@"paths"] : @{};
  NSDictionary *info = [spec[@"info"] isKindOfClass:[NSDictionary class]] ? spec[@"info"] : @{};
  return @{
    @"metricsPath" : @"/metrics",
    @"healthPath" : @"/healthz",
    @"readinessPath" : @"/readyz",
    @"livePath" : @"/livez",
    @"clusterPath" : @"/clusterz",
    @"openAPI" : @{
      @"title" : OTTrimmedString(info[@"title"]),
      @"version" : OTTrimmedString(info[@"version"]),
      @"pathCount" : @([paths count]),
    },
  };
}

- (NSDictionary *)dashboardSummary {
  NSDictionary *signals = @{
    @"health" : [self signalSummaryForPath:@"/healthz"],
    @"ready" : [self signalSummaryForPath:@"/readyz"],
    @"live" : [self signalSummaryForPath:@"/livez"],
  };
  NSDictionary *metrics = [self metricsSummary];
  NSDictionary *jobs = [self jobsSummary];
  NSDictionary *notifications = [self notificationsSummary];
  NSDictionary *storage = [self storageSummary];
  NSDictionary *search = [self searchSummary];
  NSArray *cards = @[
    @{ @"label" : @"Requests", @"value" : [[OTNumberValue(metrics[@"requestsTotal"]) stringValue] ?: @"0" copy] },
    @{ @"label" : @"Errors", @"value" : [[OTNumberValue(metrics[@"errorsTotal"]) stringValue] ?: @"0" copy] },
    @{ @"label" : @"Pending Jobs", @"value" : [[OTNumberValue(jobs[@"totals"][@"pending"]) stringValue] ?: @"0" copy] },
    @{ @"label" : @"Dead Letters", @"value" : [[OTNumberValue(jobs[@"totals"][@"deadLetters"]) stringValue] ?: @"0" copy] },
    @{ @"label" : @"Notifications", @"value" : [NSString stringWithFormat:@"%lu", (unsigned long)[notifications[@"recentOutbox"] count]] },
    @{ @"label" : @"Storage Objects", @"value" : [NSString stringWithFormat:@"%lu", (unsigned long)[storage[@"recentObjects"] count]] },
  ];
  return @{
    @"config" : [self resolvedConfigSummary],
    @"signals" : signals,
    @"metrics" : metrics,
    @"jobs" : jobs,
    @"notifications" : notifications,
    @"storage" : storage,
    @"search" : search,
    @"automation" : [self automationSummary],
    @"cards" : cards,
  };
}

@end

@implementation ALNOpsModuleController

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _runtime = [ALNOpsModuleRuntime sharedRuntime];
    _authRuntime = [ALNAuthModuleRuntime sharedRuntime];
  }
  return self;
}

- (NSString *)opsReturnPathForContext:(ALNContext *)ctx {
  NSString *path = OTTrimmedString(ctx.request.path);
  NSString *query = OTTrimmedString(ctx.request.queryString);
  if ([query length] > 0) {
    return [NSString stringWithFormat:@"%@?%@", path, query];
  }
  return ([path length] > 0) ? path : (self.runtime.prefix ?: @"/ops");
}

- (BOOL)opsRolesAllowContext:(ALNContext *)ctx {
  return OTRolesAllowAccess([ctx authRoles], self.runtime.accessRoles);
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                                 extra:(NSDictionary *)extra {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: @"Arlen Ops";
  context[@"pageHeading"] = heading ?: @"Operations";
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"opsPrefix"] = self.runtime.prefix ?: @"/ops";
  context[@"opsAPIPrefix"] = self.runtime.apiPrefix ?: @"/ops/api";
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"summary"] = [self.runtime dashboardSummary] ?: @{};
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extra];
  }
  return context;
}

- (void)renderAPIErrorWithStatus:(NSInteger)status
                            code:(NSString *)code
                         message:(NSString *)message
                            meta:(NSDictionary *)meta {
  [self setStatus:status];
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:meta ?: @{}];
  payload[@"code"] = code ?: @"error";
  payload[@"error"] = message ?: @"request rejected";
  [self renderJSONEnvelopeWithData:nil meta:payload error:NULL];
}

- (BOOL)requireOpsHTML:(ALNContext *)ctx {
  NSString *returnTo = [self opsReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    OTPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  if (![self opsRolesAllowContext:ctx]) {
    [self setStatus:403];
    [self renderTemplate:@"modules/ops/result/index"
                 context:[self pageContextWithTitle:@"Ops Access"
                                            heading:@"Access denied"
                                            message:@"You do not have the operator/admin role required for ops."
                                             errors:nil
                                              extra:nil]
                  layout:@"modules/ops/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < self.runtime.minimumAuthAssuranceLevel) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                                                    OTPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (BOOL)requireOpsAPI:(ALNContext *)ctx {
  if ([[ctx authSubject] length] == 0) {
    [self renderAPIErrorWithStatus:401
                              code:@"unauthorized"
                           message:@"Authentication required"
                              meta:nil];
    return NO;
  }
  if (![self opsRolesAllowContext:ctx]) {
    [self renderAPIErrorWithStatus:403
                              code:@"forbidden"
                           message:@"Missing operator/admin role"
                              meta:@{ @"required_roles_any" : self.runtime.accessRoles ?: @[] }];
    return NO;
  }
  if ([ctx authAssuranceLevel] < self.runtime.minimumAuthAssuranceLevel) {
    [self renderAPIErrorWithStatus:403
                              code:@"step_up_required"
                           message:@"Additional authentication assurance is required"
                              meta:@{
                                @"minimumAuthAssuranceLevel" : @(self.runtime.minimumAuthAssuranceLevel),
                                @"stepUpPath" : [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                              }];
    return NO;
  }
  return YES;
}

- (id)dashboard:(ALNContext *)ctx {
  (void)ctx;
  [self renderTemplate:@"modules/ops/dashboard/index"
               context:[self pageContextWithTitle:@"Operations"
                                          heading:@"Operations"
                                          message:@""
                                           errors:nil
                                            extra:nil]
                layout:@"modules/ops/layouts/main"
                 error:NULL];
  return nil;
}

- (id)apiSummary:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:[self.runtime dashboardSummary] meta:nil error:NULL];
  return nil;
}

- (id)apiSignals:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *summary = [self.runtime dashboardSummary];
  [self renderJSONEnvelopeWithData:@{ @"signals" : summary[@"signals"] ?: @{} } meta:nil error:NULL];
  return nil;
}

- (id)apiMetrics:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *summary = [self.runtime dashboardSummary];
  [self renderJSONEnvelopeWithData:@{
    @"metrics" : summary[@"metrics"] ?: @{},
    @"automation" : summary[@"automation"] ?: @{},
  }
                              meta:nil
                             error:NULL];
  return nil;
}

- (id)apiOpenAPI:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"openapi" : [self.runtime.application openAPISpecification] ?: @{} }
                              meta:nil
                             error:NULL];
  return nil;
}

@end

@implementation ALNOpsModule

- (NSString *)moduleIdentifier {
  return @"ops";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  ALNOpsModuleRuntime *runtime = [ALNOpsModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireOpsHTML" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/"
                              name:@"ops_dashboard"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"dashboard"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:@"requireOpsAPI" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/summary"
                              name:@"ops_api_summary"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"apiSummary"];
  [application registerRouteMethod:@"GET"
                              path:@"/signals"
                              name:@"ops_api_signals"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"apiSignals"];
  [application registerRouteMethod:@"GET"
                              path:@"/metrics"
                              name:@"ops_api_metrics"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"apiMetrics"];
  [application registerRouteMethod:@"GET"
                              path:@"/openapi"
                              name:@"ops_api_openapi"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"apiOpenAPI"];
  [application endRouteGroup];

  for (NSString *routeName in @[ @"ops_api_summary", @"ops_api_signals", @"ops_api_metrics", @"ops_api_openapi" ]) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Operations module API"
                         operationID:routeName
                                tags:@[ @"ops" ]
                      requiredScopes:nil
                       requiredRoles:nil
                     includeInOpenAPI:YES
                                error:NULL];
  }
  return YES;
}

@end
