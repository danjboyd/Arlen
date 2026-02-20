#import "ALNServices.h"

#include <errno.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

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

static NSDate *ALNDateFromTimestampValue(id value, NSDate *defaultValue) {
  if ([value isKindOfClass:[NSDate class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(doubleValue)]) {
    return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
  }
  return defaultValue ?: [NSDate date];
}

static ALNJobEnvelope *ALNJobEnvelopeFromDictionary(id value) {
  if (![value isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSDictionary *dict = (NSDictionary *)value;
  NSString *jobID = ALNNonEmptyString(dict[@"jobID"], @"");
  NSString *name = ALNNonEmptyString(dict[@"name"], @"");
  if ([jobID length] == 0 || [name length] == 0) {
    return nil;
  }

  NSUInteger attempt = [dict[@"attempt"] respondsToSelector:@selector(unsignedIntegerValue)]
                           ? [dict[@"attempt"] unsignedIntegerValue]
                           : 0;
  NSUInteger maxAttempts =
      [dict[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
          ? [dict[@"maxAttempts"] unsignedIntegerValue]
          : 1;
  NSUInteger sequence = [dict[@"sequence"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [dict[@"sequence"] unsignedIntegerValue]
                            : 0;
  NSDictionary *payload = ALNNormalizeDictionary(dict[@"payload"]);
  NSDate *createdAt = ALNDateFromTimestampValue(dict[@"createdAt"], [NSDate date]);
  NSDate *notBefore = ALNDateFromTimestampValue(dict[@"notBefore"], createdAt);

  return [[ALNJobEnvelope alloc] initWithJobID:jobID
                                          name:name
                                       payload:payload
                                       attempt:attempt
                                   maxAttempts:maxAttempts
                                     notBefore:notBefore
                                     createdAt:createdAt
                                      sequence:sequence];
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

@interface ALNFileJobAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, copy) NSString *storagePath;
@property(nonatomic, strong) NSFileManager *fileManager;
@property(nonatomic, strong) NSLock *lock;

@end

@implementation ALNFileJobAdapter

- (instancetype)initWithStoragePath:(NSString *)storagePath
                         adapterName:(NSString *)adapterName
                               error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSString *normalizedPath = [[ALNNonEmptyString(storagePath, @"") stringByExpandingTildeInPath]
      stringByStandardizingPath];
  if ([normalizedPath length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(120, @"job adapter storage path is required", nil);
    }
    return nil;
  }

  _adapterNameValue = [ALNNonEmptyString(adapterName, @"file_jobs") copy];
  _storagePath = [normalizedPath copy];
  _fileManager = [[NSFileManager alloc] init];
  _lock = [[NSLock alloc] init];

  NSString *directory = [_storagePath stringByDeletingLastPathComponent];
  NSError *directoryError = nil;
  if (![_fileManager createDirectoryAtPath:directory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&directoryError]) {
    if (error != NULL) {
      *error = ALNServiceError(121, @"job adapter storage directory could not be created", directoryError);
    }
    return nil;
  }

  if (![_fileManager fileExistsAtPath:_storagePath]) {
    NSError *writeError = nil;
    if (![self writeState:@{
          @"sequenceCounter" : @(0),
          @"pending" : @[],
          @"leased" : @{},
          @"deadLetters" : @[],
        }
               error:&writeError]) {
      if (error != NULL) {
        *error = writeError;
      }
      return nil;
    }
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"file_jobs";
}

- (NSDictionary *)defaultState {
  return @{
    @"sequenceCounter" : @(0),
    @"pending" : @[],
    @"leased" : @{},
    @"deadLetters" : @[],
  };
}

- (BOOL)writeState:(NSDictionary *)state error:(NSError **)error {
  NSError *serializeError = nil;
  NSData *payload = [NSPropertyListSerialization dataWithPropertyList:state ?: [self defaultState]
                                                                format:NSPropertyListBinaryFormat_v1_0
                                                               options:0
                                                                 error:&serializeError];
  if (payload == nil) {
    if (error != NULL) {
      *error = ALNServiceError(122, @"job adapter state could not be serialized", serializeError);
    }
    return NO;
  }

  NSError *writeError = nil;
  if (![payload writeToFile:self.storagePath options:NSDataWritingAtomic error:&writeError]) {
    if (error != NULL) {
      *error = ALNServiceError(123, @"job adapter state could not be persisted", writeError);
    }
    return NO;
  }
  return YES;
}

- (NSDictionary *)readState:(NSError **)error {
  NSData *payload = [NSData dataWithContentsOfFile:self.storagePath options:0 error:error];
  if (payload == nil) {
    if (error != NULL && *error == nil) {
      *error = ALNServiceError(124, @"job adapter state could not be read", nil);
    }
    return nil;
  }

  NSError *parseError = nil;
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id parsed = [NSPropertyListSerialization propertyListWithData:payload
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:&parseError];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNServiceError(125, @"job adapter state is malformed", parseError);
    }
    return nil;
  }
  return parsed;
}

- (NSArray *)sortedPendingFromState:(NSDictionary *)state {
  NSArray *rawPending = [state[@"pending"] isKindOfClass:[NSArray class]] ? state[@"pending"] : @[];
  NSMutableArray *pending = [NSMutableArray array];
  for (id entry in rawPending) {
    ALNJobEnvelope *envelope = ALNJobEnvelopeFromDictionary(entry);
    if (envelope != nil) {
      [pending addObject:envelope];
    }
  }
  [pending sortUsingComparator:^NSComparisonResult(ALNJobEnvelope *a, ALNJobEnvelope *b) {
    NSComparisonResult dueOrder = [a.notBefore compare:b.notBefore];
    if (dueOrder != NSOrderedSame) {
      return dueOrder;
    }
    if (a.sequence < b.sequence) {
      return NSOrderedAscending;
    }
    if (a.sequence > b.sequence) {
      return NSOrderedDescending;
    }
    return NSOrderedSame;
  }];
  return [NSArray arrayWithArray:pending];
}

- (NSMutableDictionary *)mutableLeasedMapFromState:(NSDictionary *)state {
  NSDictionary *rawLeased = [state[@"leased"] isKindOfClass:[NSDictionary class]] ? state[@"leased"] : @{};
  NSMutableDictionary *leased = [NSMutableDictionary dictionary];
  for (id key in rawLeased) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    ALNJobEnvelope *envelope = ALNJobEnvelopeFromDictionary(rawLeased[key]);
    if (envelope != nil) {
      leased[key] = envelope;
    }
  }
  return leased;
}

- (NSArray *)deadLettersFromState:(NSDictionary *)state {
  NSArray *rawDeadLetters = [state[@"deadLetters"] isKindOfClass:[NSArray class]] ? state[@"deadLetters"] : @[];
  NSMutableArray *deadLetters = [NSMutableArray array];
  for (id entry in rawDeadLetters) {
    ALNJobEnvelope *envelope = ALNJobEnvelopeFromDictionary(entry);
    if (envelope != nil) {
      [deadLetters addObject:envelope];
    }
  }
  return [NSArray arrayWithArray:deadLetters];
}

- (NSDictionary *)stateDictionaryWithSequenceCounter:(NSUInteger)sequenceCounter
                                             pending:(NSArray *)pending
                                              leased:(NSDictionary *)leased
                                         deadLetters:(NSArray *)deadLetters {
  NSMutableArray *pendingPayload = [NSMutableArray array];
  for (ALNJobEnvelope *envelope in pending ?: @[]) {
    [pendingPayload addObject:[envelope dictionaryRepresentation]];
  }

  NSMutableDictionary *leasedPayload = [NSMutableDictionary dictionary];
  for (id key in leased ?: @{}) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    ALNJobEnvelope *envelope = [leased[key] isKindOfClass:[ALNJobEnvelope class]] ? leased[key] : nil;
    if (envelope != nil) {
      leasedPayload[key] = [envelope dictionaryRepresentation];
    }
  }

  NSMutableArray *deadLetterPayload = [NSMutableArray array];
  for (ALNJobEnvelope *envelope in deadLetters ?: @[]) {
    [deadLetterPayload addObject:[envelope dictionaryRepresentation]];
  }

  return @{
    @"sequenceCounter" : @(sequenceCounter),
    @"pending" : pendingPayload,
    @"leased" : leasedPayload,
    @"deadLetters" : deadLetterPayload,
  };
}

- (NSString *)enqueueJobNamed:(NSString *)name
                      payload:(NSDictionary *)payload
                      options:(NSDictionary *)options
                        error:(NSError **)error {
  NSString *normalizedName = ALNNonEmptyString(name, @"");
  if ([normalizedName length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(126, @"job name is required", nil);
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
  NSError *stateError = nil;
  NSDictionary *state = [self readState:&stateError];
  if (state == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = stateError;
    }
    return nil;
  }

  NSUInteger sequenceCounter = [state[@"sequenceCounter"] respondsToSelector:@selector(unsignedIntegerValue)]
                                   ? [state[@"sequenceCounter"] unsignedIntegerValue]
                                   : 0;
  sequenceCounter += 1;
  NSString *jobID = [NSString stringWithFormat:@"job-%lu", (unsigned long)sequenceCounter];
  ALNJobEnvelope *envelope = [[ALNJobEnvelope alloc] initWithJobID:jobID
                                                               name:normalizedName
                                                            payload:ALNNormalizeDictionary(payload)
                                                            attempt:0
                                                        maxAttempts:maxAttempts
                                                          notBefore:notBefore
                                                          createdAt:[NSDate date]
                                                           sequence:sequenceCounter];

  NSMutableArray *pending = [NSMutableArray arrayWithArray:[self sortedPendingFromState:state]];
  [pending addObject:envelope];
  [pending sortUsingComparator:^NSComparisonResult(ALNJobEnvelope *a, ALNJobEnvelope *b) {
    NSComparisonResult dueOrder = [a.notBefore compare:b.notBefore];
    if (dueOrder != NSOrderedSame) {
      return dueOrder;
    }
    if (a.sequence < b.sequence) {
      return NSOrderedAscending;
    }
    if (a.sequence > b.sequence) {
      return NSOrderedDescending;
    }
    return NSOrderedSame;
  }];

  NSDictionary *nextState = [self stateDictionaryWithSequenceCounter:sequenceCounter
                                                              pending:pending
                                                               leased:[self mutableLeasedMapFromState:state]
                                                          deadLetters:[self deadLettersFromState:state]];
  NSError *writeError = nil;
  BOOL persisted = [self writeState:nextState error:&writeError];
  [self.lock unlock];
  if (!persisted) {
    if (error != NULL) {
      *error = writeError;
    }
    return nil;
  }
  return jobID;
}

- (ALNJobEnvelope *)dequeueDueJobAt:(NSDate *)timestamp error:(NSError **)error {
  NSDate *now = timestamp ?: [NSDate date];
  [self.lock lock];
  NSError *stateError = nil;
  NSDictionary *state = [self readState:&stateError];
  if (state == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = stateError;
    }
    return nil;
  }

  NSMutableArray *pending = [NSMutableArray arrayWithArray:[self sortedPendingFromState:state]];
  NSMutableDictionary *leased = [self mutableLeasedMapFromState:state];
  NSArray *deadLetters = [self deadLettersFromState:state];
  NSUInteger sequenceCounter = [state[@"sequenceCounter"] respondsToSelector:@selector(unsignedIntegerValue)]
                                   ? [state[@"sequenceCounter"] unsignedIntegerValue]
                                   : 0;

  NSUInteger foundIndex = NSNotFound;
  ALNJobEnvelope *selected = nil;
  for (NSUInteger idx = 0; idx < [pending count]; idx++) {
    ALNJobEnvelope *candidate = [pending[idx] isKindOfClass:[ALNJobEnvelope class]] ? pending[idx] : nil;
    if (candidate != nil && [candidate.notBefore compare:now] != NSOrderedDescending) {
      foundIndex = idx;
      selected = candidate;
      break;
    }
  }

  if (selected == nil || foundIndex == NSNotFound) {
    [self.lock unlock];
    return nil;
  }

  [pending removeObjectAtIndex:foundIndex];
  ALNJobEnvelope *leasedEnvelope = [[ALNJobEnvelope alloc] initWithJobID:selected.jobID
                                                                     name:selected.name
                                                                  payload:selected.payload
                                                                  attempt:selected.attempt + 1
                                                              maxAttempts:selected.maxAttempts
                                                                notBefore:selected.notBefore
                                                                createdAt:selected.createdAt
                                                                 sequence:selected.sequence];
  leased[leasedEnvelope.jobID] = leasedEnvelope;

  NSDictionary *nextState = [self stateDictionaryWithSequenceCounter:sequenceCounter
                                                              pending:pending
                                                               leased:leased
                                                          deadLetters:deadLetters];
  NSError *writeError = nil;
  BOOL persisted = [self writeState:nextState error:&writeError];
  [self.lock unlock];
  if (!persisted) {
    if (error != NULL) {
      *error = writeError;
    }
    return nil;
  }
  return [leasedEnvelope copy];
}

- (BOOL)acknowledgeJobID:(NSString *)jobID error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(jobID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(127, @"job ID is required", nil);
    }
    return NO;
  }

  [self.lock lock];
  NSError *stateError = nil;
  NSDictionary *state = [self readState:&stateError];
  if (state == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = stateError;
    }
    return NO;
  }

  NSMutableDictionary *leased = [self mutableLeasedMapFromState:state];
  if (leased[normalizedID] == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(128, @"job is not currently leased", nil);
    }
    return NO;
  }
  [leased removeObjectForKey:normalizedID];

  NSDictionary *nextState = [self stateDictionaryWithSequenceCounter:[state[@"sequenceCounter"] unsignedIntegerValue]
                                                              pending:[self sortedPendingFromState:state]
                                                               leased:leased
                                                          deadLetters:[self deadLettersFromState:state]];
  NSError *writeError = nil;
  BOOL persisted = [self writeState:nextState error:&writeError];
  [self.lock unlock];
  if (!persisted) {
    if (error != NULL) {
      *error = writeError;
    }
    return NO;
  }
  return YES;
}

- (BOOL)retryJob:(ALNJobEnvelope *)job
    delaySeconds:(NSTimeInterval)delaySeconds
           error:(NSError **)error {
  if (![job isKindOfClass:[ALNJobEnvelope class]]) {
    if (error != NULL) {
      *error = ALNServiceError(129, @"job envelope is required", nil);
    }
    return NO;
  }

  NSString *jobID = ALNNonEmptyString(job.jobID, @"");
  if ([jobID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(130, @"job ID is required for retry", nil);
    }
    return NO;
  }

  [self.lock lock];
  NSError *stateError = nil;
  NSDictionary *state = [self readState:&stateError];
  if (state == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = stateError;
    }
    return NO;
  }

  NSMutableArray *pending = [NSMutableArray arrayWithArray:[self sortedPendingFromState:state]];
  NSMutableDictionary *leased = [self mutableLeasedMapFromState:state];
  NSMutableArray *deadLetters = [NSMutableArray arrayWithArray:[self deadLettersFromState:state]];
  ALNJobEnvelope *leasedEnvelope = [leased[jobID] isKindOfClass:[ALNJobEnvelope class]] ? leased[jobID] : nil;
  if (leasedEnvelope == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(131, @"job is not currently leased", nil);
    }
    return NO;
  }
  [leased removeObjectForKey:jobID];

  if (leasedEnvelope.attempt >= leasedEnvelope.maxAttempts) {
    [deadLetters addObject:leasedEnvelope];
  } else {
    NSTimeInterval safeDelay = (delaySeconds > 0.0) ? delaySeconds : 0.0;
    ALNJobEnvelope *requeued = [[ALNJobEnvelope alloc] initWithJobID:leasedEnvelope.jobID
                                                                 name:leasedEnvelope.name
                                                              payload:leasedEnvelope.payload
                                                              attempt:leasedEnvelope.attempt
                                                          maxAttempts:leasedEnvelope.maxAttempts
                                                            notBefore:[NSDate dateWithTimeIntervalSinceNow:safeDelay]
                                                            createdAt:leasedEnvelope.createdAt
                                                             sequence:leasedEnvelope.sequence];
    [pending addObject:requeued];
    [pending sortUsingComparator:^NSComparisonResult(ALNJobEnvelope *a, ALNJobEnvelope *b) {
      NSComparisonResult dueOrder = [a.notBefore compare:b.notBefore];
      if (dueOrder != NSOrderedSame) {
        return dueOrder;
      }
      if (a.sequence < b.sequence) {
        return NSOrderedAscending;
      }
      if (a.sequence > b.sequence) {
        return NSOrderedDescending;
      }
      return NSOrderedSame;
    }];
  }

  NSDictionary *nextState = [self stateDictionaryWithSequenceCounter:[state[@"sequenceCounter"] unsignedIntegerValue]
                                                              pending:pending
                                                               leased:leased
                                                          deadLetters:deadLetters];
  NSError *writeError = nil;
  BOOL persisted = [self writeState:nextState error:&writeError];
  [self.lock unlock];
  if (!persisted) {
    if (error != NULL) {
      *error = writeError;
    }
    return NO;
  }
  return YES;
}

- (NSArray *)pendingJobsSnapshot {
  [self.lock lock];
  NSDictionary *state = [self readState:NULL];
  NSArray *snapshot = [self sortedPendingFromState:state ?: @{}];
  [self.lock unlock];
  return snapshot ?: @[];
}

- (NSArray *)deadLetterJobsSnapshot {
  [self.lock lock];
  NSDictionary *state = [self readState:NULL];
  NSArray *snapshot = [self deadLettersFromState:state ?: @{}];
  [self.lock unlock];
  return snapshot ?: @[];
}

- (void)reset {
  [self.lock lock];
  (void)[self writeState:[self defaultState] error:NULL];
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

@interface ALNRedisCacheAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, copy) NSString *host;
@property(nonatomic, assign) NSUInteger port;
@property(nonatomic, assign) NSInteger databaseIndex;
@property(nonatomic, copy) NSString *password;
@property(nonatomic, copy) NSString *namespacePrefix;
@property(nonatomic, assign) NSTimeInterval ioTimeoutSeconds;

@end

static BOOL ALNParseSignedInteger(NSString *text, long long *outValue) {
  if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
    return NO;
  }
  const char *raw = [text UTF8String];
  if (raw == NULL) {
    return NO;
  }
  errno = 0;
  char *end = NULL;
  long long parsed = strtoll(raw, &end, 10);
  if (errno != 0 || end == NULL || *end != '\0') {
    return NO;
  }
  if (outValue != NULL) {
    *outValue = parsed;
  }
  return YES;
}

static NSError *ALNRedisClientError(NSInteger code, NSString *message, NSError *underlying) {
  return ALNServiceError(code, message, underlying);
}

static BOOL ALNRedisWriteBytes(int socketFD, const uint8_t *bytes, size_t length, NSError **error) {
  size_t written = 0;
  while (written < length) {
    ssize_t count = send(socketFD, bytes + written, length - written, 0);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (error != NULL) {
        *error = ALNRedisClientError(2200,
                                     [NSString stringWithFormat:@"redis write failed: %s", strerror(errno)],
                                     nil);
      }
      return NO;
    }
    if (count == 0) {
      if (error != NULL) {
        *error = ALNRedisClientError(2201, @"redis connection closed during write", nil);
      }
      return NO;
    }
    written += (size_t)count;
  }
  return YES;
}

static BOOL ALNRedisWriteData(int socketFD, NSData *data, NSError **error) {
  return ALNRedisWriteBytes(socketFD, (const uint8_t *)[data bytes], [data length], error);
}

static BOOL ALNRedisReadExact(int socketFD, uint8_t *buffer, size_t length, NSError **error) {
  size_t readCount = 0;
  while (readCount < length) {
    ssize_t count = recv(socketFD, buffer + readCount, length - readCount, 0);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (error != NULL) {
        *error = ALNRedisClientError(2202,
                                     [NSString stringWithFormat:@"redis read failed: %s", strerror(errno)],
                                     nil);
      }
      return NO;
    }
    if (count == 0) {
      if (error != NULL) {
        *error = ALNRedisClientError(2203, @"redis connection closed during read", nil);
      }
      return NO;
    }
    readCount += (size_t)count;
  }
  return YES;
}

static NSString *ALNRedisReadLine(int socketFD, NSError **error) {
  NSMutableData *buffer = [NSMutableData data];
  while (YES) {
    uint8_t byte = 0;
    if (!ALNRedisReadExact(socketFD, &byte, 1, error)) {
      return nil;
    }
    if (byte == '\r') {
      uint8_t lf = 0;
      if (!ALNRedisReadExact(socketFD, &lf, 1, error)) {
        return nil;
      }
      if (lf != '\n') {
        if (error != NULL) {
          *error = ALNRedisClientError(2204, @"redis protocol error: expected LF after CR", nil);
        }
        return nil;
      }
      break;
    }
    [buffer appendBytes:&byte length:1];
    if ([buffer length] > (1024 * 1024)) {
      if (error != NULL) {
        *error = ALNRedisClientError(2205, @"redis protocol error: line too long", nil);
      }
      return nil;
    }
  }

  NSString *line = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
  if (line == nil) {
    if (error != NULL) {
      *error = ALNRedisClientError(2206, @"redis protocol error: line is not UTF-8", nil);
    }
    return nil;
  }
  return line;
}

static id ALNRedisReadReply(int socketFD, NSError **error);

static id ALNRedisReadArrayReply(int socketFD, NSString *countText, NSError **error) {
  long long count = 0;
  if (!ALNParseSignedInteger(countText, &count) || count < -1) {
    if (error != NULL) {
      *error = ALNRedisClientError(2207, @"redis protocol error: invalid array length", nil);
    }
    return nil;
  }
  if (count == -1) {
    return [NSNull null];
  }
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (long long index = 0; index < count; index++) {
    NSError *stepError = nil;
    id item = ALNRedisReadReply(socketFD, &stepError);
    if (stepError != nil) {
      if (error != NULL) {
        *error = stepError;
      }
      return nil;
    }
    [out addObject:item ?: [NSNull null]];
  }
  return [NSArray arrayWithArray:out];
}

static id ALNRedisReadBulkReply(int socketFD, NSString *lengthText, NSError **error) {
  long long length = 0;
  if (!ALNParseSignedInteger(lengthText, &length) || length < -1) {
    if (error != NULL) {
      *error = ALNRedisClientError(2208, @"redis protocol error: invalid bulk length", nil);
    }
    return nil;
  }
  if (length == -1) {
    return [NSNull null];
  }

  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
  if (length > 0 && !ALNRedisReadExact(socketFD, [data mutableBytes], (size_t)length, error)) {
    return nil;
  }
  uint8_t tail[2] = { 0, 0 };
  if (!ALNRedisReadExact(socketFD, tail, 2, error)) {
    return nil;
  }
  if (tail[0] != '\r' || tail[1] != '\n') {
    if (error != NULL) {
      *error = ALNRedisClientError(2209, @"redis protocol error: malformed bulk terminator", nil);
    }
    return nil;
  }
  return [NSData dataWithData:data];
}

static id ALNRedisReadReply(int socketFD, NSError **error) {
  uint8_t prefix = 0;
  if (!ALNRedisReadExact(socketFD, &prefix, 1, error)) {
    return nil;
  }

  NSString *line = ALNRedisReadLine(socketFD, error);
  if (line == nil) {
    return nil;
  }

  if (prefix == '+') {
    return line;
  }
  if (prefix == '-') {
    if (error != NULL) {
      *error = ALNRedisClientError(2210, [NSString stringWithFormat:@"redis error reply: %@", line], nil);
    }
    return nil;
  }
  if (prefix == ':') {
    long long value = 0;
    if (!ALNParseSignedInteger(line, &value)) {
      if (error != NULL) {
        *error = ALNRedisClientError(2211, @"redis protocol error: invalid integer reply", nil);
      }
      return nil;
    }
    return @(value);
  }
  if (prefix == '$') {
    return ALNRedisReadBulkReply(socketFD, line, error);
  }
  if (prefix == '*') {
    return ALNRedisReadArrayReply(socketFD, line, error);
  }

  if (error != NULL) {
    *error = ALNRedisClientError(2212, @"redis protocol error: unknown reply prefix", nil);
  }
  return nil;
}

static BOOL ALNRedisWriteCommand(int socketFD, NSArray *parts, NSError **error) {
  NSMutableData *payload = [NSMutableData data];
  NSString *header = [NSString stringWithFormat:@"*%lu\r\n", (unsigned long)[parts count]];
  [payload appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
  for (id part in parts ?: @[]) {
    NSData *bytes = nil;
    if ([part isKindOfClass:[NSData class]]) {
      bytes = part;
    } else if ([part isKindOfClass:[NSString class]]) {
      bytes = [(NSString *)part dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([part respondsToSelector:@selector(description)]) {
      bytes = [[part description] dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (bytes == nil) {
      bytes = [NSData data];
    }
    NSString *bulkHeader = [NSString stringWithFormat:@"$%lu\r\n", (unsigned long)[bytes length]];
    [payload appendData:[bulkHeader dataUsingEncoding:NSUTF8StringEncoding]];
    [payload appendData:bytes];
    [payload appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }
  return ALNRedisWriteData(socketFD, payload, error);
}

static int ALNRedisOpenSocketConnection(NSString *host,
                                        NSUInteger port,
                                        NSTimeInterval timeoutSeconds,
                                        NSError **error) {
  NSString *normalizedHost = ALNNonEmptyString(host, @"");
  if ([normalizedHost length] == 0) {
    if (error != NULL) {
      *error = ALNRedisClientError(2213, @"redis host is required", nil);
    }
    return -1;
  }
  if (port == 0 || port > 65535) {
    if (error != NULL) {
      *error = ALNRedisClientError(2214, @"redis port must be between 1 and 65535", nil);
    }
    return -1;
  }

  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;

  char portBuffer[16];
  snprintf(portBuffer, sizeof(portBuffer), "%u", (unsigned int)port);

  struct addrinfo *result = NULL;
  int resolveStatus = getaddrinfo([normalizedHost UTF8String], portBuffer, &hints, &result);
  if (resolveStatus != 0 || result == NULL) {
    if (error != NULL) {
      *error = ALNRedisClientError(
          2215,
          [NSString stringWithFormat:@"redis address resolution failed: %s", gai_strerror(resolveStatus)],
          nil);
    }
    if (result != NULL) {
      freeaddrinfo(result);
    }
    return -1;
  }

  int socketFD = -1;
  long timeoutMillis = (long)(timeoutSeconds * 1000.0);
  if (timeoutMillis <= 0) {
    timeoutMillis = 2500;
  }
  struct timeval timeoutValue;
  timeoutValue.tv_sec = timeoutMillis / 1000;
  timeoutValue.tv_usec = (timeoutMillis % 1000) * 1000;

  for (struct addrinfo *candidate = result; candidate != NULL; candidate = candidate->ai_next) {
    socketFD = socket(candidate->ai_family, candidate->ai_socktype, candidate->ai_protocol);
    if (socketFD < 0) {
      continue;
    }

    (void)setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, sizeof(timeoutValue));
    (void)setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, sizeof(timeoutValue));

    if (connect(socketFD, candidate->ai_addr, candidate->ai_addrlen) == 0) {
      break;
    }
    close(socketFD);
    socketFD = -1;
  }
  freeaddrinfo(result);

  if (socketFD < 0) {
    if (error != NULL) {
      *error = ALNRedisClientError(2216,
                                   [NSString stringWithFormat:@"redis connect failed: %s", strerror(errno)],
                                   nil);
    }
    return -1;
  }
  return socketFD;
}

@implementation ALNRedisCacheAdapter

- (instancetype)initWithURLString:(NSString *)urlString
                        namespace:(NSString *)namespacePrefix
                      adapterName:(NSString *)adapterName
                            error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSString *normalizedURL = ALNNonEmptyString(urlString, @"");
  NSURLComponents *components = [NSURLComponents componentsWithString:normalizedURL];
  NSString *scheme = [[components.scheme lowercaseString] copy];
  if (components == nil || ![scheme isEqualToString:@"redis"]) {
    if (error != NULL) {
      *error = ALNRedisClientError(2217, @"redis URL must use redis:// scheme", nil);
    }
    return nil;
  }

  NSString *host = ALNNonEmptyString(components.host, @"");
  if ([host length] == 0) {
    if (error != NULL) {
      *error = ALNRedisClientError(2218, @"redis URL must include host", nil);
    }
    return nil;
  }
  NSUInteger port = components.port != nil ? [components.port unsignedIntegerValue] : 6379;
  if (port == 0 || port > 65535) {
    if (error != NULL) {
      *error = ALNRedisClientError(2219, @"redis URL has invalid port", nil);
    }
    return nil;
  }

  NSInteger dbIndex = 0;
  NSString *path = ALNNonEmptyString(components.path, @"");
  if ([path hasPrefix:@"/"] && [path length] > 1) {
    NSString *dbText = [path substringFromIndex:1];
    long long parsedDB = 0;
    if (!ALNParseSignedInteger(dbText, &parsedDB) || parsedDB < 0) {
      if (error != NULL) {
        *error = ALNRedisClientError(2220, @"redis URL database path must be a non-negative integer", nil);
      }
      return nil;
    }
    dbIndex = (NSInteger)parsedDB;
  }

  _host = [host copy];
  _port = port;
  _databaseIndex = dbIndex;
  _password = [ALNNonEmptyString(components.password, @"") copy];
  _namespacePrefix = [ALNNonEmptyString(namespacePrefix, @"arlen:cache") copy];
  _adapterNameValue =
      [ALNNonEmptyString(adapterName,
                         [NSString stringWithFormat:@"redis_cache@%@:%lu", host, (unsigned long)port]) copy];
  _ioTimeoutSeconds = 2.5;
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"redis_cache";
}

- (NSString *)indexKey {
  return [NSString stringWithFormat:@"%@:__keys__", self.namespacePrefix ?: @"arlen:cache"];
}

- (NSString *)namespacedKeyForKey:(NSString *)key {
  return [NSString stringWithFormat:@"%@:%@", self.namespacePrefix ?: @"arlen:cache", key ?: @""];
}

- (int)openConnectionWithError:(NSError **)error {
  int fd = ALNRedisOpenSocketConnection(self.host, self.port, self.ioTimeoutSeconds, error);
  if (fd < 0) {
    return -1;
  }

  if ([self.password length] > 0) {
    NSError *authError = nil;
    if (!ALNRedisWriteCommand(fd, @[ @"AUTH", self.password ], &authError)) {
      close(fd);
      if (error != NULL) {
        *error = authError;
      }
      return -1;
    }
    id authReply = ALNRedisReadReply(fd, &authError);
    if (authReply == nil || ![[authReply description] isEqualToString:@"OK"]) {
      close(fd);
      if (error != NULL) {
        *error = authError ?: ALNRedisClientError(2221, @"redis AUTH failed", nil);
      }
      return -1;
    }
  }

  if (self.databaseIndex > 0) {
    NSError *selectError = nil;
    if (!ALNRedisWriteCommand(fd, @[ @"SELECT", [NSString stringWithFormat:@"%ld", (long)self.databaseIndex] ],
                              &selectError)) {
      close(fd);
      if (error != NULL) {
        *error = selectError;
      }
      return -1;
    }
    id selectReply = ALNRedisReadReply(fd, &selectError);
    if (selectReply == nil || ![[selectReply description] isEqualToString:@"OK"]) {
      close(fd);
      if (error != NULL) {
        *error = selectError ?: ALNRedisClientError(2222, @"redis SELECT failed", nil);
      }
      return -1;
    }
  }

  return fd;
}

- (id)runCommand:(NSArray *)parts error:(NSError **)error {
  int fd = [self openConnectionWithError:error];
  if (fd < 0) {
    return nil;
  }

  NSError *commandError = nil;
  BOOL wrote = ALNRedisWriteCommand(fd, parts, &commandError);
  id reply = nil;
  if (wrote) {
    reply = ALNRedisReadReply(fd, &commandError);
  }
  close(fd);

  if (!wrote || commandError != nil) {
    if (error != NULL) {
      *error = commandError ?: ALNRedisClientError(2223, @"redis command failed", nil);
    }
    return nil;
  }
  return reply;
}

- (NSData *)serializedRecordForObject:(id)object
                           expiresAt:(NSDate *)expiresAt
                               error:(NSError **)error {
  NSDictionary *record = @{
    @"value" : object ?: [NSNull null],
    @"expiresAt" : expiresAt != nil ? @([expiresAt timeIntervalSince1970]) : [NSNull null]
  };
  NSError *serializeError = nil;
  NSData *payload = [NSPropertyListSerialization dataWithPropertyList:record
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&serializeError];
  if (payload == nil) {
    if (error != NULL) {
      *error = ALNRedisClientError(2224, @"cache value is not property-list serializable", serializeError);
    }
    return nil;
  }
  return payload;
}

- (NSDictionary *)recordFromPayload:(NSData *)payload error:(NSError **)error {
  if (![payload isKindOfClass:[NSData class]]) {
    if (error != NULL) {
      *error = ALNRedisClientError(2225, @"redis cache payload is not data", nil);
    }
    return nil;
  }
  NSError *parseError = nil;
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id parsed = [NSPropertyListSerialization propertyListWithData:payload
                                                        options:NSPropertyListImmutable
                                                         format:&format
                                                          error:&parseError];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNRedisClientError(2226, @"redis cache payload is malformed", parseError);
    }
    return nil;
  }
  return parsed;
}

- (BOOL)setObject:(id)object
           forKey:(NSString *)key
       ttlSeconds:(NSTimeInterval)ttlSeconds
            error:(NSError **)error {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    if (error != NULL) {
      *error = ALNRedisClientError(2227, @"cache key is required", nil);
    }
    return NO;
  }
  if (object == nil || object == [NSNull null]) {
    return [self removeObjectForKey:normalizedKey error:error];
  }

  NSDate *expiresAt = nil;
  if (ttlSeconds > 0.0) {
    expiresAt = [NSDate dateWithTimeIntervalSinceNow:ttlSeconds];
  }

  NSData *payload = [self serializedRecordForObject:object expiresAt:expiresAt error:error];
  if (payload == nil) {
    return NO;
  }

  NSString *storageKey = [self namespacedKeyForKey:normalizedKey];
  id setReply = [self runCommand:@[ @"SET", storageKey, payload ] error:error];
  if (setReply == nil || ![[setReply description] isEqualToString:@"OK"]) {
    if (setReply != nil && error != NULL) {
      *error = ALNRedisClientError(2228, @"redis SET failed", nil);
    }
    return NO;
  }

  (void)[self runCommand:@[ @"SADD", [self indexKey], storageKey ] error:NULL];
  return YES;
}

- (id)objectForKey:(NSString *)key atTime:(NSDate *)timestamp error:(NSError **)error {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    if (error != NULL) {
      *error = ALNRedisClientError(2229, @"cache key is required", nil);
    }
    return nil;
  }

  NSString *storageKey = [self namespacedKeyForKey:normalizedKey];
  id reply = [self runCommand:@[ @"GET", storageKey ] error:error];
  if (reply == nil) {
    return nil;
  }
  if (reply == [NSNull null]) {
    return nil;
  }

  NSData *payload = [reply isKindOfClass:[NSData class]] ? reply : nil;
  NSDictionary *record = [self recordFromPayload:payload error:error];
  if (record == nil) {
    return nil;
  }

  NSDate *now = timestamp ?: [NSDate date];
  id expiresAtValue = record[@"expiresAt"];
  if ([expiresAtValue respondsToSelector:@selector(doubleValue)]) {
    NSTimeInterval expiresAtInterval = [expiresAtValue doubleValue];
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSince1970:expiresAtInterval];
    if ([expiresAt compare:now] != NSOrderedDescending) {
      (void)[self removeObjectForKey:normalizedKey error:NULL];
      return nil;
    }
  }

  id value = record[@"value"];
  return (value == [NSNull null]) ? nil : value;
}

- (BOOL)removeObjectForKey:(NSString *)key error:(NSError **)error {
  NSString *normalizedKey = ALNNonEmptyString(key, @"");
  if ([normalizedKey length] == 0) {
    if (error != NULL) {
      *error = ALNRedisClientError(2230, @"cache key is required", nil);
    }
    return NO;
  }

  NSString *storageKey = [self namespacedKeyForKey:normalizedKey];
  if ([self runCommand:@[ @"DEL", storageKey ] error:error] == nil && error != NULL && *error != nil) {
    return NO;
  }
  (void)[self runCommand:@[ @"SREM", [self indexKey], storageKey ] error:NULL];
  return YES;
}

- (BOOL)clearWithError:(NSError **)error {
  NSString *indexKey = [self indexKey];
  id reply = [self runCommand:@[ @"SMEMBERS", indexKey ] error:error];
  if (reply == nil && error != NULL && *error != nil) {
    return NO;
  }

  if ([reply isKindOfClass:[NSArray class]]) {
    for (id entry in (NSArray *)reply) {
      NSString *storageKey = nil;
      if ([entry isKindOfClass:[NSData class]]) {
        storageKey = [[NSString alloc] initWithData:entry encoding:NSUTF8StringEncoding];
      } else if ([entry isKindOfClass:[NSString class]]) {
        storageKey = entry;
      }
      if ([storageKey length] == 0) {
        continue;
      }
      if ([self runCommand:@[ @"DEL", storageKey ] error:error] == nil && error != NULL && *error != nil) {
        return NO;
      }
    }
  }

  if ([self runCommand:@[ @"DEL", indexKey ] error:error] == nil && error != NULL && *error != nil) {
    return NO;
  }
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

@interface ALNFileMailAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, copy) NSString *storageDirectory;
@property(nonatomic, strong) NSFileManager *fileManager;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) NSUInteger nextDeliveryID;

@end

@implementation ALNFileMailAdapter

- (instancetype)initWithStorageDirectory:(NSString *)storageDirectory
                             adapterName:(NSString *)adapterName
                                   error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSString *normalizedDirectory =
      [[ALNNonEmptyString(storageDirectory, @"") stringByExpandingTildeInPath] stringByStandardizingPath];
  if ([normalizedDirectory length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(420, @"mail storage directory is required", nil);
    }
    return nil;
  }

  _adapterNameValue = [ALNNonEmptyString(adapterName, @"file_mail") copy];
  _storageDirectory = [normalizedDirectory copy];
  _fileManager = [[NSFileManager alloc] init];
  _lock = [[NSLock alloc] init];
  _nextDeliveryID = 0;

  NSError *directoryError = nil;
  if (![_fileManager createDirectoryAtPath:_storageDirectory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&directoryError]) {
    if (error != NULL) {
      *error = ALNServiceError(421, @"mail storage directory could not be created", directoryError);
    }
    return nil;
  }

  NSArray *existing = [_fileManager contentsOfDirectoryAtPath:_storageDirectory error:NULL];
  for (NSString *item in existing ?: @[]) {
    if (![item hasPrefix:@"mail-"] || ![item hasSuffix:@".plist"]) {
      continue;
    }
    NSString *numeric = [item substringWithRange:NSMakeRange([@"mail-" length],
                                                              [item length] - [@"mail-" length] - [@".plist" length])];
    NSUInteger parsed = (NSUInteger)[numeric integerValue];
    if (parsed > _nextDeliveryID) {
      _nextDeliveryID = parsed;
    }
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"file_mail";
}

- (NSString *)deliveryPathForID:(NSString *)deliveryID {
  return [self.storageDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", deliveryID ?: @""]];
}

- (NSString *)nextDeliveryIdentifier {
  self.nextDeliveryID += 1;
  return [NSString stringWithFormat:@"mail-%lu", (unsigned long)self.nextDeliveryID];
}

- (NSString *)deliverMessage:(ALNMailMessage *)message error:(NSError **)error {
  if (![message isKindOfClass:[ALNMailMessage class]]) {
    if (error != NULL) {
      *error = ALNServiceError(422, @"mail message is required", nil);
    }
    return nil;
  }
  if ([[message to] count] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(423, @"mail message requires at least one recipient", nil);
    }
    return nil;
  }

  [self.lock lock];
  NSString *deliveryID = [self nextDeliveryIdentifier];
  NSDictionary *entry = @{
    @"deliveryID" : deliveryID ?: @"",
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"message" : [message dictionaryRepresentation],
  };
  NSError *serializeError = nil;
  NSData *payload = [NSPropertyListSerialization dataWithPropertyList:entry
                                                                format:NSPropertyListBinaryFormat_v1_0
                                                               options:0
                                                                 error:&serializeError];
  if (payload == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(424, @"mail delivery payload could not be serialized", serializeError);
    }
    return nil;
  }

  NSError *writeError = nil;
  BOOL wrote = [payload writeToFile:[self deliveryPathForID:deliveryID]
                            options:NSDataWritingAtomic
                              error:&writeError];
  [self.lock unlock];
  if (!wrote) {
    if (error != NULL) {
      *error = ALNServiceError(425, @"mail delivery payload could not be persisted", writeError);
    }
    return nil;
  }
  return deliveryID;
}

- (NSArray *)deliveriesSnapshot {
  [self.lock lock];
  NSError *listError = nil;
  NSArray *contents = [self.fileManager contentsOfDirectoryAtPath:self.storageDirectory error:&listError];
  if (contents == nil) {
    (void)listError;
    [self.lock unlock];
    return @[];
  }

  NSMutableArray *entries = [NSMutableArray array];
  NSArray *sorted = [contents sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *item in sorted) {
    if (![item hasSuffix:@".plist"]) {
      continue;
    }
    NSString *path = [self.storageDirectory stringByAppendingPathComponent:item];
    NSData *payload = [NSData dataWithContentsOfFile:path];
    if (payload == nil) {
      continue;
    }
    NSError *parseError = nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id parsed = [NSPropertyListSerialization propertyListWithData:payload
                                                          options:NSPropertyListImmutable
                                                           format:&format
                                                            error:&parseError];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
      (void)parseError;
      continue;
    }
    [entries addObject:parsed];
  }
  [self.lock unlock];
  return [NSArray arrayWithArray:entries];
}

- (void)reset {
  [self.lock lock];
  NSArray *contents = [self.fileManager contentsOfDirectoryAtPath:self.storageDirectory error:NULL];
  for (NSString *item in contents ?: @[]) {
    if (![item hasSuffix:@".plist"]) {
      continue;
    }
    NSString *path = [self.storageDirectory stringByAppendingPathComponent:item];
    (void)[self.fileManager removeItemAtPath:path error:NULL];
  }
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

@interface ALNFileSystemAttachmentAdapter ()

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, copy) NSString *rootDirectory;
@property(nonatomic, strong) NSFileManager *fileManager;
@property(nonatomic, strong) NSLock *lock;

@end

@implementation ALNFileSystemAttachmentAdapter

- (instancetype)initWithRootDirectory:(NSString *)rootDirectory
                          adapterName:(NSString *)adapterName
                                error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSString *normalizedRoot = [[ALNNonEmptyString(rootDirectory, @"") stringByExpandingTildeInPath]
      stringByStandardizingPath];
  if ([normalizedRoot length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(550, @"attachment root directory is required", nil);
    }
    return nil;
  }

  _adapterNameValue = [ALNNonEmptyString(adapterName, @"filesystem_attachment") copy];
  _rootDirectory = [normalizedRoot copy];
  _fileManager = [[NSFileManager alloc] init];
  _lock = [[NSLock alloc] init];

  NSError *directoryError = nil;
  BOOL created = [_fileManager createDirectoryAtPath:_rootDirectory
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:&directoryError];
  if (!created) {
    if (error != NULL) {
      *error = ALNServiceError(551, @"attachment root directory could not be created", directoryError);
    }
    return nil;
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"filesystem_attachment";
}

- (NSString *)attachmentDataPathForID:(NSString *)attachmentID {
  return [self.rootDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bin", attachmentID ?: @""]];
}

- (NSString *)attachmentMetadataPathForID:(NSString *)attachmentID {
  return [self.rootDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", attachmentID ?: @""]];
}

- (NSString *)nextAttachmentID {
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSString *suffix = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"att-%@", suffix ?: @""];
}

- (NSDictionary *)normalizedMetadataEntry:(NSDictionary *)entry {
  return @{
    @"attachmentID" : ALNNonEmptyString(entry[@"attachmentID"], @""),
    @"name" : ALNNonEmptyString(entry[@"name"], @""),
    @"contentType" : ALNNonEmptyString(entry[@"contentType"], @"application/octet-stream"),
    @"sizeBytes" : [entry[@"sizeBytes"] respondsToSelector:@selector(unsignedLongLongValue)]
        ? @([entry[@"sizeBytes"] unsignedLongLongValue])
        : @(0),
    @"createdAt" : [entry[@"createdAt"] respondsToSelector:@selector(doubleValue)] ? @([entry[@"createdAt"] doubleValue]) : @(0),
    @"metadata" : ALNNormalizeDictionary(entry[@"metadata"]),
  };
}

- (NSDictionary *)metadataEntryForAttachmentID:(NSString *)attachmentID error:(NSError **)error {
  NSString *metadataPath = [self attachmentMetadataPathForID:attachmentID];
  if (![self.fileManager fileExistsAtPath:metadataPath]) {
    return nil;
  }

  NSData *metadataData = [NSData dataWithContentsOfFile:metadataPath];
  if (metadataData == nil) {
    if (error != NULL) {
      *error = ALNServiceError(552, @"attachment metadata could not be read", nil);
    }
    return nil;
  }

  NSError *parseError = nil;
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id parsed = [NSPropertyListSerialization propertyListWithData:metadataData
                                                        options:NSPropertyListImmutable
                                                         format:&format
                                                          error:&parseError];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNServiceError(553, @"attachment metadata is malformed", parseError);
    }
    return nil;
  }
  return parsed;
}

- (NSString *)saveAttachmentNamed:(NSString *)name
                      contentType:(NSString *)contentType
                             data:(NSData *)data
                         metadata:(NSDictionary *)metadata
                            error:(NSError **)error {
  NSString *normalizedName = ALNNonEmptyString(name, @"");
  if ([normalizedName length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(554, @"attachment name is required", nil);
    }
    return nil;
  }
  if (![data isKindOfClass:[NSData class]]) {
    if (error != NULL) {
      *error = ALNServiceError(555, @"attachment data is required", nil);
    }
    return nil;
  }

  NSString *normalizedType = ALNNonEmptyString(contentType, @"application/octet-stream");
  NSDictionary *userMetadata = ALNNormalizeDictionary(metadata);
  NSString *attachmentID = [self nextAttachmentID];
  NSDictionary *entry = @{
    @"attachmentID" : attachmentID ?: @"",
    @"name" : normalizedName,
    @"contentType" : normalizedType,
    @"sizeBytes" : @([data length]),
    @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
    @"metadata" : userMetadata,
  };

  NSError *serializeError = nil;
  NSData *metadataData = [NSPropertyListSerialization dataWithPropertyList:entry
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0
                                                                      error:&serializeError];
  if (metadataData == nil) {
    if (error != NULL) {
      *error = ALNServiceError(556, @"attachment metadata could not be serialized", serializeError);
    }
    return nil;
  }

  NSString *dataPath = [self attachmentDataPathForID:attachmentID];
  NSString *metadataPath = [self attachmentMetadataPathForID:attachmentID];

  [self.lock lock];
  BOOL wroteData = [data writeToFile:dataPath atomically:YES];
  if (!wroteData) {
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(557, @"attachment data could not be persisted", nil);
    }
    return nil;
  }

  BOOL wroteMetadata = [metadataData writeToFile:metadataPath atomically:YES];
  if (!wroteMetadata) {
    (void)[self.fileManager removeItemAtPath:dataPath error:NULL];
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(558, @"attachment metadata could not be persisted", nil);
    }
    return nil;
  }
  [self.lock unlock];
  return attachmentID;
}

- (NSData *)attachmentDataForID:(NSString *)attachmentID
                       metadata:(NSDictionary **)metadata
                          error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(attachmentID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(559, @"attachment ID is required", nil);
    }
    return nil;
  }

  [self.lock lock];
  NSError *readError = nil;
  NSDictionary *entry = [self metadataEntryForAttachmentID:normalizedID error:&readError];
  if (entry == nil) {
    [self.lock unlock];
    if (readError != nil && error != NULL) {
      *error = readError;
    }
    return nil;
  }

  NSString *dataPath = [self attachmentDataPathForID:normalizedID];
  NSData *data = [NSData dataWithContentsOfFile:dataPath];
  if (data == nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = ALNServiceError(560, @"attachment data could not be read", nil);
    }
    return nil;
  }

  if (metadata != NULL) {
    *metadata = [self normalizedMetadataEntry:entry];
  }
  [self.lock unlock];
  return data;
}

- (NSDictionary *)attachmentMetadataForID:(NSString *)attachmentID error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(attachmentID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(561, @"attachment ID is required", nil);
    }
    return nil;
  }

  [self.lock lock];
  NSError *readError = nil;
  NSDictionary *entry = [self metadataEntryForAttachmentID:normalizedID error:&readError];
  [self.lock unlock];
  if (entry == nil) {
    if (readError != nil && error != NULL) {
      *error = readError;
    }
    return nil;
  }
  return [self normalizedMetadataEntry:entry];
}

- (BOOL)deleteAttachmentID:(NSString *)attachmentID error:(NSError **)error {
  NSString *normalizedID = ALNNonEmptyString(attachmentID, @"");
  if ([normalizedID length] == 0) {
    if (error != NULL) {
      *error = ALNServiceError(562, @"attachment ID is required", nil);
    }
    return NO;
  }

  NSString *dataPath = [self attachmentDataPathForID:normalizedID];
  NSString *metadataPath = [self attachmentMetadataPathForID:normalizedID];

  [self.lock lock];
  BOOL hadData = [self.fileManager fileExistsAtPath:dataPath];
  BOOL hadMetadata = [self.fileManager fileExistsAtPath:metadataPath];

  if (hadData && ![self.fileManager removeItemAtPath:dataPath error:error]) {
    [self.lock unlock];
    return NO;
  }
  if (hadMetadata && ![self.fileManager removeItemAtPath:metadataPath error:error]) {
    [self.lock unlock];
    return NO;
  }
  [self.lock unlock];
  return hadData || hadMetadata;
}

- (NSArray *)listAttachmentMetadata {
  [self.lock lock];
  NSError *listError = nil;
  NSArray *contents = [self.fileManager contentsOfDirectoryAtPath:self.rootDirectory error:&listError];
  if (contents == nil) {
    (void)listError;
    [self.lock unlock];
    return @[];
  }

  NSMutableArray *entries = [NSMutableArray array];
  for (NSString *item in contents) {
    if (![item hasSuffix:@".plist"]) {
      continue;
    }
    NSString *attachmentID = [item substringToIndex:[item length] - [@".plist" length]];
    NSDictionary *entry = [self metadataEntryForAttachmentID:attachmentID error:NULL];
    if (entry == nil) {
      continue;
    }
    [entries addObject:[self normalizedMetadataEntry:entry]];
  }
  [self.lock unlock];
  NSSortDescriptor *sortDescriptor =
      [NSSortDescriptor sortDescriptorWithKey:@"attachmentID" ascending:YES selector:@selector(compare:)];
  [entries sortUsingDescriptors:@[ sortDescriptor ]];
  return [NSArray arrayWithArray:entries];
}

- (void)reset {
  [self.lock lock];
  NSArray *contents = [self.fileManager contentsOfDirectoryAtPath:self.rootDirectory error:NULL];
  for (NSString *item in contents ?: @[]) {
    NSString *path = [self.rootDirectory stringByAppendingPathComponent:item];
    (void)[self.fileManager removeItemAtPath:path error:NULL];
  }
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
