#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNLive.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "../shared/ALNWebTestSupport.h"

@interface LiveProtocolTests : XCTestCase
@end

@implementation LiveProtocolTests

- (void)testRequestIsLiveWhenHeaderOrAcceptMatches {
  ALNRequest *headerRequest = [[ALNRequest alloc] initWithMethod:@"POST"
                                                            path:@"/items"
                                                     queryString:@""
                                                         headers:@{ @"X-Arlen-Live" : @"true" }
                                                            body:[NSData data]];
  XCTAssertTrue([ALNLive requestIsLive:headerRequest]);

  ALNRequest *acceptRequest = [[ALNRequest alloc] initWithMethod:@"GET"
                                                            path:@"/items"
                                                     queryString:@""
                                                         headers:@{
                                                           @"Accept" : [NSString stringWithFormat:@"%@, text/html",
                                                                                       [ALNLive acceptContentType]]
                                                         }
                                                            body:[NSData data]];
  XCTAssertTrue([ALNLive requestIsLive:acceptRequest]);

  ALNRequest *plainRequest = [[ALNRequest alloc] initWithMethod:@"GET"
                                                           path:@"/items"
                                                    queryString:@""
                                                        headers:@{ @"Accept" : @"text/html" }
                                                           body:[NSData data]];
  XCTAssertFalse([ALNLive requestIsLive:plainRequest]);
}

- (void)testRequestMetadataNormalizesLiveHeaders {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"POST"
                                                      path:@"/items"
                                               queryString:@""
                                                   headers:@{
                                                     @"X-Arlen-Live" : @"true",
                                                     @"X-Arlen-Live-Target" : @" #orders ",
                                                     @"X-Arlen-Live-Swap" : @" UPDATE ",
                                                     @"X-Arlen-Live-Component" : @" order-list ",
                                                     @"X-Arlen-Live-Event" : @" submit ",
                                                     @"X-Arlen-Live-Source" : @" FORM ",
                                                     @"X-Arlen-Live-Container" : @" #feed ",
                                                     @"X-Arlen-Live-Key" : @" row-42 ",
                                                     @"X-Arlen-Live-Poll" : @" 5s ",
                                                     @"X-Arlen-Live-Defer" : @" 250ms ",
                                                     @"X-Arlen-Live-Lazy" : @" true ",
                                                   }
                                                      body:[NSData data]];

  NSDictionary *metadata = [ALNLive requestMetadataForRequest:request];
  XCTAssertEqualObjects(@"#orders", metadata[@"target"]);
  XCTAssertEqualObjects(@"update", metadata[@"swap"]);
  XCTAssertEqualObjects(@"order-list", metadata[@"component"]);
  XCTAssertEqualObjects(@"submit", metadata[@"event"]);
  XCTAssertEqualObjects(@"form", metadata[@"source"]);
  XCTAssertEqualObjects(@"#feed", metadata[@"container"]);
  XCTAssertEqualObjects(@"row-42", metadata[@"key"]);
  XCTAssertEqualObjects(@"5s", metadata[@"poll"]);
  XCTAssertEqualObjects(@"250ms", metadata[@"defer"]);
  XCTAssertEqualObjects(@(YES), metadata[@"lazy"]);
}

- (void)testRenderResponseSerializesPayloadAndHeaders {
  ALNResponse *response = [[ALNResponse alloc] init];
  NSError *error = nil;
  BOOL ok = [ALNLive renderResponse:response
                         operations:@[
                           [ALNLive replaceOperationForTarget:@"#items" html:@"<li>Alpha</li>"],
                           [ALNLive navigateOperationForLocation:@"/orders" replace:YES],
                         ]
                               meta:@{ @"request_id" : @"req-live-1" }
                              error:&error];

  XCTAssertTrue(ok);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects([ALNLive contentType], [response headerForName:@"Content-Type"]);
  XCTAssertEqualObjects([ALNLive protocolVersion],
                        [response headerForName:@"X-Arlen-Live-Protocol"]);
  XCTAssertEqualObjects(@"no-store", [response headerForName:@"Cache-Control"]);
  XCTAssertEqualObjects(@"Accept, X-Arlen-Live", [response headerForName:@"Vary"]);

  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects([ALNLive protocolVersion], payload[@"version"]);
  XCTAssertEqualObjects(@"req-live-1", payload[@"meta"][@"request_id"]);
  XCTAssertEqual((NSUInteger)2, [payload[@"operations"] count]);
  XCTAssertEqualObjects(@"replace", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#items", payload[@"operations"][0][@"target"]);
  XCTAssertEqualObjects(@"<li>Alpha</li>", payload[@"operations"][0][@"html"]);
  XCTAssertEqualObjects(@"navigate", payload[@"operations"][1][@"op"]);
  XCTAssertEqualObjects(@"/orders", payload[@"operations"][1][@"location"]);
  XCTAssertEqualObjects(@(YES), payload[@"operations"][1][@"replace"]);
}

- (void)testValidatedPayloadRejectsMalformedOperation {
  NSError *error = nil;
  NSDictionary *payload = [ALNLive validatedPayloadWithOperations:@[
    @{
      @"op" : @"replace",
      @"html" : @"<p>Missing target</p>",
    }
  ]
                                                              meta:nil
                                                             error:&error];

  XCTAssertNil(payload);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"target selector"]);
}

- (void)testValidatedPayloadSupportsKeyedCollectionOperations {
  NSError *error = nil;
  NSDictionary *payload = [ALNLive validatedPayloadWithOperations:@[
    [ALNLive upsertKeyedOperationForContainer:@"#feed"
                                          key:@"alpha"
                                         html:@"<li data-arlen-live-key=\"alpha\">Alpha</li>"
                                      prepend:NO],
    [ALNLive removeKeyedOperationForContainer:@"#feed" key:@"alpha"],
  ]
                                                              meta:@{ @"channel" : @"live.feed" }
                                                             error:&error];

  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [payload[@"operations"] count]);
  XCTAssertEqualObjects(@"upsert", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#feed", payload[@"operations"][0][@"container"]);
  XCTAssertEqualObjects(@"alpha", payload[@"operations"][0][@"key"]);
  XCTAssertEqualObjects(@"discard", payload[@"operations"][1][@"op"]);
  XCTAssertEqualObjects(@"[data-arlen-live-key=\"alpha\"]",
                        [ALNLive keyedTargetSelectorForContainer:nil key:@"alpha"]);
}

- (void)testValidatedPayloadRejectsOversizedOperationSet {
  NSMutableArray *operations = [NSMutableArray array];
  for (NSUInteger idx = 0; idx < 65; idx++) {
    [operations addObject:[ALNLive replaceOperationForTarget:@"#items" html:@"<li>Alpha</li>"]];
  }

  NSError *error = nil;
  NSDictionary *payload = [ALNLive validatedPayloadWithOperations:operations meta:nil error:&error];

  XCTAssertNil(payload);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"operation count"]);
}

- (void)testValidatedPayloadRejectsOversizedMeta {
  NSMutableString *large = [NSMutableString string];
  for (NSUInteger idx = 0; idx < 17000; idx++) {
    [large appendString:@"x"];
  }

  NSError *error = nil;
  NSDictionary *payload =
      [ALNLive validatedPayloadWithOperations:@[
        [ALNLive updateOperationForTarget:@"#panel" html:@"<div>ok</div>"]
      ]
                                        meta:@{ @"notes" : large }
                                       error:&error];

  XCTAssertNil(payload);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"meta exceeds"]);
}

- (void)testRuntimeJavaScriptContainsExpectedEntrypoints {
  NSString *script = [ALNLive runtimeJavaScript];

  XCTAssertTrue([script containsString:@"window.ArlenLive"]);
  XCTAssertTrue([script containsString:@"data-arlen-live"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-target"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-swap"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-component"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-event"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-stream"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-src"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-poll"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-lazy"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-defer"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-upload-progress"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-key"]);
  XCTAssertTrue([script containsString:@"data-arlen-live-empty"]);
  XCTAssertTrue([script containsString:@"arlen:live:backpressure"]);
  XCTAssertTrue([script containsString:@"arlen:live:auth-expired"]);
  XCTAssertTrue([script containsString:@"application/vnd.arlen.live+json"]);
}

@end
