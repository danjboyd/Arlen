#import "ALNEventStream.h"

#import "ALNContext.h"
#import "ALNPlatform.h"
#import "ALNRequest.h"

NSString *const ALNEventStreamErrorDomain = @"Arlen.EventStream.Error";

static NSString *ALNEventStreamTrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static NSError *ALNEventStreamError(ALNEventStreamErrorCode code,
                                    NSString *message,
                                    NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  if ([message length] > 0) {
    userInfo[NSLocalizedDescriptionKey] = message;
  }
  if ([details count] > 0) {
    [userInfo addEntriesFromDictionary:details];
  }
  return [NSError errorWithDomain:ALNEventStreamErrorDomain code:code userInfo:userInfo];
}

static NSString *ALNNormalizedEventStreamIdentifier(NSString *value) {
  return ALNEventStreamTrimmedString(value);
}

static NSDictionary *ALNNormalizedEventMaterial(NSDictionary *event, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSDictionary *dictionary = [event isKindOfClass:[NSDictionary class]] ? event : nil;
  if (dictionary == nil) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidEnvelope,
                                   @"Event payload must be a dictionary",
                                   @{ @"field" : @"event" });
    }
    return nil;
  }

  NSString *eventType = ALNEventStreamTrimmedString(dictionary[@"event_type"]);
  NSDictionary *payload = [dictionary[@"payload"] isKindOfClass:[NSDictionary class]]
                              ? dictionary[@"payload"]
                              : nil;
  NSDictionary *actor = [dictionary[@"actor"] isKindOfClass:[NSDictionary class]]
                            ? dictionary[@"actor"]
                            : nil;
  NSDictionary *metadata = [dictionary[@"metadata"] isKindOfClass:[NSDictionary class]]
                               ? dictionary[@"metadata"]
                               : nil;
  NSString *idempotencyKey = ALNEventStreamTrimmedString(dictionary[@"idempotency_key"]);

  if ([eventType length] == 0) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidEnvelope,
                                   @"Event type is required",
                                   @{ @"field" : @"event_type" });
    }
    return nil;
  }
  if (payload == nil) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidEnvelope,
                                   @"Event payload must be a dictionary",
                                   @{ @"field" : @"payload" });
    }
    return nil;
  }

  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  normalized[@"event_type"] = eventType;
  normalized[@"payload"] = payload;
  if ([idempotencyKey length] > 0) {
    normalized[@"idempotency_key"] = idempotencyKey;
  }
  if (actor != nil) {
    normalized[@"actor"] = actor;
  }
  if (metadata != nil) {
    normalized[@"metadata"] = metadata;
  }
  return [normalized copy];
}

static NSString *ALNGeneratedEventID(void) {
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSString *compact = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"evt_%@", compact ?: @""];
}

@implementation ALNEventStreamCursor

- (instancetype)initWithStreamID:(NSString *)streamID sequence:(NSUInteger)sequence {
  self = [super init];
  if (self) {
    _streamID = [ALNNormalizedEventStreamIdentifier(streamID) copy] ?: @"";
    _sequence = sequence;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] initWithStreamID:self.streamID sequence:self.sequence];
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    @"stream_id" : self.streamID ?: @"",
    @"sequence" : @(self.sequence),
  };
}

@end

@implementation ALNEventEnvelope

- (instancetype)initWithStreamID:(NSString *)streamID
                        sequence:(NSUInteger)sequence
                         eventID:(NSString *)eventID
                       eventType:(NSString *)eventType
                      occurredAt:(NSString *)occurredAt
                         payload:(NSDictionary *)payload
                  idempotencyKey:(NSString *)idempotencyKey
                           actor:(NSDictionary *)actor
                        metadata:(NSDictionary *)metadata {
  self = [super init];
  if (self) {
    _streamID = [ALNNormalizedEventStreamIdentifier(streamID) copy] ?: @"";
    _sequence = sequence;
    _eventID = [ALNEventStreamTrimmedString(eventID) copy] ?: @"";
    _eventType = [ALNEventStreamTrimmedString(eventType) copy] ?: @"";
    _occurredAt = [ALNEventStreamTrimmedString(occurredAt) copy] ?: @"";
    _payload = [payload copy] ?: @{};
    NSString *normalizedIdempotencyKey = ALNEventStreamTrimmedString(idempotencyKey);
    _idempotencyKey = ([normalizedIdempotencyKey length] > 0) ? [normalizedIdempotencyKey copy] : nil;
    _actor = [actor copy];
    _metadata = [metadata copy];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] initWithStreamID:self.streamID
                                                    sequence:self.sequence
                                                     eventID:self.eventID
                                                   eventType:self.eventType
                                                  occurredAt:self.occurredAt
                                                     payload:self.payload
                                              idempotencyKey:self.idempotencyKey
                                                       actor:self.actor
                                                    metadata:self.metadata];
}

- (NSDictionary *)dictionaryRepresentation {
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"stream_id"] = self.streamID ?: @"";
  result[@"sequence"] = @(self.sequence);
  result[@"event_id"] = self.eventID ?: @"";
  result[@"event_type"] = self.eventType ?: @"";
  result[@"occurred_at"] = self.occurredAt ?: @"";
  result[@"payload"] = self.payload ?: @{};
  if ([self.idempotencyKey length] > 0) {
    result[@"idempotency_key"] = self.idempotencyKey;
  }
  if (self.actor != nil) {
    result[@"actor"] = self.actor;
  }
  if (self.metadata != nil) {
    result[@"metadata"] = self.metadata;
  }
  return [result copy];
}

@end

@implementation ALNEventStreamAppendResult

- (instancetype)initWithCommittedEvent:(ALNEventEnvelope *)committedEvent
                  livePublishAttempted:(BOOL)livePublishAttempted
                  livePublishSucceeded:(BOOL)livePublishSucceeded
                      livePublishError:(NSError *)livePublishError {
  self = [super init];
  if (self) {
    _committedEvent = committedEvent;
    _livePublishAttempted = livePublishAttempted;
    _livePublishSucceeded = livePublishSucceeded;
    _livePublishError = livePublishError;
  }
  return self;
}

@end

@implementation ALNEventStreamReplayResult

- (instancetype)initWithStreamID:(NSString *)streamID
                          events:(NSArray<ALNEventEnvelope *> *)events
                    latestCursor:(ALNEventStreamCursor *)latestCursor
           requestedAfterSequence:(NSNumber *)requestedAfterSequence
                     replayLimit:(NSUInteger)replayLimit
                    replayWindow:(NSUInteger)replayWindow
                  resyncRequired:(BOOL)resyncRequired {
  self = [super init];
  if (self) {
    _streamID = [ALNNormalizedEventStreamIdentifier(streamID) copy] ?: @"";
    _events = [events copy] ?: @[];
    _latestCursor = latestCursor ?: [[ALNEventStreamCursor alloc] initWithStreamID:_streamID sequence:0];
    _requestedAfterSequence =
        [requestedAfterSequence respondsToSelector:@selector(unsignedIntegerValue)]
            ? @([requestedAfterSequence unsignedIntegerValue])
            : nil;
    _replayLimit = replayLimit;
    _replayWindow = replayWindow;
    _resyncRequired = resyncRequired;
  }
  return self;
}

- (NSDictionary *)dictionaryRepresentation {
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"stream_id"] = self.streamID ?: @"";
  result[@"events"] =
      [self.events valueForKey:@"dictionaryRepresentation"] ?: @[];
  result[@"latest_cursor"] = [self.latestCursor dictionaryRepresentation] ?: @{};
  result[@"replay_limit"] = @(self.replayLimit);
  result[@"replay_window"] = @(self.replayWindow);
  result[@"resync_required"] = @(self.resyncRequired);
  if (self.requestedAfterSequence != nil) {
    result[@"requested_after_sequence"] = self.requestedAfterSequence;
  }
  return [result copy];
}

@end

@implementation ALNEventStreamRequestContext

+ (instancetype)requestContextWithContext:(ALNContext *)context {
  ALNRequest *request = context.request;
  return [[self alloc] initWithRequestMethod:[ALNEventStreamTrimmedString(request.method) uppercaseString]
                                 requestPath:request.path ?: @""
                          requestQueryString:request.queryString ?: @""
                                   routeName:context.routeName ?: @""
                              controllerName:context.controllerName ?: @""
                                  actionName:context.actionName ?: @""
                                 authSubject:[context authSubject]
                                  authScopes:[context authScopes] ?: @[]
                                   authRoles:[context authRoles] ?: @[]
                                  authClaims:[context authClaims]
                       authSessionIdentifier:[context authSessionIdentifier]
                                 liveRequest:[context isLiveRequest]];
}

- (instancetype)initWithRequestMethod:(NSString *)requestMethod
                          requestPath:(NSString *)requestPath
                   requestQueryString:(NSString *)requestQueryString
                            routeName:(NSString *)routeName
                       controllerName:(NSString *)controllerName
                           actionName:(NSString *)actionName
                          authSubject:(NSString *)authSubject
                           authScopes:(NSArray *)authScopes
                            authRoles:(NSArray *)authRoles
                           authClaims:(NSDictionary *)authClaims
                authSessionIdentifier:(NSString *)authSessionIdentifier
                          liveRequest:(BOOL)liveRequest {
  self = [super init];
  if (self) {
    _requestMethod = [[ALNEventStreamTrimmedString(requestMethod) uppercaseString] copy] ?: @"";
    _requestPath = [ALNEventStreamTrimmedString(requestPath) copy] ?: @"";
    _requestQueryString = [ALNEventStreamTrimmedString(requestQueryString) copy] ?: @"";
    _routeName = [ALNEventStreamTrimmedString(routeName) copy] ?: @"";
    _controllerName = [ALNEventStreamTrimmedString(controllerName) copy] ?: @"";
    _actionName = [ALNEventStreamTrimmedString(actionName) copy] ?: @"";
    NSString *normalizedSubject = ALNEventStreamTrimmedString(authSubject);
    _authSubject = ([normalizedSubject length] > 0) ? [normalizedSubject copy] : nil;
    _authScopes = [authScopes copy] ?: @[];
    _authRoles = [authRoles copy] ?: @[];
    _authClaims = [authClaims copy];
    NSString *normalizedSessionIdentifier = ALNEventStreamTrimmedString(authSessionIdentifier);
    _authSessionIdentifier =
        ([normalizedSessionIdentifier length] > 0) ? [normalizedSessionIdentifier copy] : nil;
    _liveRequest = liveRequest;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] initWithRequestMethod:self.requestMethod
                                                      requestPath:self.requestPath
                                               requestQueryString:self.requestQueryString
                                                        routeName:self.routeName
                                                   controllerName:self.controllerName
                                                       actionName:self.actionName
                                                      authSubject:self.authSubject
                                                       authScopes:self.authScopes
                                                        authRoles:self.authRoles
                                                       authClaims:self.authClaims
                                            authSessionIdentifier:self.authSessionIdentifier
                                                      liveRequest:self.liveRequest];
}

- (NSDictionary *)dictionaryRepresentation {
  NSMutableDictionary *representation = [NSMutableDictionary dictionary];
  representation[@"request_method"] = self.requestMethod ?: @"";
  representation[@"request_path"] = self.requestPath ?: @"";
  representation[@"request_query_string"] = self.requestQueryString ?: @"";
  representation[@"route_name"] = self.routeName ?: @"";
  representation[@"controller_name"] = self.controllerName ?: @"";
  representation[@"action_name"] = self.actionName ?: @"";
  representation[@"auth_scopes"] = self.authScopes ?: @[];
  representation[@"auth_roles"] = self.authRoles ?: @[];
  representation[@"live_request"] = @(self.liveRequest);
  if ([self.authSubject length] > 0) {
    representation[@"auth_subject"] = self.authSubject;
  }
  if ([self.authSessionIdentifier length] > 0) {
    representation[@"auth_session_identifier"] = self.authSessionIdentifier;
  }
  if (self.authClaims != nil) {
    representation[@"auth_claims"] = self.authClaims;
  }
  return [representation copy];
}

@end

@implementation ALNEventStreamBrokerSubscription

- (instancetype)initWithStreamID:(NSString *)streamID
                      subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber {
  self = [super init];
  if (self) {
    _streamID = [ALNNormalizedEventStreamIdentifier(streamID) copy] ?: @"";
    _subscriber = subscriber;
  }
  return self;
}

@end

@interface ALNInMemoryEventStreamStore ()

@property(nonatomic, copy) NSString *storeAdapterName;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<ALNEventEnvelope *> *> *eventsByStream;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, ALNEventEnvelope *> *> *idempotencyIndexByStream;

@end

@implementation ALNInMemoryEventStreamStore

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    NSString *normalized = ALNEventStreamTrimmedString(adapterName);
    _storeAdapterName = ([normalized length] > 0) ? [normalized copy] : @"in_memory_event_stream";
    _lock = [[NSLock alloc] init];
    _eventsByStream = [NSMutableDictionary dictionary];
    _idempotencyIndexByStream = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSString *)adapterName {
  return self.storeAdapterName ?: @"in_memory_event_stream";
}

- (ALNEventEnvelope *)appendEvent:(NSDictionary *)event
                         toStream:(NSString *)streamID
                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(streamID);
  if ([normalizedStreamID length] == 0) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Stream identifier is required",
                                   @{ @"field" : @"stream_id" });
    }
    return nil;
  }

  NSError *materialError = nil;
  NSDictionary *material = ALNNormalizedEventMaterial(event, &materialError);
  if (material == nil) {
    if (error != NULL) {
      *error = materialError;
    }
    return nil;
  }

  NSString *idempotencyKey = ALNEventStreamTrimmedString(material[@"idempotency_key"]);

  [self.lock lock];

  NSMutableDictionary<NSString *, ALNEventEnvelope *> *idempotencyIndex =
      self.idempotencyIndexByStream[normalizedStreamID];
  if ([idempotencyKey length] > 0 && idempotencyIndex[idempotencyKey] != nil) {
    ALNEventEnvelope *existing = idempotencyIndex[idempotencyKey];
    NSDictionary *existingMaterial = @{
      @"event_type" : existing.eventType ?: @"",
      @"payload" : existing.payload ?: @{},
      @"idempotency_key" : existing.idempotencyKey ?: @"",
      @"actor" : existing.actor ?: @{},
      @"metadata" : existing.metadata ?: @{},
    };
    NSDictionary *requestedMaterial = @{
      @"event_type" : material[@"event_type"] ?: @"",
      @"payload" : material[@"payload"] ?: @{},
      @"idempotency_key" : idempotencyKey ?: @"",
      @"actor" : material[@"actor"] ?: @{},
      @"metadata" : material[@"metadata"] ?: @{},
    };
    if (![existingMaterial isEqual:requestedMaterial]) {
      [self.lock unlock];
      if (error != NULL) {
        *error = ALNEventStreamError(ALNEventStreamErrorIdempotencyConflict,
                                     @"Idempotency key reuse conflicts with an existing committed event",
                                     @{
                                       @"stream_id" : normalizedStreamID,
                                       @"idempotency_key" : idempotencyKey ?: @"",
                                     });
      }
      return nil;
    }
    ALNEventEnvelope *copy = [existing copy];
    [self.lock unlock];
    return copy;
  }

  NSMutableArray<ALNEventEnvelope *> *events = self.eventsByStream[normalizedStreamID];
  if (events == nil) {
    events = [NSMutableArray array];
    self.eventsByStream[normalizedStreamID] = events;
  }

  NSUInteger nextSequence = [events count] + 1;
  ALNEventEnvelope *committed = [[ALNEventEnvelope alloc] initWithStreamID:normalizedStreamID
                                                                  sequence:nextSequence
                                                                   eventID:ALNGeneratedEventID()
                                                                 eventType:material[@"event_type"] ?: @""
                                                                occurredAt:ALNPlatformISO8601Now()
                                                                   payload:material[@"payload"] ?: @{}
                                                            idempotencyKey:([idempotencyKey length] > 0 ? idempotencyKey : nil)
                                                                     actor:material[@"actor"]
                                                                  metadata:material[@"metadata"]];
  [events addObject:committed];
  if ([idempotencyKey length] > 0) {
    if (idempotencyIndex == nil) {
      idempotencyIndex = [NSMutableDictionary dictionary];
      self.idempotencyIndexByStream[normalizedStreamID] = idempotencyIndex;
    }
    idempotencyIndex[idempotencyKey] = committed;
  }

  ALNEventEnvelope *copy = [committed copy];
  [self.lock unlock];
  return copy;
}

- (NSArray<ALNEventEnvelope *> *)eventsForStream:(NSString *)streamID
                                   afterSequence:(NSNumber *)sequence
                                           limit:(NSUInteger)limit
                                           error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(streamID);
  if ([normalizedStreamID length] == 0) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Stream identifier is required",
                                   @{ @"field" : @"stream_id" });
    }
    return nil;
  }

  NSUInteger minimumSequence = [sequence respondsToSelector:@selector(unsignedIntegerValue)]
                                   ? [sequence unsignedIntegerValue]
                                   : 0;
  NSUInteger effectiveLimit = (limit > 0) ? limit : 100;

  [self.lock lock];
  NSArray<ALNEventEnvelope *> *events = [NSArray arrayWithArray:self.eventsByStream[normalizedStreamID] ?: @[]];
  [self.lock unlock];

  NSMutableArray<ALNEventEnvelope *> *results = [NSMutableArray array];
  for (ALNEventEnvelope *eventEnvelope in events) {
    if (eventEnvelope.sequence <= minimumSequence) {
      continue;
    }
    [results addObject:[eventEnvelope copy]];
    if ([results count] >= effectiveLimit) {
      break;
    }
  }
  return [results copy];
}

- (ALNEventStreamCursor *)latestCursorForStream:(NSString *)streamID
                                          error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(streamID);
  if ([normalizedStreamID length] == 0) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Stream identifier is required",
                                   @{ @"field" : @"stream_id" });
    }
    return nil;
  }

  [self.lock lock];
  NSArray<ALNEventEnvelope *> *events = self.eventsByStream[normalizedStreamID];
  ALNEventEnvelope *latest = [events lastObject];
  [self.lock unlock];
  if (latest == nil) {
    return nil;
  }
  return [[ALNEventStreamCursor alloc] initWithStreamID:normalizedStreamID sequence:latest.sequence];
}

- (void)reset {
  [self.lock lock];
  [self.eventsByStream removeAllObjects];
  [self.idempotencyIndexByStream removeAllObjects];
  [self.lock unlock];
}

@end

@interface ALNInMemoryEventStreamBroker ()

@property(nonatomic, copy) NSString *brokerAdapterName;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, NSMutableArray<ALNEventStreamBrokerSubscription *> *> *subscriptionsByStream;

@end

@implementation ALNInMemoryEventStreamBroker

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self) {
    NSString *normalized = ALNEventStreamTrimmedString(adapterName);
    _brokerAdapterName = ([normalized length] > 0) ? [normalized copy] : @"in_memory_event_stream_broker";
    _lock = [[NSLock alloc] init];
    _subscriptionsByStream = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSString *)adapterName {
  return self.brokerAdapterName ?: @"in_memory_event_stream_broker";
}

- (BOOL)publishCommittedEvent:(ALNEventEnvelope *)event
                     onStream:(NSString *)streamID
                        error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(streamID);
  if ([normalizedStreamID length] == 0 || event == nil) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Committed event and stream identifier are required",
                                   @{ @"field" : @"stream_id" });
    }
    return NO;
  }

  NSArray<ALNEventStreamBrokerSubscription *> *subscriptions = nil;
  [self.lock lock];
  subscriptions =
      [NSArray arrayWithArray:self.subscriptionsByStream[normalizedStreamID] ?: @[]];
  [self.lock unlock];

  for (ALNEventStreamBrokerSubscription *subscription in subscriptions) {
    id<ALNEventStreamLiveSubscriber> subscriber = subscription.subscriber;
    if (subscriber == nil) {
      continue;
    }
    @try {
      [subscriber receiveCommittedEvent:[event copy] onStream:normalizedStreamID];
    } @catch (NSException *exception) {
      (void)exception;
    }
  }
  return YES;
}

- (ALNEventStreamBrokerSubscription *)subscribeToStream:(NSString *)streamID
                                             subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber
                                                  error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(streamID);
  if ([normalizedStreamID length] == 0 || subscriber == nil) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Stream identifier and subscriber are required",
                                   @{ @"field" : @"stream_id" });
    }
    return nil;
  }

  ALNEventStreamBrokerSubscription *subscription =
      [[ALNEventStreamBrokerSubscription alloc] initWithStreamID:normalizedStreamID
                                                      subscriber:subscriber];
  [self.lock lock];
  NSMutableArray<ALNEventStreamBrokerSubscription *> *subscriptions =
      self.subscriptionsByStream[normalizedStreamID];
  if (subscriptions == nil) {
    subscriptions = [NSMutableArray array];
    self.subscriptionsByStream[normalizedStreamID] = subscriptions;
  }
  [subscriptions addObject:subscription];
  [self.lock unlock];
  return subscription;
}

- (void)unsubscribe:(ALNEventStreamBrokerSubscription *)subscription {
  if (subscription == nil) {
    return;
  }
  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(subscription.streamID);
  if ([normalizedStreamID length] == 0) {
    return;
  }

  [self.lock lock];
  NSMutableArray<ALNEventStreamBrokerSubscription *> *subscriptions =
      self.subscriptionsByStream[normalizedStreamID];
  [subscriptions removeObjectIdenticalTo:subscription];
  if ([subscriptions count] == 0) {
    [self.subscriptionsByStream removeObjectForKey:normalizedStreamID];
  }
  [self.lock unlock];
}

- (void)reset {
  [self.lock lock];
  [self.subscriptionsByStream removeAllObjects];
  [self.lock unlock];
}

@end

@implementation ALNEventStreamService

- (instancetype)initWithStore:(id<ALNEventStreamStore>)store broker:(id<ALNEventStreamBroker>)broker {
  self = [super init];
  if (self) {
    _store = store;
    _broker = broker;
  }
  return self;
}

- (ALNEventStreamAppendResult *)appendEvent:(NSDictionary *)event
                                   toStream:(NSString *)streamID
                                      error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (self.store == nil) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Event stream store is required",
                                   @{ @"field" : @"store" });
    }
    return nil;
  }

  ALNEventEnvelope *committed = [self.store appendEvent:event toStream:streamID error:error];
  if (committed == nil) {
    return nil;
  }

  BOOL livePublishAttempted = (self.broker != nil);
  BOOL livePublishSucceeded = NO;
  NSError *livePublishError = nil;
  if (self.broker != nil) {
    livePublishSucceeded =
        [self.broker publishCommittedEvent:committed onStream:committed.streamID error:&livePublishError];
  }

  return [[ALNEventStreamAppendResult alloc] initWithCommittedEvent:committed
                                               livePublishAttempted:livePublishAttempted
                                               livePublishSucceeded:livePublishSucceeded
                                                   livePublishError:livePublishError];
}

- (ALNEventStreamReplayResult *)replayStream:(NSString *)streamID
                               afterSequence:(NSNumber *)sequence
                                       limit:(NSUInteger)limit
                                replayWindow:(NSUInteger)replayWindow
                                       error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (self.store == nil) {
    if (error != NULL) {
      *error = ALNEventStreamError(ALNEventStreamErrorInvalidArgument,
                                   @"Event stream store is required",
                                   @{ @"field" : @"store" });
    }
    return nil;
  }

  NSString *normalizedStreamID = ALNNormalizedEventStreamIdentifier(streamID);
  NSUInteger requestedAfterSequence =
      [sequence respondsToSelector:@selector(unsignedIntegerValue)] ? [sequence unsignedIntegerValue] : 0;
  NSUInteger effectiveLimit = (limit > 0) ? limit : 100;
  NSUInteger effectiveWindow = (replayWindow > 0) ? replayWindow : effectiveLimit;

  ALNEventStreamCursor *latestCursor =
      [self.store latestCursorForStream:normalizedStreamID error:error];
  if (latestCursor == nil && error != NULL && *error != nil) {
    return nil;
  }
  if (latestCursor == nil) {
    latestCursor = [[ALNEventStreamCursor alloc] initWithStreamID:normalizedStreamID sequence:0];
  }

  NSUInteger latestSequence = latestCursor.sequence;
  BOOL resyncRequired = NO;
  if (requestedAfterSequence > latestSequence) {
    resyncRequired = YES;
  } else {
    NSUInteger backlog = latestSequence - requestedAfterSequence;
    if (backlog > effectiveWindow || backlog > effectiveLimit) {
      resyncRequired = YES;
    }
  }

  NSArray<ALNEventEnvelope *> *events = @[];
  if (!resyncRequired) {
    events = [self.store eventsForStream:normalizedStreamID
                           afterSequence:(sequence != nil ? @([sequence unsignedIntegerValue]) : nil)
                                   limit:effectiveLimit
                                   error:error];
    if (events == nil) {
      return nil;
    }
  } else if (error != NULL) {
    *error = ALNEventStreamError(ALNEventStreamErrorResyncRequired,
                                 @"Requested cursor is outside the deterministic replay boundary",
                                 @{
                                   @"stream_id" : normalizedStreamID ?: @"",
                                   @"requested_after_sequence" : @(requestedAfterSequence),
                                   @"latest_sequence" : @(latestSequence),
                                   @"replay_limit" : @(effectiveLimit),
                                   @"replay_window" : @(effectiveWindow),
                                 });
  }

  return [[ALNEventStreamReplayResult alloc] initWithStreamID:normalizedStreamID
                                                       events:events ?: @[]
                                                 latestCursor:latestCursor
                                        requestedAfterSequence:(sequence != nil ? @([sequence unsignedIntegerValue]) : nil)
                                                  replayLimit:effectiveLimit
                                                 replayWindow:effectiveWindow
                                               resyncRequired:resyncRequired];
}

@end
