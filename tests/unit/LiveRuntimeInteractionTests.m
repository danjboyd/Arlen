#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNLive.h"
#import "../shared/ALNLiveTestSupport.h"

@interface LiveRuntimeInteractionTests : XCTestCase
@end

@implementation LiveRuntimeInteractionTests

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

- (void)testLiveGETFormSerializesQueryBusyStateAndAppliesPayload {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" :
        @"<form id=\"filters\" method=\"get\" action=\"/orders\" data-arlen-live data-arlen-live-target=\"#orders\" data-arlen-live-swap=\"update\">"
         "<input type=\"text\" name=\"owner\" value=\"Pat\">"
         "<input type=\"text\" name=\"status\" value=\"Live\">"
         "<button id=\"submit-filter\" type=\"submit\" name=\"commit\" value=\"Filter\">Filter</button>"
         "</form>"
         "<div id=\"orders\">Old</div>",
    @"responses" : @[
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : [ALNLive contentType] },
                             [self JSONStringForObject:[self payloadWithOperations:@[
                               [ALNLive updateOperationForTarget:@"#orders" html:@"<p>Filtered</p>"],
                             ]]],
                             @"http://example.test/orders?owner=Pat&status=Live&commit=Filter",
                             NO,
                             @{ @"delayMs" : @(25), @"transport" : @"fetch" }),
    ],
    @"actions" : @[
      @{
        @"type" : @"submit_form",
        @"selector" : @"#filters",
        @"submitter" : @"#submit-filter",
        @"await" : @(NO),
        @"id" : @"filtersRequest",
      },
      @{ @"type" : @"snapshot", @"selector" : @"#filters" },
      @{ @"type" : @"snapshot", @"selector" : @"#submit-filter" },
      @{ @"type" : @"advance_time", @"ms" : @(25) },
      @{ @"type" : @"await", @"id" : @"filtersRequest" },
    ],
    @"inspect" : @[ @"#filters", @"#submit-filter", @"#orders" ],
  }];

  NSArray<NSDictionary *> *requests = ALNLiveRuntimeRequestsForTransport(result, @"fetch");
  NSDictionary *request = [requests count] > 0 ? requests[0] : @{};
  NSDictionary *busyForm = [result[@"actionResults"] isKindOfClass:[NSArray class]] &&
                                   [result[@"actionResults"] count] > 1 &&
                                   [result[@"actionResults"][1] isKindOfClass:[NSDictionary class]]
                               ? result[@"actionResults"][1]
                               : @{};
  NSDictionary *busyButton = [result[@"actionResults"] isKindOfClass:[NSArray class]] &&
                                     [result[@"actionResults"] count] > 2 &&
                                     [result[@"actionResults"][2] isKindOfClass:[NSDictionary class]]
                                 ? result[@"actionResults"][2]
                                 : @{};
  NSDictionary *finalForm = ALNLiveRuntimeElementSnapshot(result, @"#filters");
  NSDictionary *finalButton = ALNLiveRuntimeElementSnapshot(result, @"#submit-filter");
  NSDictionary *orders = ALNLiveRuntimeElementSnapshot(result, @"#orders");

  XCTAssertEqual((NSUInteger)1, [requests count]);
  XCTAssertEqualObjects(@"GET", request[@"method"]);
  XCTAssertTrue([request[@"url"] containsString:@"owner=Pat"]);
  XCTAssertTrue([request[@"url"] containsString:@"status=Live"]);
  XCTAssertTrue([request[@"url"] containsString:@"commit=Filter"]);
  XCTAssertEqualObjects(@"true", request[@"headers"][@"X-Arlen-Live"]);
  XCTAssertEqualObjects(@"#orders", request[@"headers"][@"X-Arlen-Live-Target"]);
  XCTAssertEqualObjects(@"update", request[@"headers"][@"X-Arlen-Live-Swap"]);
  XCTAssertEqualObjects(@"form", request[@"headers"][@"X-Arlen-Live-Source"]);
  XCTAssertEqualObjects(@"true", busyForm[@"attributes"][@"data-arlen-live-busy"]);
  XCTAssertEqualObjects(@(YES), busyButton[@"disabled"]);
  XCTAssertEqualObjects(@"false", busyButton[@"attributes"][@"data-arlen-live-disabled-before"]);
  XCTAssertEqualObjects(@"false", finalForm[@"attributes"][@"data-arlen-live-busy"]);
  XCTAssertEqualObjects(@(NO), finalButton[@"disabled"]);
  XCTAssertEqualObjects(@"<p>Filtered</p>", orders[@"innerHTML"]);
}

- (void)testLivePOSTFormFallsBackToNavigationOnHTMLResponse {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" :
        @"<form id=\"create-order\" method=\"post\" action=\"/orders\" data-arlen-live data-arlen-live-target=\"#orders\">"
         "<input type=\"text\" name=\"title\" value=\"Alpha\">"
         "<button id=\"create-order-submit\" type=\"submit\" name=\"commit\" value=\"Create\">Create</button>"
         "</form>"
         "<div id=\"orders\">Old</div>",
    @"responses" : @[
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : @"text/html; charset=utf-8" },
                             @"<p>Created</p>",
                             @"http://example.test/orders/42",
                             NO,
                             @{ @"transport" : @"fetch" }),
    ],
    @"actions" : @[
      @{
        @"type" : @"submit_form",
        @"selector" : @"#create-order",
        @"submitter" : @"#create-order-submit",
      },
    ],
    @"inspect" : @[ @"#orders" ],
  }];

  NSArray<NSDictionary *> *requests = ALNLiveRuntimeRequestsForTransport(result, @"fetch");
  NSDictionary *request = [requests count] > 0 ? requests[0] : @{};
  NSDictionary *locations = [result[@"locations"] isKindOfClass:[NSDictionary class]] ? result[@"locations"] : @{};
  NSDictionary *orders = ALNLiveRuntimeElementSnapshot(result, @"#orders");

  XCTAssertEqual((NSUInteger)1, [requests count]);
  XCTAssertEqualObjects(@"POST", request[@"method"]);
  XCTAssertEqualObjects(@"form-data", request[@"body"][@"kind"]);
  XCTAssertEqualObjects(@[ @"http://example.test/orders/42" ], locations[@"assign"]);
  XCTAssertEqualObjects(@"Old", orders[@"textContent"]);
}

- (void)testLiveFileUploadUsesXHRAndEmitsProgress {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" :
        @"<form id=\"upload-form\" method=\"post\" action=\"/upload\" data-arlen-live data-arlen-live-target=\"#upload-result\" data-arlen-live-upload-progress=\"#progress\">"
         "<input type=\"file\" name=\"artifact\" value=\"report.csv\">"
         "<button id=\"upload-submit\" type=\"submit\">Upload</button>"
         "</form>"
         "<progress id=\"progress\"></progress>"
         "<div id=\"upload-result\">Waiting</div>",
    @"responses" : @[
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : [ALNLive contentType] },
                             [self JSONStringForObject:[self payloadWithOperations:@[
                               [ALNLive updateOperationForTarget:@"#upload-result" html:@"<p>Uploaded</p>"],
                             ]]],
                             @"http://example.test/upload",
                             NO,
                             @{
                               @"delayMs" : @(20),
                               @"transport" : @"xhr",
                               @"uploadProgress" : @[ @[ @(5), @(10) ], @[ @(10), @(10) ] ],
                             }),
    ],
    @"actions" : @[
      @{
        @"type" : @"submit_form",
        @"selector" : @"#upload-form",
        @"submitter" : @"#upload-submit",
        @"await" : @(NO),
        @"id" : @"uploadRequest",
      },
      @{ @"type" : @"snapshot", @"selector" : @"#progress" },
      @{ @"type" : @"advance_time", @"ms" : @(10) },
      @{ @"type" : @"snapshot", @"selector" : @"#progress" },
      @{ @"type" : @"advance_time", @"ms" : @(10) },
      @{ @"type" : @"await", @"id" : @"uploadRequest" },
    ],
    @"inspect" : @[ @"#progress", @"#upload-result" ],
  }];

  NSArray<NSDictionary *> *requests = ALNLiveRuntimeRequestsForTransport(result, @"xhr");
  NSDictionary *initialProgress = [result[@"actionResults"] isKindOfClass:[NSArray class]] &&
                                          [result[@"actionResults"] count] > 1 &&
                                          [result[@"actionResults"][1] isKindOfClass:[NSDictionary class]]
                                      ? result[@"actionResults"][1]
                                      : @{};
  NSDictionary *midProgress = [result[@"actionResults"] isKindOfClass:[NSArray class]] &&
                                      [result[@"actionResults"] count] > 3 &&
                                      [result[@"actionResults"][3] isKindOfClass:[NSDictionary class]]
                                  ? result[@"actionResults"][3]
                                  : @{};
  NSDictionary *finalProgress = ALNLiveRuntimeElementSnapshot(result, @"#progress");
  NSDictionary *uploadResult = ALNLiveRuntimeElementSnapshot(result, @"#upload-result");
  NSArray<NSDictionary *> *events = ALNLiveRuntimeEventsNamed(result, @"arlen:live:upload-progress");

  XCTAssertEqual((NSUInteger)1, [requests count]);
  XCTAssertEqualObjects(@"POST", requests[0][@"method"]);
  XCTAssertEqualObjects(@"#upload-result", requests[0][@"headers"][@"X-Arlen-Live-Target"]);
  XCTAssertEqualObjects(@"0", initialProgress[@"attributes"][@"data-arlen-live-upload-percent"]);
  XCTAssertEqualObjects(@"50", midProgress[@"attributes"][@"data-arlen-live-upload-percent"]);
  XCTAssertEqualObjects(@"100", finalProgress[@"attributes"][@"data-arlen-live-upload-percent"]);
  XCTAssertEqualObjects(@"<p>Uploaded</p>", uploadResult[@"innerHTML"]);
  XCTAssertGreaterThanOrEqual([events count], (NSUInteger)3);
}

- (void)testDeferredRegionHydratesThenPolls {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" :
        @"<section id=\"pulse\" data-arlen-live-src=\"/pulse\" data-arlen-live-target=\"#pulse\" data-arlen-live-swap=\"update\" data-arlen-live-poll=\"5s\" data-arlen-live-defer=\"250ms\"><p>Loading</p></section>",
    @"responses" : @[
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : @"text/html; charset=utf-8" },
                             @"<div class=\"pulse\">First</div>",
                             @"http://example.test/pulse",
                             NO,
                             @{ @"transport" : @"fetch" }),
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : @"text/html; charset=utf-8" },
                             @"<div class=\"pulse\">Second</div>",
                             @"http://example.test/pulse",
                             NO,
                             @{ @"transport" : @"fetch" }),
    ],
    @"actions" : @[
      @{ @"type" : @"start" },
      @{ @"type" : @"snapshot", @"selector" : @"#pulse" },
      @{ @"type" : @"advance_time", @"ms" : @(249) },
      @{ @"type" : @"snapshot", @"selector" : @"#pulse" },
      @{ @"type" : @"advance_time", @"ms" : @(1) },
      @{ @"type" : @"snapshot", @"selector" : @"#pulse" },
      @{ @"type" : @"advance_time", @"ms" : @(5000) },
      @{ @"type" : @"snapshot", @"selector" : @"#pulse" },
    ],
    @"inspect" : @[ @"#pulse" ],
  }];

  NSArray<NSDictionary *> *requests = ALNLiveRuntimeRequestsForTransport(result, @"fetch");
  NSArray *results = [result[@"actionResults"] isKindOfClass:[NSArray class]] ? result[@"actionResults"] : @[];
  NSDictionary *beforeDelay = [results count] > 1 && [results[1] isKindOfClass:[NSDictionary class]] ? results[1] : @{};
  NSDictionary *beforeHydrate = [results count] > 3 && [results[3] isKindOfClass:[NSDictionary class]] ? results[3] : @{};
  NSDictionary *afterHydrate = [results count] > 5 && [results[5] isKindOfClass:[NSDictionary class]] ? results[5] : @{};
  NSDictionary *afterPoll = [results count] > 7 && [results[7] isKindOfClass:[NSDictionary class]] ? results[7] : @{};
  NSArray<NSDictionary *> *regionStartEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:region-start");
  NSArray<NSDictionary *> *regionEndEvents = ALNLiveRuntimeEventsNamed(result, @"arlen:live:region-end");

  XCTAssertEqual((NSUInteger)2, [requests count]);
  XCTAssertEqualObjects(@"<p>Loading</p>", beforeDelay[@"innerHTML"]);
  XCTAssertEqualObjects(@"<p>Loading</p>", beforeHydrate[@"innerHTML"]);
  XCTAssertEqualObjects(@"<div class=\"pulse\">First</div>", afterHydrate[@"innerHTML"]);
  XCTAssertEqualObjects(@"true", afterHydrate[@"attributes"][@"data-arlen-live-hydrated"]);
  XCTAssertEqualObjects(@"<div class=\"pulse\">Second</div>", afterPoll[@"innerHTML"]);
  XCTAssertEqual((NSUInteger)2, [regionStartEvents count]);
  XCTAssertEqual((NSUInteger)2, [regionEndEvents count]);
}

- (void)testLazyRegionWaitsForIntersectionAndFallsBackWithoutObserver {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *intersectionResult = [self runScenario:@{
    @"html" :
        @"<section id=\"insights\" data-arlen-live-src=\"/insights\" data-arlen-live-target=\"#insights\" data-arlen-live-lazy><p>Waiting</p></section>",
    @"responses" : @[
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : @"text/html; charset=utf-8" },
                             @"<div>Lazy</div>",
                             @"http://example.test/insights",
                             NO,
                             @{ @"transport" : @"fetch" }),
    ],
    @"actions" : @[
      @{ @"type" : @"start" },
      @{ @"type" : @"snapshot", @"selector" : @"#insights" },
      @{ @"type" : @"trigger_intersection", @"selector" : @"#insights" },
      @{ @"type" : @"snapshot", @"selector" : @"#insights" },
    ],
    @"inspect" : @[ @"#insights" ],
  }];

  NSArray<NSDictionary *> *intersectionRequests = ALNLiveRuntimeRequestsForTransport(intersectionResult, @"fetch");
  NSArray *intersectionActions =
      [intersectionResult[@"actionResults"] isKindOfClass:[NSArray class]] ? intersectionResult[@"actionResults"] : @[];
  NSDictionary *beforeIntersection =
      [intersectionActions count] > 1 && [intersectionActions[1] isKindOfClass:[NSDictionary class]]
          ? intersectionActions[1]
          : @{};
  NSDictionary *afterIntersection =
      [intersectionActions count] > 3 && [intersectionActions[3] isKindOfClass:[NSDictionary class]]
          ? intersectionActions[3]
          : @{};

  XCTAssertEqual((NSUInteger)1, [intersectionRequests count]);
  XCTAssertEqualObjects(@"<p>Waiting</p>", beforeIntersection[@"innerHTML"]);
  XCTAssertEqualObjects(@"<div>Lazy</div>", afterIntersection[@"innerHTML"]);

  NSDictionary *fallbackResult = [self runScenario:@{
    @"disableIntersectionObserver" : @(YES),
    @"html" :
        @"<section id=\"insights\" data-arlen-live-src=\"/insights\" data-arlen-live-target=\"#insights\" data-arlen-live-lazy><p>Waiting</p></section>",
    @"responses" : @[
      ALNLiveRuntimeResponse(200,
                             @{ @"Content-Type" : @"text/html; charset=utf-8" },
                             @"<div>Fallback</div>",
                             @"http://example.test/insights",
                             NO,
                             @{ @"transport" : @"fetch" }),
    ],
    @"actions" : @[
      @{ @"type" : @"start" },
      @{ @"type" : @"snapshot", @"selector" : @"#insights" },
    ],
    @"inspect" : @[ @"#insights" ],
  }];

  NSArray<NSDictionary *> *fallbackRequests = ALNLiveRuntimeRequestsForTransport(fallbackResult, @"fetch");
  NSArray *fallbackActions =
      [fallbackResult[@"actionResults"] isKindOfClass:[NSArray class]] ? fallbackResult[@"actionResults"] : @[];
  NSDictionary *afterFallbackStart =
      [fallbackActions count] > 1 && [fallbackActions[1] isKindOfClass:[NSDictionary class]]
          ? fallbackActions[1]
          : @{};

  XCTAssertEqual((NSUInteger)1, [fallbackRequests count]);
  XCTAssertEqualObjects(@"<div>Fallback</div>", afterFallbackStart[@"innerHTML"]);
}

@end
