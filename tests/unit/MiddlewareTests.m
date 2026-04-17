#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <openssl/hmac.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSessionMiddleware.h"
#import "../shared/ALNWebTestSupport.h"

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

- (id)submitEcho:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"name" : [self stringParamForName:@"name"] ?: @"",
    @"csrf" : [self stringParamForName:@"csrf_token"] ?: @"",
    @"all_params" : [self params] ?: @{},
  };
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

- (NSDictionary *)sessionAndCSRFConfig {
  return @{
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
  };
}

- (ALNApplication *)securityApplicationWithConfig:(NSDictionary *)config
                                       submitPath:(NSString *)submitPath
                                       submitName:(NSString *)submitName
                                     submitAction:(NSString *)submitAction {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config ?: @{}];
  [app registerRouteMethod:@"GET"
                      path:@"/form"
                      name:@"form"
           controllerClass:[MiddlewareFormController class]
                    action:@"form"];
  [app registerRouteMethod:@"POST"
                      path:submitPath ?: @"/submit"
                      name:submitName ?: @"submit"
           controllerClass:[MiddlewareFormController class]
                    action:submitAction ?: @"submit"];
  return app;
}

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

- (ALNResponse *)dispatchPolicyRequestForApp:(ALNApplication *)app
                                        path:(NSString *)path
                               remoteAddress:(NSString *)remoteAddress
                                     headers:(NSDictionary *)headers {
  ALNRequest *request = [self requestWithMethod:@"GET"
                                           path:path ?: @"/admin"
                                        headers:headers ?: @{}];
  request.remoteAddress = remoteAddress ?: @"";
  return [app dispatchRequest:request];
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return ALNTestRequestWithMethod(method, path, queryString, headers, body);
}

- (NSDictionary *)jsonFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  NSDictionary *json = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  XCTAssertNotNil(json);
  return json ?: @{};
}

- (NSString *)cookiePairFromSetCookie:(NSString *)setCookie {
  return ALNTestCookiePairFromSetCookie(setCookie);
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

- (ALNApplication *)routePolicyApplicationWithSecurity:(NSDictionary *)security
                                                 route:(NSString *)routePath
                                              policies:(NSArray *)policies {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"security" : security ?: @{},
  }];
  [app registerRouteMethod:@"GET"
                      path:routePath ?: @"/admin"
                      name:@"admin_ping"
                   formats:nil
           controllerClass:[MiddlewareFormController class]
               guardAction:nil
                    action:@"ping"
                  policies:policies];
  return app;
}

- (void)testRoutePolicySourceIPAllowlistAllowsDirectPeer {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"sourceIPAllowlist" : @[ @"127.0.0.1/32", @"2001:db8::/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"127.0.0.1"
                                                    headers:@{}];
  ALNAssertResponseStatus(response, 200);
  XCTAssertEqualObjects(@"pong\n", ALNTestStringFromResponse(response));
}

- (void)testRoutePolicySourceIPAllowlistDeniesDirectPeerOutsideCIDR {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"sourceIPAllowlist" : @[ @"10.0.0.0/8" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"203.0.113.10"
                                                    headers:@{}];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRoutePolicyTrustedProxyUsesForwardedClientIP {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"203.0.113.10/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"127.0.0.1"
                                                    headers:@{
                                                      @"Forwarded" : @"for=203.0.113.10;proto=https",
                                                    }];
  ALNAssertResponseStatus(response, 200);
}

- (void)testRoutePolicyIgnoresSpoofedXForwardedForFromUntrustedPeer {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"203.0.113.10/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"198.51.100.20"
                                                    headers:@{
                                                      @"X-Forwarded-For" : @"203.0.113.10",
                                                    }];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRouteSidePolicyAttachmentProtectsNamedRoute {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"sourceIPAllowlist" : @[ @"192.0.2.10/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security
                                                          route:@"/private"
                                                       policies:@[ @"admin" ]];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *allowed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/private"
                                             remoteAddress:@"192.0.2.10"
                                                   headers:@{}];
  ALNAssertResponseStatus(allowed, 200);
  ALNResponse *denied = [self dispatchPolicyRequestForApp:app
                                                     path:@"/private"
                                            remoteAddress:@"192.0.2.11"
                                                  headers:@{}];
  ALNAssertResponseStatus(denied, 403);
}

- (void)testRoutePolicyRequireAuthDeniesUnauthenticatedRequest {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"requireAuth" : @(YES),
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"127.0.0.1"
                                                    headers:@{}];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"authentication_required", [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRoutePolicyConfigRejectsInvalidCIDRAndUnsupportedFields {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"security" : @{
      @"trustedProxies" : @[ @"not-a-cidr" ],
      @"routePolicies" : @{
        @"admin" : @{
          @"pathPrefixes" : @[ @"/admin" ],
          @"sourceIPAllowlist" : @[ @"10.0.0.0/99" ],
          @"trustedProxyHeaders" : @(YES),
        }
      }
    }
  }];
  NSError *error = nil;
  XCTAssertFalse([app startWithError:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(@"invalid_route_policy_config", error.userInfo[@"reason"]);
  NSArray *details = [error.userInfo[@"details"] isKindOfClass:[NSArray class]] ? error.userInfo[@"details"] : @[];
  XCTAssertTrue([details count] >= 3);
}

- (void)testRoutePolicyStartRejectsUnknownRouteSidePolicy {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{},
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security
                                                          route:@"/private"
                                                       policies:@[ @"missing_admin_policy" ]];

  NSError *error = nil;
  XCTAssertFalse([app startWithError:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(@"invalid_route_policy_references", error.userInfo[@"reason"]);
  NSArray *details = [error.userInfo[@"details"] isKindOfClass:[NSArray class]] ? error.userInfo[@"details"] : @[];
  XCTAssertEqual((NSUInteger)1, [details count]);
  XCTAssertEqualObjects(@"unknown_route_policy", details[0][@"code"]);
  XCTAssertEqualObjects(@"missing_admin_policy", details[0][@"policy"]);
}

- (void)testSessionAndCSRFMiddlewareAllowValidUnsafeRequest {
  ALNApplication *app = [self securityApplicationWithConfig:[self sessionAndCSRFConfig]
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  ALNAssertResponseStatus(formResponse, 200);
  NSString *setCookie = [formResponse headerForName:@"Set-Cookie"];
  XCTAssertTrue([setCookie containsString:@"arlen_session="]);
  [harness recycleCookiesFromResponse:formResponse];
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  XCTAssertTrue([token length] > 0);

  ALNResponse *submitResponse = [harness dispatchMethod:@"POST"
                                                   path:@"/submit"
                                            queryString:@""
                                                headers:@{ @"x-csrf-token" : token ?: @"" }
                                                   body:nil];
  ALNAssertResponseStatus(submitResponse, 200);
  XCTAssertEqualObjects(@"submitted\n", ALNTestStringFromResponse(submitResponse));
}

- (void)testCSRFMiddlewareRejectsMissingToken {
  ALNApplication *app = [self securityApplicationWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
    },
    @"csrf" : @{ @"enabled" : @(YES) }
  }
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  [harness recycleCookiesFromResponse:formResponse];
  ALNResponse *submitResponse = [harness dispatchMethod:@"POST" path:@"/submit"];
  ALNAssertResponseStatus(submitResponse, 403);
}

- (void)testSessionMiddlewareRejectsTamperedCookie {
  ALNApplication *app = [self securityApplicationWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
    },
    @"csrf" : @{ @"enabled" : @(YES) }
  }
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  NSString *setCookie = [formResponse headerForName:@"Set-Cookie"];
  NSString *cookiePair = [self cookiePairFromSetCookie:setCookie];
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  XCTAssertTrue([token length] > 0);

  NSMutableString *tamperedCookie = [cookiePair mutableCopy];
  NSRange equalsRange = [tamperedCookie rangeOfString:@"="];
  NSUInteger tamperIndex =
      (equalsRange.location != NSNotFound && equalsRange.location + 1 < [tamperedCookie length])
          ? (equalsRange.location + 1)
          : NSNotFound;
  if (tamperIndex != NSNotFound) {
    unichar current = [tamperedCookie characterAtIndex:tamperIndex];
    unichar replacement = (current == 'a') ? 'b' : 'a';
    [tamperedCookie replaceCharactersInRange:NSMakeRange(tamperIndex, 1)
                                  withString:[NSString stringWithFormat:@"%C", replacement]];
  }

  [harness resetRecycledState];
  ALNResponse *submitResponse = [harness dispatchMethod:@"POST"
                                                   path:@"/submit"
                                            queryString:@""
                                                headers:@{
                                                  @"cookie" : tamperedCookie ?: @"",
                                                  @"x-csrf-token" : token ?: @"",
                                                }
                                                   body:nil];
  ALNAssertResponseStatus(submitResponse, 403);
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
  ALNApplication *app = [self securityApplicationWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
    },
    @"csrf" : @{ @"enabled" : @(YES) }
  }
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  [harness recycleCookiesFromResponse:formResponse];
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  XCTAssertTrue([token length] > 0);

  NSString *queryString = [NSString stringWithFormat:@"csrf_token=%@", token];
  ALNResponse *submitResponse = [harness dispatchMethod:@"POST"
                                                   path:@"/submit"
                                            queryString:queryString
                                                headers:@{}
                                                   body:nil];
  ALNAssertResponseStatus(submitResponse, 403);
}

- (void)testCSRFMiddlewareAllowsUnsafeFormBodyToken {
  ALNApplication *app = [self securityApplicationWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
    },
    @"csrf" : @{ @"enabled" : @(YES) }
  }
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  [harness recycleCookiesFromResponse:formResponse];
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  NSData *body =
      [[NSString stringWithFormat:@"csrf_token=%@", token] dataUsingEncoding:NSUTF8StringEncoding];

  ALNResponse *submitResponse = [harness dispatchMethod:@"POST"
                                                   path:@"/submit"
                                            queryString:@""
                                                headers:@{
                                                  @"content-type" :
                                                      @"application/x-www-form-urlencoded",
                                                }
                                                   body:body];
  ALNAssertResponseStatus(submitResponse, 200);
}

- (void)testControllerHelpersExposeURLFormBodyParametersAfterCSRFSucceeds {
  ALNApplication *app = [self securityApplicationWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
    },
    @"csrf" : @{ @"enabled" : @(YES) }
  }
                                                 submitPath:@"/submit-echo"
                                                 submitName:@"submit_echo"
                                               submitAction:@"submitEcho"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  [harness recycleCookiesFromResponse:formResponse];
  NSDictionary *formJSON = [self jsonFromResponse:formResponse];
  NSString *token = formJSON[@"csrf"];
  NSData *body =
      [[NSString stringWithFormat:@"csrf_token=%@&name=Peggy", token ?: @""]
          dataUsingEncoding:NSUTF8StringEncoding];

  ALNResponse *submitResponse = [harness dispatchMethod:@"POST"
                                                   path:@"/submit-echo"
                                            queryString:@""
                                                headers:@{
                                                  @"content-type" :
                                                      @"application/x-www-form-urlencoded",
                                                }
                                                   body:body];
  ALNAssertResponseStatus(submitResponse, 200);
  NSDictionary *payload = [self jsonFromResponse:submitResponse];
  XCTAssertEqualObjects(@"Peggy", payload[@"name"]);
  XCTAssertEqualObjects(token, payload[@"csrf"]);
  NSDictionary *allParams = [payload[@"all_params"] isKindOfClass:[NSDictionary class]]
                                ? payload[@"all_params"]
                                : @{};
  XCTAssertEqualObjects(@"Peggy", allParams[@"name"]);
  XCTAssertEqualObjects(token, allParams[@"csrf_token"]);
}

- (void)testRateLimitMiddlewareRejectsAfterLimit {
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"rateLimit" : @{
      @"enabled" : @(YES),
      @"requests" : @(1),
      @"windowSeconds" : @(60),
    }
  }
                                                     routeMethod:@"GET"
                                                            path:@"/ping"
                                                       routeName:@"ping"
                                                 controllerClass:[MiddlewareFormController class]
                                                          action:@"ping"
                                                     middlewares:nil];

  ALNResponse *first = [harness dispatchMethod:@"GET" path:@"/ping"];
  ALNAssertResponseStatus(first, 200);

  ALNResponse *second = [harness dispatchMethod:@"GET" path:@"/ping"];
  ALNAssertResponseStatus(second, 429);
  XCTAssertNotNil([second headerForName:@"Retry-After"]);
}

- (void)testSecurityHeadersAreAppliedByDefault {
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
  }
                                                     routeMethod:@"GET"
                                                            path:@"/ping"
                                                       routeName:@"ping"
                                                 controllerClass:[MiddlewareFormController class]
                                                          action:@"ping"
                                                     middlewares:nil];

  ALNResponse *response = [harness dispatchMethod:@"GET" path:@"/ping"];
  ALNAssertResponseHeaderEquals(response, @"X-Content-Type-Options", @"nosniff");
  ALNAssertResponseHeaderEquals(response, @"X-Frame-Options", @"SAMEORIGIN");
  ALNAssertResponseHeaderEquals(response, @"Content-Security-Policy", @"default-src 'self'");
}

@end
