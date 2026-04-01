#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNLive.h"
#import "../shared/ALNLiveTestSupport.h"

@interface LiveRuntimeDOMTests : XCTestCase
@end

@implementation LiveRuntimeDOMTests

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

- (void)testBasicHTMLOperationsMutateTargets {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" : @"<div id=\"panel\">Old</div><ul id=\"list\"><li>Existing</li></ul><div id=\"remove-me\">Gone</div>",
    @"actions" : @[
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive replaceOperationForTarget:@"#panel" html:@"<section id=\"panel\">New</section>"],
          [ALNLive prependOperationForTarget:@"#list" html:@"<li>First</li>"],
          [ALNLive appendOperationForTarget:@"#list" html:@"<li>Last</li>"],
          [ALNLive removeOperationForTarget:@"#remove-me"],
        ]],
      },
    ],
    @"inspect" : @[ @"#panel", @"#list", @"#remove-me" ],
  }];

  NSDictionary *panel = ALNLiveRuntimeElementSnapshot(result, @"#panel");
  NSDictionary *list = ALNLiveRuntimeElementSnapshot(result, @"#list");
  XCTAssertEqualObjects(@"<section id=\"panel\">New</section>", panel[@"outerHTML"]);
  XCTAssertEqualObjects(@"<li>First</li><li>Existing</li><li>Last</li>", list[@"innerHTML"]);
  XCTAssertNil(ALNLiveRuntimeElementSnapshot(result, @"#remove-me"));
}

- (void)testKeyedOperationsReplaceAndRestoreEmptyState {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *insertAndReplace = [self runScenario:@{
    @"html" : @"<ul id=\"feed\"><li data-arlen-live-empty>No items</li></ul>",
    @"actions" : @[
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive upsertKeyedOperationForContainer:@"#feed"
                                                key:@"alpha"
                                               html:@"<li data-arlen-live-key=\"alpha\">Alpha</li>"
                                            prepend:NO],
        ]],
      },
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive upsertKeyedOperationForContainer:@"#feed"
                                                key:@"alpha"
                                               html:@"<li data-arlen-live-key=\"alpha\">Alpha updated</li>"
                                            prepend:NO],
        ]],
      },
    ],
    @"inspect" : @[ @"#feed", @"[data-arlen-live-empty]" ],
  }];

  NSDictionary *feed = ALNLiveRuntimeElementSnapshot(insertAndReplace, @"#feed");
  NSDictionary *placeholder = ALNLiveRuntimeElementSnapshot(insertAndReplace, @"[data-arlen-live-empty]");
  XCTAssertEqual((NSUInteger)1,
                 [[feed[@"outerHTML"] componentsSeparatedByString:@"data-arlen-live-key=\"alpha\""] count] - 1);
  XCTAssertTrue([feed[@"outerHTML"] containsString:@"Alpha updated"]);
  XCTAssertEqualObjects(@"", placeholder[@"attributes"][@"hidden"]);
  XCTAssertEqualObjects(@(YES), placeholder[@"hidden"]);

  NSDictionary *discard = [self runScenario:@{
    @"html" : @"<ul id=\"feed\"><li data-arlen-live-key=\"alpha\">Alpha updated</li><li data-arlen-live-empty hidden>No items</li></ul>",
    @"actions" : @[
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive removeKeyedOperationForContainer:@"#feed" key:@"alpha"],
        ]],
      },
    ],
    @"inspect" : @[ @"#feed", @"[data-arlen-live-empty]", @"[data-arlen-live-key=\"alpha\"]" ],
  }];

  NSDictionary *feedAfterDiscard = ALNLiveRuntimeElementSnapshot(discard, @"#feed");
  NSDictionary *placeholderAfterDiscard = ALNLiveRuntimeElementSnapshot(discard, @"[data-arlen-live-empty]");
  XCTAssertFalse([feedAfterDiscard[@"outerHTML"] containsString:@"data-arlen-live-key=\"alpha\""]);
  XCTAssertEqualObjects(@(NO), placeholderAfterDiscard[@"hidden"]);
  XCTAssertNil(ALNLiveRuntimeElementSnapshot(discard, @"[data-arlen-live-key=\"alpha\"]"));
}

- (void)testNavigateOperationsRecordAssignAndReplace {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"actions" : @[
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive navigateOperationForLocation:@"/orders/42" replace:NO],
        ]],
      },
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive navigateOperationForLocation:@"/orders/99" replace:YES],
        ]],
      },
    ],
  }];

  NSDictionary *locations = [result[@"locations"] isKindOfClass:[NSDictionary class]] ? result[@"locations"] : @{};
  XCTAssertEqualObjects(@[ @"/orders/42" ], locations[@"assign"]);
  XCTAssertEqualObjects(@[ @"/orders/99" ], locations[@"replace"]);
}

- (void)testDispatchOperationEmitsTargetedCustomEvent {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" : @"<div id=\"panel\"></div>",
    @"actions" : @[
      @{
        @"type" : @"apply_payload",
        @"payload" : [self payloadWithOperations:@[
          [ALNLive dispatchOperationForEvent:@"order:updated"
                                      detail:@{ @"count" : @(2), @"owner" : @"Pat" }
                                      target:@"#panel"],
        ]],
      },
    ],
    @"inspect" : @[ @"#panel" ],
  }];

  NSArray<NSDictionary *> *events = ALNLiveRuntimeEventsNamed(result, @"order:updated");
  XCTAssertEqual((NSUInteger)1, [events count]);
  XCTAssertEqualObjects(@"#panel", events[0][@"target"]);
  XCTAssertEqualObjects(@(2), events[0][@"detail"][@"count"]);
  XCTAssertEqualObjects(@"Pat", events[0][@"detail"][@"owner"]);
}

- (void)testUnknownOperationsAndInvalidSelectorsWarnWithoutMutation {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *result = [self runScenario:@{
    @"html" : @"<div id=\"panel\">Stable</div>",
    @"actions" : @[
      @{
        @"type" : @"apply_payload",
        @"payload" : @{
          @"version" : [ALNLive protocolVersion],
          @"operations" : @[
            @{ @"op" : @"mystery", @"target" : @"#panel" },
            @{ @"op" : @"replace", @"target" : @"[", @"html" : @"<p>Broken</p>" },
          ],
        },
      },
    ],
    @"inspect" : @[ @"#panel" ],
  }];

  NSDictionary *panel = ALNLiveRuntimeElementSnapshot(result, @"#panel");
  NSArray *warnings = [result[@"warnings"] isKindOfClass:[NSArray class]] ? result[@"warnings"] : @[];
  XCTAssertEqualObjects(@"<div id=\"panel\">Stable</div>", panel[@"outerHTML"]);
  XCTAssertGreaterThanOrEqual([warnings count], (NSUInteger)2);
}

@end
