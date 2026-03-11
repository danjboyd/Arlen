#import "ALNJobsModule.h"

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"

NSString *const ALNJobsModuleErrorDomain = @"Arlen.Modules.Jobs.Error";

static NSString *const ALNJobsManagedPayloadKey = @"aln.jobs_module";
static NSUInteger const ALNJobsRunHistoryLimit = 20;

static NSString *JMTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *JMLowerTrimmedString(id value) {
  return [[JMTrimmedString(value) lowercaseString] copy];
}

static NSDictionary *JMNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSError *JMError(ALNJobsModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"jobs module error";
  return [NSError errorWithDomain:ALNJobsModuleErrorDomain code:code userInfo:userInfo];
}

static NSString *JMPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = JMTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/jobs";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = JMTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *JMConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = JMTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/jobs";
  }
  NSString *override = JMTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return JMPathJoin(prefix, override);
  }
  return JMPathJoin(prefix, defaultSuffix);
}

static NSDictionary *JMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSString *JMQueryDecodeComponent(NSString *component) {
  NSString *withSpaces = [[component ?: @"" stringByReplacingOccurrencesOfString:@"+" withString:@" "]
      stringByRemovingPercentEncoding];
  return withSpaces ?: @"";
}

static NSDictionary *JMFormParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
  if ([raw length] == 0) {
    return @{};
  }
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSString *pair in [raw componentsSeparatedByString:@"&"]) {
    if ([pair length] == 0) {
      continue;
    }
    NSRange separator = [pair rangeOfString:@"="];
    NSString *name = nil;
    NSString *value = nil;
    if (separator.location == NSNotFound) {
      name = pair;
      value = @"";
    } else {
      name = [pair substringToIndex:separator.location];
      value = [pair substringFromIndex:(separator.location + 1)];
    }
    NSString *decodedName = JMQueryDecodeComponent(name);
    if ([decodedName length] == 0) {
      continue;
    }
    parameters[decodedName] = JMQueryDecodeComponent(value);
  }
  return parameters;
}

static NSString *JMPercentEncodedQueryComponent(NSString *value) {
  NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [allowed removeCharactersInString:@"&=+"];
  return [JMTrimmedString(value) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSDictionary *JMManagedPayload(NSDictionary *payload,
                                      NSString *queueName,
                                      NSString *source,
                                      NSString *scheduleIdentifier) {
  NSMutableDictionary *managed = [NSMutableDictionary dictionary];
  managed[@"payload"] = JMNormalizeDictionary(payload);
  managed[@"queue"] = [JMTrimmedString(queueName) length] > 0 ? JMTrimmedString(queueName) : @"default";
  if ([JMTrimmedString(source) length] > 0) {
    managed[@"source"] = JMTrimmedString(source);
  }
  if ([JMTrimmedString(scheduleIdentifier) length] > 0) {
    managed[@"scheduleIdentifier"] = JMTrimmedString(scheduleIdentifier);
  }
  return @{ ALNJobsManagedPayloadKey : managed };
}

static NSDictionary *JMUnwrappedManagedPayload(NSDictionary *payload) {
  NSDictionary *managed = [payload[ALNJobsManagedPayloadKey] isKindOfClass:[NSDictionary class]]
                              ? payload[ALNJobsManagedPayloadKey]
                              : nil;
  if (managed == nil) {
    return @{
      @"payload" : JMNormalizeDictionary(payload),
      @"queue" : @"default",
      @"source" : @"external",
      @"managed" : @NO,
      @"scheduleIdentifier" : @"",
    };
  }
  return @{
    @"payload" : JMNormalizeDictionary(managed[@"payload"]),
    @"queue" : [JMTrimmedString(managed[@"queue"]) length] > 0 ? JMTrimmedString(managed[@"queue"]) : @"default",
    @"source" : [JMTrimmedString(managed[@"source"]) length] > 0 ? JMTrimmedString(managed[@"source"]) : @"module",
    @"managed" : @YES,
    @"scheduleIdentifier" : JMTrimmedString(managed[@"scheduleIdentifier"]),
  };
}

static NSString *JMScheduleMinuteBucket(NSDate *timestamp) {
  NSTimeInterval value = floor([[timestamp ?: [NSDate date] dateByAddingTimeInterval:0] timeIntervalSince1970] / 60.0);
  return [NSString stringWithFormat:@"%.0f", value];
}

static BOOL JMCronFieldMatches(NSString *field, NSInteger value, NSInteger minimum, NSInteger maximum) {
  NSString *normalized = JMTrimmedString(field);
  if ([normalized length] == 0 || [normalized isEqualToString:@"*"]) {
    return YES;
  }
  if ([normalized hasPrefix:@"*/"]) {
    NSInteger step = [[normalized substringFromIndex:2] integerValue];
    return (step > 0) ? ((value - minimum) % step) == 0 : NO;
  }
  NSInteger exact = [normalized integerValue];
  if (exact < minimum || exact > maximum) {
    return NO;
  }
  return value == exact;
}

static BOOL JMDateMatchesCronExpression(NSString *expression, NSDate *timestamp) {
  NSString *normalized = JMTrimmedString(expression);
  if ([normalized isEqualToString:@"@hourly"]) {
    normalized = @"0 * * * *";
  } else if ([normalized isEqualToString:@"@daily"]) {
    normalized = @"0 0 * * *";
  }
  NSArray *fields = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSMutableArray *compact = [NSMutableArray array];
  for (NSString *field in fields) {
    if ([JMTrimmedString(field) length] > 0) {
      [compact addObject:JMTrimmedString(field)];
    }
  }
  if ([compact count] != 5) {
    return NO;
  }

  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  NSDateComponents *components =
      [calendar components:(NSCalendarUnitMinute | NSCalendarUnitHour | NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitWeekday)
                  fromDate:timestamp ?: [NSDate date]];
  NSInteger weekday = components.weekday - 1;
  if (weekday < 0) {
    weekday = 0;
  }

  return JMCronFieldMatches(compact[0], components.minute, 0, 59) &&
         JMCronFieldMatches(compact[1], components.hour, 0, 23) &&
         JMCronFieldMatches(compact[2], components.day, 1, 31) &&
         JMCronFieldMatches(compact[3], components.month, 1, 12) &&
         JMCronFieldMatches(compact[4], weekday, 0, 6);
}

static BOOL JMValidateCronExpressionSyntax(NSString *expression) {
  NSString *normalized = JMTrimmedString(expression);
  if ([normalized isEqualToString:@"@hourly"] || [normalized isEqualToString:@"@daily"]) {
    return YES;
  }
  NSArray *fields = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSMutableArray *compact = [NSMutableArray array];
  for (NSString *field in fields) {
    if ([JMTrimmedString(field) length] > 0) {
      [compact addObject:JMTrimmedString(field)];
    }
  }
  if ([compact count] != 5) {
    return NO;
  }
  return YES;
}

static NSDictionary *JMRecordRunSummary(NSString *kind, NSDictionary *summary) {
  return @{
    @"kind" : JMTrimmedString(kind),
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"summary" : JMNormalizeDictionary(summary),
  };
}

static NSArray<NSString *> *JMDedupedStringArray(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray<NSString *> *results = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (id entry in (NSArray *)value) {
    NSString *normalized = JMTrimmedString(entry);
    if ([normalized length] == 0 || [seen containsObject:normalized]) {
      continue;
    }
    [seen addObject:normalized];
    [results addObject:normalized];
  }
  return results;
}

static NSDictionary *JMNormalizedRetryBackoff(id value) {
  NSDictionary *raw = JMNormalizeDictionary(value);
  if ([raw count] == 0) {
    return @{};
  }
  NSString *strategy = JMLowerTrimmedString(raw[@"strategy"]);
  if ([strategy length] == 0) {
    strategy = @"fixed";
  }
  NSTimeInterval baseSeconds =
      [raw[@"baseSeconds"] respondsToSelector:@selector(doubleValue)] ? [raw[@"baseSeconds"] doubleValue] : 0.0;
  if (baseSeconds < 0.0) {
    baseSeconds = 0.0;
  }
  double multiplier = [raw[@"multiplier"] respondsToSelector:@selector(doubleValue)] ? [raw[@"multiplier"] doubleValue] : 2.0;
  if (multiplier < 1.0) {
    multiplier = 1.0;
  }
  NSTimeInterval maxSeconds =
      [raw[@"maxSeconds"] respondsToSelector:@selector(doubleValue)] ? [raw[@"maxSeconds"] doubleValue] : 0.0;
  if (maxSeconds < 0.0) {
    maxSeconds = 0.0;
  }
  return @{
    @"strategy" : strategy,
    @"baseSeconds" : @(baseSeconds),
    @"multiplier" : @(multiplier),
    @"maxSeconds" : @(maxSeconds),
  };
}

static NSDictionary *JMNormalizedUniqueness(id value) {
  NSDictionary *raw = JMNormalizeDictionary(value);
  if ([raw count] == 0) {
    return @{};
  }
  BOOL enabled = [raw[@"enabled"] respondsToSelector:@selector(boolValue)] && [raw[@"enabled"] boolValue];
  NSString *scope = JMLowerTrimmedString(raw[@"scope"]);
  if ([scope length] == 0) {
    scope = @"job";
  }
  return @{
    @"enabled" : @(enabled),
    @"scope" : scope,
  };
}

static NSString *JMEscapedJSONStringFragment(NSString *value) {
  NSString *result = [value ?: @"" stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  result = [result stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  result = [result stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
  result = [result stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
  result = [result stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
  return result;
}

static NSString *JMCanonicalValueString(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"null";
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictionary = (NSDictionary *)value;
    NSArray *keys = [[dictionary allKeys] sortedArrayUsingComparator:^NSComparisonResult(id lhs, id rhs) {
      return [JMTrimmedString(lhs) compare:JMTrimmedString(rhs)];
    }];
    NSMutableArray *parts = [NSMutableArray array];
    for (id key in keys) {
      NSString *normalizedKey = JMTrimmedString(key);
      NSString *fragment = [NSString stringWithFormat:@"\"%@\":%@",
                                                      JMEscapedJSONStringFragment(normalizedKey),
                                                      JMCanonicalValueString(dictionary[key])];
      [parts addObject:fragment];
    }
    return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@","]];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      [parts addObject:JMCanonicalValueString(entry)];
    }
    return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
  }
  if ([value isKindOfClass:[NSString class]]) {
    return [NSString stringWithFormat:@"\"%@\"", JMEscapedJSONStringFragment((NSString *)value)];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue] ?: @"0";
  }
  return [NSString stringWithFormat:@"\"%@\"", JMEscapedJSONStringFragment([value description] ?: @"")];
}

static NSString *JMDerivedIdempotencyKey(NSString *identifier,
                                         NSDictionary *uniqueness,
                                         NSDictionary *payload) {
  if (![uniqueness[@"enabled"] boolValue]) {
    return @"";
  }
  NSString *scope = JMLowerTrimmedString(uniqueness[@"scope"]);
  if ([scope isEqualToString:@"payload"]) {
    return [NSString stringWithFormat:@"jobs:%@:payload:%@",
                                      JMTrimmedString(identifier),
                                      JMCanonicalValueString(JMNormalizeDictionary(payload))];
  }
  return [NSString stringWithFormat:@"jobs:%@:job", JMTrimmedString(identifier)];
}

static NSString *JMResolvedPersistencePath(ALNApplication *application, NSDictionary *moduleConfig) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  BOOL enabled = ![persistence[@"enabled"] respondsToSelector:@selector(boolValue)] ||
                 [persistence[@"enabled"] boolValue];
  if (!enabled) {
    return @"";
  }
  NSString *configured = JMTrimmedString(persistence[@"path"]);
  if ([configured length] > 0) {
    if ([configured hasPrefix:@"/"]) {
      return configured;
    }
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
    return [cwd stringByAppendingPathComponent:configured];
  }
  NSString *environment = JMLowerTrimmedString(application.environment);
  if ([environment isEqualToString:@"test"]) {
    return @"";
  }
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
  return [cwd stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"var/module_state/jobs-%@.plist",
                                              ([environment length] > 0) ? environment : @"development"]];
}

static NSDictionary *JMReadPropertyListAtPath(NSString *path, NSError **error) {
  NSString *statePath = JMTrimmedString(path);
  if ([statePath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:statePath]) {
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfFile:statePath options:0 error:error];
  if (data == nil) {
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id object = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static BOOL JMWritePropertyListAtPath(NSString *path, NSDictionary *payload, NSError **error) {
  NSString *statePath = JMTrimmedString(path);
  if ([statePath length] == 0) {
    return YES;
  }
  NSString *directory = [statePath stringByDeletingLastPathComponent];
  if ([directory length] > 0 &&
      ![[NSFileManager defaultManager] fileExistsAtPath:directory] &&
      ![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
    return NO;
  }
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:(payload ?: @{})
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return [data writeToFile:statePath options:NSDataWritingAtomic error:error];
}

@protocol ALNJobsInspectableAdapter <NSObject>
- (NSArray *)leasedJobsSnapshot;
@end

@protocol ALNJobsOptionalAuthRuntime <NSObject>
+ (instancetype)sharedRuntime;
- (nullable NSString *)loginPath;
- (nullable NSString *)logoutPath;
- (nullable NSString *)totpPath;
- (BOOL)isAdminContext:(ALNContext *)context
                 error:(NSError **)error;
@end

static id<ALNJobsOptionalAuthRuntime> JMSharedAuthRuntime(void) {
  Class runtimeClass = NSClassFromString(@"ALNAuthModuleRuntime");
  if (runtimeClass == Nil || ![(id)runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    return nil;
  }
  return [(id<ALNJobsOptionalAuthRuntime>)runtimeClass sharedRuntime];
}

@interface ALNJobsModuleController : ALNController

@property(nonatomic, strong) ALNJobsModuleRuntime *runtime;
@property(nonatomic, strong) id<ALNJobsOptionalAuthRuntime> authRuntime;

- (BOOL)requireJobsHTML:(ALNContext *)ctx;

@end

@interface ALNJobsModuleRuntime ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, strong, readwrite) id<ALNJobAdapter> jobsAdapter;
@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, assign, readwrite) NSUInteger defaultWorkerRunLimit;
@property(nonatomic, assign, readwrite) NSTimeInterval defaultRetryDelaySeconds;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id<ALNJobsJobDefinition>> *jobDefinitionsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *jobMetadataByIdentifier;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *schedules;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastTriggeredAtByScheduleIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *lastTriggeredBucketByScheduleIdentifier;
@property(nonatomic, strong) NSMutableSet<NSString *> *pausedQueues;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *replayedDeadLetterTimestamps;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *runHistory;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, copy) NSString *persistencePath;

- (BOOL)registerJobDefinition:(id<ALNJobsJobDefinition>)definition
                       source:(NSString *)source
                        error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)normalizedScheduleDefinition:(NSDictionary *)schedule
                                                  error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)jobSummaryFromEnvelope:(ALNJobEnvelope *)envelope state:(NSString *)state;
- (NSDictionary *)operatorStateDocumentLocked;
- (void)restoreOperatorStateFromDocument:(NSDictionary *)document;
- (BOOL)persistOperatorStateWithError:(NSError *_Nullable *_Nullable)error;

@end

@implementation ALNJobsModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNJobsModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNJobsModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _prefix = @"/jobs";
    _apiPrefix = @"/jobs/api";
    _defaultWorkerRunLimit = 50;
    _defaultRetryDelaySeconds = 5.0;
    _lock = [[NSLock alloc] init];
    _jobDefinitionsByIdentifier = [NSMutableDictionary dictionary];
    _jobMetadataByIdentifier = [NSMutableDictionary dictionary];
    _schedules = [NSMutableArray array];
    _lastTriggeredAtByScheduleIdentifier = [NSMutableDictionary dictionary];
    _lastTriggeredBucketByScheduleIdentifier = [NSMutableDictionary dictionary];
    _pausedQueues = [NSMutableSet set];
    _replayedDeadLetterTimestamps = [NSMutableDictionary dictionary];
    _runHistory = [NSMutableArray array];
    _persistenceEnabled = NO;
    _persistencePath = @"";
  }
  return self;
}

- (NSDictionary *)operatorStateDocumentLocked {
  NSArray *pausedQueues = [[self.pausedQueues allObjects] sortedArrayUsingSelector:@selector(compare:)] ?: @[];
  return @{
    @"pausedQueues" : pausedQueues,
    @"lastTriggeredAtByScheduleIdentifier" : [self.lastTriggeredAtByScheduleIdentifier copy] ?: @{},
    @"lastTriggeredBucketByScheduleIdentifier" : [self.lastTriggeredBucketByScheduleIdentifier copy] ?: @{},
    @"replayedDeadLetterTimestamps" : [self.replayedDeadLetterTimestamps copy] ?: @{},
    @"runHistory" : ([[NSArray alloc] initWithArray:self.runHistory copyItems:YES] ?: @[]),
  };
}

- (void)restoreOperatorStateFromDocument:(NSDictionary *)document {
  [self.lastTriggeredAtByScheduleIdentifier removeAllObjects];
  NSDictionary *lastTriggered = [document[@"lastTriggeredAtByScheduleIdentifier"] isKindOfClass:[NSDictionary class]]
                                    ? document[@"lastTriggeredAtByScheduleIdentifier"]
                                    : @{};
  for (id key in lastTriggered) {
    NSString *identifier = JMTrimmedString(key);
    if ([identifier length] == 0 || ![lastTriggered[key] respondsToSelector:@selector(doubleValue)]) {
      continue;
    }
    self.lastTriggeredAtByScheduleIdentifier[identifier] = @([lastTriggered[key] doubleValue]);
  }

  [self.lastTriggeredBucketByScheduleIdentifier removeAllObjects];
  NSDictionary *lastBuckets = [document[@"lastTriggeredBucketByScheduleIdentifier"] isKindOfClass:[NSDictionary class]]
                                  ? document[@"lastTriggeredBucketByScheduleIdentifier"]
                                  : @{};
  for (id key in lastBuckets) {
    NSString *identifier = JMTrimmedString(key);
    NSString *bucket = JMTrimmedString(lastBuckets[key]);
    if ([identifier length] == 0 || [bucket length] == 0) {
      continue;
    }
    self.lastTriggeredBucketByScheduleIdentifier[identifier] = bucket;
  }

  [self.pausedQueues removeAllObjects];
  for (NSString *queue in JMDedupedStringArray(document[@"pausedQueues"])) {
    [self.pausedQueues addObject:queue];
  }

  [self.replayedDeadLetterTimestamps removeAllObjects];
  NSDictionary *replayed = [document[@"replayedDeadLetterTimestamps"] isKindOfClass:[NSDictionary class]]
                               ? document[@"replayedDeadLetterTimestamps"]
                               : @{};
  for (id key in replayed) {
    NSString *jobID = JMTrimmedString(key);
    if ([jobID length] == 0 || ![replayed[key] respondsToSelector:@selector(doubleValue)]) {
      continue;
    }
    self.replayedDeadLetterTimestamps[jobID] = @([replayed[key] doubleValue]);
  }

  [self.runHistory removeAllObjects];
  NSArray *runHistory = [document[@"runHistory"] isKindOfClass:[NSArray class]] ? document[@"runHistory"] : @[];
  for (NSDictionary *entry in runHistory) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [self.runHistory addObject:[entry copy]];
  }
  while ([self.runHistory count] > ALNJobsRunHistoryLimit) {
    [self.runHistory removeObjectAtIndex:0];
  }
}

- (BOOL)persistOperatorStateWithError:(NSError **)error {
  NSString *statePath = JMTrimmedString(self.persistencePath);
  if (!self.persistenceEnabled || [statePath length] == 0) {
    return YES;
  }
  [self.lock lock];
  NSDictionary *document = [self operatorStateDocumentLocked];
  [self.lock unlock];
  return JMWritePropertyListAtPath(statePath, document, error);
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  if (application == nil || application.jobsAdapter == nil) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       @"jobs module requires an application with a jobs adapter",
                       nil);
    }
    return NO;
  }

  NSDictionary *moduleConfig = [application.config[@"jobsModule"] isKindOfClass:[NSDictionary class]]
                                   ? application.config[@"jobsModule"]
                                   : @{};
  NSDictionary *workerConfig = [moduleConfig[@"worker"] isKindOfClass:[NSDictionary class]]
                                   ? moduleConfig[@"worker"]
                                   : @{};

  [self.lock lock];
  self.application = application;
  self.jobsAdapter = application.jobsAdapter;
  self.moduleConfig = moduleConfig;
  self.prefix = JMConfiguredPath(moduleConfig, @"prefix", @"");
  self.apiPrefix = JMConfiguredPath(moduleConfig, @"apiPrefix", @"api");
  self.persistencePath = JMResolvedPersistencePath(application, moduleConfig);
  self.persistenceEnabled = ([JMTrimmedString(self.persistencePath) length] > 0);
  self.defaultWorkerRunLimit = [workerConfig[@"maxJobsPerRun"] respondsToSelector:@selector(unsignedIntegerValue)]
                                   ? [workerConfig[@"maxJobsPerRun"] unsignedIntegerValue]
                                   : 50;
  if (self.defaultWorkerRunLimit == 0) {
    self.defaultWorkerRunLimit = 50;
  }
  self.defaultRetryDelaySeconds =
      [workerConfig[@"retryDelaySeconds"] respondsToSelector:@selector(doubleValue)]
          ? [workerConfig[@"retryDelaySeconds"] doubleValue]
          : 5.0;
  if (self.defaultRetryDelaySeconds < 0.0) {
    self.defaultRetryDelaySeconds = 0.0;
  }
  [self.jobDefinitionsByIdentifier removeAllObjects];
  [self.jobMetadataByIdentifier removeAllObjects];
  [self.schedules removeAllObjects];
  [self.lastTriggeredAtByScheduleIdentifier removeAllObjects];
  [self.lastTriggeredBucketByScheduleIdentifier removeAllObjects];
  [self.pausedQueues removeAllObjects];
  [self.replayedDeadLetterTimestamps removeAllObjects];
  [self.runHistory removeAllObjects];
  NSDictionary *persistedState = self.persistenceEnabled ? JMReadPropertyListAtPath(self.persistencePath, NULL) : nil;
  if ([persistedState isKindOfClass:[NSDictionary class]]) {
    [self restoreOperatorStateFromDocument:persistedState];
  }
  [self.lock unlock];

  NSArray *providerClasses =
      [moduleConfig[@"jobProviderClasses"] isKindOfClass:[NSArray class]]
          ? moduleConfig[@"jobProviderClasses"]
          : ([moduleConfig[@"providers"] isKindOfClass:[NSDictionary class]] &&
                     [moduleConfig[@"providers"][@"classes"] isKindOfClass:[NSArray class]]
                 ? moduleConfig[@"providers"][@"classes"]
                 : @[]);
  for (id rawClassName in providerClasses) {
    NSString *className = JMTrimmedString(rawClassName);
    if ([className length] == 0) {
      continue;
    }
    Class klass = NSClassFromString(className);
    id provider = klass != Nil ? [[klass alloc] init] : nil;
    if (provider == nil || ![provider conformsToProtocol:@protocol(ALNJobsJobProvider)]) {
      if (error != NULL) {
        *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"jobs provider %@ is invalid", className],
                         @{ @"class" : className });
      }
      return NO;
    }
    NSError *providerError = nil;
    NSArray *definitions =
        [(id<ALNJobsJobProvider>)provider jobsModuleJobDefinitionsForRuntime:self error:&providerError];
    if (definitions == nil) {
      if (error != NULL) {
        *error = providerError ?: JMError(ALNJobsModuleErrorInvalidConfiguration,
                                          @"jobs provider failed to supply definitions",
                                          @{ @"class" : className });
      }
      return NO;
    }
    for (id definition in definitions) {
      if (![self registerJobDefinition:definition source:className error:error]) {
        return NO;
      }
    }
  }

  NSArray *scheduleProviderClasses =
      [moduleConfig[@"scheduleProviderClasses"] isKindOfClass:[NSArray class]]
          ? moduleConfig[@"scheduleProviderClasses"]
          : ([moduleConfig[@"schedules"] isKindOfClass:[NSDictionary class]] &&
                     [moduleConfig[@"schedules"][@"classes"] isKindOfClass:[NSArray class]]
                 ? moduleConfig[@"schedules"][@"classes"]
                 : @[]);
  NSMutableArray *normalizedSchedules = [NSMutableArray array];
  for (id rawClassName in scheduleProviderClasses) {
    NSString *className = JMTrimmedString(rawClassName);
    if ([className length] == 0) {
      continue;
    }
    Class klass = NSClassFromString(className);
    id provider = klass != Nil ? [[klass alloc] init] : nil;
    if (provider == nil || ![provider conformsToProtocol:@protocol(ALNJobsScheduleProvider)]) {
      if (error != NULL) {
        *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"jobs schedule provider %@ is invalid", className],
                         @{ @"class" : className });
      }
      return NO;
    }
    NSError *providerError = nil;
    NSArray *definitions =
        [(id<ALNJobsScheduleProvider>)provider jobsModuleScheduleDefinitionsForRuntime:self error:&providerError];
    if (definitions == nil) {
      if (error != NULL) {
        *error = providerError ?: JMError(ALNJobsModuleErrorInvalidConfiguration,
                                          @"jobs schedule provider failed to supply definitions",
                                          @{ @"class" : className });
      }
      return NO;
    }
    for (id rawDefinition in definitions) {
      NSDictionary *schedule = [self normalizedScheduleDefinition:JMNormalizeDictionary(rawDefinition)
                                                            error:error];
      if (schedule == nil) {
        return NO;
      }
      [normalizedSchedules addObject:schedule];
    }
  }
  [normalizedSchedules sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    return [JMTrimmedString(lhs[@"identifier"]) compare:JMTrimmedString(rhs[@"identifier"])];
  }];
  [self.lock lock];
  [self.schedules addObjectsFromArray:normalizedSchedules];
  [self.lock unlock];
  return YES;
}

- (NSDictionary *)resolvedConfigSummary {
  [self.lock lock];
  NSDictionary *summary = @{
    @"prefix" : self.prefix ?: @"/jobs",
    @"apiPrefix" : self.apiPrefix ?: @"/jobs/api",
    @"defaultWorkerRunLimit" : @(self.defaultWorkerRunLimit),
    @"defaultRetryDelaySeconds" : @(self.defaultRetryDelaySeconds),
    @"jobCount" : @([self.jobMetadataByIdentifier count]),
    @"scheduleCount" : @([self.schedules count]),
  };
  [self.lock unlock];
  return summary;
}

- (NSArray<NSDictionary *> *)registeredJobDefinitions {
  [self.lock lock];
  NSArray *keys = [[self.jobMetadataByIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *definitions = [NSMutableArray array];
  for (NSString *identifier in keys) {
    NSDictionary *metadata = self.jobMetadataByIdentifier[identifier];
    if ([metadata isKindOfClass:[NSDictionary class]]) {
      [definitions addObject:[metadata copy]];
    }
  }
  [self.lock unlock];
  return definitions;
}

- (NSArray<NSDictionary *> *)registeredSchedules {
  [self.lock lock];
  NSArray *schedules = [[NSArray alloc] initWithArray:self.schedules copyItems:YES];
  [self.lock unlock];
  return schedules ?: @[];
}

- (NSDictionary *)jobDefinitionMetadataForIdentifier:(NSString *)identifier {
  NSString *jobID = JMTrimmedString(identifier);
  if ([jobID length] == 0) {
    return nil;
  }
  [self.lock lock];
  NSDictionary *metadata = [self.jobMetadataByIdentifier[jobID] copy];
  [self.lock unlock];
  return metadata;
}

- (BOOL)registerSystemJobDefinition:(id<ALNJobsJobDefinition>)definition
                              error:(NSError **)error {
  return [self registerJobDefinition:definition source:@"system" error:error];
}

- (BOOL)registerSystemScheduleDefinition:(NSDictionary *)schedule
                                   error:(NSError **)error {
  NSDictionary *normalized = [self normalizedScheduleDefinition:JMNormalizeDictionary(schedule)
                                                          error:error];
  if (normalized == nil) {
    return NO;
  }
  NSString *identifier = JMTrimmedString(normalized[@"identifier"]);
  NSMutableDictionary *scheduleWithSource = [normalized mutableCopy] ?: [NSMutableDictionary dictionary];
  scheduleWithSource[@"source"] = @"system";
  scheduleWithSource[@"system"] = @YES;

  [self.lock lock];
  for (NSDictionary *existing in self.schedules ?: @[]) {
    if ([JMTrimmedString(existing[@"identifier"]) isEqualToString:identifier]) {
      [self.lock unlock];
      if (error != NULL) {
        *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"duplicate jobs schedule %@", identifier],
                         @{ @"identifier" : identifier ?: @"" });
      }
      return NO;
    }
  }
  [self.schedules addObject:[scheduleWithSource copy]];
  [self.schedules sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    return [JMTrimmedString(lhs[@"identifier"]) compare:JMTrimmedString(rhs[@"identifier"])];
  }];
  [self.lock unlock];
  return YES;
}

- (BOOL)registerJobDefinition:(id<ALNJobsJobDefinition>)definition
                       source:(NSString *)source
                        error:(NSError **)error {
  if (definition == nil || ![definition conformsToProtocol:@protocol(ALNJobsJobDefinition)]) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       @"job definition must conform to ALNJobsJobDefinition",
                       nil);
    }
    return NO;
  }
  NSString *identifier = JMTrimmedString([definition jobsModuleJobIdentifier]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration, @"job identifier is required", nil);
    }
    return NO;
  }

  NSDictionary *metadata = JMNormalizeDictionary([definition jobsModuleJobMetadata]);
  NSString *queue = JMTrimmedString(metadata[@"queue"]);
  if ([queue length] == 0) {
    queue = @"default";
  }
  NSUInteger maxAttempts = [metadata[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [metadata[@"maxAttempts"] unsignedIntegerValue]
                               : 3;
  if (maxAttempts == 0) {
    maxAttempts = 3;
  }
  BOOL allowManualEnqueue = ![metadata[@"allowManualEnqueue"] respondsToSelector:@selector(boolValue)] ||
                            [metadata[@"allowManualEnqueue"] boolValue];
  NSInteger queuePriority = [metadata[@"queuePriority"] respondsToSelector:@selector(integerValue)]
                                ? [metadata[@"queuePriority"] integerValue]
                                : 0;
  NSArray<NSString *> *tags = JMDedupedStringArray(metadata[@"tags"]);
  NSDictionary *uniqueness = JMNormalizedUniqueness(metadata[@"uniqueness"]);
  NSDictionary *retryBackoff = JMNormalizedRetryBackoff(metadata[@"retryBackoff"]);
  NSDictionary *normalizedMetadata = @{
    @"identifier" : identifier,
    @"title" : [JMTrimmedString(metadata[@"title"]) length] > 0 ? JMTrimmedString(metadata[@"title"]) : identifier,
    @"description" : JMTrimmedString(metadata[@"description"]),
    @"queue" : queue,
    @"queuePriority" : @(queuePriority),
    @"maxAttempts" : @(maxAttempts),
    @"tags" : tags ?: @[],
    @"uniqueness" : uniqueness ?: @{},
    @"retryBackoff" : retryBackoff ?: @{},
    @"allowManualEnqueue" : @(allowManualEnqueue),
    @"source" : JMTrimmedString(source),
    @"system" : @([JMLowerTrimmedString(source) isEqualToString:@"system"]),
  };

  [self.lock lock];
  if (self.jobDefinitionsByIdentifier[identifier] != nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"duplicate jobs definition %@", identifier],
                       @{ @"identifier" : identifier });
    }
    return NO;
  }
  self.jobDefinitionsByIdentifier[identifier] = definition;
  self.jobMetadataByIdentifier[identifier] = normalizedMetadata;
  [self.lock unlock];
  return YES;
}

- (NSDictionary *)normalizedScheduleDefinition:(NSDictionary *)schedule
                                         error:(NSError **)error {
  NSString *identifier = JMTrimmedString(schedule[@"identifier"]);
  if ([identifier length] == 0) {
    identifier = JMTrimmedString(schedule[@"id"]);
  }
  NSString *job = JMTrimmedString(schedule[@"job"]);
  NSString *cron = JMTrimmedString(schedule[@"cron"]);
  NSTimeInterval intervalSeconds =
      [schedule[@"intervalSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [schedule[@"intervalSeconds"] doubleValue]
          : ([schedule[@"interval"] respondsToSelector:@selector(doubleValue)]
                 ? [schedule[@"interval"] doubleValue]
                 : 0.0);
  NSString *queue = JMTrimmedString(schedule[@"queue"]);
  if ([queue length] == 0) {
    NSDictionary *metadata = [self jobDefinitionMetadataForIdentifier:job];
    queue = [JMTrimmedString(metadata[@"queue"]) length] > 0 ? JMTrimmedString(metadata[@"queue"]) : @"default";
  }
  NSUInteger maxAttempts = [schedule[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [schedule[@"maxAttempts"] unsignedIntegerValue]
                               : 0;
  BOOL enabled = ![schedule[@"enabled"] respondsToSelector:@selector(boolValue)] ||
                 [schedule[@"enabled"] boolValue];

  if ([identifier length] == 0 || [job length] == 0) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       @"schedule definitions require identifier and job",
                       nil);
    }
    return nil;
  }
  if ([self jobDefinitionMetadataForIdentifier:job] == nil) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"schedule %@ references unknown job %@", identifier, job],
                       @{ @"schedule" : identifier, @"job" : job });
    }
    return nil;
  }
  if (intervalSeconds <= 0.0 && [cron length] == 0) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       @"schedule definitions require intervalSeconds or cron",
                       @{ @"schedule" : identifier });
    }
    return nil;
  }
  if ([cron length] > 0 && !JMValidateCronExpressionSyntax(cron)) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"unsupported cron expression %@", cron],
                       @{ @"schedule" : identifier, @"cron" : cron });
    }
    return nil;
  }

  return @{
    @"identifier" : identifier,
    @"job" : job,
    @"intervalSeconds" : @(intervalSeconds > 0.0 ? intervalSeconds : 0.0),
    @"cron" : cron ?: @"",
    @"queue" : [queue length] > 0 ? queue : @"default",
    @"payload" : JMNormalizeDictionary(schedule[@"payload"]),
    @"maxAttempts" : @(maxAttempts),
    @"enabled" : @(enabled),
  };
}

- (NSString *)enqueueJobIdentifier:(NSString *)identifier
                           payload:(NSDictionary *)payload
                           options:(NSDictionary *)options
                             error:(NSError **)error {
  NSString *jobID = JMTrimmedString(identifier);
  if ([jobID length] == 0) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorValidationFailed, @"job identifier is required", nil);
    }
    return nil;
  }

  [self.lock lock];
  id<ALNJobsJobDefinition> definition = self.jobDefinitionsByIdentifier[jobID];
  NSDictionary *metadata = self.jobMetadataByIdentifier[jobID];
  [self.lock unlock];
  if (definition == nil || metadata == nil) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown jobs definition %@", jobID],
                       @{ @"job" : jobID });
    }
    return nil;
  }

  NSDictionary *normalizedPayload = JMNormalizeDictionary(payload);
  NSError *validationError = nil;
  if (![definition jobsModuleValidatePayload:normalizedPayload error:&validationError]) {
    if (error != NULL) {
      *error = validationError ?: JMError(ALNJobsModuleErrorValidationFailed,
                                          @"job payload was rejected",
                                          @{ @"job" : jobID });
    }
    return nil;
  }

  NSDictionary *defaultOptions =
      [definition respondsToSelector:@selector(jobsModuleDefaultEnqueueOptions)]
          ? JMNormalizeDictionary([definition jobsModuleDefaultEnqueueOptions])
          : @{};
  NSMutableDictionary *normalizedOptions = [NSMutableDictionary dictionaryWithDictionary:defaultOptions];
  [normalizedOptions addEntriesFromDictionary:JMNormalizeDictionary(options)];
  NSString *queue = JMTrimmedString(normalizedOptions[@"queue"]);
  if ([queue length] == 0) {
    queue = JMTrimmedString(metadata[@"queue"]);
  }
  if ([queue length] == 0) {
    queue = @"default";
  }
  if ([self isQueuePaused:queue]) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorUnsupported,
                       [NSString stringWithFormat:@"queue %@ is currently paused", queue],
                       @{ @"queue" : queue });
    }
    return nil;
  }

  NSUInteger maxAttempts = [normalizedOptions[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [normalizedOptions[@"maxAttempts"] unsignedIntegerValue]
                               : [metadata[@"maxAttempts"] unsignedIntegerValue];
  if (maxAttempts == 0) {
    maxAttempts = 3;
  }
  NSString *source = JMTrimmedString(normalizedOptions[@"source"]);
  if ([source length] == 0) {
    source = @"manual";
  }
  NSString *scheduleIdentifier = JMTrimmedString(normalizedOptions[@"scheduleIdentifier"]);

  NSMutableDictionary *adapterOptions = [NSMutableDictionary dictionary];
  adapterOptions[@"maxAttempts"] = @(maxAttempts);
  NSString *idempotencyKey = JMTrimmedString(normalizedOptions[@"idempotencyKey"]);
  if ([idempotencyKey length] == 0) {
    idempotencyKey = JMDerivedIdempotencyKey(jobID, metadata[@"uniqueness"], normalizedPayload);
  }
  if ([idempotencyKey length] > 0) {
    adapterOptions[@"idempotencyKey"] = idempotencyKey;
  }
  if ([normalizedOptions[@"notBefore"] isKindOfClass:[NSDate class]]) {
    adapterOptions[@"notBefore"] = normalizedOptions[@"notBefore"];
  } else if ([normalizedOptions[@"notBefore"] respondsToSelector:@selector(doubleValue)]) {
    adapterOptions[@"notBefore"] = @([normalizedOptions[@"notBefore"] doubleValue]);
  }

  NSDictionary *managedPayload = JMManagedPayload(normalizedPayload, queue, source, scheduleIdentifier);
  return [self.jobsAdapter enqueueJobNamed:jobID payload:managedPayload options:adapterOptions error:error];
}

- (NSDictionary *)runSchedulerAt:(NSDate *)timestamp error:(NSError **)error {
  NSDate *now = timestamp ?: [NSDate date];
  NSMutableArray *triggered = [NSMutableArray array];
  NSUInteger skippedPaused = 0;

  [self.lock lock];
  NSArray *schedules = [[NSArray alloc] initWithArray:self.schedules copyItems:YES];
  [self.lock unlock];

  for (NSDictionary *schedule in schedules) {
    if (![schedule[@"enabled"] boolValue]) {
      continue;
    }

    NSString *identifier = JMTrimmedString(schedule[@"identifier"]);
    NSString *queue = JMTrimmedString(schedule[@"queue"]);
    if ([self isQueuePaused:queue]) {
      skippedPaused += 1;
      continue;
    }

    BOOL due = NO;
    NSTimeInterval intervalSeconds = [schedule[@"intervalSeconds"] doubleValue];
    NSString *cron = JMTrimmedString(schedule[@"cron"]);
    [self.lock lock];
    NSNumber *lastTriggered = self.lastTriggeredAtByScheduleIdentifier[identifier];
    NSString *lastBucket = self.lastTriggeredBucketByScheduleIdentifier[identifier];
    [self.lock unlock];

    if (intervalSeconds > 0.0) {
      NSTimeInterval lastValue = [lastTriggered respondsToSelector:@selector(doubleValue)] ? [lastTriggered doubleValue] : 0.0;
      due = (lastValue <= 0.0) || (([now timeIntervalSince1970] - lastValue) >= intervalSeconds);
    } else if ([cron length] > 0) {
      NSString *currentBucket = JMScheduleMinuteBucket(now);
      due = JMDateMatchesCronExpression(cron, now) && ![lastBucket isEqualToString:currentBucket];
    }

    if (!due) {
      continue;
    }

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"queue"] = queue;
    options[@"source"] = @"schedule";
    options[@"scheduleIdentifier"] = identifier;
    options[@"notBefore"] = now;
    NSUInteger maxAttempts = [schedule[@"maxAttempts"] unsignedIntegerValue];
    if (maxAttempts > 0) {
      options[@"maxAttempts"] = @(maxAttempts);
    }

    NSError *enqueueError = nil;
    NSString *jobID = [self enqueueJobIdentifier:schedule[@"job"]
                                         payload:schedule[@"payload"]
                                         options:options
                                           error:&enqueueError];
    if ([jobID length] == 0) {
      if (error != NULL) {
        *error = enqueueError ?: JMError(ALNJobsModuleErrorExecutionFailed,
                                         @"scheduler could not enqueue job",
                                         @{ @"schedule" : identifier });
      }
      return nil;
    }

    [self.lock lock];
    self.lastTriggeredAtByScheduleIdentifier[identifier] = @([now timeIntervalSince1970]);
    self.lastTriggeredBucketByScheduleIdentifier[identifier] = JMScheduleMinuteBucket(now);
    [self.lock unlock];
    [triggered addObject:@{
      @"schedule" : identifier,
      @"job" : schedule[@"job"] ?: @"",
      @"jobID" : jobID,
      @"queue" : queue ?: @"default",
    }];
  }

  NSDictionary *summary = @{
    @"triggeredCount" : @([triggered count]),
    @"skippedPausedCount" : @(skippedPaused),
    @"triggered" : triggered,
  };
  [self.lock lock];
  [self.runHistory addObject:JMRecordRunSummary(@"scheduler", summary)];
  while ([self.runHistory count] > ALNJobsRunHistoryLimit) {
    [self.runHistory removeObjectAtIndex:0];
  }
  [self.lock unlock];
  if (![self persistOperatorStateWithError:error]) {
    return nil;
  }
  return summary;
}

- (NSDictionary *)runWorkerAt:(NSDate *)timestamp
                        limit:(NSUInteger)limit
                        error:(NSError **)error {
  if ([self isQueuePaused:@"default"]) {
    NSDictionary *summary = @{
      @"leasedCount" : @(0),
      @"acknowledgedCount" : @(0),
      @"retriedCount" : @(0),
      @"handlerErrorCount" : @(0),
      @"reachedRunLimit" : @NO,
      @"pausedDefaultQueue" : @YES,
    };
    [self.lock lock];
    [self.runHistory addObject:JMRecordRunSummary(@"worker", summary)];
    while ([self.runHistory count] > ALNJobsRunHistoryLimit) {
      [self.runHistory removeObjectAtIndex:0];
    }
    [self.lock unlock];
    if (![self persistOperatorStateWithError:error]) {
      return nil;
    }
    return summary;
  }

  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:self.jobsAdapter];
  worker.maxJobsPerRun = (limit > 0) ? limit : self.defaultWorkerRunLimit;
  worker.retryDelaySeconds = self.defaultRetryDelaySeconds;
  ALNJobWorkerRunSummary *runSummary = [worker runDueJobsAt:timestamp runtime:self error:error];
  if (runSummary == nil) {
    return nil;
  }
  NSMutableDictionary *summary = [NSMutableDictionary dictionaryWithDictionary:[runSummary dictionaryRepresentation]];
  summary[@"pausedDefaultQueue"] = @NO;
  [self.lock lock];
  [self.runHistory addObject:JMRecordRunSummary(@"worker", summary)];
  while ([self.runHistory count] > ALNJobsRunHistoryLimit) {
    [self.runHistory removeObjectAtIndex:0];
  }
  [self.lock unlock];
  if (![self persistOperatorStateWithError:error]) {
    return nil;
  }
  return summary;
}

- (ALNJobWorkerDisposition)handleJob:(ALNJobEnvelope *)job
                               error:(NSError **)error {
  NSString *identifier = JMTrimmedString(job.name);
  [self.lock lock];
  id<ALNJobsJobDefinition> definition = self.jobDefinitionsByIdentifier[identifier];
  [self.lock unlock];
  if (definition == nil) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown jobs definition %@", identifier],
                       @{ @"job" : identifier ?: @"" });
    }
    return ALNJobWorkerDispositionRetry;
  }

  NSDictionary *unwrapped = JMUnwrappedManagedPayload(JMNormalizeDictionary(job.payload));
  NSDictionary *payload = JMNormalizeDictionary(unwrapped[@"payload"]);
  NSDictionary *context = @{
    @"jobID" : JMTrimmedString(job.jobID),
    @"attempt" : @(job.attempt),
    @"maxAttempts" : @(job.maxAttempts),
    @"queue" : unwrapped[@"queue"] ?: @"default",
    @"source" : unwrapped[@"source"] ?: @"module",
    @"scheduleIdentifier" : unwrapped[@"scheduleIdentifier"] ?: @"",
    @"scheduledAt" : job.notBefore ?: [NSDate date],
  };

  NSError *validationError = nil;
  if (![definition jobsModuleValidatePayload:payload error:&validationError]) {
    if (error != NULL) {
      *error = validationError ?: JMError(ALNJobsModuleErrorValidationFailed,
                                          @"job payload validation failed during execution",
                                          @{ @"job" : identifier });
    }
    return ALNJobWorkerDispositionRetry;
  }

  NSError *performError = nil;
  BOOL ok = [definition jobsModulePerformPayload:payload context:context error:&performError];
  if (!ok && error != NULL) {
    *error = performError ?: JMError(ALNJobsModuleErrorExecutionFailed,
                                     @"job execution failed",
                                     @{ @"job" : identifier });
  }
  return ok ? ALNJobWorkerDispositionAcknowledge : ALNJobWorkerDispositionRetry;
}

- (NSTimeInterval)jobWorker:(ALNJobWorker *)worker
           retryDelayForJob:(ALNJobEnvelope *)job
               handlerError:(NSError *)handlerError
             baseRetryDelay:(NSTimeInterval)baseRetryDelay {
  (void)worker;
  (void)handlerError;
  NSDictionary *metadata = [self jobDefinitionMetadataForIdentifier:JMTrimmedString(job.name)] ?: @{};
  NSDictionary *retryBackoff = [metadata[@"retryBackoff"] isKindOfClass:[NSDictionary class]] ? metadata[@"retryBackoff"] : @{};
  NSString *strategy = JMLowerTrimmedString(retryBackoff[@"strategy"]);
  NSTimeInterval baseSeconds =
      [retryBackoff[@"baseSeconds"] respondsToSelector:@selector(doubleValue)] ? [retryBackoff[@"baseSeconds"] doubleValue] : baseRetryDelay;
  if (baseSeconds < 0.0) {
    baseSeconds = 0.0;
  }
  NSTimeInterval delay = baseSeconds;
  NSUInteger attempt = (job.attempt > 0) ? job.attempt : 1;
  if ([strategy isEqualToString:@"linear"]) {
    delay = baseSeconds * (NSTimeInterval)attempt;
  } else if ([strategy isEqualToString:@"exponential"]) {
    double multiplier = [retryBackoff[@"multiplier"] respondsToSelector:@selector(doubleValue)]
                            ? [retryBackoff[@"multiplier"] doubleValue]
                            : 2.0;
    if (multiplier < 1.0) {
      multiplier = 1.0;
    }
    delay = baseSeconds;
    for (NSUInteger index = 1; index < attempt; index++) {
      delay *= multiplier;
    }
  }
  NSTimeInterval maxSeconds =
      [retryBackoff[@"maxSeconds"] respondsToSelector:@selector(doubleValue)] ? [retryBackoff[@"maxSeconds"] doubleValue] : 0.0;
  if (maxSeconds > 0.0 && delay > maxSeconds) {
    delay = maxSeconds;
  }
  if (delay < 0.0) {
    delay = 0.0;
  }
  return delay;
}

- (NSDictionary *)jobSummaryFromEnvelope:(ALNJobEnvelope *)envelope state:(NSString *)state {
  NSDictionary *unwrapped = JMUnwrappedManagedPayload(JMNormalizeDictionary(envelope.payload));
  NSString *identifier = JMTrimmedString(envelope.name);
  NSDictionary *metadata = [self jobDefinitionMetadataForIdentifier:identifier] ?: @{};
  NSString *jobID = JMTrimmedString(envelope.jobID);
  NSNumber *replayedAt = nil;
  [self.lock lock];
  replayedAt = self.replayedDeadLetterTimestamps[jobID];
  [self.lock unlock];
  return @{
    @"jobID" : jobID,
    @"job" : identifier,
    @"title" : metadata[@"title"] ?: identifier,
    @"queue" : unwrapped[@"queue"] ?: @"default",
    @"payload" : JMNormalizeDictionary(unwrapped[@"payload"]),
    @"attempt" : @(envelope.attempt),
    @"maxAttempts" : @(envelope.maxAttempts),
    @"notBefore" : @([envelope.notBefore timeIntervalSince1970]),
    @"createdAt" : @([envelope.createdAt timeIntervalSince1970]),
    @"sequence" : @(envelope.sequence),
    @"state" : JMTrimmedString(state),
    @"source" : unwrapped[@"source"] ?: @"module",
    @"scheduleIdentifier" : unwrapped[@"scheduleIdentifier"] ?: @"",
    @"managed" : unwrapped[@"managed"] ?: @NO,
    @"replayedAt" : replayedAt ?: [NSNull null],
  };
}

- (NSArray<NSDictionary *> *)pendingJobs {
  NSMutableArray *jobs = [NSMutableArray array];
  for (id entry in [self.jobsAdapter pendingJobsSnapshot] ?: @[]) {
    if ([entry isKindOfClass:[ALNJobEnvelope class]]) {
      [jobs addObject:[self jobSummaryFromEnvelope:entry state:@"pending"]];
    }
  }
  return jobs;
}

- (NSArray<NSDictionary *> *)leasedJobs {
  if (![self.jobsAdapter conformsToProtocol:@protocol(ALNJobsInspectableAdapter)]) {
    return @[];
  }
  NSMutableArray *jobs = [NSMutableArray array];
  for (id entry in [(id<ALNJobsInspectableAdapter>)self.jobsAdapter leasedJobsSnapshot] ?: @[]) {
    if ([entry isKindOfClass:[ALNJobEnvelope class]]) {
      [jobs addObject:[self jobSummaryFromEnvelope:entry state:@"leased"]];
    }
  }
  return jobs;
}

- (NSArray<NSDictionary *> *)deadLetterJobs {
  NSMutableArray *jobs = [NSMutableArray array];
  for (id entry in [self.jobsAdapter deadLetterJobsSnapshot] ?: @[]) {
    if ([entry isKindOfClass:[ALNJobEnvelope class]]) {
      [jobs addObject:[self jobSummaryFromEnvelope:entry state:@"dead_letter"]];
    }
  }
  return jobs;
}

- (NSDictionary *)replayDeadLetterJobID:(NSString *)jobID
                           delaySeconds:(NSTimeInterval)delaySeconds
                                  error:(NSError **)error {
  NSString *targetJobID = JMTrimmedString(jobID);
  if ([targetJobID length] == 0) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorValidationFailed, @"dead-letter job ID is required", nil);
    }
    return nil;
  }

  ALNJobEnvelope *match = nil;
  for (id entry in [self.jobsAdapter deadLetterJobsSnapshot] ?: @[]) {
    if (![entry isKindOfClass:[ALNJobEnvelope class]]) {
      continue;
    }
    ALNJobEnvelope *envelope = entry;
    if ([JMTrimmedString(envelope.jobID) isEqualToString:targetJobID]) {
      match = envelope;
      break;
    }
  }
  if (match == nil) {
    if (error != NULL) {
      *error = JMError(ALNJobsModuleErrorNotFound,
                       [NSString stringWithFormat:@"dead-letter job %@ was not found", targetJobID],
                       @{ @"jobID" : targetJobID });
    }
    return nil;
  }

  NSDictionary *unwrapped = JMUnwrappedManagedPayload(JMNormalizeDictionary(match.payload));
  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  options[@"queue"] = unwrapped[@"queue"] ?: @"default";
  options[@"source"] = @"dead_letter_replay";
  if (delaySeconds > 0.0) {
    options[@"notBefore"] = @(delaySeconds);
  }
  NSError *enqueueError = nil;
  NSString *newJobID = [self enqueueJobIdentifier:match.name
                                          payload:unwrapped[@"payload"]
                                          options:options
                                            error:&enqueueError];
  if ([newJobID length] == 0) {
    if (error != NULL) {
      *error = enqueueError;
    }
    return nil;
  }

  [self.lock lock];
  self.replayedDeadLetterTimestamps[targetJobID] = @([[NSDate date] timeIntervalSince1970]);
  [self.lock unlock];
  if (![self persistOperatorStateWithError:error]) {
    return nil;
  }
  return @{
    @"deadLetterJobID" : targetJobID,
    @"replayedJobID" : newJobID,
  };
}

- (BOOL)pauseQueueNamed:(NSString *)queueName
                  error:(NSError **)error {
  NSString *queue = JMTrimmedString(queueName);
  if ([queue length] == 0) {
    queue = @"default";
  }
  [self.lock lock];
  [self.pausedQueues addObject:queue];
  [self.lock unlock];
  return [self persistOperatorStateWithError:error];
}

- (BOOL)resumeQueueNamed:(NSString *)queueName
                   error:(NSError **)error {
  NSString *queue = JMTrimmedString(queueName);
  if ([queue length] == 0) {
    queue = @"default";
  }
  [self.lock lock];
  [self.pausedQueues removeObject:queue];
  [self.lock unlock];
  return [self persistOperatorStateWithError:error];
}

- (BOOL)isQueuePaused:(NSString *)queueName {
  NSString *queue = JMTrimmedString(queueName);
  if ([queue length] == 0) {
    queue = @"default";
  }
  [self.lock lock];
  BOOL paused = [self.pausedQueues containsObject:queue];
  [self.lock unlock];
  return paused;
}

- (NSDictionary *)dashboardSummary {
  NSArray *definitions = [self registeredJobDefinitions];
  NSArray *schedules = [self registeredSchedules];
  NSArray *pending = [self pendingJobs];
  NSArray *leased = [self leasedJobs];
  NSArray *deadLetters = [self deadLetterJobs];
  NSMutableDictionary *queues = [NSMutableDictionary dictionary];
  for (NSDictionary *definition in definitions) {
    NSString *queue = [JMTrimmedString(definition[@"queue"]) length] > 0 ? JMTrimmedString(definition[@"queue"]) : @"default";
    if (queues[queue] == nil) {
      queues[queue] = [@{
        @"name" : queue,
        @"paused" : @([self isQueuePaused:queue]),
        @"pendingCount" : @0,
        @"leasedCount" : @0,
        @"deadLetterCount" : @0,
        @"state" : [self isQueuePaused:queue] ? @"paused" : @"active",
      } mutableCopy];
    }
  }
  for (NSDictionary *schedule in schedules) {
    NSString *queue = [JMTrimmedString(schedule[@"queue"]) length] > 0 ? JMTrimmedString(schedule[@"queue"]) : @"default";
    if (queues[queue] == nil) {
      queues[queue] = [@{
        @"name" : queue,
        @"paused" : @([self isQueuePaused:queue]),
        @"pendingCount" : @0,
        @"leasedCount" : @0,
        @"deadLetterCount" : @0,
        @"state" : [self isQueuePaused:queue] ? @"paused" : @"active",
      } mutableCopy];
    }
  }
  [self.lock lock];
  NSArray *pausedQueues = [[self.pausedQueues allObjects] copy] ?: @[];
  [self.lock unlock];
  for (NSString *queue in pausedQueues) {
    if (queues[queue] == nil) {
      queues[queue] = [@{
        @"name" : queue,
        @"paused" : @YES,
        @"pendingCount" : @0,
        @"leasedCount" : @0,
        @"deadLetterCount" : @0,
        @"state" : @"paused",
      } mutableCopy];
    }
  }
  for (NSDictionary *job in [pending arrayByAddingObjectsFromArray:leased]) {
    NSString *queue = [JMTrimmedString(job[@"queue"]) length] > 0 ? job[@"queue"] : @"default";
    NSMutableDictionary *entry = [queues[queue] isKindOfClass:[NSMutableDictionary class]]
                                     ? queues[queue]
                                     : [@{
                                         @"name" : queue,
                                         @"paused" : @([self isQueuePaused:queue]),
                                         @"pendingCount" : @0,
                                         @"leasedCount" : @0,
                                         @"deadLetterCount" : @0,
                                         @"state" : [self isQueuePaused:queue] ? @"paused" : @"active",
                                       } mutableCopy];
    if ([JMTrimmedString(job[@"state"]) isEqualToString:@"leased"]) {
      entry[@"leasedCount"] = @([entry[@"leasedCount"] unsignedIntegerValue] + 1);
    } else {
      entry[@"pendingCount"] = @([entry[@"pendingCount"] unsignedIntegerValue] + 1);
    }
    queues[queue] = entry;
  }
  for (NSDictionary *job in deadLetters) {
    NSString *queue = [JMTrimmedString(job[@"queue"]) length] > 0 ? job[@"queue"] : @"default";
    NSMutableDictionary *entry = [queues[queue] isKindOfClass:[NSMutableDictionary class]]
                                     ? queues[queue]
                                     : [@{
                                         @"name" : queue,
                                         @"paused" : @([self isQueuePaused:queue]),
                                         @"pendingCount" : @0,
                                         @"leasedCount" : @0,
                                         @"deadLetterCount" : @0,
                                         @"state" : [self isQueuePaused:queue] ? @"paused" : @"active",
                                       } mutableCopy];
    entry[@"deadLetterCount"] = @([entry[@"deadLetterCount"] unsignedIntegerValue] + 1);
    queues[queue] = entry;
  }
  NSArray *queueEntries = [[queues allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    return [JMTrimmedString(lhs[@"name"]) compare:JMTrimmedString(rhs[@"name"])];
  }];
  [self.lock lock];
  NSArray *recentRuns = [[NSArray alloc] initWithArray:self.runHistory copyItems:YES];
  [self.lock unlock];
  return @{
    @"definitions" : definitions ?: @[],
    @"schedules" : schedules ?: @[],
    @"pendingJobs" : pending ?: @[],
    @"leasedJobs" : leased ?: @[],
    @"deadLetterJobs" : deadLetters ?: @[],
    @"queues" : queueEntries ?: @[],
    @"recentRuns" : recentRuns ?: @[],
    @"totals" : @{
      @"definitions" : @([definitions count]),
      @"schedules" : @([schedules count]),
      @"pending" : @([pending count]),
      @"leased" : @([leased count]),
      @"deadLetters" : @([deadLetters count]),
    },
  };
}

@end

@implementation ALNJobsModuleController

- (instancetype)init {
  self = [super init];
  if (self) {
    _runtime = [ALNJobsModuleRuntime sharedRuntime];
    _authRuntime = JMSharedAuthRuntime();
  }
  return self;
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:[self params] ?: @{}];
  NSDictionary *bodyParameters = @{};
  NSString *contentType = JMLowerTrimmedString([self headerValueForName:@"Content-Type"]);
  if ([contentType containsString:@"application/json"]) {
    bodyParameters = JMJSONParametersFromBody(self.context.request.body);
  } else {
    bodyParameters = JMFormParametersFromBody(self.context.request.body);
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (NSString *)jobsReturnPathForContext:(ALNContext *)ctx {
  NSString *path = JMTrimmedString(ctx.request.path);
  return [path length] > 0 ? path : (self.runtime.prefix ?: @"/jobs");
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                                extra:(NSDictionary *)extra {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: @"Arlen Jobs";
  context[@"pageHeading"] = heading ?: context[@"pageTitle"];
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"jobsPrefix"] = self.runtime.prefix ?: @"/jobs";
  context[@"jobsAPIPrefix"] = self.runtime.apiPrefix ?: @"/jobs/api";
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"summary"] = [self.runtime dashboardSummary] ?: @{};
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extra];
  }
  return context;
}

- (BOOL)requireJobsHTML:(ALNContext *)ctx {
  NSString *returnTo = [self jobsReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    JMPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  BOOL adminAllowed = [self.authRuntime respondsToSelector:@selector(isAdminContext:error:)]
                          ? [self.authRuntime isAdminContext:ctx error:NULL]
                          : [[ctx authRoles] containsObject:@"admin"];
  if (!adminAllowed) {
    [self setStatus:403];
    [self renderTemplate:@"modules/jobs/result/index"
                 context:[self pageContextWithTitle:@"Jobs Access"
                                            heading:@"Access denied"
                                            message:@"You do not have the operator/admin role required for jobs."
                                             errors:nil
                                              extra:nil]
                  layout:@"modules/jobs/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < 2) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                                                    JMPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (id)dashboard:(ALNContext *)ctx {
  (void)ctx;
  [self renderTemplate:@"modules/jobs/dashboard/index"
               context:[self pageContextWithTitle:@"Jobs"
                                          heading:@"Jobs"
                                          message:@""
                                           errors:nil
                                            extra:nil]
                layout:@"modules/jobs/layouts/main"
                 error:NULL];
  return nil;
}

- (id)runSchedulerHTML:(ALNContext *)ctx {
  (void)ctx;
  [self.runtime runSchedulerAt:[NSDate date] error:NULL];
  [self redirectTo:self.runtime.prefix ?: @"/jobs" status:302];
  return nil;
}

- (id)runWorkerHTML:(ALNContext *)ctx {
  (void)ctx;
  [self.runtime runWorkerAt:[NSDate date] limit:0 error:NULL];
  [self redirectTo:self.runtime.prefix ?: @"/jobs" status:302];
  return nil;
}

- (id)apiDefinitions:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"definitions" : [self.runtime registeredJobDefinitions] ?: @[] }
                              meta:nil
                             error:NULL];
  return nil;
}

- (id)apiSchedules:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"schedules" : [self.runtime registeredSchedules] ?: @[] }
                              meta:nil
                             error:NULL];
  return nil;
}

- (id)apiQueues:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *summary = [self.runtime dashboardSummary];
  [self renderJSONEnvelopeWithData:@{ @"queues" : summary[@"queues"] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiPendingJobs:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"jobs" : [self.runtime pendingJobs] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiLeasedJobs:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"jobs" : [self.runtime leasedJobs] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiDeadLetterJobs:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"jobs" : [self.runtime deadLetterJobs] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiEnqueue:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSString *identifier = JMTrimmedString(parameters[@"job"]);
  NSDictionary *payload = JMNormalizeDictionary(parameters[@"payload"]);
  if ([payload count] == 0 && [parameters[@"payload_json"] isKindOfClass:[NSString class]]) {
    NSData *jsonData = [parameters[@"payload_json"] dataUsingEncoding:NSUTF8StringEncoding];
    id object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
    payload = [object isKindOfClass:[NSDictionary class]] ? object : @{};
  }
  NSError *error = nil;
  NSString *jobID = [self.runtime enqueueJobIdentifier:identifier
                                               payload:payload
                                               options:@{
                                                 @"queue" : JMTrimmedString(parameters[@"queue"]),
                                                 @"idempotencyKey" : JMTrimmedString(parameters[@"idempotencyKey"]),
                                               }
                                                 error:&error];
  if ([jobID length] == 0) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil
                                meta:@{
                                  @"error" : [error localizedDescription] ?: @"enqueue failed",
                                }
                               error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"jobID" : jobID } meta:nil error:NULL];
  return nil;
}

- (id)apiRunScheduler:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *summary = [self.runtime runSchedulerAt:[NSDate date] error:&error];
  if (summary == nil) {
    [self setStatus:500];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"scheduler failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:summary meta:nil error:NULL];
  return nil;
}

- (id)apiRunWorker:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSUInteger limit = [parameters[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)]
                         ? [parameters[@"limit"] unsignedIntegerValue]
                         : 0;
  NSError *error = nil;
  NSDictionary *summary = [self.runtime runWorkerAt:[NSDate date] limit:limit error:&error];
  if (summary == nil) {
    [self setStatus:500];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"worker failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:summary meta:nil error:NULL];
  return nil;
}

- (id)apiReplayDeadLetter:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *summary = [self.runtime replayDeadLetterJobID:[self stringParamForName:@"jobID"] ?: @""
                                                 delaySeconds:[parameters[@"delaySeconds"] respondsToSelector:@selector(doubleValue)]
                                                                  ? [parameters[@"delaySeconds"] doubleValue]
                                                                  : 0.0
                                                        error:&error];
  if (summary == nil) {
    [self setStatus:(error.code == ALNJobsModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"replay failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:summary meta:nil error:NULL];
  return nil;
}

- (id)apiPauseQueue:(ALNContext *)ctx {
  NSError *error = nil;
  BOOL ok = [self.runtime pauseQueueNamed:[self stringParamForName:@"queue"] ?: @"default" error:&error];
  if (!ok) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"pause failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"queue" : [self stringParamForName:@"queue"] ?: @"default", @"paused" : @YES }
                              meta:nil
                             error:NULL];
  return nil;
}

- (id)apiResumeQueue:(ALNContext *)ctx {
  NSError *error = nil;
  BOOL ok = [self.runtime resumeQueueNamed:[self stringParamForName:@"queue"] ?: @"default" error:&error];
  if (!ok) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"resume failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"queue" : [self stringParamForName:@"queue"] ?: @"default", @"paused" : @NO }
                              meta:nil
                             error:NULL];
  return nil;
}

@end

@implementation ALNJobsModule

- (NSString *)moduleIdentifier {
  return @"jobs";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireJobsHTML" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/"
                              name:@"jobs_dashboard"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"dashboard"];
  [application registerRouteMethod:@"POST"
                              path:@"/run-scheduler"
                              name:@"jobs_run_scheduler_html"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"runSchedulerHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/run-worker"
                              name:@"jobs_run_worker_html"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"runWorkerHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/definitions"
                              name:@"jobs_api_definitions"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiDefinitions"];
  [application registerRouteMethod:@"GET"
                              path:@"/schedules"
                              name:@"jobs_api_schedules"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiSchedules"];
  [application registerRouteMethod:@"GET"
                              path:@"/queues"
                              name:@"jobs_api_queues"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiQueues"];
  [application registerRouteMethod:@"GET"
                              path:@"/jobs/pending"
                              name:@"jobs_api_pending"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiPendingJobs"];
  [application registerRouteMethod:@"GET"
                              path:@"/jobs/leased"
                              name:@"jobs_api_leased"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiLeasedJobs"];
  [application registerRouteMethod:@"GET"
                              path:@"/jobs/dead-letter"
                              name:@"jobs_api_dead_letter"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiDeadLetterJobs"];
  [application registerRouteMethod:@"POST"
                              path:@"/enqueue"
                              name:@"jobs_api_enqueue"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiEnqueue"];
  [application registerRouteMethod:@"POST"
                              path:@"/run-scheduler"
                              name:@"jobs_api_run_scheduler"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiRunScheduler"];
  [application registerRouteMethod:@"POST"
                              path:@"/run-worker"
                              name:@"jobs_api_run_worker"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiRunWorker"];
  [application registerRouteMethod:@"POST"
                              path:@"/jobs/dead-letter/:jobID/replay"
                              name:@"jobs_api_dead_letter_replay"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiReplayDeadLetter"];
  [application registerRouteMethod:@"POST"
                              path:@"/queues/:queue/pause"
                              name:@"jobs_api_queue_pause"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiPauseQueue"];
  [application registerRouteMethod:@"POST"
                              path:@"/queues/:queue/resume"
                              name:@"jobs_api_queue_resume"
                   controllerClass:[ALNJobsModuleController class]
                            action:@"apiResumeQueue"];
  [application endRouteGroup];

  NSArray *apiRoutes = @[
    @"jobs_api_definitions",
    @"jobs_api_schedules",
    @"jobs_api_queues",
    @"jobs_api_pending",
    @"jobs_api_leased",
    @"jobs_api_dead_letter",
    @"jobs_api_enqueue",
    @"jobs_api_run_scheduler",
    @"jobs_api_run_worker",
    @"jobs_api_dead_letter_replay",
    @"jobs_api_queue_pause",
    @"jobs_api_queue_resume",
  ];
  for (NSString *routeName in apiRoutes) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Jobs module API"
                         operationID:routeName
                                tags:@[ @"jobs" ]
                      requiredScopes:nil
                       requiredRoles:@[ @"admin" ]
                     includeInOpenAPI:YES
                                error:NULL];
    id<ALNJobsOptionalAuthRuntime> authRuntime = JMSharedAuthRuntime();
    [application configureAuthAssuranceForRouteNamed:routeName
                           minimumAuthAssuranceLevel:2
                     maximumAuthenticationAgeSeconds:0
                                          stepUpPath:[authRuntime totpPath] ?: @"/auth/mfa/totp"
                                               error:NULL];
  }

  return YES;
}

@end
