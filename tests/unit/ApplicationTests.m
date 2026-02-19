#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface AppHeaderMiddleware : NSObject <ALNMiddleware>
@end

@implementation AppHeaderMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  context.stash[@"middleware"] = @"yes";
  [context.response setHeader:@"X-Middleware" value:@"ran"];
  return YES;
}

@end

@interface AppHaltingMiddleware : NSObject <ALNMiddleware>
@end

@implementation AppHaltingMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  context.response.statusCode = 401;
  [context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [context.response setTextBody:@"blocked by middleware\n"];
  context.response.committed = YES;
  return NO;
}

@end

@interface AppJSONController : ALNController
@end

@implementation AppJSONController

+ (NSJSONWritingOptions)jsonWritingOptions {
  return NSJSONWritingPrettyPrinted;
}

- (id)dict:(ALNContext *)ctx {
  return @{
    @"ok" : @(YES),
    @"middleware" : ctx.stash[@"middleware"] ?: @"",
  };
}

- (id)array:(ALNContext *)ctx {
  (void)ctx;
  return @[ @"a", @"b" ];
}

- (id)explicit:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL ok = [self renderJSON:@{ @"explicit" : @(YES) } error:&error];
  if (!ok || error != nil) {
    [self setStatus:500];
    [self renderText:@"explicit render failed\n"];
  }
  return @{ @"ignored" : @(YES) };
}

@end

@interface ApplicationTests : XCTestCase
@end

@implementation ApplicationTests

- (ALNApplication *)buildAppWithHaltingMiddleware:(BOOL)useHalting {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"host" : @"127.0.0.1",
    @"port" : @(3000),
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/dict"
                      name:@"dict"
           controllerClass:[AppJSONController class]
                    action:@"dict"];
  [app registerRouteMethod:@"GET"
                      path:@"/array"
                      name:@"array"
           controllerClass:[AppJSONController class]
                    action:@"array"];
  [app registerRouteMethod:@"GET"
                      path:@"/explicit"
                      name:@"explicit"
           controllerClass:[AppJSONController class]
                    action:@"explicit"];

  if (useHalting) {
    [app addMiddleware:[[AppHaltingMiddleware alloc] init]];
  } else {
    [app addMiddleware:[[AppHeaderMiddleware alloc] init]];
  }
  return app;
}

- (ALNRequest *)requestForPath:(NSString *)path {
  return [[ALNRequest alloc] initWithMethod:@"GET"
                                      path:path
                               queryString:@""
                                   headers:@{}
                                      body:[NSData data]];
}

- (void)testImplicitJSONForDictionaryReturn {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/dict"]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects(@"application/json; charset=utf-8",
                        [response headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"ran", [response headerForName:@"X-Middleware"]);

  NSString *body = [[NSString alloc] initWithData:response.bodyData
                                         encoding:NSUTF8StringEncoding];
  XCTAssertTrue([body containsString:@"\"ok\""]);
  XCTAssertTrue([body containsString:@"middleware"]);
  XCTAssertTrue([body containsString:@"yes"]);
}

- (void)testImplicitJSONForArrayReturn {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/array"]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects(@"application/json; charset=utf-8",
                        [response headerForName:@"Content-Type"]);
}

- (void)testExplicitJSONTakesPrecedence {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/explicit"]];
  NSString *body = [[NSString alloc] initWithData:response.bodyData
                                         encoding:NSUTF8StringEncoding];
  XCTAssertTrue([body containsString:@"\"explicit\""]);
  XCTAssertFalse([body containsString:@"ignored"]);
}

- (void)testMiddlewareCanShortCircuitRequest {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:YES];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/dict"]];
  XCTAssertEqual((NSInteger)401, response.statusCode);
  NSString *body = [[NSString alloc] initWithData:response.bodyData
                                         encoding:NSUTF8StringEncoding];
  XCTAssertTrue([body containsString:@"blocked by middleware"]);
}

- (void)testUnknownRouteReturns404 {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/missing"]];
  XCTAssertEqual((NSInteger)404, response.statusCode);
}

@end
