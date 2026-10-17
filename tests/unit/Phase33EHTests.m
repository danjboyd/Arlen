#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNEventStream.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNPlatform.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface Phase33EHAuthorizationHook : NSObject <ALNEventStreamAuthorizationHook>

@property(nonatomic, assign) BOOL allowAppend;
@property(nonatomic, assign) BOOL allowReplay;
@property(nonatomic, assign) BOOL allowSubscribe;

@end

@implementation Phase33EHAuthorizationHook

- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID
                                     event:(NSDictionary *)event
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  (void)streamID;
  (void)event;
  (void)requestContext;
  if (!self.allowAppend && error != NULL) {
    *error = [NSError errorWithDomain:ALNEventStreamErrorDomain
                                 code:ALNEventStreamErrorUnauthorized
                             userInfo:@{ NSLocalizedDescriptionKey : @"append denied" }];
  }
  return self.allowAppend;
}

- (BOOL)authorizeEventStreamReplayOfStream:(NSString *)streamID
                             afterSequence:(NSNumber *)sequence
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  (void)streamID;
  (void)sequence;
  (void)requestContext;
  if (!self.allowReplay && error != NULL) {
    *error = [NSError errorWithDomain:ALNEventStreamErrorDomain
                                 code:ALNEventStreamErrorUnauthorized
                             userInfo:@{ NSLocalizedDescriptionKey : @"replay denied" }];
  }
  return self.allowReplay;
}

- (BOOL)authorizeEventStreamSubscribeToStream:(NSString *)streamID
                               requestContext:(ALNEventStreamRequestContext *)requestContext
                                        error:(NSError **)error {
  (void)streamID;
  (void)requestContext;
  if (!self.allowSubscribe && error != NULL) {
    *error = [NSError errorWithDomain:ALNEventStreamErrorDomain
                                 code:ALNEventStreamErrorUnauthorized
                             userInfo:@{ NSLocalizedDescriptionKey : @"subscribe denied" }];
  }
  return self.allowSubscribe;
}

@end

@interface Phase33EHSubscriber : NSObject <ALNEventStreamLiveSubscriber>

@property(nonatomic, strong) NSMutableArray<NSDictionary *> *received;

@end

@implementation Phase33EHSubscriber

- (instancetype)init {
  self = [super init];
  if (self) {
    _received = [NSMutableArray array];
  }
  return self;
}

- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID {
  [self.received addObject:@{
    @"stream_id" : streamID ?: @"",
    @"sequence" : @(event.sequence),
    @"event_type" : event.eventType ?: @"",
  }];
}

@end

@interface Phase33EHFailingBroker : NSObject <ALNEventStreamBroker>
@end

@implementation Phase33EHFailingBroker

- (NSString *)adapterName {
  return @"failing";
}

- (BOOL)publishCommittedEvent:(ALNEventEnvelope *)event
                     onStream:(NSString *)streamID
                        error:(NSError **)error {
  (void)event;
  (void)streamID;
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase33EH"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"broker publish failed" }];
  }
  return NO;
}

- (ALNEventStreamBrokerSubscription *)subscribeToStream:(NSString *)streamID
                                             subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber
                                                  error:(NSError **)error {
  (void)streamID;
  (void)subscriber;
  (void)error;
  return nil;
}

- (void)unsubscribe:(ALNEventStreamBrokerSubscription *)subscription {
  (void)subscription;
}

@end

@interface Phase33EHController : ALNController
@end

@implementation Phase33EHController

- (id)wsStream:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL ok = [self acceptWebSocketStream:@"conversation:33"
                          afterSequence:[self queryIntegerForName:@"after_sequence"]
                                  limit:2
                           replayWindow:2
                                  error:&error];
  if (!ok) {
    [self setStatus:(error.code == ALNEventStreamErrorUnauthorized) ? 403 : 500];
    [self renderText:error.localizedDescription ?: @"ws stream failed\n"];
  }
  return nil;
}

- (id)sseStream:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL ok = [self renderSSEStream:@"conversation:33"
                    afterSequence:[self queryIntegerForName:@"after_sequence"]
                            limit:2
                     replayWindow:2
                            error:&error];
  if (!ok) {
    [self setStatus:(error.code == ALNEventStreamErrorUnauthorized) ? 403 : 500];
    [self renderText:error.localizedDescription ?: @"sse stream failed\n"];
  }
  return nil;
}

- (id)replay:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL ok = [self renderEventStreamReplay:@"conversation:33"
                            afterSequence:[self queryIntegerForName:@"after_sequence"]
                                    limit:1
                             replayWindow:1
                                    error:&error];
  if (!ok) {
    [self setStatus:(error.code == ALNEventStreamErrorUnauthorized) ? 403 : 500];
    [self renderText:error.localizedDescription ?: @"replay failed\n"];
  }
  return nil;
}

@end

// Records sequences from concurrent publishers.
@interface Phase33EHSequenceRecorder : NSObject <ALNEventStreamLiveSubscriber>
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *sequences;
@end

@implementation Phase33EHSequenceRecorder
- (instancetype)init {
  self = [super init];
  if (self) {
    _lock = [[NSLock alloc] init];
    _sequences = [NSMutableArray array];
  }
  return self;
}
- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID {
  (void)streamID;
  [self.lock lock];
  [self.sequences addObject:@(event.sequence)];
  [self.lock unlock];
}
@end

@interface Phase33EHTests : XCTestCase
@end

@implementation Phase33EHTests

- (NSArray<NSNumber *> *)sequencesInStore:(ALNInMemoryEventStreamStore *)store
                                   stream:(NSString *)stream
                            afterSequence:(NSNumber *)after
                                    limit:(NSUInteger)limit {
  NSArray<ALNEventEnvelope *> *events = [store eventsForStream:stream afterSequence:after limit:limit error:NULL];
  return [events valueForKey:@"sequence"] ?: @[];
}

- (void)appendCount:(NSUInteger)count toStore:(ALNInMemoryEventStreamStore *)store stream:(NSString *)stream {
  for (NSUInteger idx = 0; idx < count; idx++) {
    NSDictionary *event = @{ @"event_type" : @"tick", @"payload" : @{ @"i" : @(idx) } };
    XCTAssertNotNil([store appendEvent:event toStream:stream error:NULL]);
  }
}

// GitHub issue 242: the in-memory store kept every event forever and copied
// the whole stream for each replay.
- (void)testInMemoryStoreRetentionKeepsTheNewestEventsAndSequencesContinue_Issue242 {
  ALNInMemoryEventStreamStore *store = [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:nil];
  XCTAssertEqual((NSUInteger)10000, store.maxEventsPerStream);
  store.maxEventsPerStream = 3;
  [self appendCount:5 toStore:store stream:@"s"];
  XCTAssertEqualObjects((@[ @3, @4, @5 ]), [self sequencesInStore:store stream:@"s" afterSequence:nil limit:10]);
  XCTAssertEqual((NSUInteger)5, [store latestCursorForStream:@"s" error:NULL].sequence);
  XCTAssertEqual((NSUInteger)3, [store oldestCursorForStream:@"s" error:NULL].sequence);
  [self appendCount:1 toStore:store stream:@"s"];
  XCTAssertEqualObjects((@[ @4, @5, @6 ]), [self sequencesInStore:store stream:@"s" afterSequence:nil limit:10]);
  XCTAssertEqualObjects((@[ @5, @6 ]), [self sequencesInStore:store stream:@"s" afterSequence:@4 limit:10]);

  store.maxEventsPerStream = 0;
  store.maxEventAgeSeconds = 0.05;
  ALNPlatformSleepMilliseconds(120);
  [self appendCount:1 toStore:store stream:@"s"];
  XCTAssertEqualObjects((@[ @7 ]), [self sequencesInStore:store stream:@"s" afterSequence:nil limit:10],
                        @"events older than maxEventAgeSeconds are dropped");
}

- (void)testInMemoryStoreReplayStartsAtTheCursorOffset_Issue242 {
  ALNInMemoryEventStreamStore *store = [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:nil];
  store.maxEventsPerStream = 0;
  [self appendCount:2000 toStore:store stream:@"big"];
  XCTAssertEqualObjects((@[ @1996, @1997, @1998, @1999, @2000 ]),
                        [self sequencesInStore:store stream:@"big" afterSequence:@1995 limit:10]);
  XCTAssertEqualObjects((@[ @1, @2 ]), [self sequencesInStore:store stream:@"big" afterSequence:@0 limit:2]);
  XCTAssertEqualObjects(@[], [self sequencesInStore:store stream:@"big" afterSequence:@2000 limit:10]);
}

- (void)testReplayFromBeforeTheOldestKeptEventRequiresResync_Issue242 {
  ALNInMemoryEventStreamStore *store = [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:nil];
  store.maxEventsPerStream = 3;
  [self appendCount:5 toStore:store stream:@"s"];
  ALNEventStreamService *service = [[ALNEventStreamService alloc] initWithStore:store broker:nil];
  NSError *error = nil;
  ALNEventStreamReplayResult *gap = [service replayStream:@"s" afterSequence:@1 limit:10 replayWindow:10 error:&error];
  XCTAssertTrue(gap.resyncRequired, @"events 2 and 3 are gone; replaying from 4 would be a silent gap");
  XCTAssertEqual((NSInteger)ALNEventStreamErrorResyncRequired, error.code);
  error = nil;
  ALNEventStreamReplayResult *kept = [service replayStream:@"s" afterSequence:@2 limit:10 replayWindow:10 error:&error];
  XCTAssertFalse(kept.resyncRequired);
  XCTAssertNil(error);
  XCTAssertEqualObjects((@[ @3, @4, @5 ]), [kept.events valueForKey:@"sequence"]);
}

// GitHub issue 240: concurrent appends published out of commit order.
- (void)testConcurrentAppendsPublishInSequenceOrder_Issue240 {
  ALNInMemoryEventStreamStore *store = [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:nil];
  ALNInMemoryEventStreamBroker *broker = [[ALNInMemoryEventStreamBroker alloc] initWithAdapterName:nil];
  Phase33EHSequenceRecorder *recorder = [[Phase33EHSequenceRecorder alloc] init];
  XCTAssertNotNil([broker subscribeToStream:@"s" subscriber:recorder error:NULL]);
  NSUInteger threads = 8;
  NSUInteger perThread = 50;
  dispatch_group_t group = dispatch_group_create();
  for (NSUInteger t = 0; t < threads; t++) {
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      // Each request builds its own service, as controllers do.
      ALNEventStreamService *service = [[ALNEventStreamService alloc] initWithStore:store broker:broker];
      for (NSUInteger idx = 0; idx < perThread; idx++) {
        (void)[service appendEvent:@{ @"event_type" : @"tick", @"payload" : @{} } toStream:@"s" error:NULL];
      }
    });
  }
  XCTAssertEqual(0L, dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC))));
  [recorder.lock lock];
  NSArray<NSNumber *> *received = [recorder.sequences copy];
  [recorder.lock unlock];
  NSMutableArray<NSNumber *> *expected = [NSMutableArray array];
  for (NSUInteger seq = 1; seq <= threads * perThread; seq++) {
    [expected addObject:@(seq)];
  }
  XCTAssertEqualObjects(expected, received);
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers {
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:[NSData data]];
}

- (NSDictionary *)jsonDictionaryFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id parsed =
      [NSJSONSerialization JSONObjectWithData:[response bodyDataForTransmission] options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([parsed isKindOfClass:[NSDictionary class]]);
  return [parsed isKindOfClass:[NSDictionary class]] ? parsed : @{};
}

- (void)testInMemoryEventStreamBrokerPublishesAndUnsubscribes {
  ALNInMemoryEventStreamBroker *broker =
      [[ALNInMemoryEventStreamBroker alloc] initWithAdapterName:@"phase33-broker"];
  Phase33EHSubscriber *subscriber = [[Phase33EHSubscriber alloc] init];
  NSError *error = nil;
  ALNEventStreamBrokerSubscription *subscription =
      [broker subscribeToStream:@"conversation:33" subscriber:subscriber error:&error];
  XCTAssertNotNil(subscription);
  XCTAssertNil(error);

  ALNEventEnvelope *event = [[ALNEventEnvelope alloc] initWithStreamID:@"conversation:33"
                                                              sequence:1
                                                               eventID:@"evt_1"
                                                             eventType:@"message_created"
                                                            occurredAt:@"2026-04-15T21:00:00Z"
                                                               payload:@{ @"body" : @"hello" }
                                                        idempotencyKey:nil
                                                                 actor:nil
                                                              metadata:nil];
  XCTAssertTrue([broker publishCommittedEvent:event onStream:@"conversation:33" error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [subscriber.received count]);

  [broker unsubscribe:subscription];
  XCTAssertTrue([broker publishCommittedEvent:event onStream:@"conversation:33" error:&error]);
  XCTAssertEqual((NSUInteger)1, [subscriber.received count]);
}

- (void)testEventStreamServiceReturnsCommittedEventWhenLivePublishFails {
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  ALNEventStreamService *service =
      [[ALNEventStreamService alloc] initWithStore:store
                                            broker:[[Phase33EHFailingBroker alloc] init]];

  NSError *error = nil;
  ALNEventStreamAppendResult *result = [service appendEvent:@{
    @"event_type" : @"message_created",
    @"payload" : @{ @"body" : @"hello" },
  }
                                                  toStream:@"conversation:33"
                                                     error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, result.committedEvent.sequence);
  XCTAssertTrue(result.livePublishAttempted);
  XCTAssertFalse(result.livePublishSucceeded);
  XCTAssertNotNil(result.livePublishError);

  NSArray<ALNEventEnvelope *> *replay =
      [store eventsForStream:@"conversation:33" afterSequence:nil limit:10 error:&error];
  XCTAssertEqual((NSUInteger)1, [replay count]);
  XCTAssertEqual((NSUInteger)1, replay[0].sequence);
}

- (void)testEventStreamReplayResultRequiresResyncWhenBoundaryExceeded {
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  NSError *error = nil;
  for (NSUInteger idx = 1; idx <= 3; idx++) {
    ALNEventEnvelope *event = [store appendEvent:@{
      @"event_type" : @"message_created",
      @"payload" : @{ @"index" : @(idx) },
    }
                                      toStream:@"conversation:33"
                                         error:&error];
    XCTAssertNotNil(event);
    XCTAssertNil(error);
  }

  ALNEventStreamService *service =
      [[ALNEventStreamService alloc] initWithStore:store
                                            broker:[[ALNInMemoryEventStreamBroker alloc] initWithAdapterName:nil]];
  ALNEventStreamReplayResult *result = [service replayStream:@"conversation:33"
                                               afterSequence:@0
                                                       limit:1
                                                replayWindow:1
                                                       error:&error];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.resyncRequired);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEventStreamErrorResyncRequired, error.code);
}

- (void)testControllerEventStreamTransportAndReplayContracts {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
  }];
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  [app setEventStreamStore:store];
  [app setEventStreamBroker:[[ALNInMemoryEventStreamBroker alloc] initWithAdapterName:@"phase33-broker"]];

  Phase33EHAuthorizationHook *hook = [[Phase33EHAuthorizationHook alloc] init];
  hook.allowAppend = YES;
  hook.allowReplay = YES;
  hook.allowSubscribe = YES;
  [app setEventStreamAuthorizationHook:hook];

  NSError *error = nil;
  [store appendEvent:@{
    @"event_type" : @"message_created",
    @"payload" : @{ @"body" : @"one" },
  }
         toStream:@"conversation:33"
            error:&error];
  [store appendEvent:@{
    @"event_type" : @"message_created",
    @"payload" : @{ @"body" : @"two" },
  }
         toStream:@"conversation:33"
            error:&error];
  XCTAssertNil(error);

  [app registerRouteMethod:@"GET"
                      path:@"/ws/stream"
                      name:@"ws_stream"
           controllerClass:[Phase33EHController class]
                    action:@"wsStream"];
  [app registerRouteMethod:@"GET"
                      path:@"/sse/stream"
                      name:@"sse_stream"
           controllerClass:[Phase33EHController class]
                    action:@"sseStream"];
  [app registerRouteMethod:@"GET"
                      path:@"/streams/replay"
                      name:@"stream_replay"
           controllerClass:[Phase33EHController class]
                    action:@"replay"];

  ALNResponse *ws =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ws/stream"
                                       queryString:@"after_sequence=1"
                                           headers:@{
                                             @"upgrade" : @"websocket",
                                             @"connection" : @"Upgrade",
                                             @"sec-websocket-key" : @"unit-test-key",
                                             @"sec-websocket-version" : @"13",
                                           }]];
  XCTAssertEqual((NSInteger)101, ws.statusCode);
  XCTAssertEqualObjects(@"stream", [ws headerForName:@"X-Arlen-WebSocket-Mode"]);
  XCTAssertEqualObjects(@"conversation:33", [ws headerForName:@"X-Arlen-Event-Stream-Id"]);
  XCTAssertEqualObjects(@"1", [ws headerForName:@"X-Arlen-Event-Stream-After-Sequence"]);

  ALNResponse *sse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/sse/stream"
                                       queryString:@"after_sequence=1"
                                           headers:@{}]];
  XCTAssertEqual((NSInteger)200, sse.statusCode);
  XCTAssertEqualObjects(@"stream", [sse headerForName:@"X-Arlen-SSE-Mode"]);
  XCTAssertEqualObjects(@"conversation:33", [sse headerForName:@"X-Arlen-Event-Stream-Id"]);
  XCTAssertEqualObjects(@"2", [sse headerForName:@"X-Arlen-Event-Stream-Replay-Limit"]);
  XCTAssertEqualObjects(@"text/event-stream; charset=utf-8", [sse headerForName:@"Content-Type"]);

  ALNResponse *resync =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/streams/replay"
                                       queryString:@"after_sequence=0"
                                           headers:@{}]];
  XCTAssertEqual((NSInteger)409, resync.statusCode);
  NSDictionary *resyncJSON = [self jsonDictionaryFromResponse:resync];
  XCTAssertEqualObjects(@"resync_required", resyncJSON[@"status"]);
  XCTAssertEqualObjects(@"conversation:33", resyncJSON[@"stream_id"]);
  XCTAssertEqualObjects(@2, resyncJSON[@"latest_cursor"][@"sequence"]);
}

@end
