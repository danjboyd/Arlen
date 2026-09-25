#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "../shared/ALNWebTestSupport.h"

@interface SecurityHeadersBaselineController : ALNController
@end

@implementation SecurityHeadersBaselineController

- (id)plain:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"plain\n"];
  return nil;
}

- (id)customPolicy:(ALNContext *)ctx {
  [ctx.response setHeader:@"Content-Security-Policy" value:@"default-src 'none'"];
  [self renderText:@"custom\n"];
  return nil;
}

@end

@interface SecurityHeadersBaselineTests : XCTestCase
@end

@implementation SecurityHeadersBaselineTests

- (ALNApplication *)applicationWithConfig:(NSDictionary *)extra {
  NSMutableDictionary *config = [@{ @"environment" : @"test", @"logFormat" : @"json" } mutableCopy];
  [config addEntriesFromDictionary:extra ?: @{}];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  [app registerRouteMethod:@"GET"
                      path:@"/plain"
                      name:@"plain"
           controllerClass:[SecurityHeadersBaselineController class]
                    action:@"plain"];
  [app registerRouteMethod:@"GET"
                      path:@"/custom"
                      name:@"custom"
           controllerClass:[SecurityHeadersBaselineController class]
                    action:@"customPolicy"];
  return app;
}

- (ALNResponse *)app:(ALNApplication *)app path:(NSString *)path accept:(NSString *)accept {
  return [app dispatchRequest:ALNTestRequestWithMethod(@"GET", path, @"", @{ @"accept" : accept ?: @"text/html" }, nil)];
}

- (void)assertBaseline:(ALNResponse *)response csp:(NSString *)csp label:(NSString *)label {
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"], @"%@", label);
  XCTAssertEqualObjects(@"SAMEORIGIN", [response headerForName:@"X-Frame-Options"], @"%@", label);
  XCTAssertEqualObjects(@"strict-origin-when-cross-origin", [response headerForName:@"Referrer-Policy"], @"%@", label);
  XCTAssertEqualObjects(@"same-origin", [response headerForName:@"Cross-Origin-Opener-Policy"], @"%@", label);
  XCTAssertEqualObjects(@"same-site", [response headerForName:@"Cross-Origin-Resource-Policy"], @"%@", label);
  XCTAssertEqualObjects(@"none", [response headerForName:@"X-Permitted-Cross-Domain-Policies"], @"%@", label);
  XCTAssertEqualObjects(csp, [response headerForName:@"Content-Security-Policy"], @"%@", label);
}

- (void)testRouteMissAndBuiltInResponsesCarryBaselineHeaders {
  ALNApplication *app = [self applicationWithConfig:nil];
  NSString *csp = @"default-src 'self'";
  ALNResponse *miss = [self app:app path:@"/definitely/missing" accept:@"text/html"];
  XCTAssertEqual((NSInteger)404, miss.statusCode);
  [self assertBaseline:miss csp:csp label:@"html 404"];
  ALNResponse *jsonMiss = [self app:app path:@"/definitely/missing" accept:@"application/json"];
  XCTAssertEqual((NSInteger)404, jsonMiss.statusCode);
  [self assertBaseline:jsonMiss csp:csp label:@"json 404"];
  for (NSString *path in @[ @"/healthz", @"/openapi.json", @"/openapi", @"/arlen/live.js" ]) {
    ALNResponse *builtIn = [self app:app path:path accept:@"text/html"];
    [self assertBaseline:builtIn csp:csp label:path];
  }
  [self assertBaseline:[self app:app path:@"/plain" accept:@"text/html"] csp:csp label:@"routed"];
}

- (void)testConfiguredPolicyAndControllerOverrides {
  ALNApplication *app = [self applicationWithConfig:@{
    @"securityHeaders" : @{ @"contentSecurityPolicy" : @"default-src 'self'; img-src 'self' data:" },
  }];
  NSString *csp = @"default-src 'self'; img-src 'self' data:";
  XCTAssertEqualObjects(csp, app.baselineSecurityHeaders[@"Content-Security-Policy"]);
  XCTAssertEqual((NSUInteger)7, [app.baselineSecurityHeaders count]);
  [self assertBaseline:[self app:app path:@"/missing" accept:@"text/html"] csp:csp label:@"custom 404"];
  [self assertBaseline:[self app:app path:@"/healthz" accept:@"text/html"] csp:csp label:@"custom healthz"];
  ALNResponse *custom = [self app:app path:@"/custom" accept:@"text/html"];
  XCTAssertEqualObjects(@"default-src 'none'", [custom headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [custom headerForName:@"X-Content-Type-Options"]);
}

- (void)testDisabledSecurityHeadersStayOffEverywhere {
  ALNApplication *app = [self applicationWithConfig:@{ @"securityHeaders" : @{ @"enabled" : @(NO) } }];
  XCTAssertEqualObjects(@{}, app.baselineSecurityHeaders);
  for (NSString *path in @[ @"/missing", @"/healthz", @"/openapi.json", @"/plain" ]) {
    ALNResponse *response = [self app:app path:path accept:@"text/html"];
    XCTAssertNil([response headerForName:@"X-Content-Type-Options"], @"%@", path);
    XCTAssertNil([response headerForName:@"Content-Security-Policy"], @"%@", path);
  }
}

@end
