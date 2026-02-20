#import "ALNServices.h"

NSString *const ALNServiceErrorDomain = @"Arlen.Services.Error";

static NSError *ALNServiceError(NSInteger code, NSString *message, NSError *underlying) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"service error";
  if (underlying != nil) {
    userInfo[NSUnderlyingErrorKey] = underlying;
  }
  return [NSError errorWithDomain:ALNServiceErrorDomain code:code userInfo:userInfo];
}

static NSString *ALNNonEmptyString(NSString *value, NSString *defaultValue) {
  if (![value isKindOfClass:[NSString class]]) {
    return defaultValue ?: @"";
  }
  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return defaultValue ?: @"";
  }
  return trimmed;
}

static NSArray *ALNNormalizeStringArray(NSArray *values) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = ALNNonEmptyString(value, @"");
    if ([trimmed length] == 0) {
      continue;
    }
    [normalized addObject:trimmed];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSDictionary *ALNNormalizeDictionary(NSDictionary *value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSString *ALNNormalizeLocale(NSString *locale) {
  NSString *value = ALNNonEmptyString(locale, @"");
  value = [[value lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
  return value;
}

@interface ALNJobEnvelope ()

@property(nonatomic, copy, readwrite) NSString *jobID;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSDictionary *payload;
@property(nonatomic, assign, readwrite) NSUInteger attempt;
@property(nonatomic, assign, readwrite) NSUInteger maxAttempts;
@property(nonatomic, strong, readwrite) NSDate *notBefore;
@property(nonatomic, strong, readwrite) NSDate *createdAt;
@property(nonatomic, assign, readwrite) NSUInteger sequence;

@end

@implementation ALNJobEnvelope

- (instancetype)initWithJobID:(NSString *)jobID
                         name:(NSString *)name
                      payload:(NSDictionary *)payload
                      attempt:(NSUInteger)attempt
                  maxAttempts:(NSUInteger)maxAttempts
                    notBefore:(NSDate *)notBefore
                    createdAt:(NSDate *)createdAt
                     sequence:(NSUInteger)sequence {
  self = [super init];
  if (self) {
    _jobID = [ALNNonEmptyString(jobID, @"") copy];
    _name = [ALNNonEmptyString(name, @"") copy];
    _payload = [ALNNormalizeDictionary(payload) copy];
    _attempt = attempt;
    _maxAttempts = (maxAttempts > 0) ? maxAttempts : 1;
    _notBefore = notBefore ?: [NSDate date];
    _createdAt = createdAt ?: [NSDate date];
    _sequence = sequence;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[ALNJobEnvelope allocWithZone:zone] initWithJobID:self.jobID
                                                       name:self.name
                                                    payload:self.payload
                                                    attempt:self.attempt
                                                maxAttempts:self.maxAttempts
                                                  notBefore:self.notBefore
                                                  createdAt:self.createdAt
                                                   sequence:self.sequence];
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    @"jobID" : self.jobID ?: @"",
    @"name" : self.name ?: @"",
    @"payload" : self.payload ?: @{},
    @"attempt" : @(self.attempt),
    @"maxAttempts" : @(self.maxAttempts),
    @"notBefore" : @([self.notBefore timeIntervalSince1970]),
    @"createdAt" : @([self.createdAt timeIntervalSince1970]),
    @"sequence" : @(self.sequence),
  };
}

@end

@interface ALNJobWorkerRunSummary ()

@property(nonatomic, assign, readwrite) NSUInteger leasedCount;
@property(nonatomic, assign, readwrite) NSUInteger acknowledgedCount;
@property(nonatomic, assign, readwrite) NSUInteger retriedCount;
@property(nonatomic, assign, readwrite) NSUInteger handlerErrorCount;
@property(nonatomic, assign, readwrite) BOOL reachedRunLimit;

@end

@implementation ALNJobWorkerRunSummary

- (instancetype)initWithLeasedCount:(NSUInteger)leasedCount
                  acknowledgedCount:(NSUInteger)acknowledgedCount
                       retriedCount:(NSUInteger)retriedCount
                  handlerErrorCount:(NSUInteger)handlerErrorCount
                    reachedRunLimit:(BOOL)reachedRunLimit {
  self = [super init];
  if (self) {
    _leasedCount = leasedCount;
    _acknowledgedCount = acknowledgedCount;
    _retriedCount = retriedCount;
    _handlerErrorCount = handlerErrorCount;
    _reachedRunLimit = reachedRunLimit;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[ALNJobWorkerRunSummary allocWithZone:zone] initWithLeasedCount:self.leasedCount
                                                         acknowledgedCount:self.acknowledgedCount
                                                              retriedCount:self.retriedCount
                                                         handlerErrorCount:self.handlerErrorCount
                                                           reachedRunLimit:self.reachedRunLimit];
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    @"leasedCount" : @(self.leasedCount),
    @"acknowledgedCount" : @(self.acknowledgedCount),
    @"retriedCount" : @(self.retriedCount),
    @"handlerErrorCount" : @(self.handlerErrorCount),
    @"reachedRunLimit" : @(self.reachedRunLimit),
  };
}

@end

@interface ALNJobWorker ()

@property(nonatomic, strong) id<ALNJobAdapter> jobsAdapter;

@end

@implementation ALNJobWorker

- (instancetype)initWithJobsAdapter:(id<ALNJobAdapter>)jobsAdapter {
  self = [super init];
  if (self) {
    _jobsAdapter = jobsAdapter;
    _maxJobsPerRun = 50;
    _retryDelaySeconds = 5.0;
  }
  return self;
}

- (ALNJobWorkerRunSummary *)runDueJobsAt:(NSDate *)timestamp
                                  runtime:(id<ALNJobWorkerRuntime>)runtime
                                    error:(NSError **)error {
  if (self.jobsAdapter == nil) {
    if (error != NULL) {
      *error = ALNServiceError(500, @"jobs adapter is required", nil);
    }
    return nil;
  }
  if (runtime == nil) {
    if (error != NULL) {
      *error = ALNServiceError(501, @"job worker runtime is required", nil);
    }
    return nil;
  }

  NSDate *runAt = timestamp ?: [NSDate date];
  NSUInteger maxJobs = (self.maxJobsPerRun > 0) ? self.maxJobsPerRun : 1;
  NSUInteger leasedCount = 0;
  NSUInteger acknowledgedCount = 0;
  NSUInteger retriedCount = 0;
  NSUInteger handlerErrorCount = 0;
  BOOL reachedRunLimit = NO;

  for (NSUInteger index = 0; index < maxJobs; index++) {
    NSError *dequeueError = nil;
    ALNJobEnvelope *job = [self.jobsAdapter dequeueDueJobAt:runAt error:&dequeueError];
    if (dequeueError != nil) {
      if (error != NULL) {
        *error = ALNServiceError(502, @"failed to dequeue due job", dequeueError);
      }
      return nil;
    }
    if (job == nil) {
      reachedRunLimit = NO;
      break;
    }

    leasedCount += 1;

    NSError *handlerError = nil;
    ALNJobWorkerDisposition disposition = [runtime handleJob:job error:&handlerError];
    if (handlerError != nil) {
      handlerErrorCount += 1;
    }

    if (disposition == ALNJobWorkerDispositionAcknowledge) {
      NSError *ackError = nil;
      if (![self.jobsAdapter acknowledgeJobID:job.jobID error:&ackError]) {
        if (error != NULL) {
          *error = ALNServiceError(503, @"failed to acknowledge job", ackError);
        }
        return nil;
      }
      acknowledgedCount += 1;
      continue;
    }

    NSTimeInterval retryDelay = (self.retryDelaySeconds > 0.0) ? self.retryDelaySeconds : 0.0;
    NSError *retryError = nil;
    if (![self.jobsAdapter retryJob:job delaySeconds:retryDelay error:&retryError]) {
      if (error != NULL) {
        *error = ALNServiceError(504, @"failed to retry job", retryError);
      }
      return nil;
    }
    retriedCount += 1;
  }

  if (leasedCount >= maxJobs) {
    reachedRunLimit = YES;
  }

  return [[ALNJobWorkerRunSummary alloc] initWithLeasedCount:leasedCount
                                            acknowledgedCount:acknowledgedCount
                                                 retriedCount:retriedCount
                                            handlerErrorCount:handlerErrorCount
                                              reachedRunLimit:reachedRunLimit];
}

@end

@interface ALNInMemoryJobAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableArray *pending;
@property(nonatomic, strong) NSMutableDictionary *leasedByID;
@property(nonatomic, strong) NSMutableArray *deadLetters;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) NSUInteger sequenceCounter;

@end

@implementation ALNInMemoryJobAdapter

- (instancetype)init {
  return [self initWithAdapterName:nil];
}

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    _adapterNameValue = [ALNNonEmptyString(adapterName, @"in_memory_jobs") copy];
    _pending = [NSMutableArray array];
    _leasedByID = [NSMutableDictionary dictionary];
    _deadLetters = [NSMutableArray array];
    _lock = [[NSLock alloc] init];
    _sequenceCounter = 0;
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"in_memory_jobs";
}

- (void)insertPendingEnvelope:(ALNJobEnvelope *)envelope {
  NSUInteger index = 0;
  for (id candidate in self.pending) {
    if (![candidate isKindOfClass:[ALNJobEnvelope class]]) {
      index += 1;
      continue;
    }
    ALNJobEnvelope *current = (ALNJobEnvelope *)candidate;
    NSComparisonResult dueOrder = [current.notBefore compare:envelope.notBefore];
    if (dueOrder == NSOrderedDescending) {
      break;
    }
    if (dueOrder == NSOrderedSame && current.sequence > envelope.sequence) {
      break;
    }
    index += 1;
  }
  [self.pending insertObject:envelope atIndex:index];
}

- (NSString *)enqueueJobNamed:(NSString *)name
                      payload:(NSDictionary *)payload
                      options:(NSDictionary *)options
                        error:(NSError **)error {
  NSString *normalizedName = ALNNonEmptyString(name, @"");
  if ([normalizedName length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(100, @"job name is required", nil);
    }
    return nil;
  }

  NSDictionary *normalizedOptions = ALNNormalizeDictionary(options);
  NSUInteger maxAttempts = 3;
  id configuredAttempts = normalizedOptions[@"maxAttempts"];
  if ([configuredAttempts respondsToSelector:@selector(unsignedIntegerValue)] &&
      [configuredAttempts unsignedIntegerValue] > 0) {
    maxAttempts = [configuredAttempts unsignedIntegerValue];
  }

  NSDate *notBefore = [NSDate date];
  id configuredNotBefore = normalizedOptions[@"notBefore"];
  if ([configuredNotBefore isKindOfClass:[NSDate class]]) {
    notBefore = configuredNotBefore;
  } else if ([configuredNotBefore respondsToSelector:@selector(doubleValue)]) {
    NSTimeInterval delay = [configuredNotBefore doubleValue];
    if (delay > 0) {
      notBefore = [NSDate dateWithTimeIntervalSinceNow:delay];
    }
  }

  [self.lock lock];
  self.sequenceCounter += 1;
  NSString *jobID = [NSString stringWithFormat:@"job-%lu", (unsigned long)self.sequenceCounter];
  ALNJobEnvelope *envelope = [[ALNJobEnvelope alloc] initWithJobID:jobID
                                                               name:normalizedName
                                                            payload:ALNNormalizeDictionary(payload)
                                                            attempt:0
                                                        maxAttempts:maxAttempts
                                                          notBefore:notBefore
                                                          createdAt:[NSDate date]
                                                           sequence:self.sequenceCounter];
  [self insertPendingEnvelope:envelope];
  [self.lock unlock];
  return jobID;
}

- (ALNJobEnvelope *)dequeueDueJobAt:(NSDate *)timestamp error:(NSError **)error {
  (void)error;
  NSDate *now = timestamp ?: [NSDate date];

  [self.lock lock];
  NSUInteger foundIndex = NSNotFound;
  ALNJobEnvelope *selected = nil;
  for (NSUInteger idx = 0; idx < [self.pending count]; idx++) {
    id candidate = self.pending[idx];
    if (![candidate isKindOfClass:[ALNJobEnvelope class]]) {
      continue;
    }
    ALNJobEnvelope *current = (ALNJobEnvelope *)candidate;
    if ([current.notBefore compare:now] != NSOrderedDescending) {
      foundIndex = idx;
      selected = current;
      break;
    }
  }

  if (foundIndex == NSNotFound || selected == nil) {
    [self.lock unlock];
    return nil;
  }

  [self.pending removeObjectAtIndex:foundIndex];
  ALNJobEnvelope *leased = [[ALNJobEnvelope alloc] initWithJobID:selected.jobID
                                                             name:selected.name
                                                          payload:selected.payload
                                                          attempt:selected.attempt + 1
                                                      maxAttempts:selected.maxAttempts
                                                        notBefore:selected.notBefore
                                                        createdAt:selected.createdAt
                                                         sequence:selected.sequence];
  self.leasedByID[leased.jobID] = leased;
  [self.lock unlock];
  return [leased copy];
}

- (BOOL)acknowledgeJobID:(NSString *)jobID error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(jobID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(101, @"job ID is required", nil);
    }
    return NO;
  }

  [self.lock lock];
  BOOL exists = (self.leasedByID[normalizedID] != nil);
  if (exists) {
    [self.leasedByID removeObjectForKey:normalizedID];
  }
  [self.lock unlock];

  if (!exists && error != NULL) {
    *error = ALNServiceError(102, @"job is not currently leased", nil);
  }
  return exists;
}

- (BOOL)retryJob:(ALNJobEnvelope *)job
    delaySeconds:(NSTimeInterval)delaySeconds
           error:(NSError **)error {
  if (![job isKindOfClass:[ALNJobEnvelope class]]) {
    if (error != NULL) {
      *error = ALNServiceError(103, @"job envelope is required", nil);
    }
    return NO;
  }

  NSString *jobID = ALNNonEmptyString(job.jobID, @"");
  if ([jobID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(104, @"job ID is required for retry", nil);
    }
    return NO;
  }

  [self.lock lock];
  ALNJobEnvelope *leased = [self.leasedByID[jobID] isKindOfClass:[ALNJobEnvelope class]]
                               ? self.leasedByID[jobID]
                               : nil;
  if (leased == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(105, @"job is not currently leased", nil);
    }
    return NO;
  }

  [self.leasedByID removeObjectForKey:jobID];
  if (leased.attempt >= leased.maxAttempts) {
    [self.deadLetters addObject:leased];
    [self.lock unlock];
    return YES;
  }

  NSTimeInterval safeDelay = (delaySeconds > 0.0) ? delaySeconds : 0.0;
  ALNJobEnvelope *requeued = [[ALNJobEnvelope alloc] initWithJobID:leased.jobID
                                                               name:leased.name
                                                            payload:leased.payload
                                                            attempt:leased.attempt
                                                        maxAttempts:leased.maxAttempts
                                                          notBefore:[NSDate dateWithTimeIntervalSinceNow:safeDelay]
                                                          createdAt:leased.createdAt
                                                           sequence:leased.sequence];
  [self insertPendingEnvelope:requeued];
  [self.lock unlock];
  return YES;
}

- (NSArray *)pendingJobsSnapshot {
  [self.lock lock];
  NSArray *snapshot = [NSArray arrayWithArray:self.pending];
  [self.lock unlock];
  return snapshot;
}

- (NSArray *)deadLetterJobsSnapshot {
  [self.lock lock];
  NSArray *snapshot = [NSArray arrayWithArray:self.deadLetters];
  [self.lock unlock];
  return snapshot;
}

- (void)reset {
  [self.lock lock];
  [self.pending removeAllObjects];
  [self.leasedByID removeAllObjects];
  [self.deadLetters removeAllObjects];
  self.sequenceCounter = 0;
  [self.lock unlock];
}

@end

@interface ALNInMemoryCacheAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableDictionary *entriesByKey;
@property(nonatomic, strong) NSLock *lock;

@end

@implementation ALNInMemoryCacheAdapter

- (instancetype)init {
  return [self initWithAdapterName:nil];
}

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    _adapterNameValue = [ALNNonEmptyString(adapterName, @"in_memory_cache") copy];
    _entriesByKey = [NSMutableDictionary dictionary];
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"in_memory_cache";
}

- (BOOL)setObject:(id)object
           forKey:(NSString *)key
       ttlSeconds:(NSTimeInterval)ttlSeconds
            error:(NSError **)error {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(200, @"cache key is required", nil);
    }
    return NO;
  }

  [self.lock lock];
  if (object == nil || object == [NSNull null]) {
    [self.entriesByKey removeObjectForKey:normalizedKey];
    [self.lock unlock];
    return YES;
  }

  NSDate *expiresAt = nil;
  if (ttlSeconds > 0.0) {
    expiresAt = [NSDate dateWithTimeIntervalSinceNow:ttlSeconds];
  }
  self.entriesByKey[normalizedKey] = @{
    @"value" : object,
    @"expiresAt" : expiresAt ?: [NSNull null]
  };
  [self.lock unlock];
  return YES;
}

- (id)objectForKey:(NSString *)key atTime:(NSDate *)timestamp error:(NSError **)error {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(201, @"cache key is required", nil);
    }
    return nil;
  }

  NSDate *now = timestamp ?: [NSDate date];
  [self.lock lock];
  NSDictionary *entry = [self.entriesByKey[normalizedKey] isKindOfClass:[NSDictionary class]]
                             ? self.entriesByKey[normalizedKey]
                             : nil;
  if (entry == nil) {
    [self.lock unlock];
    return nil;
  }

  NSDate *expiresAt = [entry[@"expiresAt"] isKindOfClass:[NSDate class]] ? entry[@"expiresAt"] : nil;
  if (expiresAt != nil && [expiresAt compare:now] != NSOrderedDescending) {
    [self.entriesByKey removeObjectForKey:normalizedKey];
    [self.lock unlock];
    return nil;
  }

  id value = entry[@"value"];
  [self.lock unlock];
  return value;
}

- (BOOL)removeObjectForKey:(NSString *)key error:(NSError **)error {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(202, @"cache key is required", nil);
    }
    return NO;
  }

  [self.lock lock];
  [self.entriesByKey removeObjectForKey:normalizedKey];
  [self.lock unlock];
  return YES;
}

- (BOOL)clearWithError:(NSError **)error {
  (void)error;
  [self.lock lock];
  [self.entriesByKey removeAllObjects];
  [self.lock unlock];
  return YES;
}

@end

@interface ALNInMemoryLocalizationAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableDictionary *catalogByLocale;
@property(nonatomic, strong) NSLock *lock;

@end

@implementation ALNInMemoryLocalizationAdapter

- (instancetype)init {
  return [self initWithAdapterName:nil];
}

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    _adapterNameValue = [ALNNonEmptyString(adapterName, @"in_memory_i18n") copy];
    _catalogByLocale = [NSMutableDictionary dictionary];
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"in_memory_i18n";
}

- (BOOL)registerTranslations:(NSDictionary *)translations
                      locale:(NSString *)locale
                       error:(NSError **)error {
  NSString *normalizedLocale = ALNNormalizeLocale(locale);
  if ([normalizedLocale length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(300, @"locale is required", nil);
    }
    return NO;
  }

  NSDictionary *incoming = ALNNormalizeDictionary(translations);
  NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
  for (id key in incoming) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *stringKey = ALNNonEmptyString(key, @"");
    if ([stringKey length] == 0) {
      continue;
    }
    id value = incoming[key];
    if ([value isKindOfClass:[NSString class]]) {
      filtered[stringKey] = value;
    } else if ([value respondsToSelector:@selector(description)]) {
      filtered[stringKey] = [value description];
    }
  }

  [self.lock lock];
  NSMutableDictionary *existing =
      [self.catalogByLocale[normalizedLocale] isKindOfClass:[NSMutableDictionary class]]
          ? self.catalogByLocale[normalizedLocale]
          : [NSMutableDictionary dictionary];
  [existing addEntriesFromDictionary:filtered];
  self.catalogByLocale[normalizedLocale] = existing;
  [self.lock unlock];
  return YES;
}

- (NSString *)applyArguments:(NSDictionary *)arguments toTemplate:(NSString *)template {
  NSString *resolved = template ?: @"";
  for (id key in arguments ?: @{}) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *placeholder = [NSString stringWithFormat:@"%%{%@}", key];
    id value = arguments[key];
    NSString *replacement = [value respondsToSelector:@selector(description)] ? [value description] : @"";
    resolved = [resolved stringByReplacingOccurrencesOfString:placeholder withString:replacement ?: @""];
  }
  return resolved;
}

- (NSString *)localizedStringForKey:(NSString *)key
                             locale:(NSString *)locale
                     fallbackLocale:(NSString *)fallbackLocale
                       defaultValue:(NSString *)defaultValue
                          arguments:(NSDictionary *)arguments {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    return defaultValue ?: @"";
  }

  NSString *primaryLocale = ALNNormalizeLocale(locale);
  NSString *fallback = ALNNormalizeLocale(fallbackLocale);
  if ([primaryLocale length] == 0) {
    primaryLocale = fallback;
  }
  if ([fallback length] == 0) {
    fallback = @"en";
  }

  NSString *template = nil;
  [self.lock lock];
  NSDictionary *primaryCatalog = [self.catalogByLocale[primaryLocale] isKindOfClass:[NSDictionary class]]
                                     ? self.catalogByLocale[primaryLocale]
                                     : nil;
  template = [primaryCatalog[normalizedKey] isKindOfClass:[NSString class]]
                 ? primaryCatalog[normalizedKey]
                 : nil;

  if (template == nil) {
    NSDictionary *fallbackCatalog = [self.catalogByLocale[fallback] isKindOfClass:[NSDictionary class]]
                                        ? self.catalogByLocale[fallback]
                                        : nil;
    template = [fallbackCatalog[normalizedKey] isKindOfClass:[NSString class]]
                   ? fallbackCatalog[normalizedKey]
                   : nil;
  }
  [self.lock unlock];

  NSString *resolvedTemplate = template ?: defaultValue ?: normalizedKey;
  return [self applyArguments:ALNNormalizeDictionary(arguments) toTemplate:resolvedTemplate];
}

- (NSArray *)availableLocales {
  [self.lock lock];
  NSArray *locales = [[self.catalogByLocale allKeys] sortedArrayUsingSelector:@selector(compare:)];
  [self.lock unlock];
  return locales ?: @[];
}

@end

@interface ALNMailMessage ()

@property(nonatomic, copy, readwrite) NSString *from;
@property(nonatomic, copy, readwrite) NSArray *to;
@property(nonatomic, copy, readwrite) NSArray *cc;
@property(nonatomic, copy, readwrite) NSArray *bcc;
@property(nonatomic, copy, readwrite) NSString *subject;
@property(nonatomic, copy, readwrite) NSString *textBody;
@property(nonatomic, copy, readwrite) NSString *htmlBody;
@property(nonatomic, copy, readwrite) NSDictionary *headers;
@property(nonatomic, copy, readwrite) NSDictionary *metadata;

@end

@implementation ALNMailMessage

- (instancetype)initWithFrom:(NSString *)from
                          to:(NSArray *)to
                          cc:(NSArray *)cc
                         bcc:(NSArray *)bcc
                     subject:(NSString *)subject
                    textBody:(NSString *)textBody
                    htmlBody:(NSString *)htmlBody
                     headers:(NSDictionary *)headers
                    metadata:(NSDictionary *)metadata {
  self = [super init];
  if (self) {
    _from = [ALNNonEmptyString(from, @"") copy];
    _to = [ALNNormalizeStringArray(to) copy];
    _cc = [ALNNormalizeStringArray(cc) copy];
    _bcc = [ALNNormalizeStringArray(bcc) copy];
    _subject = [ALNNonEmptyString(subject, @"") copy];
    _textBody = [textBody isKindOfClass:[NSString class]] ? [textBody copy] : @"";
    _htmlBody = [htmlBody isKindOfClass:[NSString class]] ? [htmlBody copy] : @"";
    _headers = [ALNNormalizeDictionary(headers) copy];
    _metadata = [ALNNormalizeDictionary(metadata) copy];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[ALNMailMessage allocWithZone:zone] initWithFrom:self.from
                                                         to:self.to
                                                         cc:self.cc
                                                        bcc:self.bcc
                                                    subject:self.subject
                                                   textBody:self.textBody
                                                   htmlBody:self.htmlBody
                                                    headers:self.headers
                                                   metadata:self.metadata];
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    @"from" : self.from ?: @"",
    @"to" : self.to ?: @[],
    @"cc" : self.cc ?: @[],
    @"bcc" : self.bcc ?: @[],
    @"subject" : self.subject ?: @"",
    @"textBody" : self.textBody ?: @"",
    @"htmlBody" : self.htmlBody ?: @"",
    @"headers" : self.headers ?: @{},
    @"metadata" : self.metadata ?: @{},
  };
}

@end

@interface ALNInMemoryMailAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableArray *deliveries;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) NSUInteger nextDeliveryID;

@end

@implementation ALNInMemoryMailAdapter

- (instancetype)init {
  return [self initWithAdapterName:nil];
}

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    _adapterNameValue = [ALNNonEmptyString(adapterName, @"in_memory_mail") copy];
    _deliveries = [NSMutableArray array];
    _lock = [[NSLock alloc] init];
    _nextDeliveryID = 0;
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"in_memory_mail";
}

- (NSString *)deliverMessage:(ALNMailMessage *)message error:(NSError **)error {
  if (![message isKindOfClass:[ALNMailMessage class]]) {
    if (error != NULL) {
      *error = ALNServiceError(400, @"mail message is required", nil);
    }
    return nil;
  }
  if ([[message to] count] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(401, @"mail message requires at least one recipient", nil);
    }
    return nil;
  }

  [self.lock lock];
  self.nextDeliveryID += 1;
  NSString *deliveryID = [NSString stringWithFormat:@"mail-%lu", (unsigned long)self.nextDeliveryID];
  [self.deliveries addObject:@{
    @"deliveryID" : deliveryID,
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"message" : [message dictionaryRepresentation],
  }];
  [self.lock unlock];
  return deliveryID;
}

- (NSArray *)deliveriesSnapshot {
  [self.lock lock];
  NSArray *snapshot = [NSArray arrayWithArray:self.deliveries];
  [self.lock unlock];
  return snapshot;
}

- (void)reset {
  [self.lock lock];
  [self.deliveries removeAllObjects];
  self.nextDeliveryID = 0;
  [self.lock unlock];
}

@end

@interface ALNInMemoryAttachmentAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableDictionary *attachmentByID;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) NSUInteger nextAttachmentID;

@end

@implementation ALNInMemoryAttachmentAdapter

- (instancetype)init {
  return [self initWithAdapterName:nil];
}

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    _adapterNameValue = [ALNNonEmptyString(adapterName, @"in_memory_attachment") copy];
    _attachmentByID = [NSMutableDictionary dictionary];
    _lock = [[NSLock alloc] init];
    _nextAttachmentID = 0;
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"in_memory_attachment";
}

- (NSString *)saveAttachmentNamed:(NSString *)name
                      contentType:(NSString *)contentType
                             data:(NSData *)data
                         metadata:(NSDictionary *)metadata
                            error:(NSError **)error {
  NSString *normalizedName = ALNNonEmptyString(name, @"");
  if ([normalizedName length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(500, @"attachment name is required", nil);
    }
    return nil;
  }
  if (![data isKindOfClass:[NSData class]]) {
    if (error != NULL) {
      *error = ALNServiceError(501, @"attachment data is required", nil);
    }
    return nil;
  }

  NSString *normalizedType = ALNNonEmptyString(contentType, @"application/octet-stream");
  NSDictionary *userMetadata = ALNNormalizeDictionary(metadata);

  [self.lock lock];
  self.nextAttachmentID += 1;
  NSString *attachmentID = [NSString stringWithFormat:@"att-%lu", (unsigned long)self.nextAttachmentID];
  self.attachmentByID[attachmentID] = @{
    @"attachmentID" : attachmentID,
    @"name" : normalizedName,
    @"contentType" : normalizedType,
    @"sizeBytes" : @([data length]),
    @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
    @"metadata" : userMetadata,
    @"data" : data,
  };
  [self.lock unlock];
  return attachmentID;
}

- (NSData *)attachmentDataForID:(NSString *)attachmentID
                       metadata:(NSDictionary **)metadata
                          error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(attachmentID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(502, @"attachment ID is required", nil);
    }
    return nil;
  }

  [self.lock lock];
  NSDictionary *entry = [self.attachmentByID[normalizedID] isKindOfClass:[NSDictionary class]]
                            ? self.attachmentByID[normalizedID]
                            : nil;
  if (entry == nil) {
    [self.lock unlock];
    return nil;
  }

  if (metadata != NULL) {
    *metadata = @{
      @"attachmentID" : entry[@"attachmentID"] ?: @"",
      @"name" : entry[@"name"] ?: @"",
      @"contentType" : entry[@"contentType"] ?: @"application/octet-stream",
      @"sizeBytes" : entry[@"sizeBytes"] ?: @(0),
      @"createdAt" : entry[@"createdAt"] ?: @(0),
      @"metadata" : entry[@"metadata"] ?: @{},
    };
  }

  NSData *data = [entry[@"data"] isKindOfClass:[NSData class]] ? entry[@"data"] : nil;
  [self.lock unlock];
  return data;
}

- (NSDictionary *)attachmentMetadataForID:(NSString *)attachmentID error:(NSError **)error {
  NSDictionary *metadata = nil;
  NSData *data = [self attachmentDataForID:attachmentID metadata:&metadata error:error];
  (void)data;
  return metadata;
}

- (BOOL)deleteAttachmentID:(NSString *)attachmentID error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(attachmentID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(503, @"attachment ID is required", nil);
    }
    return NO;
  }

  [self.lock lock];
  BOOL exists = (self.attachmentByID[normalizedID] != nil);
  if (exists) {
    [self.attachmentByID removeObjectForKey:normalizedID];
  }
  [self.lock unlock];
  return exists;
}

- (NSArray *)listAttachmentMetadata {
  [self.lock lock];
  NSArray *sortedIDs = [[self.attachmentByID allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *attachmentID in sortedIDs) {
    NSDictionary *entry = [self.attachmentByID[attachmentID] isKindOfClass:[NSDictionary class]]
                              ? self.attachmentByID[attachmentID]
                              : nil;
    if (entry == nil) {
      continue;
    }
    [out addObject:@{
      @"attachmentID" : entry[@"attachmentID"] ?: @"",
      @"name" : entry[@"name"] ?: @"",
      @"contentType" : entry[@"contentType"] ?: @"application/octet-stream",
      @"sizeBytes" : entry[@"sizeBytes"] ?: @(0),
      @"createdAt" : entry[@"createdAt"] ?: @(0),
      @"metadata" : entry[@"metadata"] ?: @{},
    }];
  }
  [self.lock unlock];
  return out;
}

- (void)reset {
  [self.lock lock];
  [self.attachmentByID removeAllObjects];
  self.nextAttachmentID = 0;
  [self.lock unlock];
}

@end

static NSError *ALNConformanceStepError(NSString *suite, NSString *step, NSError *underlying) {
  NSString *message = [NSString stringWithFormat:@"%@ conformance failed at step '%@'",
                                                 suite ?: @"service",
                                                 step ?: @""];
  return ALNServiceError(900, message, underlying);
}

BOOL ALNRunJobAdapterConformanceSuite(id<ALNJobAdapter> adapter, NSError **error) {
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"adapter_required", nil);
    }
    return NO;
  }

  [adapter reset];
  NSError *stepError = nil;
  NSString *firstID = [adapter enqueueJobNamed:@"phase3e.first" payload:@{ @"index" : @1 } options:@{} error:&stepError];
  if ([firstID length] == 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"enqueue_first", stepError);
    }
    return NO;
  }

  NSString *secondID = [adapter enqueueJobNamed:@"phase3e.second"
                                        payload:@{ @"index" : @2 }
                                        options:@{ @"maxAttempts" : @2 }
                                          error:&stepError];
  if ([secondID length] == 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"enqueue_second", stepError);
    }
    return NO;
  }

  ALNJobEnvelope *firstLease = [adapter dequeueDueJobAt:[NSDate date] error:&stepError];
  if (![firstLease isKindOfClass:[ALNJobEnvelope class]] || ![firstLease.jobID isEqualToString:firstID]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"dequeue_first_order", stepError);
    }
    return NO;
  }

  if (![adapter acknowledgeJobID:firstLease.jobID error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"ack_first", stepError);
    }
    return NO;
  }

  ALNJobEnvelope *secondLease = [adapter dequeueDueJobAt:[NSDate date] error:&stepError];
  if (![secondLease isKindOfClass:[ALNJobEnvelope class]] || ![secondLease.jobID isEqualToString:secondID]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"dequeue_second_order", stepError);
    }
    return NO;
  }
  if (secondLease.attempt != 1) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"attempt_first_lease", nil);
    }
    return NO;
  }

  if (![adapter retryJob:secondLease delaySeconds:0 error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"retry_first", stepError);
    }
    return NO;
  }

  ALNJobEnvelope *secondLeaseAgain = [adapter dequeueDueJobAt:[NSDate date] error:&stepError];
  if (![secondLeaseAgain isKindOfClass:[ALNJobEnvelope class]] ||
      ![secondLeaseAgain.jobID isEqualToString:secondID] ||
      secondLeaseAgain.attempt != 2) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"dequeue_retry", stepError);
    }
    return NO;
  }

  if (![adapter retryJob:secondLeaseAgain delaySeconds:0 error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"retry_to_dead_letter", stepError);
    }
    return NO;
  }

  NSArray *deadLetters = [adapter deadLetterJobsSnapshot];
  if ([deadLetters count] != 1) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"dead_letter_count", nil);
    }
    return NO;
  }

  if ([[adapter pendingJobsSnapshot] count] != 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"jobs", @"pending_empty_after_completion", nil);
    }
    return NO;
  }

  [adapter reset];
  return YES;
}

BOOL ALNRunCacheAdapterConformanceSuite(id<ALNCacheAdapter> adapter, NSError **error) {
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"adapter_required", nil);
    }
    return NO;
  }

  NSError *stepError = nil;
  if (![adapter clearWithError:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"clear", stepError);
    }
    return NO;
  }

  if (![adapter setObject:@"value-1" forKey:@"key-1" ttlSeconds:60 error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"set", stepError);
    }
    return NO;
  }

  NSString *fetched = [adapter objectForKey:@"key-1" atTime:[NSDate date] error:&stepError];
  if (![fetched isEqualToString:@"value-1"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"get", stepError);
    }
    return NO;
  }

  if (![adapter setObject:@"value-2" forKey:@"key-ttl" ttlSeconds:1 error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"set_ttl", stepError);
    }
    return NO;
  }

  NSString *expired = [adapter objectForKey:@"key-ttl"
                                     atTime:[NSDate dateWithTimeIntervalSinceNow:2]
                                      error:&stepError];
  if (expired != nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"ttl_expiry", nil);
    }
    return NO;
  }

  if (![adapter removeObjectForKey:@"key-1" error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"remove", stepError);
    }
    return NO;
  }

  id afterRemove = [adapter objectForKey:@"key-1" atTime:[NSDate date] error:&stepError];
  if (afterRemove != nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"remove_verify", nil);
    }
    return NO;
  }

  if (![adapter clearWithError:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"cache", @"clear_end", stepError);
    }
    return NO;
  }
  return YES;
}

BOOL ALNRunLocalizationAdapterConformanceSuite(id<ALNLocalizationAdapter> adapter, NSError **error) {
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"adapter_required", nil);
    }
    return NO;
  }

  NSError *stepError = nil;
  if (![adapter registerTranslations:@{
        @"greeting" : @"Hello %{name}",
        @"farewell" : @"Goodbye",
      }
                                   locale:@"en"
                                    error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"register_en", stepError);
    }
    return NO;
  }

  if (![adapter registerTranslations:@{
        @"greeting" : @"Hola %{name}",
      }
                                   locale:@"es"
                                    error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"register_es", stepError);
    }
    return NO;
  }

  NSString *spanish = [adapter localizedStringForKey:@"greeting"
                                              locale:@"es"
                                      fallbackLocale:@"en"
                                        defaultValue:@""
                                           arguments:@{ @"name" : @"Arlen" }];
  if (![spanish isEqualToString:@"Hola Arlen"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"translate_primary", nil);
    }
    return NO;
  }

  NSString *fallback = [adapter localizedStringForKey:@"farewell"
                                               locale:@"fr"
                                       fallbackLocale:@"en"
                                         defaultValue:@""
                                            arguments:nil];
  if (![fallback isEqualToString:@"Goodbye"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"translate_fallback", nil);
    }
    return NO;
  }

  NSString *defaultValue = [adapter localizedStringForKey:@"missing_key"
                                                   locale:@"fr"
                                           fallbackLocale:@"en"
                                             defaultValue:@"Default Value"
                                                arguments:nil];
  if (![defaultValue isEqualToString:@"Default Value"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"translate_default", nil);
    }
    return NO;
  }

  NSArray *locales = [adapter availableLocales];
  if (![locales containsObject:@"en"] || ![locales containsObject:@"es"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"i18n", @"available_locales", nil);
    }
    return NO;
  }

  return YES;
}

BOOL ALNRunMailAdapterConformanceSuite(id<ALNMailAdapter> adapter, NSError **error) {
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"mail", @"adapter_required", nil);
    }
    return NO;
  }

  [adapter reset];
  ALNMailMessage *message = [[ALNMailMessage alloc] initWithFrom:@"noreply@example.test"
                                                               to:@[ @"ops@example.test" ]
                                                               cc:nil
                                                              bcc:nil
                                                          subject:@"Phase3E"
                                                         textBody:@"mail adapter ok"
                                                         htmlBody:nil
                                                          headers:@{ @"X-Trace-ID" : @"phase3e-mail" }
                                                         metadata:@{ @"tenant" : @"core" }];
  NSError *stepError = nil;
  NSString *deliveryID = [adapter deliverMessage:message error:&stepError];
  if ([deliveryID length] == 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"mail", @"deliver", stepError);
    }
    return NO;
  }

  NSArray *deliveries = [adapter deliveriesSnapshot];
  if ([deliveries count] != 1) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"mail", @"delivery_count", nil);
    }
    return NO;
  }

  NSDictionary *entry = [deliveries firstObject];
  NSDictionary *renderedMessage =
      [entry[@"message"] isKindOfClass:[NSDictionary class]] ? entry[@"message"] : @{};
  if (![[renderedMessage[@"subject"] description] isEqualToString:@"Phase3E"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"mail", @"delivery_content", nil);
    }
    return NO;
  }

  [adapter reset];
  if ([[adapter deliveriesSnapshot] count] != 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"mail", @"reset", nil);
    }
    return NO;
  }
  return YES;
}

BOOL ALNRunAttachmentAdapterConformanceSuite(id<ALNAttachmentAdapter> adapter, NSError **error) {
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"adapter_required", nil);
    }
    return NO;
  }

  [adapter reset];
  NSData *data = [@"phase3e-attachment" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *stepError = nil;
  NSString *attachmentID = [adapter saveAttachmentNamed:@"phase3e.txt"
                                            contentType:@"text/plain"
                                                   data:data
                                               metadata:@{ @"scope" : @"test" }
                                                  error:&stepError];
  if ([attachmentID length] == 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"save", stepError);
    }
    return NO;
  }

  NSDictionary *metadata = nil;
  NSData *readBack = [adapter attachmentDataForID:attachmentID metadata:&metadata error:&stepError];
  if (readBack == nil || ![readBack isEqualToData:data]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"read_back", stepError);
    }
    return NO;
  }

  if (![[metadata[@"name"] description] isEqualToString:@"phase3e.txt"] ||
      ![[metadata[@"contentType"] description] isEqualToString:@"text/plain"]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"metadata", nil);
    }
    return NO;
  }

  NSArray *listed = [adapter listAttachmentMetadata];
  if ([listed count] != 1) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"list_count", nil);
    }
    return NO;
  }

  if (![adapter deleteAttachmentID:attachmentID error:&stepError]) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"delete", stepError);
    }
    return NO;
  }

  if ([adapter attachmentMetadataForID:attachmentID error:&stepError] != nil) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"attachment", @"delete_verify", nil);
    }
    return NO;
  }

  [adapter reset];
  return YES;
}

BOOL ALNRunServiceCompatibilitySuite(id<ALNJobAdapter> jobsAdapter,
                                     id<ALNCacheAdapter> cacheAdapter,
                                     id<ALNLocalizationAdapter> localizationAdapter,
                                     id<ALNMailAdapter> mailAdapter,
                                     id<ALNAttachmentAdapter> attachmentAdapter,
                                     NSError **error) {
  NSError *stepError = nil;
  if (!ALNRunJobAdapterConformanceSuite(jobsAdapter, &stepError)) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"services", @"jobs", stepError);
    }
    return NO;
  }
  if (!ALNRunCacheAdapterConformanceSuite(cacheAdapter, &stepError)) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"services", @"cache", stepError);
    }
    return NO;
  }
  if (!ALNRunLocalizationAdapterConformanceSuite(localizationAdapter, &stepError)) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"services", @"i18n", stepError);
    }
    return NO;
  }
  if (!ALNRunMailAdapterConformanceSuite(mailAdapter, &stepError)) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"services", @"mail", stepError);
    }
    return NO;
  }
  if (!ALNRunAttachmentAdapterConformanceSuite(attachmentAdapter, &stepError)) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"services", @"attachment", stepError);
    }
    return NO;
  }
  return YES;
}
