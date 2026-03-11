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

static NSDictionary *OTNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSArray *OTNormalizeArray(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static id OTPropertyListValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *normalized = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      [normalized addObject:OTPropertyListValue(entry)];
    }
    return normalized;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
    for (id key in (NSDictionary *)value) {
      if (![key isKindOfClass:[NSString class]]) {
        continue;
      }
      normalized[key] = OTPropertyListValue(((NSDictionary *)value)[key]);
    }
    return normalized;
  }
  return OTTrimmedString([value description]);
}

static NSDictionary *OTReadPropertyListAtPath(NSString *path) {
  NSString *resolvedPath = OTTrimmedString(path);
  if ([resolvedPath length] == 0) {
    return @{};
  }
  NSData *data = [NSData dataWithContentsOfFile:resolvedPath];
  if ([data length] == 0) {
    return @{};
  }
  id object = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static BOOL OTWritePropertyListAtPath(NSString *path, NSDictionary *payload, NSError **error) {
  NSString *resolvedPath = OTTrimmedString(path);
  if ([resolvedPath length] == 0) {
    return YES;
  }
  NSString *directory = [resolvedPath stringByDeletingLastPathComponent];
  if ([directory length] > 0 &&
      ![[NSFileManager defaultManager] fileExistsAtPath:directory] &&
      ![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
    return NO;
  }
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:OTPropertyListValue(payload ?: @{})
                                                            format:NSPropertyListXMLFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return [data writeToFile:resolvedPath options:NSDataWritingAtomic error:error];
}

static NSString *OTResolvedStatus(id value, NSString *fallback) {
  NSString *status = OTLowerTrimmedString(value);
  NSSet *allowed = [NSSet setWithArray:@[ @"healthy", @"degraded", @"failing", @"informational" ]];
  if ([allowed containsObject:status]) {
    return status;
  }
  return ([OTLowerTrimmedString(fallback) length] > 0) ? OTLowerTrimmedString(fallback) : @"informational";
}

static NSDictionary *OTStatusCard(NSString *label, NSString *value, NSString *status, NSString *href, NSString *summary) {
  NSMutableDictionary *card = [NSMutableDictionary dictionary];
  card[@"label"] = label ?: @"Metric";
  card[@"value"] = value ?: @"0";
  card[@"status"] = OTResolvedStatus(status, @"informational");
  if ([OTTrimmedString(href) length] > 0) {
    card[@"href"] = OTTrimmedString(href);
  }
  if ([OTTrimmedString(summary) length] > 0) {
    card[@"summary"] = OTTrimmedString(summary);
  }
  return card;
}

static NSDictionary *OTStatusWidget(NSString *title, NSString *value, NSString *body, NSString *status, NSString *href) {
  NSMutableDictionary *widget = [NSMutableDictionary dictionary];
  widget[@"title"] = title ?: @"Widget";
  widget[@"status"] = OTResolvedStatus(status, @"informational");
  if ([OTTrimmedString(value) length] > 0) {
    widget[@"value"] = OTTrimmedString(value);
  }
  if ([OTTrimmedString(body) length] > 0) {
    widget[@"body"] = OTTrimmedString(body);
  }
  if ([OTTrimmedString(href) length] > 0) {
    widget[@"href"] = OTTrimmedString(href);
  }
  return widget;
}

static NSString *OTSignalStatus(NSDictionary *signal) {
  NSInteger statusCode = [signal[@"statusCode"] respondsToSelector:@selector(integerValue)] ? [signal[@"statusCode"] integerValue] : 0;
  if (statusCode == 0 || statusCode >= 500) {
    return @"failing";
  }
  if (statusCode >= 400) {
    return @"degraded";
  }
  return @"healthy";
}

static NSString *OTJobsStatus(NSDictionary *summary) {
  if (![summary[@"available"] boolValue]) {
    return @"informational";
  }
  NSDictionary *totals = OTNormalizeDictionary(summary[@"totals"]);
  if ([totals[@"deadLetters"] integerValue] > 0) {
    return @"failing";
  }
  for (NSDictionary *queue in OTNormalizeArray(summary[@"queues"])) {
    if ([queue[@"paused"] boolValue]) {
      return @"degraded";
    }
  }
  return @"healthy";
}

static NSString *OTNotificationsStatus(NSDictionary *summary) {
  if (![summary[@"available"] boolValue]) {
    return @"informational";
  }
  for (NSDictionary *entry in OTNormalizeArray(summary[@"recentOutbox"])) {
    NSString *state = OTLowerTrimmedString(entry[@"state"]);
    if ([state isEqualToString:@"failed"]) {
      return @"degraded";
    }
  }
  return @"healthy";
}

static NSString *OTStorageStatus(NSDictionary *summary) {
  if (![summary[@"available"] boolValue]) {
    return @"informational";
  }
  for (NSDictionary *entry in OTNormalizeArray(summary[@"recentActivity"])) {
    if ([OTLowerTrimmedString(entry[@"name"]) containsString:@"failed"]) {
      return @"degraded";
    }
  }
  for (NSDictionary *record in OTNormalizeArray(summary[@"recentObjects"])) {
    if ([OTLowerTrimmedString(record[@"variantState"]) isEqualToString:@"failed"]) {
      return @"degraded";
    }
  }
  return @"healthy";
}

static NSString *OTSearchStatus(NSDictionary *summary) {
  if (![summary[@"available"] boolValue]) {
    return @"informational";
  }
  return OTResolvedStatus(summary[@"status"], @"healthy");
}

static NSString *OTOverallStatus(NSDictionary *signals,
                                 NSDictionary *jobs,
                                 NSDictionary *notifications,
                                 NSDictionary *storage,
                                 NSDictionary *search,
                                 NSDictionary *metrics) {
  for (NSDictionary *signal in @[ signals[@"health"] ?: @{}, signals[@"ready"] ?: @{}, signals[@"live"] ?: @{} ]) {
    NSString *status = OTSignalStatus(signal);
    if ([status isEqualToString:@"failing"]) {
      return @"failing";
    }
    if ([status isEqualToString:@"degraded"]) {
      return @"degraded";
    }
  }
  for (NSString *status in @[ OTJobsStatus(jobs), OTNotificationsStatus(notifications), OTStorageStatus(storage), OTSearchStatus(search) ]) {
    if ([status isEqualToString:@"failing"]) {
      return @"failing";
    }
    if ([status isEqualToString:@"degraded"]) {
      return @"degraded";
    }
  }
  double errorRate = [metrics[@"errorRate"] respondsToSelector:@selector(doubleValue)] ? [metrics[@"errorRate"] doubleValue] : 0.0;
  if (errorRate >= 0.1) {
    return @"degraded";
  }
  return @"healthy";
}

static NSUInteger const ALNOpsSnapshotHistoryLimit = 48U;

@interface ALNOpsModuleRuntime ()

@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *accessRoles;
@property(nonatomic, assign, readwrite) NSUInteger minimumAuthAssuranceLevel;
@property(nonatomic, strong, readwrite, nullable) ALNApplication *application;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *historySnapshots;
@property(nonatomic, strong) NSArray<id<ALNOpsCardProvider>> *cardProviders;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, copy) NSString *statePath;
@property(nonatomic, strong) NSLock *lock;

- (BOOL)loadPersistedStateWithError:(NSError **)error;
- (BOOL)persistStateWithError:(NSError **)error;
- (NSArray<NSString *> *)configuredCardProviderClassNames;
- (BOOL)loadCardProvidersWithError:(NSError **)error;
- (NSArray<NSDictionary *> *)contributedCardsWithError:(NSError **)error;
- (NSArray<NSDictionary *> *)contributedWidgetsWithError:(NSError **)error;
- (NSDictionary *)recordSnapshotFromSummary:(NSDictionary *)summary;

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
    _historySnapshots = [NSMutableArray array];
    _cardProviders = @[];
    _persistenceEnabled = NO;
    _statePath = @"";
    _lock = [[NSLock alloc] init];
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
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"persistence"] : @{};
  self.statePath = OTTrimmedString(persistence[@"path"]);
  self.persistenceEnabled = ([self.statePath length] > 0);
  [self.lock lock];
  [self.historySnapshots removeAllObjects];
  [self.lock unlock];
  if (![self loadCardProvidersWithError:error]) {
    return NO;
  }
  if (![self loadPersistedStateWithError:error]) {
    return NO;
  }
  return [self persistStateWithError:error];
}

- (NSDictionary *)resolvedConfigSummary {
  return @{
    @"prefix" : self.prefix ?: @"/ops",
    @"apiPrefix" : self.apiPrefix ?: @"/ops/api",
    @"accessRoles" : self.accessRoles ?: @[ @"operator", @"admin" ],
    @"minimumAuthAssuranceLevel" : @(self.minimumAuthAssuranceLevel),
    @"persistenceEnabled" : @(self.persistenceEnabled),
    @"statePath" : self.statePath ?: @"",
    @"cardProviderCount" : @([self.cardProviders count]),
  };
}

- (NSArray<NSString *> *)configuredCardProviderClassNames {
  NSDictionary *providers = [self.moduleConfig[@"cardProviders"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"cardProviders"] : @{};
  NSArray *rawClasses = [providers[@"classes"] isKindOfClass:[NSArray class]] ? providers[@"classes"] : @[];
  NSMutableArray *classNames = [NSMutableArray array];
  for (id entry in rawClasses) {
    NSString *className = OTTrimmedString(entry);
    if ([className length] == 0 || [classNames containsObject:className]) {
      continue;
    }
    [classNames addObject:className];
  }
  return [NSArray arrayWithArray:classNames];
}

- (BOOL)loadCardProvidersWithError:(NSError **)error {
  NSMutableArray *providers = [NSMutableArray array];
  for (NSString *className in [self configuredCardProviderClassNames]) {
    Class klass = NSClassFromString(className);
    if (klass == Nil) {
      if (error != NULL) {
        *error = OTError(ALNOpsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"ops card provider class %@ could not be resolved", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    if (![klass conformsToProtocol:@protocol(ALNOpsCardProvider)]) {
      if (error != NULL) {
        *error = OTError(ALNOpsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"%@ must conform to ALNOpsCardProvider", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    [providers addObject:[[klass alloc] init]];
  }
  self.cardProviders = [NSArray arrayWithArray:providers];
  return YES;
}

- (BOOL)loadPersistedStateWithError:(NSError **)error {
  (void)error;
  if (!self.persistenceEnabled) {
    return YES;
  }
  NSDictionary *payload = OTReadPropertyListAtPath(self.statePath);
  [self.lock lock];
  self.historySnapshots = ([OTNormalizeArray(payload[@"historySnapshots"]) mutableCopy] ?: [NSMutableArray array]);
  while ([self.historySnapshots count] > ALNOpsSnapshotHistoryLimit) {
    [self.historySnapshots removeObjectAtIndex:0];
  }
  [self.lock unlock];
  return YES;
}

- (BOOL)persistStateWithError:(NSError **)error {
  if (!self.persistenceEnabled) {
    return YES;
  }
  NSDictionary *payload = nil;
  [self.lock lock];
  payload = @{
    @"historySnapshots" : [NSArray arrayWithArray:self.historySnapshots ?: @[]],
  };
  [self.lock unlock];
  return OTWritePropertyListAtPath(self.statePath, payload, error);
}

- (NSArray<NSDictionary *> *)contributedCardsWithError:(NSError **)error {
  NSMutableArray *cards = [NSMutableArray array];
  for (id<ALNOpsCardProvider> provider in self.cardProviders ?: @[]) {
    NSError *providerError = nil;
    NSArray *entries = [provider opsModuleCardsForRuntime:self error:&providerError];
    if (entries == nil && providerError != nil) {
      if (error != NULL) {
        *error = providerError;
      }
      continue;
    }
    for (NSDictionary *entry in OTNormalizeArray(entries)) {
      NSString *label = OTTrimmedString(entry[@"label"]);
      NSString *value = OTTrimmedString([entry[@"value"] description]);
      if ([label length] == 0 || [value length] == 0) {
        continue;
      }
      [cards addObject:OTStatusCard(label, value, entry[@"status"], entry[@"href"], entry[@"summary"])];
    }
  }
  return [NSArray arrayWithArray:cards];
}

- (NSArray<NSDictionary *> *)contributedWidgetsWithError:(NSError **)error {
  NSMutableArray *widgets = [NSMutableArray array];
  for (id<ALNOpsCardProvider> provider in self.cardProviders ?: @[]) {
    if (![provider respondsToSelector:@selector(opsModuleWidgetsForRuntime:error:)]) {
      continue;
    }
    NSError *providerError = nil;
    NSArray *entries = [provider opsModuleWidgetsForRuntime:self error:&providerError];
    if (entries == nil && providerError != nil) {
      if (error != NULL) {
        *error = providerError;
      }
      continue;
    }
    for (NSDictionary *entry in OTNormalizeArray(entries)) {
      NSString *title = OTTrimmedString(entry[@"title"]);
      NSString *value = OTTrimmedString([entry[@"value"] description]);
      NSString *body = OTTrimmedString(entry[@"body"]);
      if ([title length] == 0 || ([value length] == 0 && [body length] == 0)) {
        continue;
      }
      [widgets addObject:OTStatusWidget(title, value, body, entry[@"status"], entry[@"href"])];
    }
  }
  return [NSArray arrayWithArray:widgets];
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
  if (runtime.application == nil || runtime.application != self.application) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  NSDictionary *summary = [runtime dashboardSummary];
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
    @"available" : @YES,
    @"totals" : [summary[@"totals"] isKindOfClass:[NSDictionary class]] ? summary[@"totals"] : @{},
    @"queues" : [summary[@"queues"] isKindOfClass:[NSArray class]] ? summary[@"queues"] : @[],
    @"recentRuns" : OTTailArray(summary[@"recentRuns"], 5),
    @"pendingJobs" : [runtime pendingJobs] ?: @[],
    @"leasedJobs" : [runtime leasedJobs] ?: @[],
    @"deadLetterJobs" : [runtime deadLetterJobs] ?: @[],
  }];
  result[@"status"] = OTJobsStatus(result);
  return result;
}

- (NSDictionary *)notificationsSummary {
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  if (runtime.application == nil || runtime.application != self.application) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *cards = [summary[@"cards"] isKindOfClass:[NSArray class]] ? summary[@"cards"] : @[];
  NSArray *recent = [summary[@"recentOutbox"] isKindOfClass:[NSArray class]] ? summary[@"recentOutbox"] : @[];
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
    @"available" : @YES,
    @"cards" : cards,
    @"recentOutbox" : OTTailArray(recent, 5),
    @"recentFanout" : [summary[@"recentFanout"] isKindOfClass:[NSArray class]] ? summary[@"recentFanout"] : @[],
  }];
  result[@"status"] = OTNotificationsStatus(result);
  return result;
}

- (NSDictionary *)storageSummary {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  if (runtime.application == nil || runtime.application != self.application) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *collections = [summary[@"collections"] isKindOfClass:[NSArray class]] ? summary[@"collections"] : @[];
  NSArray *recent = [summary[@"recentObjects"] isKindOfClass:[NSArray class]] ? summary[@"recentObjects"] : @[];
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
    @"available" : @YES,
    @"cards" : [summary[@"cards"] isKindOfClass:[NSArray class]] ? summary[@"cards"] : @[],
    @"collections" : collections,
    @"recentObjects" : OTTailArray(recent, 5),
    @"recentActivity" : [summary[@"recentActivity"] isKindOfClass:[NSArray class]] ? summary[@"recentActivity"] : @[],
    @"attachmentAdapter" : [summary[@"attachmentAdapter"] isKindOfClass:[NSDictionary class]] ? summary[@"attachmentAdapter"] : @{},
  }];
  result[@"status"] = OTStorageStatus(result);
  return result;
}

- (NSDictionary *)searchSummary {
  Class runtimeClass = NSClassFromString(@"ALNSearchModuleRuntime");
  if (runtimeClass == Nil || ![runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  id (*sharedRuntimeIMP)(id, SEL) = (id (*)(id, SEL))[runtimeClass methodForSelector:@selector(sharedRuntime)];
  id runtime = sharedRuntimeIMP(runtimeClass, @selector(sharedRuntime));
  if (![runtime respondsToSelector:@selector(application)]) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  ALNApplication *mountedApplication = [runtime valueForKey:@"application"];
  if (mountedApplication == nil || mountedApplication != self.application) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  if (![runtime respondsToSelector:@selector(dashboardSummary)]) {
    return @{ @"available" : @NO, @"status" : @"informational" };
  }
  NSDictionary *(*dashboardIMP)(id, SEL) = (NSDictionary *(*)(id, SEL))[runtime methodForSelector:@selector(dashboardSummary)];
  NSDictionary *summary = dashboardIMP(runtime, @selector(dashboardSummary));
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:summary ?: @{}];
  result[@"available"] = @YES;
  result[@"status"] = OTSearchStatus(result);
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

- (NSDictionary *)recordSnapshotFromSummary:(NSDictionary *)summary {
  NSDictionary *jobs = OTNormalizeDictionary(summary[@"jobs"]);
  NSDictionary *notifications = OTNormalizeDictionary(summary[@"notifications"]);
  NSDictionary *storage = OTNormalizeDictionary(summary[@"storage"]);
  NSDictionary *search = OTNormalizeDictionary(summary[@"search"]);
  NSDictionary *metrics = OTNormalizeDictionary(summary[@"metrics"]);
  NSDictionary *snapshot = @{
    @"recordedAt" : @([[NSDate date] timeIntervalSince1970]),
    @"overallStatus" : OTResolvedStatus(summary[@"status"], @"healthy"),
    @"jobs" : @{
      @"status" : OTResolvedStatus(jobs[@"status"], @"informational"),
      @"pending" : jobs[@"totals"][@"pending"] ?: @0,
      @"deadLetters" : jobs[@"totals"][@"deadLetters"] ?: @0,
    },
    @"notifications" : @{
      @"status" : OTResolvedStatus(notifications[@"status"], @"informational"),
      @"recentOutboxCount" : @([OTNormalizeArray(notifications[@"recentOutbox"]) count]),
    },
    @"storage" : @{
      @"status" : OTResolvedStatus(storage[@"status"], @"informational"),
      @"recentObjectCount" : @([OTNormalizeArray(storage[@"recentObjects"]) count]),
    },
    @"search" : @{
      @"status" : OTResolvedStatus(search[@"status"], @"informational"),
      @"documents" : search[@"totals"][@"documents"] ?: @0,
      @"resources" : search[@"totals"][@"resources"] ?: @0,
    },
    @"metrics" : @{
      @"requestsTotal" : metrics[@"requestsTotal"] ?: @0,
      @"errorsTotal" : metrics[@"errorsTotal"] ?: @0,
      @"errorRate" : metrics[@"errorRate"] ?: @0,
    },
  };
  [self.lock lock];
  [self.historySnapshots addObject:snapshot];
  while ([self.historySnapshots count] > ALNOpsSnapshotHistoryLimit) {
    [self.historySnapshots removeObjectAtIndex:0];
  }
  [self.lock unlock];
  (void)[self persistStateWithError:NULL];
  return snapshot;
}

- (nullable NSDictionary *)moduleDrilldownForIdentifier:(NSString *)identifier {
  NSString *moduleID = OTLowerTrimmedString(identifier);
  NSDictionary *summary = [self dashboardSummary];
  NSDictionary *moduleSummary = nil;
  NSString *label = @"";
  if ([moduleID isEqualToString:@"jobs"]) {
    moduleSummary = summary[@"jobs"];
    label = @"Jobs";
  } else if ([moduleID isEqualToString:@"notifications"]) {
    moduleSummary = summary[@"notifications"];
    label = @"Notifications";
  } else if ([moduleID isEqualToString:@"storage"]) {
    moduleSummary = summary[@"storage"];
    label = @"Storage";
  } else if ([moduleID isEqualToString:@"search"]) {
    moduleSummary = summary[@"search"];
    label = @"Search";
  } else {
    return nil;
  }
  NSMutableArray *history = [NSMutableArray array];
  [self.lock lock];
  for (NSDictionary *entry in self.historySnapshots ?: @[]) {
    NSDictionary *moduleEntry = [entry[moduleID] isKindOfClass:[NSDictionary class]] ? entry[moduleID] : nil;
    if (moduleEntry == nil) {
      continue;
    }
    [history addObject:@{
      @"recordedAt" : entry[@"recordedAt"] ?: @0,
      @"overallStatus" : entry[@"overallStatus"] ?: @"informational",
      @"module" : moduleEntry,
    }];
  }
  [self.lock unlock];
  return @{
    @"identifier" : moduleID,
    @"label" : label,
    @"status" : OTResolvedStatus(moduleSummary[@"status"], @"informational"),
    @"summary" : moduleSummary ?: @{},
    @"history" : history ?: @[],
    @"paths" : @{
      @"html" : [NSString stringWithFormat:@"%@/modules/%@", self.prefix ?: @"/ops", moduleID ?: @""],
      @"api" : [NSString stringWithFormat:@"%@/modules/%@", self.apiPrefix ?: @"/ops/api", moduleID ?: @""],
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
  NSDictionary *automation = [self automationSummary];
  NSString *overallStatus = OTOverallStatus(signals, jobs, notifications, storage, search, metrics);
  NSMutableArray *cards = [NSMutableArray arrayWithArray:@[
    OTStatusCard(@"Requests",
                 [[OTNumberValue(metrics[@"requestsTotal"]) stringValue] ?: @"0" copy],
                 @"informational",
                 @"",
                 @""),
    OTStatusCard(@"Errors",
                 [[OTNumberValue(metrics[@"errorsTotal"]) stringValue] ?: @"0" copy],
                 ([OTNumberValue(metrics[@"errorsTotal"]) integerValue] > 0) ? @"degraded" : @"healthy",
                 @"",
                 @""),
    OTStatusCard(@"Jobs",
                 [[OTNumberValue(jobs[@"totals"][@"pending"]) stringValue] ?: @"0" copy],
                 jobs[@"status"],
                 [NSString stringWithFormat:@"%@/modules/jobs", self.prefix ?: @"/ops"],
                 @"pending jobs"),
    OTStatusCard(@"Notifications",
                 [NSString stringWithFormat:@"%lu", (unsigned long)[OTNormalizeArray(notifications[@"recentOutbox"]) count]],
                 notifications[@"status"],
                 [NSString stringWithFormat:@"%@/modules/notifications", self.prefix ?: @"/ops"],
                 @"recent outbox"),
    OTStatusCard(@"Storage",
                 [NSString stringWithFormat:@"%lu", (unsigned long)[OTNormalizeArray(storage[@"recentObjects"]) count]],
                 storage[@"status"],
                 [NSString stringWithFormat:@"%@/modules/storage", self.prefix ?: @"/ops"],
                 @"recent objects"),
    OTStatusCard(@"Search",
                 [[OTNumberValue(search[@"totals"][@"documents"]) stringValue] ?: @"0" copy],
                 search[@"status"],
                 [NSString stringWithFormat:@"%@/modules/search", self.prefix ?: @"/ops"],
                 @"indexed documents"),
  ]];
  NSError *providerError = nil;
  [cards addObjectsFromArray:[self contributedCardsWithError:&providerError] ?: @[]];
  NSError *widgetProviderError = nil;
  NSArray *widgets = [self contributedWidgetsWithError:&widgetProviderError] ?: @[];
  NSError *resolvedProviderError = providerError ?: widgetProviderError;
  NSDictionary *summary = @{
    @"config" : [self resolvedConfigSummary],
    @"signals" : signals,
    @"metrics" : metrics,
    @"jobs" : jobs,
    @"notifications" : notifications,
    @"storage" : storage,
    @"search" : search,
    @"automation" : automation,
    @"status" : overallStatus ?: @"healthy",
    @"providerError" : (resolvedProviderError != nil) ? (resolvedProviderError.localizedDescription ?: @"provider error") : @"",
    @"drilldowns" : @{
      @"jobs" : @{
        @"html" : [NSString stringWithFormat:@"%@/modules/jobs", self.prefix ?: @"/ops"],
        @"api" : [NSString stringWithFormat:@"%@/modules/jobs", self.apiPrefix ?: @"/ops/api"],
      },
      @"notifications" : @{
        @"html" : [NSString stringWithFormat:@"%@/modules/notifications", self.prefix ?: @"/ops"],
        @"api" : [NSString stringWithFormat:@"%@/modules/notifications", self.apiPrefix ?: @"/ops/api"],
      },
      @"storage" : @{
        @"html" : [NSString stringWithFormat:@"%@/modules/storage", self.prefix ?: @"/ops"],
        @"api" : [NSString stringWithFormat:@"%@/modules/storage", self.apiPrefix ?: @"/ops/api"],
      },
      @"search" : @{
        @"html" : [NSString stringWithFormat:@"%@/modules/search", self.prefix ?: @"/ops"],
        @"api" : [NSString stringWithFormat:@"%@/modules/search", self.apiPrefix ?: @"/ops/api"],
      },
    },
    @"cards" : cards,
    @"widgets" : widgets,
  };
  [self recordSnapshotFromSummary:summary];
  [self.lock lock];
  NSArray *history = [NSArray arrayWithArray:self.historySnapshots ?: @[]];
  [self.lock unlock];
  NSMutableDictionary *response = [summary mutableCopy];
  response[@"history"] = history ?: @[];
  return response;
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

- (id)moduleDrilldown:(ALNContext *)ctx {
  NSString *identifier = OTLowerTrimmedString([ctx paramValueForName:@"module"]);
  NSDictionary *drilldown = [self.runtime moduleDrilldownForIdentifier:identifier];
  if (drilldown == nil) {
    [self setStatus:404];
    [self renderTemplate:@"modules/ops/result/index"
                 context:[self pageContextWithTitle:@"Ops Module"
                                            heading:@"Module not found"
                                            message:@"The requested ops drilldown is not available."
                                             errors:nil
                                              extra:nil]
                  layout:@"modules/ops/layouts/main"
                   error:NULL];
    return nil;
  }
  [self renderTemplate:@"modules/ops/drilldown/index"
               context:[self pageContextWithTitle:[NSString stringWithFormat:@"%@ Ops", drilldown[@"label"] ?: @"Module"]
                                          heading:drilldown[@"label"] ?: @"Module"
                                          message:@""
                                           errors:nil
                                            extra:@{ @"drilldown" : drilldown ?: @{} }]
                layout:@"modules/ops/layouts/main"
                 error:NULL];
  return nil;
}

- (id)apiSummary:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:[self.runtime dashboardSummary] meta:nil error:NULL];
  return nil;
}

- (id)apiModuleDrilldown:(ALNContext *)ctx {
  NSString *identifier = OTLowerTrimmedString([ctx paramValueForName:@"module"]);
  NSDictionary *drilldown = [self.runtime moduleDrilldownForIdentifier:identifier];
  if (drilldown == nil) {
    [self renderAPIErrorWithStatus:404 code:@"not_found" message:@"ops module drilldown not found" meta:@{ @"module" : identifier ?: @"" }];
    return nil;
  }
  [self renderJSONEnvelopeWithData:drilldown meta:nil error:NULL];
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
  [application registerRouteMethod:@"GET"
                              path:@"/modules/:module"
                              name:@"ops_module_drilldown"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"moduleDrilldown"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:@"requireOpsAPI" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/summary"
                              name:@"ops_api_summary"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"apiSummary"];
  [application registerRouteMethod:@"GET"
                              path:@"/modules/:module"
                              name:@"ops_api_module_drilldown"
                   controllerClass:[ALNOpsModuleController class]
                            action:@"apiModuleDrilldown"];
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

  for (NSString *routeName in @[ @"ops_api_summary", @"ops_api_module_drilldown", @"ops_api_signals", @"ops_api_metrics", @"ops_api_openapi" ]) {
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
