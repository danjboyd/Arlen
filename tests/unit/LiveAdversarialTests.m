#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNLive.h"
#import "ALNRequest.h"
#import "../shared/ALNLiveTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface LiveAdversarialTests : XCTestCase
@end

@implementation LiveAdversarialTests

- (NSDictionary *)fixtureCatalog {
  NSError *error = nil;
  NSDictionary *catalog =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase25/live_adversarial_cases.json", &error);
  XCTAssertNotNil(catalog);
  XCTAssertNil(error);
  return catalog ?: @{};
}

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

- (NSDictionary *)payloadWithOperations:(NSArray *)operations {
  NSError *error = nil;
  NSDictionary *payload = [ALNLive validatedPayloadWithOperations:operations meta:nil error:&error];
  XCTAssertNotNil(payload);
  XCTAssertNil(error);
  return payload ?: @{};
}

- (void)testEscapedKeyFixturesProduceDeterministicSelectors {
  NSDictionary *catalog = [self fixtureCatalog];
  NSArray *cases = [catalog[@"escapedKeyCases"] isKindOfClass:[NSArray class]]
                       ? catalog[@"escapedKeyCases"]
                       : @[];
  for (NSDictionary *entry in cases) {
    NSString *container = [entry[@"container"] isKindOfClass:[NSString class]] ? entry[@"container"] : @"";
    NSString *key = [entry[@"key"] isKindOfClass:[NSString class]] ? entry[@"key"] : @"";
    NSString *expected = [entry[@"expectedTarget"] isKindOfClass:[NSString class]]
                             ? entry[@"expectedTarget"]
                             : @"";
    XCTAssertEqualObjects(expected, [ALNLive keyedTargetSelectorForContainer:container key:key], @"%@", entry[@"name"]);
  }
}

- (void)testEscapedKeyFixtureCasesRoundTripThroughRuntimeHarness {
  if (![self requireHarness]) {
    return;
  }

  NSDictionary *catalog = [self fixtureCatalog];
  NSArray *cases = [catalog[@"escapedKeyCases"] isKindOfClass:[NSArray class]]
                       ? catalog[@"escapedKeyCases"]
                       : @[];
  for (NSDictionary *entry in cases) {
    if ([entry[@"runtimeSafe"] respondsToSelector:@selector(boolValue)] &&
        ![entry[@"runtimeSafe"] boolValue]) {
      continue;
    }
    NSString *container = [entry[@"container"] isKindOfClass:[NSString class]] ? entry[@"container"] : @"#feed";
    NSString *key = [entry[@"key"] isKindOfClass:[NSString class]] ? entry[@"key"] : @"";
    NSString *label = [entry[@"label"] isKindOfClass:[NSString class]] ? entry[@"label"] : @"";
    NSString *target = [entry[@"expectedTarget"] isKindOfClass:[NSString class]] ? entry[@"expectedTarget"] : @"";
    NSString *html = [NSString stringWithFormat:@"<li data-arlen-live-key=\"%@\">%@</li>", key, label];

    NSDictionary *result = [self runScenario:@{
      @"html" : @"<ul id=\"feed\"><li data-arlen-live-empty>No items</li></ul>",
      @"actions" : @[
        @{
          @"type" : @"apply_payload",
          @"payload" : [self payloadWithOperations:@[
            [ALNLive upsertKeyedOperationForContainer:container key:key html:html prepend:NO],
          ]],
        },
        @{ @"type" : @"snapshot", @"selector" : target },
        @{
          @"type" : @"apply_payload",
          @"payload" : [self payloadWithOperations:@[
            [ALNLive removeKeyedOperationForContainer:container key:key],
          ]],
        },
      ],
      @"inspect" : @[ target ],
    }];

    NSArray *actionResults = [result[@"actionResults"] isKindOfClass:[NSArray class]] ? result[@"actionResults"] : @[];
    NSDictionary *inserted =
        [actionResults count] > 1 && [actionResults[1] isKindOfClass:[NSDictionary class]]
            ? actionResults[1]
            : @{};

    XCTAssertTrue([inserted[@"outerHTML"] containsString:label], @"%@", entry[@"name"]);
    XCTAssertNil(ALNLiveRuntimeElementSnapshot(result, target), @"%@", entry[@"name"]);
  }
}

- (void)testValidatedPayloadRejectsInvalidNavigateLocationsFromFixtures {
  NSDictionary *catalog = [self fixtureCatalog];
  NSArray *locations = [catalog[@"invalidNavigateLocations"] isKindOfClass:[NSArray class]]
                           ? catalog[@"invalidNavigateLocations"]
                           : @[];
  for (NSString *location in locations) {
    NSError *error = nil;
    NSDictionary *payload = [ALNLive validatedPayloadWithOperations:@[
      [ALNLive navigateOperationForLocation:location replace:NO]
    ]
                                                                meta:nil
                                                               error:&error];
    XCTAssertNil(payload, @"%@", location);
    XCTAssertNotNil(error, @"%@", location);
    XCTAssertTrue([error.localizedDescription containsString:@"relative paths or http(s) URLs"], @"%@", location);
  }

  NSError *controlError = nil;
  NSDictionary *controlPayload = [ALNLive validatedPayloadWithOperations:@[
    [ALNLive navigateOperationForLocation:@"https://example.test/\nboom" replace:NO]
  ]
                                                                  meta:nil
                                                                 error:&controlError];
  XCTAssertNil(controlPayload);
  XCTAssertNotNil(controlError);
  XCTAssertTrue([controlError.localizedDescription containsString:@"control characters"]);
}

- (void)testValidatedPayloadRejectsInvalidDispatchDetailAndMetaShapes {
  NSError *dispatchError = nil;
  NSDictionary *dispatchPayload = [ALNLive validatedPayloadWithOperations:@[
    @{
      @"op" : @"dispatch",
      @"event" : @"order:updated",
      @"detail" : @{ @"when" : [NSDate date] },
    }
  ]
                                                                 meta:nil
                                                                error:&dispatchError];
  XCTAssertNil(dispatchPayload);
  XCTAssertNotNil(dispatchError);
  XCTAssertTrue([dispatchError.localizedDescription containsString:@"JSON serializable"]);

  NSError *metaKeyError = nil;
  NSDictionary *metaKeyPayload =
      [ALNLive validatedPayloadWithOperations:@[
        [ALNLive updateOperationForTarget:@"#panel" html:@"<p>ok</p>"]
      ]
                                        meta:@{ @42 : @"not allowed" }
                                       error:&metaKeyError];
  XCTAssertNil(metaKeyPayload);
  XCTAssertNotNil(metaKeyError);
  XCTAssertTrue([metaKeyError.localizedDescription containsString:@"keys must be strings"]);

  NSError *metaValueError = nil;
  NSDictionary *metaValuePayload =
      [ALNLive validatedPayloadWithOperations:@[
        [ALNLive updateOperationForTarget:@"#panel" html:@"<p>ok</p>"]
      ]
                                        meta:@{ @"when" : [NSDate date] }
                                       error:&metaValueError];
  XCTAssertNil(metaValuePayload);
  XCTAssertNotNil(metaValueError);
  XCTAssertTrue([metaValueError.localizedDescription containsString:@"JSON serializable"]);
}

- (void)testRequestMetadataNormalizesLazyHeaderValues {
  ALNRequest *falseRequest = [[ALNRequest alloc] initWithMethod:@"GET"
                                                           path:@"/orders"
                                                    queryString:@""
                                                        headers:@{
                                                          @"X-Arlen-Live" : @"true",
                                                          @"X-Arlen-Live-Lazy" : @" off ",
                                                        }
                                                           body:[NSData data]];
  NSDictionary *falseMetadata = [ALNLive requestMetadataForRequest:falseRequest];
  XCTAssertEqualObjects(@(NO), falseMetadata[@"lazy"]);

  ALNRequest *invalidRequest = [[ALNRequest alloc] initWithMethod:@"GET"
                                                             path:@"/orders"
                                                      queryString:@""
                                                          headers:@{
                                                            @"X-Arlen-Live" : @"true",
                                                            @"X-Arlen-Live-Lazy" : @" maybe ",
                                                          }
                                                             body:[NSData data]];
  NSDictionary *invalidMetadata = [ALNLive requestMetadataForRequest:invalidRequest];
  XCTAssertNil(invalidMetadata[@"lazy"]);
}

@end
