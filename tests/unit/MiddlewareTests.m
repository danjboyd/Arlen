#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <openssl/hmac.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSessionMiddleware.h"

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

@interface ALNSessionMiddleware (MiddlewareTestsAccess)
- (NSString *)encodeSessionDictionary:(NSDictionary *)session;
- (NSMutableDictionary *)decodeSessionToken:(NSString *)token requiresRefresh:(BOOL *)requiresRefresh;
@end

@implementation MiddlewareTests

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers {
  return [[ALNRequest alloc] initWithMethod:method
                                      path:path
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:[NSData data]];
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                          headers:(NSDictionary *)headers {
  return [self requestWithMethod:method
                            path:path
                     queryString:@""
                         headers:headers];
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return [[ALNRequest alloc] initWithMethod:method
                                      path:path
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:body ?: [NSData data]];
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

- (NSString *)base64URLFromData:(NSData *)data {
  NSString *base64 = [data base64EncodedStringWithOptions:0];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return base64;
}

- (NSData *)hmacSHA256:(NSData *)input key:(NSData *)key {
  if ([input length] == 0 || [key length] == 0) {
    return nil;
  }
  unsigned int digestLength = 0;
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned char *result = HMAC(EVP_sha256(),
                               [key bytes],
                               (int)[key length],
                               [input bytes],
                               (size_t)[input length],
                               digest,
                               &digestLength);
  if (result == NULL || digestLength == 0) {
    return nil;
  }
  return [NSData dataWithBytes:digest length:(NSUInteger)digestLength];
}

- (NSString *)legacySessionTokenForSession:(NSDictionary *)session
                                    secret:(NSString *)secret
                             maxAgeSeconds:(NSUInteger)maxAgeSeconds {
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSDictionary *payload = @{
    @"iat" : @((NSInteger)now),
    @"exp" : @((NSInteger)(now + (NSTimeInterval)maxAgeSeconds)),
    @"data" : session ?: @{},
  };
  NSData *plaintext = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
  NSString *payloadPart = [self base64URLFromData:plaintext];
  NSString *prefix = [NSString stringWithFormat:@"v2.%@", payloadPart];
  NSData *signature =
      [self hmacSHA256:[prefix dataUsingEncoding:NSUTF8StringEncoding]
                   key:[secret dataUsingEncoding:NSUTF8StringEncoding]];
  return [NSString stringWithFormat:@"%@.%@", prefix, [self base64URLFromData:signature]];
}

- (void)testSessionAndCSRFMiddlewareAllowValidUnsafeRequest {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
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
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
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

- (void)testSessionMiddlewareRejectsTamperedCookie {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
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
  NSString *setCookie = [formResponse headerForName:@"Set-Cookie"];
  NSString *cookiePair = [self cookiePairFromSetCookie:setCookie];
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  XCTAssertTrue([token length] > 0);

  NSMutableString *tamperedCookie = [cookiePair mutableCopy];
  if ([tamperedCookie length] > 2) {
    unichar last = [tamperedCookie characterAtIndex:[tamperedCookie length] - 1];
    unichar replacement = (last == 'a') ? 'b' : 'a';
    [tamperedCookie replaceCharactersInRange:NSMakeRange([tamperedCookie length] - 1, 1)
                                  withString:[NSString stringWithFormat:@"%C", replacement]];
  }

  ALNResponse *submitResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/submit"
                                           headers:@{
                                             @"cookie" : tamperedCookie ?: @"",
                                             @"x-csrf-token" : token,
                                           }]];
  XCTAssertEqual((NSInteger)403, submitResponse.statusCode);
}

- (void)testSessionMiddlewareEncryptsCookiePayloadAndRoundTrips {
  NSString *secret = @"unit-test-secret-value-0123456789abcdef";
  ALNSessionMiddleware *middleware = [[ALNSessionMiddleware alloc] initWithSecret:secret
                                                                       cookieName:@"arlen_session"
                                                                    maxAgeSeconds:600
                                                                           secure:NO
                                                                         sameSite:@"Lax"];

  NSString *token = [middleware encodeSessionDictionary:@{
    @"user" : @"alice",
    @"role" : @"admin",
  }];
  XCTAssertTrue([token length] > 0);
  XCTAssertFalse([token containsString:@"alice"]);

  NSArray *parts = [token componentsSeparatedByString:@"."];
  XCTAssertEqual((NSUInteger)4, [parts count]);
  XCTAssertEqualObjects(@"v3", parts[0]);

  BOOL requiresRefresh = YES;
  NSMutableDictionary *decoded = [middleware decodeSessionToken:token requiresRefresh:&requiresRefresh];
  XCTAssertFalse(requiresRefresh);
  XCTAssertEqualObjects(@"alice", decoded[@"user"]);
  XCTAssertEqualObjects(@"admin", decoded[@"role"]);
}

- (void)testSessionMiddlewareDecodesLegacySignedCookiesAndMarksRefresh {
  NSString *secret = @"unit-test-secret-value-0123456789abcdef";
  ALNSessionMiddleware *middleware = [[ALNSessionMiddleware alloc] initWithSecret:secret
                                                                       cookieName:@"arlen_session"
                                                                    maxAgeSeconds:600
                                                                           secure:NO
                                                                         sameSite:@"Lax"];
  NSString *legacyToken = [self legacySessionTokenForSession:@{ @"user" : @"legacy" }
                                                      secret:secret
                                               maxAgeSeconds:600];

  BOOL requiresRefresh = NO;
  NSMutableDictionary *decoded = [middleware decodeSessionToken:legacyToken requiresRefresh:&requiresRefresh];
  XCTAssertTrue(requiresRefresh);
  XCTAssertEqualObjects(@"legacy", decoded[@"user"]);
}

- (void)testCSRFMiddlewareRejectsUnsafeQueryTokenByDefault {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
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
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  XCTAssertTrue([token length] > 0);

  NSString *queryString = [NSString stringWithFormat:@"csrf_token=%@", token];
  ALNResponse *submitResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/submit"
                                       queryString:queryString
                                           headers:@{ @"cookie" : cookiePair ?: @"" }]];
  XCTAssertEqual((NSInteger)403, submitResponse.statusCode);
}

- (void)testCSRFMiddlewareAllowsUnsafeFormBodyToken {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
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
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  NSData *body =
      [[NSString stringWithFormat:@"csrf_token=%@", token] dataUsingEncoding:NSUTF8StringEncoding];

  ALNResponse *submitResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/submit"
                                       queryString:@""
                                           headers:@{
                                             @"cookie" : cookiePair ?: @"",
                                             @"content-type" : @"application/x-www-form-urlencoded",
                                           }
                                              body:body]];
  XCTAssertEqual((NSInteger)200, submitResponse.statusCode);
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
