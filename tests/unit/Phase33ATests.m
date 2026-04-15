#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNEventStream.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface Phase33AuthorizationHook : NSObject <ALNEventStreamAuthorizationHook>

@property(nonatomic, assign) BOOL allowAppend;
@property(nonatomic, assign) BOOL allowReplay;
@property(nonatomic, assign) BOOL allowSubscribe;
@property(nonatomic, strong) ALNEventStreamRequestContext *lastRequestContext;

@end

@implementation Phase33AuthorizationHook

- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID
                                     event:(NSDictionary *)event
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  (void)streamID;
  (void)event;
  self.lastRequestContext = requestContext;
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
  self.lastRequestContext = requestContext;
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
  self.lastRequestContext = requestContext;
  if (!self.allowSubscribe && error != NULL) {
    *error = [NSError errorWithDomain:ALNEventStreamErrorDomain
                                 code:ALNEventStreamErrorUnauthorized
                             userInfo:@{ NSLocalizedDescriptionKey : @"subscribe denied" }];
  }
  return self.allowSubscribe;
}

@end

@interface Phase33ATests : XCTestCase
@end

@implementation Phase33ATests

- (BOOL)isISO8601UTCTimestamp:(NSString *)value {
  if (![value isKindOfClass:[NSString class]] || [value length] < 20) {
    return NO;
  }
  return ([value containsString:@"T"] && [value hasSuffix:@"Z"]);
}

- (ALNContext *)contextWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                                      path:path ?: @"/"
                                               queryString:queryString ?: @""
                                                   headers:@{}
                                                      body:[NSData data]];
  ALNResponse *response = [[ALNResponse alloc] init];
  NSMutableDictionary *stash = [NSMutableDictionary dictionary];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"text"];
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
  return [[ALNContext alloc] initWithRequest:request
                                    response:response
                                      params:@{}
                                       stash:stash
                                      logger:logger
                                   perfTrace:trace
                                   routeName:@"stream_route"
                              controllerName:@"Phase33Controller"
                                  actionName:@"append"];
}

- (void)testInMemoryEventStreamStoreAssignsAuthoritativeFields {
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  NSError *error = nil;
  ALNEventEnvelope *event =
      [store appendEvent:@{
        @"event_type" : @"message_created",
        @"payload" : @{ @"body" : @"hello" },
        @"actor" : @{ @"type" : @"session", @"id" : @"sess_1" },
        @"metadata" : @{ @"tenant" : @"alpha" },
      }
              toStream:@"ownerconnect:conversation:123"
                 error:&error];
  XCTAssertNotNil(event);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ownerconnect:conversation:123", event.streamID);
  XCTAssertEqual((NSUInteger)1, event.sequence);
  XCTAssertTrue([event.eventID hasPrefix:@"evt_"]);
  XCTAssertTrue([self isISO8601UTCTimestamp:event.occurredAt]);
  XCTAssertEqualObjects(@"message_created", event.eventType);
  XCTAssertEqualObjects(@"hello", event.payload[@"body"]);

  ALNEventStreamCursor *cursor =
      [store latestCursorForStream:@"ownerconnect:conversation:123" error:&error];
  XCTAssertNotNil(cursor);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ownerconnect:conversation:123", cursor.streamID);
  XCTAssertEqual((NSUInteger)1, cursor.sequence);
}

- (void)testInMemoryEventStreamStoreReplayIsOrderedAfterSequence {
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  NSError *error = nil;
  for (NSUInteger idx = 1; idx <= 3; idx++) {
    ALNEventEnvelope *event =
        [store appendEvent:@{
          @"event_type" : @"item_created",
          @"payload" : @{ @"index" : @(idx) },
        }
                toStream:@"queue:alpha"
                   error:&error];
    XCTAssertNotNil(event);
    XCTAssertNil(error);
  }

  NSArray<ALNEventEnvelope *> *all =
      [store eventsForStream:@"queue:alpha" afterSequence:nil limit:50 error:&error];
  XCTAssertEqual((NSUInteger)3, [all count]);
  XCTAssertEqual((NSUInteger)1, all[0].sequence);
  XCTAssertEqual((NSUInteger)2, all[1].sequence);
  XCTAssertEqual((NSUInteger)3, all[2].sequence);

  NSArray<ALNEventEnvelope *> *afterOne =
      [store eventsForStream:@"queue:alpha" afterSequence:@1 limit:50 error:&error];
  XCTAssertEqual((NSUInteger)2, [afterOne count]);
  XCTAssertEqual((NSUInteger)2, afterOne[0].sequence);
  XCTAssertEqual((NSUInteger)3, afterOne[1].sequence);
}

- (void)testInMemoryEventStreamStoreIdempotentRetryReturnsOriginalEnvelopeAndConflictsFail {
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  NSError *error = nil;
  NSDictionary *request = @{
    @"event_type" : @"message_created",
    @"payload" : @{ @"body" : @"hello" },
    @"idempotency_key" : @"req_abc123",
  };
  ALNEventEnvelope *first = [store appendEvent:request toStream:@"conversation:7" error:&error];
  XCTAssertNotNil(first);
  XCTAssertNil(error);

  ALNEventEnvelope *retry = [store appendEvent:request toStream:@"conversation:7" error:&error];
  XCTAssertNotNil(retry);
  XCTAssertNil(error);
  XCTAssertEqualObjects(first.eventID, retry.eventID);
  XCTAssertEqual(first.sequence, retry.sequence);
  XCTAssertEqualObjects(first.occurredAt, retry.occurredAt);

  NSDictionary *conflicting = @{
    @"event_type" : @"message_created",
    @"payload" : @{ @"body" : @"changed" },
    @"idempotency_key" : @"req_abc123",
  };
  ALNEventEnvelope *rejected =
      [store appendEvent:conflicting toStream:@"conversation:7" error:&error];
  XCTAssertNil(rejected);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEventStreamErrorIdempotencyConflict, error.code);
}

- (void)testEventStreamRequestContextCapturesRouteRequestAndAuthState {
  ALNContext *context = [self contextWithMethod:@"POST"
                                           path:@"/streams/ownerconnect:conversation:123"
                                    queryString:@"after_sequence=1"];
  NSError *error = nil;
  BOOL established = [ALNAuthSession establishAuthenticatedSessionForSubject:@"user-42"
                                                                    provider:@"local"
                                                                     methods:@[ @"pwd" ]
                                                                      scopes:@[ @"stream:read", @"stream:write" ]
                                                                       roles:@[ @"operator" ]
                                                              assuranceLevel:2
                                                             authenticatedAt:nil
                                                                     context:context
                                                                       error:&error];
  XCTAssertTrue(established);
  XCTAssertNil(error);

  ALNEventStreamRequestContext *requestContext =
      [ALNEventStreamRequestContext requestContextWithContext:context];
  XCTAssertEqualObjects(@"POST", requestContext.requestMethod);
  XCTAssertEqualObjects(@"/streams/ownerconnect:conversation:123", requestContext.requestPath);
  XCTAssertEqualObjects(@"after_sequence=1", requestContext.requestQueryString);
  XCTAssertEqualObjects(@"stream_route", requestContext.routeName);
  XCTAssertEqualObjects(@"Phase33Controller", requestContext.controllerName);
  XCTAssertEqualObjects(@"append", requestContext.actionName);
  XCTAssertEqualObjects(@"user-42", requestContext.authSubject);
  XCTAssertTrue([requestContext.authScopes containsObject:@"stream:read"]);
  XCTAssertTrue([requestContext.authRoles containsObject:@"operator"]);
  XCTAssertNotNil(requestContext.authSessionIdentifier);
  XCTAssertFalse(requestContext.liveRequest);
}

- (void)testApplicationEventStreamAuthorizationDefaultsDenyAndHookReceivesRequestContext {
  ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
  }];
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  [application setEventStreamStore:store];

  ALNContext *context = [self contextWithMethod:@"GET"
                                           path:@"/streams/conversation:9"
                                    queryString:@"after_sequence=2"];
  NSError *error = nil;
  BOOL denied =
      [application authorizeEventStreamSubscribeToStream:@"conversation:9"
                                                 context:context
                                                   error:&error];
  XCTAssertFalse(denied);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEventStreamErrorUnauthorized, error.code);

  Phase33AuthorizationHook *hook = [[Phase33AuthorizationHook alloc] init];
  hook.allowSubscribe = YES;
  hook.allowReplay = YES;
  hook.allowAppend = YES;
  [application setEventStreamAuthorizationHook:hook];

  error = nil;
  BOOL allowedSubscribe =
      [application authorizeEventStreamSubscribeToStream:@"conversation:9"
                                                 context:context
                                                   error:&error];
  XCTAssertTrue(allowedSubscribe);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"/streams/conversation:9", hook.lastRequestContext.requestPath);

  error = nil;
  BOOL allowedReplay =
      [application authorizeEventStreamReplayOfStream:@"conversation:9"
                                        afterSequence:@2
                                              context:context
                                                error:&error];
  XCTAssertTrue(allowedReplay);
  XCTAssertNil(error);

  error = nil;
  BOOL allowedAppend =
      [application authorizeEventStreamAppendToStream:@"conversation:9"
                                                event:@{
                                                  @"event_type" : @"message_created",
                                                  @"payload" : @{ @"body" : @"hello" }
                                                }
                                              context:context
                                                error:&error];
  XCTAssertTrue(allowedAppend);
  XCTAssertNil(error);
}

- (void)testContextExposesConfiguredEventStreamStore {
  ALNInMemoryEventStreamStore *store =
      [[ALNInMemoryEventStreamStore alloc] initWithAdapterName:@"phase33-store"];
  ALNContext *context = [self contextWithMethod:@"GET" path:@"/" queryString:nil];
  context.stash[ALNContextEventStreamStoreStashKey] = store;
  XCTAssertEqualObjects(store, [context eventStreamStore]);
}

@end
