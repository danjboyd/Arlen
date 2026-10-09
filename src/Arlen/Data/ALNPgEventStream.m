#import "ALNPgEventStream.h"

#import "ALNJSONSerialization.h"
#import "ALNPg.h"
#import "ALNPgRealtimeFanout.h"
#import "ALNPlatform.h"
#import "ALNRealtime.h"

static NSString *ALNPgEventStreamTrimmed(id value) {
  return [value isKindOfClass:[NSString class]]
             ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
             : @"";
}

static BOOL ALNPgEventStreamIdentifierIsSafe(NSString *name) {
  if ([name length] == 0 || [name length] > 63) {
    return NO;
  }
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  unichar first = [name characterAtIndex:0];
  return (first < '0' || first > '9') && [name rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

static NSString *ALNPgEventStreamJSON(id object) {
  if (object == nil) {
    return nil;
  }
  NSData *data = [ALNJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  return data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static id ALNPgEventStreamParseJSON(id text) {
  if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
    return nil;
  }
  return [ALNJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
}

static NSError *ALNPgEventStreamStreamRequired(void) {
  return ALNEventStreamMakeError(ALNEventStreamErrorInvalidArgument, @"Stream identifier is required",
                                 @{ @"field" : @"stream_id" });
}

@interface ALNPgEventStreamStore ()
@property(nonatomic, strong) ALNPg *database;
@property(nonatomic, copy) NSString *tableName;
@property(nonatomic, strong) NSLock *schemaLock;
@property(nonatomic, assign) BOOL schemaReady;
@end

@implementation ALNPgEventStreamStore

- (instancetype)initWithConnectionString:(NSString *)connectionString
                               tableName:(NSString *)tableName
                          maxConnections:(NSUInteger)maxConnections
                                   error:(NSError **)error {
  NSString *table = [tableName length] > 0 ? [tableName lowercaseString] : @"arlen_event_stream_events";
  if (!ALNPgEventStreamIdentifierIsSafe(table)) {
    if (error != NULL) {
      *error = ALNEventStreamMakeError(ALNEventStreamErrorInvalidArgument,
                                       @"event stream table name must match [a-z_][a-z0-9_]{0,62}",
                                       @{ @"field" : @"tableName" });
    }
    return nil;
  }
  self = [super init];
  if (self != nil) {
    _tableName = [table copy];
    _schemaLock = [[NSLock alloc] init];
    _database = [[ALNPg alloc] initWithConnectionString:connectionString
                                         maxConnections:MAX((NSUInteger)1, maxConnections)
                                                  error:error];
    if (_database == nil) {
      return nil;
    }
    // Appends come from many request threads; wait briefly for a pooled
    // connection instead of failing when all are busy (ALNPg defaults to fail-fast).
    _database.acquireTimeout = 5.0;
  }
  return self;
}

- (NSString *)adapterName {
  return @"postgresql_event_stream";
}

- (BOOL)ensureSchema:(NSError **)error {
  [self.schemaLock lock];
  @try {
    if (self.schemaReady) {
      return YES;
    }
    NSString *create = [NSString stringWithFormat:
        @"CREATE TABLE IF NOT EXISTS %@ (stream_id TEXT NOT NULL, sequence BIGINT NOT NULL, event_id TEXT NOT NULL, "
         "event_type TEXT NOT NULL, occurred_at TEXT NOT NULL, payload TEXT NOT NULL, idempotency_key TEXT, "
         "actor TEXT, metadata TEXT, PRIMARY KEY (stream_id, sequence))",
        self.tableName];
    NSString *index = [NSString stringWithFormat:
        @"CREATE UNIQUE INDEX IF NOT EXISTS %@_idempotency ON %@ (stream_id, idempotency_key) "
         "WHERE idempotency_key IS NOT NULL",
        self.tableName, self.tableName];
    // CREATE ... IF NOT EXISTS is not safe under concurrency: two stores creating
    // the table at once can fail on pg_type_typname_nsp_index. Serialize the DDL
    // across every process sharing the database.
    NSString *lockKey = [NSString stringWithFormat:@"arlen_event_stream_schema:%@", self.tableName];
    BOOL created = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **innerError) {
      return [connection executeQuery:@"SELECT pg_advisory_xact_lock(hashtextextended($1, 0))"
                           parameters:@[ lockKey ]
                                error:innerError] != nil &&
             [connection executeCommand:create parameters:@[] error:innerError] >= 0 &&
             [connection executeCommand:index parameters:@[] error:innerError] >= 0;
    } error:error];
    if (!created) {
      return NO;
    }
    self.schemaReady = YES;
    return YES;
  } @finally {
    [self.schemaLock unlock];
  }
}

- (ALNEventEnvelope *)envelopeFromRow:(NSDictionary *)row {
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  dictionary[@"stream_id"] = row[@"stream_id"] ?: @"";
  dictionary[@"sequence"] = @([[row[@"sequence"] description] longLongValue]);
  dictionary[@"event_id"] = row[@"event_id"] ?: @"";
  dictionary[@"event_type"] = row[@"event_type"] ?: @"";
  dictionary[@"occurred_at"] = row[@"occurred_at"] ?: @"";
  dictionary[@"payload"] = ALNPgEventStreamParseJSON(row[@"payload"]) ?: @{};
  if ([row[@"idempotency_key"] isKindOfClass:[NSString class]]) {
    dictionary[@"idempotency_key"] = row[@"idempotency_key"];
  }
  id actor = ALNPgEventStreamParseJSON(row[@"actor"]);
  id metadata = ALNPgEventStreamParseJSON(row[@"metadata"]);
  if ([actor isKindOfClass:[NSDictionary class]]) {
    dictionary[@"actor"] = actor;
  }
  if ([metadata isKindOfClass:[NSDictionary class]]) {
    dictionary[@"metadata"] = metadata;
  }
  return [ALNEventEnvelope envelopeWithDictionary:dictionary];
}

- (ALNEventEnvelope *)appendEvent:(NSDictionary *)event toStream:(NSString *)streamID error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *stream = ALNPgEventStreamTrimmed(streamID);
  if ([stream length] == 0) {
    if (error != NULL) *error = ALNPgEventStreamStreamRequired();
    return nil;
  }
  NSDictionary *material = ALNEventStreamNormalizedAppendMaterial(event, error);
  if (material == nil || ![self ensureSchema:error]) {
    return nil;
  }
  NSString *idempotencyKey = ALNPgEventStreamTrimmed(material[@"idempotency_key"]);
  __block ALNEventEnvelope *result = nil;
  __block NSError *conflict = nil;
  NSString *columns = @"stream_id, sequence, event_id, event_type, occurred_at, payload, idempotency_key, actor, metadata";
  BOOL committed = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **innerError) {
    // Serialize appends per stream across every process sharing the database.
    if ([connection executeQuery:@"SELECT pg_advisory_xact_lock(hashtextextended($1, 0))"
                      parameters:@[ stream ]
                           error:innerError] == nil) {
      return NO;
    }
    if ([idempotencyKey length] > 0) {
      NSDictionary *existingRow =
          [connection executeQueryOne:[NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE stream_id = $1 AND idempotency_key = $2",
                                                                 columns, self.tableName]
                           parameters:@[ stream, idempotencyKey ]
                                error:innerError];
      if (existingRow != nil) {
        ALNEventEnvelope *existing = [self envelopeFromRow:existingRow];
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
          @"idempotency_key" : idempotencyKey,
          @"actor" : material[@"actor"] ?: @{},
          @"metadata" : material[@"metadata"] ?: @{},
        };
        if (![existingMaterial isEqual:requestedMaterial]) {
          conflict = ALNEventStreamMakeError(ALNEventStreamErrorIdempotencyConflict,
                                             @"Idempotency key reuse conflicts with an existing committed event",
                                             @{ @"stream_id" : stream, @"idempotency_key" : idempotencyKey });
        } else {
          result = existing;
        }
        return YES;
      }
    }
    NSDictionary *next = [connection executeQueryOne:[NSString stringWithFormat:
                                                          @"SELECT COALESCE(MAX(sequence), 0) + 1 AS next FROM %@ WHERE stream_id = $1",
                                                          self.tableName]
                                          parameters:@[ stream ]
                                               error:innerError];
    if (next == nil) {
      return NO;
    }
    NSUInteger sequence = (NSUInteger)[[next[@"next"] description] longLongValue];
    ALNEventEnvelope *envelope = [[ALNEventEnvelope alloc] initWithStreamID:stream
                                                                   sequence:sequence
                                                                    eventID:ALNEventStreamGeneratedEventID()
                                                                  eventType:material[@"event_type"]
                                                                 occurredAt:ALNPlatformISO8601Now()
                                                                    payload:material[@"payload"]
                                                             idempotencyKey:([idempotencyKey length] > 0 ? idempotencyKey : nil)
                                                                      actor:material[@"actor"]
                                                                   metadata:material[@"metadata"]];
    NSString *insert = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
                                                  self.tableName, columns];
    NSArray *parameters = @[
      stream, @(sequence), envelope.eventID, envelope.eventType, envelope.occurredAt,
      ALNPgEventStreamJSON(envelope.payload) ?: @"{}",
      envelope.idempotencyKey ?: [NSNull null],
      ALNPgEventStreamJSON(envelope.actor) ?: [NSNull null],
      ALNPgEventStreamJSON(envelope.metadata) ?: [NSNull null],
    ];
    if ([connection executeCommand:insert parameters:parameters error:innerError] < 0) {
      return NO;
    }
    result = envelope;
    return YES;
  }
                                                  error:error];
  if (conflict != nil) {
    if (error != NULL) *error = conflict;
    return nil;
  }
  return committed ? result : nil;
}

- (NSArray<ALNEventEnvelope *> *)eventsForStream:(NSString *)streamID
                                   afterSequence:(NSNumber *)sequence
                                           limit:(NSUInteger)limit
                                           error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *stream = ALNPgEventStreamTrimmed(streamID);
  if ([stream length] == 0) {
    if (error != NULL) *error = ALNPgEventStreamStreamRequired();
    return nil;
  }
  if (![self ensureSchema:error]) {
    return nil;
  }
  long long after = [sequence respondsToSelector:@selector(longLongValue)] ? [sequence longLongValue] : 0;
  NSArray *rows = [self.database executeQuery:[NSString stringWithFormat:
                                                   @"SELECT stream_id, sequence, event_id, event_type, occurred_at, payload, "
                                                    "idempotency_key, actor, metadata FROM %@ WHERE stream_id = $1 AND sequence > $2 "
                                                    "ORDER BY sequence LIMIT $3",
                                                   self.tableName]
                                   parameters:@[ stream, @(after), @(limit > 0 ? limit : 100) ]
                                        error:error];
  if (rows == nil) {
    return nil;
  }
  NSMutableArray<ALNEventEnvelope *> *events = [NSMutableArray arrayWithCapacity:[rows count]];
  for (NSDictionary *row in rows) {
    ALNEventEnvelope *envelope = [self envelopeFromRow:row];
    if (envelope != nil) {
      [events addObject:envelope];
    }
  }
  return events;
}

- (ALNEventStreamCursor *)latestCursorForStream:(NSString *)streamID error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *stream = ALNPgEventStreamTrimmed(streamID);
  if ([stream length] == 0) {
    if (error != NULL) *error = ALNPgEventStreamStreamRequired();
    return nil;
  }
  if (![self ensureSchema:error]) {
    return nil;
  }
  NSArray *rows = [self.database executeQuery:[NSString stringWithFormat:
                                                   @"SELECT MAX(sequence) AS latest FROM %@ WHERE stream_id = $1", self.tableName]
                                   parameters:@[ stream ]
                                        error:error];
  id latest = [rows firstObject][@"latest"];
  if (latest == nil || latest == [NSNull null]) {
    return nil;
  }
  return [[ALNEventStreamCursor alloc] initWithStreamID:stream sequence:(NSUInteger)[[latest description] longLongValue]];
}

@end

#pragma mark - Broker

@interface ALNPgEventStreamSubscriberBridge : NSObject <ALNRealtimeSubscriber>
@property(nonatomic, strong) id<ALNEventStreamLiveSubscriber> subscriber;
@property(nonatomic, copy) NSString *streamID;
@end

@implementation ALNPgEventStreamSubscriberBridge
- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel {
  (void)channel;
  ALNEventEnvelope *event = [ALNEventEnvelope envelopeWithDictionary:ALNPgEventStreamParseJSON(message)];
  if (event != nil) {
    [self.subscriber receiveCommittedEvent:event onStream:self.streamID];
  }
}
@end

@interface ALNPgEventStreamBroker ()
@property(nonatomic, strong) ALNRealtimeHub *hub;
@property(nonatomic, strong) ALNPgRealtimeFanout *fanout;
@property(nonatomic, strong) NSMutableDictionary<NSValue *, ALNRealtimeSubscription *> *hubSubscriptions;
@property(nonatomic, strong) NSLock *lock;
@end

@implementation ALNPgEventStreamBroker

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           notifyChannel:(NSString *)notifyChannel
                                   error:(NSError **)error {
  self = [super init];
  if (self != nil) {
    _hub = [[ALNRealtimeHub alloc] init];
    _fanout = [[ALNPgRealtimeFanout alloc] initWithConnectionString:connectionString
                                                      notifyChannel:[notifyChannel length] > 0 ? notifyChannel : @"arlen_event_streams"
                                                                hub:_hub
                                                              error:error];
    if (_fanout == nil) {
      return nil;
    }
    _hub.fanout = _fanout;
    _hubSubscriptions = [NSMutableDictionary dictionary];
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (NSString *)adapterName {
  return @"postgresql_event_stream_broker";
}

// Hub channels are case-insensitive; stream identifiers are not.
static NSString *ALNPgEventStreamChannel(NSString *streamID) {
  NSData *bytes = [streamID dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableString *channel = [NSMutableString stringWithString:@"evs."];
  const unsigned char *raw = bytes.bytes;
  for (NSUInteger i = 0; i < bytes.length; i++) {
    [channel appendFormat:@"%02x", raw[i]];
  }
  return channel;
}

- (BOOL)publishCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *stream = ALNPgEventStreamTrimmed(streamID);
  NSString *message = ALNPgEventStreamJSON([event dictionaryRepresentation]);
  if ([stream length] == 0 || message == nil) {
    if (error != NULL) {
      *error = ALNEventStreamMakeError(ALNEventStreamErrorInvalidArgument,
                                       @"Committed event and stream identifier are required",
                                       @{ @"field" : @"stream_id" });
    }
    return NO;
  }
  // Local subscribers now; other processes through NOTIFY.
  (void)[self.hub publishMessage:message onChannel:ALNPgEventStreamChannel(stream)];
  return YES;
}

- (ALNEventStreamBrokerSubscription *)subscribeToStream:(NSString *)streamID
                                             subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber
                                                  error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *stream = ALNPgEventStreamTrimmed(streamID);
  if ([stream length] == 0 || subscriber == nil) {
    if (error != NULL) {
      *error = ALNEventStreamMakeError(ALNEventStreamErrorInvalidArgument,
                                       @"Stream identifier and subscriber are required",
                                       @{ @"field" : @"stream_id" });
    }
    return nil;
  }
  (void)[self.fanout startWaitingUpTo:5.0];
  ALNPgEventStreamSubscriberBridge *bridge = [[ALNPgEventStreamSubscriberBridge alloc] init];
  bridge.subscriber = subscriber;
  bridge.streamID = stream;
  ALNRealtimeSubscription *hubSubscription = [self.hub subscribeChannel:ALNPgEventStreamChannel(stream) subscriber:bridge];
  if (hubSubscription == nil) {
    if (error != NULL) {
      *error = ALNEventStreamMakeError(ALNEventStreamErrorInvalidArgument, @"Subscription limit reached",
                                       @{ @"stream_id" : stream });
    }
    return nil;
  }
  ALNEventStreamBrokerSubscription *subscription =
      [[ALNEventStreamBrokerSubscription alloc] initWithStreamID:stream subscriber:subscriber];
  [self.lock lock];
  self.hubSubscriptions[[NSValue valueWithNonretainedObject:subscription]] = hubSubscription;
  [self.lock unlock];
  return subscription;
}

- (void)unsubscribe:(ALNEventStreamBrokerSubscription *)subscription {
  if (subscription == nil) {
    return;
  }
  NSValue *key = [NSValue valueWithNonretainedObject:subscription];
  [self.lock lock];
  ALNRealtimeSubscription *hubSubscription = self.hubSubscriptions[key];
  [self.hubSubscriptions removeObjectForKey:key];
  [self.lock unlock];
  [self.hub unsubscribe:hubSubscription];
}

- (void)stop {
  self.hub.fanout = nil;
}

@end
