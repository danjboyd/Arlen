#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface MiddlewareFormController : ALNController
@end

@implementation MiddlewareFormController

- (id)form:(ALNContext *)ctx {
  (void)ctx;
  NSString *token = [self csrfToken] ?: @"";
  return @{ @"csrf" : token };
}

- (id)submit:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"submitted\n"];
  return nil;
}

- (id)ping:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"pong\n"];
  return nil;
}

@end

@interface MiddlewareTests : XCTestCase
@end

@implementation MiddlewareTests

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                          headers:(NSDictionary *)headers {
  return [[ALNRequest alloc] initWithMethod:method
                                      path:path
                               queryString:@""
                                   headers:headers ?: @{}
                                      body:[NSData data]];
}

- (NSDictionary *)jsonFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(json);
  return json ?: @{};
}

- (NSString *)cookiePairFromSetCookie:(NSString *)setCookie {
  NSArray *parts = [setCookie componentsSeparatedByString:@";"];
  if ([parts count] == 0) {
    return @"";
  }
  return [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)testSessionAndCSRFMiddlewareAllowValidUnsafeRequest {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value",
      @"cookieName" : @"arlen_session",
      @"maxAgeSeconds" : @(600),
      @"secure" : @(NO),
      @"sameSite" : @"Lax",
    },
    @"csrf" : @{
      @"enabled" : @(YES),
      @"headerName" : @"x-csrf-token",
      @"queryParamName" : @"csrf_token",
    }
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/form"
                      name:@"form"
           controllerClass:[MiddlewareFormController class]
                    action:@"form"];
  [app registerRouteMethod:@"POST"
                      path:@"/submit"
                      name:@"submit"
           controllerClass:[MiddlewareFormController class]
                    action:@"submit"];

  ALNResponse *formResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/form" headers:@{}]];
  XCTAssertEqual((NSInteger)200, formResponse.statusCode);
  NSString *setCookie = [formResponse headerForName:@"Set-Cookie"];
  XCTAssertTrue([setCookie containsString:@"arlen_session="]);
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  XCTAssertTrue([token length] > 0);

  NSString *cookiePair = [self cookiePairFromSetCookie:setCookie];
  ALNResponse *submitResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/submit"
                                           headers:@{
                                             @"cookie" : cookiePair,
                                             @"x-csrf-token" : token,
                                           }]];
  XCTAssertEqual((NSInteger)200, submitResponse.statusCode);
  NSString *body = [[NSString alloc] initWithData:submitResponse.bodyData
                                         encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(@"submitted\n", body);
}

- (void)testCSRFMiddlewareRejectsMissingToken {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value",
    },
    @"csrf" : @{ @"enabled" : @(YES) }
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/form"
                      name:@"form"
           controllerClass:[MiddlewareFormController class]
                    action:@"form"];
  [app registerRouteMethod:@"POST"
                      path:@"/submit"
                      name:@"submit"
           controllerClass:[MiddlewareFormController class]
                    action:@"submit"];

  ALNResponse *formResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/form" headers:@{}]];
  NSString *cookiePair = [self cookiePairFromSetCookie:[formResponse headerForName:@"Set-Cookie"]];
  ALNResponse *submitResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/submit"
                                           headers:@{ @"cookie" : cookiePair }]];
  XCTAssertEqual((NSInteger)403, submitResponse.statusCode);
}

- (void)testRateLimitMiddlewareRejectsAfterLimit {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"rateLimit" : @{
      @"enabled" : @(YES),
      @"requests" : @(1),
      @"windowSeconds" : @(60),
    }
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/ping"
                      name:@"ping"
           controllerClass:[MiddlewareFormController class]
                    action:@"ping"];

  ALNResponse *first = [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/ping" headers:@{}]];
  XCTAssertEqual((NSInteger)200, first.statusCode);

  ALNResponse *second = [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/ping" headers:@{}]];
  XCTAssertEqual((NSInteger)429, second.statusCode);
  XCTAssertNotNil([second headerForName:@"Retry-After"]);
}

- (void)testSecurityHeadersAreAppliedByDefault {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/ping"
                      name:@"ping"
           controllerClass:[MiddlewareFormController class]
                    action:@"ping"];

  ALNResponse *response =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/ping" headers:@{}]];
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
  XCTAssertEqualObjects(@"SAMEORIGIN", [response headerForName:@"X-Frame-Options"]);
  XCTAssertEqualObjects(@"default-src 'self'", [response headerForName:@"Content-Security-Policy"]);
}

@end
