#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNEventStream.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
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

@interface Phase33EHTests : XCTestCase
@end

@implementation Phase33EHTests

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
