#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNLive.h"
#import "../shared/ALNWebTestSupport.h"

@interface LiveRuntimeOverrideController : ALNController
@end

@implementation LiveRuntimeOverrideController

- (id)runtime:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"override-runtime\n"];
  return nil;
}

@end

@interface LiveRuntimeTests : XCTestCase
@end

@implementation LiveRuntimeTests

- (ALNApplication *)freshApplication {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
  }];
}

- (void)testBuiltInLiveRuntimeServesJavaScript {
  ALNApplication *app = [self freshApplication];

  ALNResponse *response = [app dispatchRequest:ALNTestRequestWithMethod(@"GET",
                                                                        @"/arlen/live.js",
                                                                        @"",
                                                                        @{},
                                                                        nil)];

  ALNAssertResponseStatus(response, 200);
  ALNAssertResponseContentType(response, @"application/javascript");
  ALNAssertResponseBodyContains(response, @"window.ArlenLive");
  ALNAssertResponseBodyContains(response, @"data-arlen-live-stream");
}

- (void)testBuiltInLiveRuntimeSupportsHeadRequests {
  ALNApplication *app = [self freshApplication];

  ALNResponse *response = [app dispatchRequest:ALNTestRequestWithMethod(@"HEAD",
                                                                        @"/arlen/live.js",
                                                                        @"",
                                                                        @{},
                                                                        nil)];

  ALNAssertResponseStatus(response, 200);
  ALNAssertResponseContentType(response, @"application/javascript");
  XCTAssertEqual((NSUInteger)0, [response bodyLength]);
}

- (void)testApplicationRoutesOverrideBuiltInLiveRuntimePath {
  ALNApplication *app = [self freshApplication];
  [app registerRouteMethod:@"GET"
                      path:@"/arlen/live.js"
                      name:@"live_runtime_override"
           controllerClass:[LiveRuntimeOverrideController class]
                    action:@"runtime"];

  ALNResponse *response = [app dispatchRequest:ALNTestRequestWithMethod(@"GET",
                                                                        @"/arlen/live.js",
                                                                        @"",
                                                                        @{},
                                                                        nil)];

  ALNAssertResponseStatus(response, 200);
  ALNAssertResponseContentType(response, @"text/plain");
  XCTAssertEqualObjects(@"override-runtime\n", ALNTestStringFromResponse(response));
}

@end
