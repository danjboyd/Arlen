#import "ALNPgRealtimeFanout.h"

#import "ALNJSONSerialization.h"
#import "ALNPg.h"

#include <stdio.h>

static NSString *const ALNPgRealtimeFanoutErrorDomain = @"Arlen.Data.PgRealtimeFanout.Error";
// NOTIFY payloads must stay under 8000 bytes; leave room for the envelope.
static const NSUInteger ALNPgRealtimeInlinePayloadLimit = 7800;
static const NSUInteger ALNPgRealtimePruneInterval = 100;

static void ALNPgRealtimeWarn(NSString *message) {
  fprintf(stderr, "arlen realtime fanout: %s\n", [message UTF8String]);
}

static BOOL ALNPgRealtimeChannelIsSafe(NSString *channel) {
  if ([channel length] == 0 || [channel length] > 63) {
    return NO;
  }
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  unichar first = [channel characterAtIndex:0];
  return (first < '0' || first > '9') && [channel rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

@interface ALNPgRealtimeFanout ()
@property(nonatomic, copy, readwrite) NSString *originIdentifier;
@property(nonatomic, copy) NSString *connectionString;
@property(nonatomic, copy) NSString *notifyChannel;
@property(nonatomic, weak) ALNRealtimeHub *hub;
// Not an Objective-C object on GNUstep (no OS_OBJECT_USE_OBJC); released in dealloc.
@property(nonatomic, assign) dispatch_queue_t publishQueue;
@property(nonatomic, strong) ALNPg *publisher;
@property(nonatomic, strong) NSCondition *state;
@property(nonatomic, assign) BOOL stopped;
@property(nonatomic, assign) BOOL threadRunning;
@property(nonatomic, assign, readwrite) BOOL listening;
@property(nonatomic, assign) BOOL payloadTableReady;
@property(nonatomic, assign) NSUInteger storedPayloads;
@end

@implementation ALNPgRealtimeFanout

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           notifyChannel:(NSString *)notifyChannel
                                     hub:(ALNRealtimeHub *)hub
                                   error:(NSError **)error {
  NSString *channel = [notifyChannel length] > 0 ? [notifyChannel lowercaseString] : @"arlen_realtime";
  if ([connectionString length] == 0 || !ALNPgRealtimeChannelIsSafe(channel) || hub == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNPgRealtimeFanoutErrorDomain
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"realtime fanout needs a connection string and a notify channel matching [a-z_][a-z0-9_]{0,62}"
                               }];
    }
    return nil;
  }
  self = [super init];
  if (self != nil) {
    _connectionString = [connectionString copy];
    _notifyChannel = [channel copy];
    _hub = hub;
    _originIdentifier = [[[NSUUID UUID] UUIDString] copy];
    _publishQueue = dispatch_queue_create("arlen.realtime.pg-fanout.publish", DISPATCH_QUEUE_SERIAL);
    _state = [[NSCondition alloc] init];
    _publisher = [[ALNPg alloc] initWithConnectionString:connectionString maxConnections:1 error:error];
    if (_publisher == nil) {
      return nil;
    }
  }
  return self;
}

#pragma mark - Publishing

- (void)hub:(ALNRealtimeHub *)hub didPublishMessage:(NSString *)message onChannel:(NSString *)channel {
  (void)hub;
  NSString *origin = self.originIdentifier;
  dispatch_async(self.publishQueue, ^{
    [self sendMessage:message ?: @"" channel:channel ?: @"" origin:origin];
  });
}

- (void)sendMessage:(NSString *)message channel:(NSString *)channel origin:(NSString *)origin {
  NSError *error = nil;
  NSData *inline_ = [ALNJSONSerialization dataWithJSONObject:@{ @"o" : origin, @"c" : channel, @"m" : message }
                                                     options:0
                                                       error:&error];
  NSString *payload = inline_ != nil ? [[NSString alloc] initWithData:inline_ encoding:NSUTF8StringEncoding] : nil;
  if (payload != nil && [inline_ length] > ALNPgRealtimeInlinePayloadLimit) {
    // Too large for NOTIFY: store it and send the row id instead.
    NSNumber *rowID = [self storePayload:message error:&error];
    NSData *reference = rowID != nil
                            ? [ALNJSONSerialization dataWithJSONObject:@{ @"o" : origin, @"c" : channel, @"r" : rowID }
                                                               options:0
                                                                 error:&error]
                            : nil;
    payload = reference != nil ? [[NSString alloc] initWithData:reference encoding:NSUTF8StringEncoding] : nil;
  }
  if (payload == nil ||
      [self.publisher executeQuery:@"SELECT pg_notify($1, $2)" parameters:@[ self.notifyChannel, payload ] error:&error] == nil) {
    ALNPgRealtimeWarn([NSString stringWithFormat:@"publish on %@ failed: %@", channel,
                                                 error.localizedDescription ?: @"encoding failed"]);
  }
}

- (NSNumber *)storePayload:(NSString *)message error:(NSError **)error {
  if (!self.payloadTableReady) {
    if ([self.publisher executeCommand:@"CREATE TABLE IF NOT EXISTS arlen_realtime_payloads ("
                                        "id BIGSERIAL PRIMARY KEY, payload TEXT NOT NULL, "
                                        "created_at TIMESTAMPTZ NOT NULL DEFAULT now())"
                            parameters:@[]
                                 error:error] < 0) {
      return nil;
    }
    self.payloadTableReady = YES;
  }
  NSDictionary *row = [[self.publisher executeQuery:@"INSERT INTO arlen_realtime_payloads (payload) VALUES ($1) RETURNING id"
                                         parameters:@[ message ]
                                              error:error] firstObject];
  self.storedPayloads += 1;
  if (self.storedPayloads % ALNPgRealtimePruneInterval == 0) {
    // Subscribers read stored payloads immediately; anything older is garbage.
    (void)[self.publisher executeCommand:@"DELETE FROM arlen_realtime_payloads WHERE created_at < now() - interval '5 minutes'"
                              parameters:@[]
                                   error:NULL];
  }
  id identifier = row[@"id"];
  return [identifier respondsToSelector:@selector(longLongValue)] ? @([identifier longLongValue]) : nil;
}

- (void)flushPublishes {
  dispatch_sync(self.publishQueue, ^{
  });
}

#pragma mark - Listening

- (BOOL)startWaitingUpTo:(NSTimeInterval)timeout {
  [self.state lock];
  if (!self.threadRunning && !self.stopped) {
    self.threadRunning = YES;
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(listenLoop) object:nil];
    thread.name = @"arlen.realtime.pg-fanout.listen";
    [thread start];
  }
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (!self.listening && !self.stopped && [self.state waitUntilDate:deadline]) {
  }
  BOOL listening = self.listening;
  [self.state unlock];
  return listening;
}

- (BOOL)isStopped {
  [self.state lock];
  BOOL stopped = self.stopped;
  [self.state unlock];
  return stopped;
}

- (void)setListeningState:(BOOL)listening {
  [self.state lock];
  self.listening = listening;
  [self.state broadcast];
  [self.state unlock];
}

- (void)listenLoop {
  @autoreleasepool {
    NSTimeInterval backoff = 0.25;
    ALNPgConnection *connection = nil;
    while (![self isStopped]) {
      @autoreleasepool {
        NSError *error = nil;
        if (connection == nil) {
          connection = [[ALNPgConnection alloc] initWithConnectionString:self.connectionString error:&error];
          NSString *listen = [NSString stringWithFormat:@"LISTEN \"%@\"", self.notifyChannel];
          if (connection == nil || [connection executeCommand:listen parameters:@[] error:&error] < 0) {
            [connection close];
            connection = nil;
            ALNPgRealtimeWarn([NSString stringWithFormat:@"LISTEN failed, retrying in %.2fs: %@", backoff,
                                                         error.localizedDescription ?: @""]);
            [self sleepInterruptibly:backoff];
            backoff = MIN(backoff * 2.0, 5.0);
            continue;
          }
          backoff = 0.25;
          [self setListeningState:YES];
        }
        NSArray<NSDictionary *> *notifications = [connection waitForNotificationsWithTimeout:0.5 error:&error];
        if (notifications == nil) {
          ALNPgRealtimeWarn([NSString stringWithFormat:@"listener connection lost, reconnecting: %@",
                                                       error.localizedDescription ?: @""]);
          [self setListeningState:NO];
          [connection close];
          connection = nil;
          continue;
        }
        for (NSDictionary *notification in notifications) {
          [self deliverNotificationPayload:notification[@"payload"] connection:connection];
        }
      }
    }
    [connection close];
    [self setListeningState:NO];
    [self.state lock];
    self.threadRunning = NO;
    [self.state broadcast];
    [self.state unlock];
  }
}

- (void)deliverNotificationPayload:(NSString *)payload connection:(ALNPgConnection *)connection {
  NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *envelope = data != nil ? [ALNJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  if (![envelope isKindOfClass:[NSDictionary class]] || [envelope[@"o"] isEqual:self.originIdentifier]) {
    return;  // Malformed, or published by this process and already delivered locally.
  }
  NSString *channel = [envelope[@"c"] isKindOfClass:[NSString class]] ? envelope[@"c"] : nil;
  NSString *message = [envelope[@"m"] isKindOfClass:[NSString class]] ? envelope[@"m"] : nil;
  if (message == nil && envelope[@"r"] != nil) {
    NSDictionary *row = [connection executeQueryOne:@"SELECT payload FROM arlen_realtime_payloads WHERE id = $1"
                                         parameters:@[ envelope[@"r"] ]
                                              error:NULL];
    message = [row[@"payload"] isKindOfClass:[NSString class]] ? row[@"payload"] : nil;
  }
  if ([channel length] > 0 && message != nil) {
    [self.hub deliverRemoteMessage:message onChannel:channel];
  }
}

- (void)sleepInterruptibly:(NSTimeInterval)interval {
  [self.state lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:interval];
  while (!self.stopped && [self.state waitUntilDate:deadline]) {
  }
  [self.state unlock];
}

- (void)dealloc {
  if (_publishQueue != NULL) {
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_publishQueue);
#endif
    _publishQueue = NULL;
  }
}

- (void)stop {
  [self.state lock];
  self.stopped = YES;
  [self.state broadcast];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (self.threadRunning && [self.state waitUntilDate:deadline]) {
  }
  [self.state unlock];
}

@end
