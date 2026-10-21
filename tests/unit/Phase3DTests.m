#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRealtime.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface Phase3DRealtimeSubscriber : NSObject <ALNRealtimeSubscriber>

@property(nonatomic, strong) NSMutableArray *messages;

@end

@implementation Phase3DRealtimeSubscriber

- (instancetype)init {
  self = [super init];
  if (self) {
    _messages = [NSMutableArray array];
  }
  return self;
}

- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel {
  [self.messages addObject:@{
    @"channel" : channel ?: @"",
    @"message" : message ?: @"",
  }];
}

@end

@interface Phase3DMountedController : ALNController
@end

@implementation Phase3DMountedController

- (id)status:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"child-ok\n"];
  return nil;
}

- (id)apiStatus:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"mounted" : @(YES),
    @"source" : @"phase3d"
  };
}

- (id)signIn:(ALNContext *)ctx {
  NSError *error = nil;
  [ALNAuthSession establishAuthenticatedSessionForSubject:@"mounted-user"
                                                provider:@"test"
                                                 methods:@[ @"password" ]
                                          assuranceLevel:1
                                         authenticatedAt:[NSDate date]
                                                 context:ctx
                                                   error:&error];
  [self renderText:error == nil ? @"signed-in\n" : @"sign-in failed\n"];
  return nil;
}

@end

@interface Phase3DRealtimeController : ALNController
@end

@implementation Phase3DRealtimeController

- (id)wsEcho:(ALNContext *)ctx {
  (void)ctx;
  [self acceptWebSocketEcho];
  return nil;
}

- (id)sseTicker:(ALNContext *)ctx {
  (void)ctx;
  [self renderSSEEvents:@[
    @{
      @"id" : @"1",
      @"event" : @"tick",
      @"data" : @{
        @"index" : @1,
      }
    },
    @{
      @"id" : @"2",
      @"event" : @"tick",
      @"data" : @{
        @"index" : @2,
      }
    }
  ]];
  return nil;
}

@end

@interface Phase3DTests : XCTestCase
@end

@implementation Phase3DTests

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

- (NSDictionary *)jsonFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  if (error != nil || ![parsed isKindOfClass:[NSDictionary class]]) {
    NSString *body = [[NSString alloc] initWithData:response.bodyData
                                           encoding:NSUTF8StringEncoding] ?: @"";
    XCTFail(@"expected json dictionary error=%@ body=%@", error.localizedDescription ?: @"", body);
    return @{};
  }
  return parsed;
}

- (void)testRealtimeHubDeterministicFanoutAndUnsubscribe {
  ALNRealtimeHub *hub = [ALNRealtimeHub sharedHub];
  [hub reset];

  Phase3DRealtimeSubscriber *a = [[Phase3DRealtimeSubscriber alloc] init];
  Phase3DRealtimeSubscriber *b = [[Phase3DRealtimeSubscriber alloc] init];

  ALNRealtimeSubscription *subA = [hub subscribeChannel:@"updates" subscriber:a];
  ALNRealtimeSubscription *subB = [hub subscribeChannel:@"updates" subscriber:b];
  XCTAssertNotNil(subA);
  XCTAssertNotNil(subB);
  XCTAssertEqual((NSUInteger)2, [hub subscriberCountForChannel:@"updates"]);

  NSUInteger delivered = [hub publishMessage:@"hello" onChannel:@"updates"];
  XCTAssertEqual((NSUInteger)2, delivered);
  XCTAssertEqual((NSUInteger)1, [a.messages count]);
  XCTAssertEqual((NSUInteger)1, [b.messages count]);
  XCTAssertEqualObjects(@"hello", a.messages[0][@"message"]);
  XCTAssertEqualObjects(@"hello", b.messages[0][@"message"]);

  [hub unsubscribe:subA];
  delivered = [hub publishMessage:@"after-unsubscribe" onChannel:@"updates"];
  XCTAssertEqual((NSUInteger)1, delivered);
  XCTAssertEqual((NSUInteger)1, [a.messages count]);
  XCTAssertEqual((NSUInteger)2, [b.messages count]);
  XCTAssertEqualObjects(@"after-unsubscribe", b.messages[1][@"message"]);

  [hub reset];
}

- (void)testRealtimeHubAppliesSubscriberCapsAndReportsMetrics {
  ALNRealtimeHub *hub = [ALNRealtimeHub sharedHub];
  [hub reset];
  [hub configureLimitsWithMaxTotalSubscribers:2 maxSubscribersPerChannel:1];

  Phase3DRealtimeSubscriber *a = [[Phase3DRealtimeSubscriber alloc] init];
  Phase3DRealtimeSubscriber *b = [[Phase3DRealtimeSubscriber alloc] init];
  Phase3DRealtimeSubscriber *c = [[Phase3DRealtimeSubscriber alloc] init];
  Phase3DRealtimeSubscriber *d = [[Phase3DRealtimeSubscriber alloc] init];

  ALNRealtimeSubscription *subA = [hub subscribeChannel:@"updates" subscriber:a];
  XCTAssertNotNil(subA);

  ALNRealtimeSubscription *subB = [hub subscribeChannel:@"updates" subscriber:b];
  XCTAssertNil(subB);

  ALNRealtimeSubscription *subC = [hub subscribeChannel:@"alerts" subscriber:c];
  XCTAssertNotNil(subC);

  ALNRealtimeSubscription *subD = [hub subscribeChannel:@"news" subscriber:d];
  XCTAssertNil(subD);

  NSDictionary *metrics = [hub metricsSnapshot];
  XCTAssertEqual((NSInteger)2, [metrics[@"activeSubscribers"] integerValue]);
  XCTAssertEqual((NSInteger)2, [metrics[@"activeChannels"] integerValue]);
  XCTAssertEqual((NSInteger)2, [metrics[@"totalSubscriptions"] integerValue]);
  XCTAssertEqual((NSInteger)2, [metrics[@"rejectedSubscriptions"] integerValue]);
  XCTAssertEqual((NSInteger)1, [metrics[@"maxSubscribersPerChannel"] integerValue]);
  XCTAssertEqual((NSInteger)2, [metrics[@"maxTotalSubscribers"] integerValue]);

  [hub unsubscribe:subA];
  [hub unsubscribe:subC];
  metrics = [hub metricsSnapshot];
  XCTAssertEqual((NSInteger)0, [metrics[@"activeSubscribers"] integerValue]);
  XCTAssertEqual((NSInteger)2, [metrics[@"totalUnsubscriptions"] integerValue]);

  [hub reset];
}

- (void)testRealtimeHubSubscriptionRejectionReasonsAreDeterministic {
  ALNRealtimeHub *hub = [ALNRealtimeHub sharedHub];
  [hub reset];
  [hub configureLimitsWithMaxTotalSubscribers:1 maxSubscribersPerChannel:1];

  Phase3DRealtimeSubscriber *first = [[Phase3DRealtimeSubscriber alloc] init];
  Phase3DRealtimeSubscriber *second = [[Phase3DRealtimeSubscriber alloc] init];

  NSString *rejectionReason = nil;
  ALNRealtimeSubscription *firstSubscription =
      [hub subscribeChannel:@"updates" subscriber:first rejectionReason:&rejectionReason];
  XCTAssertNotNil(firstSubscription);
  XCTAssertNil(rejectionReason);

  ALNRealtimeSubscription *totalRejected =
      [hub subscribeChannel:@"alerts" subscriber:second rejectionReason:&rejectionReason];
  XCTAssertNil(totalRejected);
  XCTAssertEqualObjects(@"max_total_subscribers", rejectionReason);
  [hub reset];

  [hub configureLimitsWithMaxTotalSubscribers:0 maxSubscribersPerChannel:1];
  firstSubscription = [hub subscribeChannel:@"updates" subscriber:first rejectionReason:&rejectionReason];
  XCTAssertNotNil(firstSubscription);
  XCTAssertNil(rejectionReason);

  ALNRealtimeSubscription *channelRejected =
      [hub subscribeChannel:@"updates" subscriber:second rejectionReason:&rejectionReason];
  XCTAssertNil(channelRejected);
  XCTAssertEqualObjects(@"max_channel_subscribers", rejectionReason);

  [hub reset];
}

- (void)testRealtimeHubSubscriptionChurnReturnsToZeroSubscribers {
  ALNRealtimeHub *hub = [ALNRealtimeHub sharedHub];
  [hub reset];

  NSUInteger churnIterations = 400;
  for (NSUInteger idx = 0; idx < churnIterations; idx++) {
    Phase3DRealtimeSubscriber *subscriber = [[Phase3DRealtimeSubscriber alloc] init];
    NSString *channel = [NSString stringWithFormat:@"topic-%lu", (unsigned long)(idx % 7)];
    ALNRealtimeSubscription *subscription =
        [hub subscribeChannel:channel subscriber:subscriber];
    XCTAssertNotNil(subscription);
    [hub unsubscribe:subscription];
  }

  NSDictionary *metrics = [hub metricsSnapshot];
  XCTAssertEqual((NSInteger)0, [metrics[@"activeSubscribers"] integerValue]);
  XCTAssertEqual((NSInteger)churnIterations, [metrics[@"totalSubscriptions"] integerValue]);
  XCTAssertEqual((NSInteger)churnIterations, [metrics[@"totalUnsubscriptions"] integerValue]);
  XCTAssertEqual((NSInteger)0, [metrics[@"rejectedSubscriptions"] integerValue]);

  [hub reset];
}

- (void)testMountApplicationRoutesRewritePathAndPreserveJSONFlow {
  ALNApplication *parent = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
    @"apiOnly" : @(NO),
  }];
  ALNApplication *child = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
    @"apiOnly" : @(NO),
    @"openapi" : @{
      @"enabled" : @(NO),
      @"docsUIEnabled" : @(NO),
    },
  }];

  [child registerRouteMethod:@"GET"
                        path:@"/status"
                        name:@"child_status"
             controllerClass:[Phase3DMountedController class]
                      action:@"status"];
  [child registerRouteMethod:@"GET"
                        path:@"/api/status"
                        name:@"child_api_status"
             controllerClass:[Phase3DMountedController class]
                      action:@"apiStatus"];

  BOOL mounted = [parent mountApplication:child atPrefix:@"/embedded"];
  XCTAssertTrue(mounted);

  ALNResponse *statusResponse = [parent dispatchRequest:[self requestWithMethod:@"GET"
                                                                           path:@"/embedded/status"
                                                                    queryString:@""
                                                                        headers:@{}]];
  XCTAssertEqual((NSInteger)200, statusResponse.statusCode);
  NSString *statusBody = [[NSString alloc] initWithData:statusResponse.bodyData
                                               encoding:NSUTF8StringEncoding] ?: @"";
  XCTAssertEqualObjects(@"child-ok\n", statusBody);
  XCTAssertEqualObjects(@"/embedded", [statusResponse headerForName:@"X-Arlen-Mount-Prefix"]);

  ALNResponse *apiResponse = [parent dispatchRequest:[self requestWithMethod:@"GET"
                                                                        path:@"/embedded/api/status"
                                                                 queryString:@""
                                                                     headers:@{
                                                                       @"accept" : @"application/json",
                                                                     }]];
  XCTAssertEqual((NSInteger)200, apiResponse.statusCode);
  NSDictionary *json = [self jsonFromResponse:apiResponse];
  XCTAssertEqualObjects(@(YES), json[@"mounted"]);
  XCTAssertEqualObjects(@"phase3d", json[@"source"]);
}

- (void)testMountedChildHonorsParentPathPolicies {
  ALNApplication *parent = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"session" : @{ @"enabled" : @YES,
                    @"secret" : @"mounted-parent-policy-test-secret-0123456789" },
    @"security" : @{ @"routePolicies" : @{
      @"mounted" : @{ @"pathPrefixes" : @[ @"/embedded" ],
                       @"sourceIPAllowlist" : @[ @"127.0.0.1/32" ],
                       @"requireAuth" : @YES }
    } }
  }];
  ALNApplication *child = [[ALNApplication alloc] initWithConfig:@{ @"environment" : @"test" }];
  [child registerRouteMethod:@"GET" path:@"/status" name:@"child_status"
             controllerClass:[Phase3DMountedController class] action:@"status"];
  [parent registerRouteMethod:@"GET" path:@"/sign-in" name:@"parent_sign_in"
              controllerClass:[Phase3DMountedController class] action:@"signIn"];
  XCTAssertTrue([parent mountApplication:child atPrefix:@"/embedded"]);
  XCTAssertTrue([parent startWithError:NULL]);

  ALNRequest *blockedIP = [self requestWithMethod:@"GET" path:@"/embedded/status"
                                       queryString:@"" headers:@{}];
  blockedIP.remoteAddress = @"203.0.113.9";
  ALNResponse *ipResponse = [parent dispatchRequest:blockedIP];
  XCTAssertEqual((NSInteger)403, ipResponse.statusCode);
  XCTAssertEqualObjects(@"source_ip_denied", [ipResponse headerForName:@"X-Arlen-Policy-Denial-Reason"]);

  ALNRequest *anonymous = [self requestWithMethod:@"GET" path:@"/embedded/status"
                                      queryString:@"" headers:@{}];
  anonymous.remoteAddress = @"127.0.0.1";
  ALNResponse *authResponse = [parent dispatchRequest:anonymous];
  XCTAssertEqual((NSInteger)403, authResponse.statusCode);
  XCTAssertEqualObjects(@"authentication_required", [authResponse headerForName:@"X-Arlen-Policy-Denial-Reason"]);

  ALNResponse *signIn = [parent dispatchRequest:[self requestWithMethod:@"GET" path:@"/sign-in"
                                                         queryString:@"" headers:@{}]];
  XCTAssertEqual((NSInteger)200, signIn.statusCode);
  NSString *cookie = [[[signIn headerForName:@"Set-Cookie"] ?: @"" componentsSeparatedByString:@";"] firstObject];
  XCTAssertTrue([cookie length] > 0);
  ALNRequest *authenticated = [self requestWithMethod:@"GET" path:@"/embedded/status"
                                          queryString:@"" headers:@{ @"cookie" : cookie ?: @"" }];
  authenticated.remoteAddress = @"127.0.0.1";
  ALNResponse *allowed = [parent dispatchRequest:authenticated];
  XCTAssertEqual((NSInteger)200, allowed.statusCode);
  XCTAssertEqualObjects(@"child-ok\n", [[NSString alloc] initWithData:allowed.bodyData
                                                              encoding:NSUTF8StringEncoding]);
}

- (void)testControllerWebSocketAndSSEContracts {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/ws/echo"
                      name:@"ws_echo"
           controllerClass:[Phase3DRealtimeController class]
                    action:@"wsEcho"];
  [app registerRouteMethod:@"GET"
                      path:@"/sse/ticker"
                      name:@"sse_ticker"
           controllerClass:[Phase3DRealtimeController class]
                    action:@"sseTicker"];

  ALNResponse *ws = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                            path:@"/ws/echo"
                                                     queryString:@""
                                                         headers:@{
                                                           @"upgrade" : @"websocket",
                                                           @"connection" : @"Upgrade",
                                                           @"sec-websocket-key" : @"unit-test-key",
                                                           @"sec-websocket-version" : @"13",
                                                         }]];
  XCTAssertEqual((NSInteger)101, ws.statusCode);
  XCTAssertEqualObjects(@"websocket", [[ws headerForName:@"Upgrade"] lowercaseString]);
  XCTAssertEqualObjects(@"echo", [[ws headerForName:@"X-Arlen-WebSocket-Mode"] lowercaseString]);

  ALNResponse *sse = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                             path:@"/sse/ticker"
                                                      queryString:@""
                                                          headers:@{}]];
  XCTAssertEqual((NSInteger)200, sse.statusCode);
  XCTAssertEqualObjects(@"text/event-stream; charset=utf-8", [sse headerForName:@"Content-Type"]);
  NSString *sseBody = [[NSString alloc] initWithData:sse.bodyData
                                            encoding:NSUTF8StringEncoding] ?: @"";
  XCTAssertTrue([sseBody containsString:@"event: tick"]);
  XCTAssertTrue([sseBody containsString:@"data: {\"index\":1}"]);
  XCTAssertTrue([sseBody containsString:@"id: 2"]);
}

@end
