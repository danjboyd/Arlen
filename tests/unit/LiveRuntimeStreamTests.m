#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNLive.h"
#import "../shared/ALNLiveTestSupport.h"

@interface LiveRuntimeStreamTests : XCTestCase
@end

@implementation LiveRuntimeStreamTests

- (BOOL)requireHarness {
  if (ALNLiveRuntimeHarnessIsAvailable()) {
    return YES;
  }
  NSLog(@"%@ skipped because node is unavailable for the live runtime harness",
        NSStringFromClass([self class]));
  return NO;
}

- (NSDictionary *)runScenario:(NSDictionary *)scenario {
  NSError *error = nil;
  NSDictionary *result = ALNLiveRunRuntimeScenario(scenario, &error);
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  return result ?: @{};
}

- (NSString *)JSONStringForObject:(id)object {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:NULL];
  NSString *json = [[NSString alloc] initWithData:data ?: [NSData data]
                                         encoding:NSUTF8StringEncoding];
  return json ?: @"{}";
}

- (NSDictionary *)payloadWithOperations:(NSArray *)operations {
  NSError *error = nil;
  NSDictionary *payload = [ALNLive validatedPayloadWithOperations:operations meta:nil error:&error];
  XCTAssertNotNil(payload);
  XCTAssertNil(error);
  return payload ?: @{};
}

- (void)testStreamScanIsIdempotentAndMessagesApplyPayload {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" :
        @"<section id=\"stream-a\" data-arlen-live-stream=\"/ws/channel/demo\"></section>"
         "<section id=\"stream-b\" data-arlen-live-stream=\"/ws/channel/demo\"></section>"
         "<div id=\"panel\">Idle</div>",
    @"actions" : @[
      @{ @"type" : @"start" },
      @{ @"type" : @"snapshot", @"selector" : @"#stream-a" },
      @{ @"type" : @"scan_streams" },
      @{ @"type" : @"websocket_summary" },
      @{ @"type" : @"websocket_open", @"url" : @"/ws/channel/demo" },
      @{ @"type" : @"snapshot", @"selector" : @"#stream-a" },
      @{
        @"type" : @"websocket_message",
        @"url" : @"/ws/channel/demo",
        @"data" : [self JSONStringForObject:[self payloadWithOperations:@[
          [ALNLive updateOperationForTarget:@"#panel" html:@"<p>Connected</p>"],
        ]]],
      },
    ],
    @"inspect" : @[ @"#stream-a", @"#stream-b", @"#panel" ],
  }];

  NSArray *actionResults = [result[@"actionResults"] isKindOfClass:[NSArray class]] ? result[@"actionResults"] : @[];
  NSDictionary *connectingSnapshot =
      [actionResults count] > 1 && [actionResults[1] isKindOfClass:[NSDictionary class]]
          ? actionResults[1]
          : @{};
  NSArray *summary = [actionResults count] > 3 && [actionResults[3] isKindOfClass:[NSArray class]]
                         ? actionResults[3]
                         : @[];
  NSDictionary *openSnapshot =
      [actionResults count] > 5 && [actionResults[5] isKindOfClass:[NSDictionary class]]
          ? actionResults[5]
          : @{};
  NSDictionary *panel = ALNLiveRuntimeElementSnapshot(result, @"#panel");
  NSDictionary *streamB = ALNLiveRuntimeElementSnapshot(result, @"#stream-b");
  NSArray<NSDictionary *> *openEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:stream-open");
  NSArray *webSockets = [result[@"webSockets"] isKindOfClass:[NSArray class]] ? result[@"webSockets"] : @[];

  XCTAssertEqualObjects(@"connecting", connectingSnapshot[@"attributes"][@"data-arlen-live-stream-state"]);
  XCTAssertEqual((NSUInteger)1, [summary count]);
  XCTAssertEqual((NSUInteger)1, [webSockets count]);
  XCTAssertEqualObjects(@"open", openSnapshot[@"attributes"][@"data-arlen-live-stream-state"]);
  XCTAssertEqualObjects(@"open", streamB[@"attributes"][@"data-arlen-live-stream-state"]);
  XCTAssertEqualObjects(@"<p>Connected</p>", panel[@"innerHTML"]);
  XCTAssertEqual((NSUInteger)1, [openEvents count]);
  XCTAssertEqualObjects(@"/ws/channel/demo", openEvents[0][@"detail"][@"url"]);
}

- (void)testStreamErrorCloseReconnectAndElementRemovalBehavior {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" :
        @"<section id=\"stream\" data-arlen-live-stream=\"/ws/channel/demo\"></section>"
         "<div id=\"panel\">Idle</div>",
    @"actions" : @[
      @{ @"type" : @"start" },
      @{ @"type" : @"websocket_open", @"url" : @"/ws/channel/demo" },
      @{ @"type" : @"websocket_error", @"url" : @"/ws/channel/demo" },
      @{ @"type" : @"snapshot", @"selector" : @"#stream" },
      @{ @"type" : @"websocket_close", @"url" : @"/ws/channel/demo", @"code" : @(1006), @"reason" : @"drop" },
      @{ @"type" : @"snapshot", @"selector" : @"#stream" },
      @{ @"type" : @"advance_time", @"ms" : @(999) },
      @{ @"type" : @"websocket_summary" },
      @{ @"type" : @"advance_time", @"ms" : @(1) },
      @{ @"type" : @"websocket_summary" },
      @{ @"type" : @"websocket_close", @"url" : @"/ws/channel/demo", @"code" : @(1012), @"reason" : @"restart" },
      @{ @"type" : @"advance_time", @"ms" : @(1999) },
      @{ @"type" : @"websocket_summary" },
      @{ @"type" : @"advance_time", @"ms" : @(1) },
      @{ @"type" : @"websocket_summary" },
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive removeOperationForTarget:@"#stream"],
        ]],
      },
      @{ @"type" : @"websocket_close", @"url" : @"/ws/channel/demo", @"code" : @(1001), @"reason" : @"gone" },
      @{ @"type" : @"run_all_timers", @"limit" : @(20) },
      @{ @"type" : @"websocket_summary" },
    ],
    @"inspect" : @[ @"#stream" ],
  }];

  NSArray *actionResults = [result[@"actionResults"] isKindOfClass:[NSArray class]] ? result[@"actionResults"] : @[];
  NSDictionary *errorSnapshot =
      [actionResults count] > 3 && [actionResults[3] isKindOfClass:[NSDictionary class]]
          ? actionResults[3]
          : @{};
  NSDictionary *closedSnapshot =
      [actionResults count] > 5 && [actionResults[5] isKindOfClass:[NSDictionary class]]
          ? actionResults[5]
          : @{};
  NSArray *beforeFirstReconnect =
      [actionResults count] > 7 && [actionResults[7] isKindOfClass:[NSArray class]] ? actionResults[7] : @[];
  NSArray *afterFirstReconnect =
      [actionResults count] > 9 && [actionResults[9] isKindOfClass:[NSArray class]] ? actionResults[9] : @[];
  NSArray *beforeSecondReconnect =
      [actionResults count] > 12 && [actionResults[12] isKindOfClass:[NSArray class]] ? actionResults[12] : @[];
  NSArray *afterSecondReconnect =
      [actionResults count] > 14 && [actionResults[14] isKindOfClass:[NSArray class]] ? actionResults[14] : @[];
  NSArray *afterRemovalClose =
      [actionResults count] > 18 && [actionResults[18] isKindOfClass:[NSArray class]] ? actionResults[18] : @[];
  NSArray<NSDictionary *> *errorEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:stream-error");
  NSArray<NSDictionary *> *closeEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:stream-closed");

  XCTAssertEqualObjects(@"error", errorSnapshot[@"attributes"][@"data-arlen-live-stream-state"]);
  XCTAssertEqualObjects(@"closed", closedSnapshot[@"attributes"][@"data-arlen-live-stream-state"]);
  XCTAssertEqual((NSUInteger)1, [beforeFirstReconnect count]);
  XCTAssertEqual((NSUInteger)2, [afterFirstReconnect count]);
  XCTAssertEqual((NSUInteger)2, [beforeSecondReconnect count]);
  XCTAssertEqual((NSUInteger)3, [afterSecondReconnect count]);
  XCTAssertEqual((NSUInteger)3, [afterRemovalClose count]);
  XCTAssertEqual((NSUInteger)1, [errorEvents count]);
  XCTAssertEqual((NSUInteger)2, [closeEvents count]);
  XCTAssertEqualObjects(@(1000), closeEvents[0][@"detail"][@"retryIn"]);
  XCTAssertEqualObjects(@(2000), closeEvents[1][@"detail"][@"retryIn"]);
  XCTAssertNil(ALNLiveRuntimeElementSnapshot(result, @"#stream"));
}

- (void)testAuthExpiryAndBackpressureResponsesEmitEvents {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" : @"<div id=\"orders\">Stable</div>",
    @"actions" : @[
      @{
        @"type" : @"handle_response",
        @"response" : @{
          @"status" : @(401),
          @"url" : @"http://example.test/login",
          @"headers" : @{},
          @"contentType" : @"text/plain; charset=utf-8",
          @"text" : @"unauthorized",
        },
        @"options" : @{ @"targetSelector" : @"#orders" },
      },
      @{
        @"type" : @"handle_response",
        @"response" : @{
          @"status" : @(403),
          @"url" : @"http://example.test/forbidden",
          @"headers" : @{},
          @"contentType" : @"text/plain; charset=utf-8",
          @"text" : @"forbidden",
        },
        @"options" : @{ @"targetSelector" : @"#orders" },
      },
      @{
        @"type" : @"handle_response",
        @"response" : @{
          @"status" : @(429),
          @"url" : @"http://example.test/orders",
          @"headers" : @{ @"Retry-After" : @"3" },
          @"contentType" : @"text/plain; charset=utf-8",
          @"text" : @"too many requests",
        },
        @"options" : @{ @"targetSelector" : @"#orders" },
      },
      @{
        @"type" : @"handle_response",
        @"response" : @{
          @"status" : @(503),
          @"url" : @"http://example.test/orders",
          @"headers" : @{ @"X-Arlen-Live-Retry-After" : @"1500ms" },
          @"contentType" : @"text/plain; charset=utf-8",
          @"text" : @"busy",
        },
        @"options" : @{ @"targetSelector" : @"#orders" },
      },
    ],
    @"inspect" : @[ @"#orders" ],
  }];

  NSArray<NSDictionary *> *authEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:auth-expired");
  NSArray<NSDictionary *> *backpressureEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:backpressure");
  NSDictionary *locations = [result[@"locations"] isKindOfClass:[NSDictionary class]] ? result[@"locations"] : @{};
  NSDictionary *orders = ALNLiveRuntimeElementSnapshot(result, @"#orders");
  NSArray *expectedAssignLocations = @[ @"http://example.test/login", @"http://example.test/forbidden" ];

  XCTAssertEqual((NSUInteger)2, [authEvents count]);
  XCTAssertEqualObjects(@(401), authEvents[0][@"detail"][@"status"]);
  XCTAssertEqualObjects(@(403), authEvents[1][@"detail"][@"status"]);
  XCTAssertEqualObjects(@"#orders", authEvents[0][@"target"]);
  XCTAssertEqualObjects(@"#orders", authEvents[1][@"target"]);
  XCTAssertEqualObjects(expectedAssignLocations, locations[@"assign"]);

  XCTAssertEqual((NSUInteger)2, [backpressureEvents count]);
  XCTAssertEqualObjects(@(429), backpressureEvents[0][@"detail"][@"status"]);
  XCTAssertEqualObjects(@(3000), backpressureEvents[0][@"detail"][@"retryAfter"]);
  XCTAssertEqualObjects(@(503), backpressureEvents[1][@"detail"][@"status"]);
  XCTAssertEqualObjects(@(1500), backpressureEvents[1][@"detail"][@"retryAfter"]);
  XCTAssertEqualObjects(@"Stable", orders[@"textContent"]);
}

@end
