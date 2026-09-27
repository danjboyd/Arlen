#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRoute.h"

// GitHub issue 87: per-route request body limits.
@interface RouteBodyLimitController : ALNController
@end

@implementation RouteBodyLimitController
- (id)accept:(ALNContext *)ctx {
  return @{ @"uploads" : @(ctx.request.uploads.count) };
}
@end

@interface RouteBodyLimitTests : XCTestCase
@end

@implementation RouteBodyLimitTests

- (ALNApplication *)application {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logLevel" : @"error",
    @"requestLimits" : @{ @"maxBodyBytes" : @65536, @"maxMultipartFileBytes" : @65536 },
  }];
  [app registerRouteMethod:@"POST" path:@"/small" name:@"small" controllerClass:[RouteBodyLimitController class] action:@"accept"];
  ALNRoute *upload = [app registerRouteMethod:@"POST" path:@"/projects/:id/upload" name:@"upload"
                              controllerClass:[RouteBodyLimitController class] action:@"accept"];
  upload.maxBodyBytes = 26214400;
  ALNRoute *tiny = [app registerRouteMethod:@"POST" path:@"/tiny" name:@"tiny"
                            controllerClass:[RouteBodyLimitController class] action:@"accept"];
  tiny.maxBodyBytes = 16;
  return app;
}

- (NSData *)multipartWithFileOfLength:(NSUInteger)length {
  NSMutableData *body = [NSMutableData data];
  [body appendData:[@"--Aa\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"a.bin\"\r\n\r\n"
                       dataUsingEncoding:NSUTF8StringEncoding]];
  [body increaseLengthBy:length];
  [body appendData:[@"\r\n--Aa--\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  return body;
}

- (void)testRouteOverridesResolveBeforeDispatch {
  ALNApplication *app = [self application];
  XCTAssertEqual((NSUInteger)65536, [app maxBodyBytesForMethod:@"POST" path:@"/small"]);
  XCTAssertEqual((NSUInteger)26214400, [app maxBodyBytesForMethod:@"POST" path:@"/projects/7/upload"]);
  XCTAssertEqual((NSUInteger)26214400, [app maxBodyBytesForMethod:@"post" path:@"/projects/7/upload.json"]);
  XCTAssertEqual((NSUInteger)16, [app maxBodyBytesForMethod:@"POST" path:@"/tiny"]);
  // Unrouted paths and other methods keep the default.
  XCTAssertEqual((NSUInteger)65536, [app maxBodyBytesForMethod:@"PUT" path:@"/projects/7/upload"]);
  XCTAssertEqual((NSUInteger)65536, [app maxBodyBytesForMethod:@"POST" path:@"/nowhere"]);
  XCTAssertEqual((NSUInteger)26214400, [app largestRouteMaxBodyBytes]);

  ALNApplication *parent = [[ALNApplication alloc] initWithConfig:@{ @"environment" : @"test" }];
  XCTAssertEqual((NSUInteger)0, [parent largestRouteMaxBodyBytes]);
  XCTAssertTrue([parent mountApplication:app atPrefix:@"/files"]);
  XCTAssertEqual((NSUInteger)26214400, [parent maxBodyBytesForMethod:@"POST" path:@"/files/projects/7/upload"]);
  XCTAssertEqual((NSUInteger)26214400, [parent largestRouteMaxBodyBytes]);
}

- (void)testMultipartParsingUsesTheRouteBudget {
  ALNApplication *app = [self application];
  NSDictionary *headers = @{ @"content-type" : @"multipart/form-data; boundary=Aa" };
  NSData *twoMiB = [self multipartWithFileOfLength:2 * 1048576];
  ALNResponse *uploaded = [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"POST" path:@"/projects/7/upload"
                                                                      queryString:@"" headers:headers body:twoMiB]];
  XCTAssertEqual(200, uploaded.statusCode);
  ALNResponse *small = [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"POST" path:@"/small"
                                                                   queryString:@"" headers:headers body:twoMiB]];
  XCTAssertEqual(413, small.statusCode);
  NSDictionary *limits = [app requestLimitsForRequest:[[ALNRequest alloc] initWithMethod:@"POST" path:@"/small"
                                                                             queryString:@"" headers:headers body:twoMiB]];
  XCTAssertEqualObjects(@65536, limits[@"maxBodyBytes"]);
}

- (void)testPlistRoutesAcceptMaxBodyBytes {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logLevel" : @"error",
    @"routes" : @[ @{ @"method" : @"POST", @"path" : @"/docs", @"controller" : @"RouteBodyLimitController",
                      @"action" : @"accept", @"maxBodyBytes" : @"5242880" } ],
  }];
  NSError *error = nil;
  XCTAssertTrue([app startWithError:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)5242880, [app maxBodyBytesForMethod:@"POST" path:@"/docs"]);

  for (id bad in @[ @"0", @"lots", @-1 ]) {
    ALNApplication *invalid = [[ALNApplication alloc] initWithConfig:@{
      @"environment" : @"test",
      @"logLevel" : @"error",
      @"routes" : @[ @{ @"method" : @"POST", @"path" : @"/docs", @"controller" : @"RouteBodyLimitController",
                        @"action" : @"accept", @"maxBodyBytes" : bad } ],
    }];
    XCTAssertFalse([invalid startWithError:&error], @"%@", bad);
    XCTAssertTrue([[error.userInfo description] containsString:@"invalid_max_body_bytes"], @"%@", error);
  }
}

@end
