#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <openssl/hmac.h>

#import "ALNApplication.h"
#import "ALNClientAddressInternal.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNRateLimitMiddleware.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRoutePolicyMiddleware.h"
#import "ALNSecurityPrimitives.h"
#import "ALNSessionMiddleware.h"
#import "../shared/ALNWebTestSupport.h"

static NSUInteger MiddlewarePingInvocationCount = 0;

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
  MiddlewarePingInvocationCount += 1;
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

- (void)testRoutePolicyTrustedProxyUsesForwardedClientIPWhenConfigured {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"forwardedClientIPHeader" : @"Forwarded",
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

- (void)testRoutePolicyTrustedProxyUsesXForwardedForClientIP {
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
                                                      @"X-Forwarded-For" : @"198.51.100.2, 203.0.113.10",
                                                    }];
  ALNAssertResponseStatus(response, 200);
}

// An appending proxy (nginx $proxy_add_x_forwarded_for) puts the real peer
// after whatever the client sent, so a client-chosen left-most value must not
// pass the allowlist.
- (void)testRoutePolicyIgnoresClientSuppliedLeftMostXForwardedForHop {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"10.0.0.0/8" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *spoofed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/admin"
                                             remoteAddress:@"127.0.0.1"
                                                   headers:@{
                                                     @"X-Forwarded-For" : @"10.1.1.1, 203.0.113.9",
                                                   }];
  ALNAssertResponseStatus(spoofed, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [spoofed headerForName:@"X-Arlen-Policy-Denial-Reason"]);

  // Hops through further trusted proxies are skipped from the right.
  NSMutableDictionary *chained = [security mutableCopy];
  chained[@"trustedProxies"] = @[ @"127.0.0.1/32", @"192.0.2.0/24" ];
  ALNApplication *chainedApp = [self routePolicyApplicationWithSecurity:chained route:@"/admin" policies:nil];
  XCTAssertTrue([chainedApp startWithError:NULL]);
  ALNResponse *viaLoadBalancer = [self dispatchPolicyRequestForApp:chainedApp
                                                              path:@"/admin"
                                                     remoteAddress:@"127.0.0.1"
                                                           headers:@{
                                                             @"X-Forwarded-For" : @"203.0.113.9, 10.1.1.1, 192.0.2.7",
                                                           }];
  ALNAssertResponseStatus(viaLoadBalancer, 200);
}

// A proxy that sets only X-Forwarded-For passes a client's Forwarded header
// through untouched, so Forwarded is not read unless configured.
- (void)testRoutePolicyIgnoresForwardedHeaderByDefault {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"10.0.0.0/8" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"127.0.0.1"
                                                    headers:@{
                                                      @"Forwarded" : @"for=10.1.1.1",
                                                      @"X-Forwarded-For" : @"203.0.113.9",
                                                    }];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRoutePolicyIPv6ForwardedClientIP {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"::1/128" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"2001:db8::/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *allowed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/admin"
                                             remoteAddress:@"::1"
                                                   headers:@{ @"X-Forwarded-For" : @"2001:db9::1, [2001:db8::42]:5000" }];
  ALNAssertResponseStatus(allowed, 200);

  ALNResponse *denied = [self dispatchPolicyRequestForApp:app
                                                     path:@"/admin"
                                            remoteAddress:@"::1"
                                                  headers:@{ @"X-Forwarded-For" : @"2001:db8::42, 2001:db9::1" }];
  ALNAssertResponseStatus(denied, 403);
}

// A dual-stack listener reports the IPv4 proxy as ::ffff:127.0.0.1.
- (void)testRoutePolicyTreatsIPv4MappedPeerAndHopsAsIPv4 {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"10.0.0.0/8" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *allowed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/admin"
                                             remoteAddress:@"::ffff:127.0.0.1"
                                                   headers:@{ @"X-Forwarded-For" : @"::FFFF:10.1.1.1" }];
  ALNAssertResponseStatus(allowed, 200);

  ALNResponse *denied = [self dispatchPolicyRequestForApp:app
                                                     path:@"/admin"
                                            remoteAddress:@"::ffff:127.0.0.1"
                                                  headers:@{ @"X-Forwarded-For" : @"10.1.1.1, ::ffff:203.0.113.9" }];
  ALNAssertResponseStatus(denied, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [denied headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRoutePolicyRejectsUnsupportedForwardedClientIPHeader {
  NSError *error = [ALNRoutePolicyMiddleware validateSecurityConfiguration:@{
    @"security" : @{ @"forwardedClientIPHeader" : @"X-Real-IP" }
  }];
  XCTAssertNotNil(error);
  NSArray *details = error.userInfo[@"details"];
  XCTAssertEqualObjects(@"security.forwardedClientIPHeader", [details firstObject][@"field"]);
  XCTAssertNil([ALNRoutePolicyMiddleware validateSecurityConfiguration:@{
    @"security" : @{ @"forwardedClientIPHeader" : @"forwarded" }
  }]);
}

- (void)testRoutePolicyIPv6CIDRAllowsAndDeniesDeterministically {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"sourceIPAllowlist" : @[ @"2001:db8::/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *allowed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/admin"
                                             remoteAddress:@"2001:db8::42"
                                                   headers:@{}];
  ALNAssertResponseStatus(allowed, 200);

  ALNResponse *denied = [self dispatchPolicyRequestForApp:app
                                                     path:@"/admin"
                                            remoteAddress:@"2001:db9::42"
                                                  headers:@{}];
  ALNAssertResponseStatus(denied, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [denied headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRoutePolicyDeniesMalformedForwardedClientFromTrustedProxy {
  NSDictionary *security = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"forwardedClientIPHeader" : @"Forwarded",
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
                                                      @"Forwarded" : @"for=not-an-ip;proto=https",
                                                    }];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"forwarded_client_unresolved",
                        [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);

  // An unreadable X-Forwarded-For hop where the client should be is not
  // replaced by the proxy's own (allowlisted) address.
  NSDictionary *xff = @{
    @"trustedProxies" : @[ @"127.0.0.1/32" ],
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"trustForwardedClientIP" : @(YES),
        @"sourceIPAllowlist" : @[ @"127.0.0.1/32", @"203.0.113.10/32" ],
      }
    }
  };
  ALNApplication *xffApp = [self routePolicyApplicationWithSecurity:xff route:@"/admin" policies:nil];
  XCTAssertTrue([xffApp startWithError:NULL]);
  ALNResponse *unreadable = [self dispatchPolicyRequestForApp:xffApp
                                                         path:@"/admin"
                                                remoteAddress:@"127.0.0.1"
                                                      headers:@{ @"X-Forwarded-For" : @"203.0.113.10, unknown" }];
  ALNAssertResponseStatus(unreadable, 403);
  XCTAssertEqualObjects(@"forwarded_client_unresolved",
                        [unreadable headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testRoutePolicyDeniesWhenDirectPeerCannotBeResolved {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"sourceIPAllowlist" : @[ @"127.0.0.1/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);

  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"not-an-ip"
                                                    headers:@{}];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"direct_peer_unresolved",
                        [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);
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

- (void)testRoutePolicyDenialPreventsControllerExecution {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"sourceIPAllowlist" : @[ @"127.0.0.1/32" ],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertTrue([app startWithError:NULL]);
  MiddlewarePingInvocationCount = 0;

  ALNResponse *denied = [self dispatchPolicyRequestForApp:app
                                                     path:@"/admin"
                                            remoteAddress:@"198.51.100.10"
                                                  headers:@{}];
  ALNAssertResponseStatus(denied, 403);
  XCTAssertEqual((NSUInteger)0, MiddlewarePingInvocationCount);

  ALNResponse *allowed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/admin"
                                             remoteAddress:@"127.0.0.1"
                                                   headers:@{}];
  ALNAssertResponseStatus(allowed, 200);
  XCTAssertEqual((NSUInteger)1, MiddlewarePingInvocationCount);
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

- (void)testRoutePolicyStringListValuesAreOneElementLists {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @"/admin",
        @"sourceIPAllowlist" : @"10.0.0.0/8",
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  NSError *error = nil;
  XCTAssertTrue([app startWithError:&error], @"%@", error);

  ALNResponse *denied = [self dispatchPolicyRequestForApp:app
                                                     path:@"/admin"
                                            remoteAddress:@"127.0.0.1"
                                                  headers:@{}];
  ALNAssertResponseStatus(denied, 403);
  XCTAssertEqualObjects(@"source_ip_denied", [denied headerForName:@"X-Arlen-Policy-Denial-Reason"]);

  ALNResponse *allowed = [self dispatchPolicyRequestForApp:app
                                                      path:@"/admin"
                                             remoteAddress:@"10.1.2.3"
                                                   headers:@{}];
  ALNAssertResponseStatus(allowed, 200);
}

- (void)testRoutePolicyConfigRejectsEmptyAndMistypedLists {
  NSArray<NSDictionary *> *cases = @[
    @{ @"field" : @"sourceIPAllowlist", @"value" : @[], @"code" : @"empty_list" },
    @{ @"field" : @"sourceIPAllowlist", @"value" : @[ @"  " ], @"code" : @"empty_list" },
    @{ @"field" : @"sourceIPAllowlist", @"value" : @"", @"code" : @"empty_list" },
    @{ @"field" : @"sourceIPAllowlist", @"value" : @{ @"cidr" : @"10.0.0.0/8" }, @"code" : @"invalid_type" },
    @{ @"field" : @"pathPrefixes", @"value" : @[], @"code" : @"empty_list" },
    @{ @"field" : @"pathPrefixes", @"value" : @(1), @"code" : @"invalid_type" },
  ];
  for (NSDictionary *testCase in cases) {
    NSMutableDictionary *policy = [@{
      @"pathPrefixes" : @[ @"/admin" ],
      @"sourceIPAllowlist" : @[ @"10.0.0.0/8" ],
    } mutableCopy];
    policy[testCase[@"field"]] = testCase[@"value"];
    NSError *error = [ALNRoutePolicyMiddleware validateSecurityConfiguration:@{
      @"security" : @{ @"routePolicies" : @{ @"admin" : policy } }
    }];
    XCTAssertNotNil(error, @"%@", testCase);
    XCTAssertEqualObjects(@"invalid_route_policy_config", error.userInfo[@"reason"], @"%@", testCase);
    NSString *field = [NSString stringWithFormat:@"security.routePolicies.admin.%@", testCase[@"field"]];
    BOOL found = NO;
    for (NSDictionary *detail in error.userInfo[@"details"]) {
      found = found || ([detail[@"field"] isEqualToString:field] && [detail[@"code"] isEqualToString:testCase[@"code"]]);
    }
    XCTAssertTrue(found, @"%@ -> %@", testCase, error.userInfo[@"details"]);

    ALNApplication *app = [self routePolicyApplicationWithSecurity:@{ @"routePolicies" : @{ @"admin" : policy } }
                                                             route:@"/admin"
                                                          policies:nil];
    XCTAssertFalse([app startWithError:NULL], @"%@", testCase);
  }
}

- (void)testRoutePolicyMiddlewareDeniesEmptyAllowlistEvenWithoutStartupValidation {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"pathPrefixes" : @[ @"/admin" ],
        @"sourceIPAllowlist" : @[],
      }
    }
  };
  ALNApplication *app = [self routePolicyApplicationWithSecurity:security route:@"/admin" policies:nil];
  XCTAssertFalse([app startWithError:NULL]);
  ALNResponse *response = [self dispatchPolicyRequestForApp:app
                                                       path:@"/admin"
                                              remoteAddress:@"127.0.0.1"
                                                    headers:@{}];
  ALNAssertResponseStatus(response, 403);
  XCTAssertEqualObjects(@"invalid_policy_config", [response headerForName:@"X-Arlen-Policy-Denial-Reason"]);
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

// GitHub issue 86: a cookieless request that never reads a CSRF token must not
// start a session. A Set-Cookie on such a reply (a service worker's fetch, say)
// replaced a signed-in browser's session and signed the user out.
- (void)testCSRFDoesNotStartASessionUntilATokenIsRead_Issue86 {
  ALNApplication *app = [self securityApplicationWithConfig:[self sessionAndCSRFConfig]
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  [app registerRouteMethod:@"GET" path:@"/plain" name:@"plain" controllerClass:[MiddlewareFormController class] action:@"submit"];
  [app registerRouteMethod:@"HEAD" path:@"/plain" name:@"plain_head" controllerClass:[MiddlewareFormController class] action:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];

  for (NSString *method in @[ @"GET", @"HEAD" ]) {
    ALNResponse *plain = [harness dispatchMethod:method path:@"/plain"];
    ALNAssertResponseStatus(plain, 200);
    XCTAssertNil([plain headerForName:@"Set-Cookie"], @"%@", method);
  }
  // Rejected unsafe requests do not mint a session either.
  ALNResponse *rejected = [harness dispatchMethod:@"POST" path:@"/submit"];
  ALNAssertResponseStatus(rejected, 403);
  XCTAssertNil([rejected headerForName:@"Set-Cookie"]);

  // A page that renders the token starts the session, and the token then works.
  ALNResponse *form = [harness dispatchMethod:@"GET" path:@"/form"];
  XCTAssertTrue([[form headerForName:@"Set-Cookie"] containsString:@"arlen_session="]);
  NSString *token = [self jsonFromResponse:form][@"csrf"];
  XCTAssertTrue([token length] > 0);
  [harness recycleCookiesFromResponse:form];
  // An established session keeps its token; reading it again does not rotate it.
  XCTAssertEqualObjects(token, [self jsonFromResponse:[harness dispatchMethod:@"GET" path:@"/form"]][@"csrf"]);
  ALNResponse *submitted = [harness dispatchMethod:@"POST"
                                              path:@"/submit"
                                       queryString:@""
                                           headers:@{ @"x-csrf-token" : token ?: @"" }
                                              body:nil];
  ALNAssertResponseStatus(submitted, 200);
}

- (void)testCSRFTokenIsNotMintedWhenCSRFIsDisabled_Issue86 {
  NSMutableDictionary *config = [[self sessionAndCSRFConfig] mutableCopy];
  config[@"csrf"] = @{ @"enabled" : @(NO) };
  ALNApplication *app = [self securityApplicationWithConfig:config
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];
  ALNResponse *form = [harness dispatchMethod:@"GET" path:@"/form"];
  XCTAssertEqualObjects(@"", [self jsonFromResponse:form][@"csrf"]);
  XCTAssertNil([form headerForName:@"Set-Cookie"]);
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

- (ALNWebTestHarness *)csrfHarnessWithToken:(NSString **)token {
  ALNApplication *app = [self securityApplicationWithConfig:[self sessionAndCSRFConfig]
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];
  ALNResponse *formResponse = [harness dispatchMethod:@"GET" path:@"/form"];
  [harness recycleCookiesFromResponse:formResponse];
  if (token != NULL) {
    *token = [self jsonFromResponse:formResponse][@"csrf"];
  }
  return harness;
}

- (void)testCSRFExemptPathPrefixesSkipOnlyCookielessRequestsBelowThePrefix {
  NSMutableDictionary *config = [[self sessionAndCSRFConfig] mutableCopy];
  config[@"csrf"] = @{ @"enabled" : @(YES), @"exemptPathPrefixes" : @[ @"/submit/" ] };
  ALNApplication *app = [self securityApplicationWithConfig:config
                                                 submitPath:@"/submit"
                                                 submitName:@"submit"
                                               submitAction:@"submit"];
  [app registerRouteMethod:@"POST" path:@"/submitted" name:@"submitted" controllerClass:[MiddlewareFormController class] action:@"submit"];

  ALNWebTestHarness *cookieless = [ALNWebTestHarness harnessWithApplication:app];
  ALNResponse *exempt = [cookieless dispatchMethod:@"POST" path:@"/submit"];
  ALNAssertResponseStatus(exempt, 200);
  XCTAssertNil([exempt headerForName:@"Set-Cookie"]);
  // Prefixes match whole path segments only.
  ALNAssertResponseStatus([cookieless dispatchMethod:@"POST" path:@"/submitted"], 403);

  ALNWebTestHarness *withSession = [ALNWebTestHarness harnessWithApplication:app];
  [withSession recycleCookiesFromResponse:[withSession dispatchMethod:@"GET" path:@"/form"]];
  ALNAssertResponseStatus([withSession dispatchMethod:@"POST" path:@"/submit"], 403);
}

- (void)testCSRFRejectionReturnsJSONEnvelopeForJSONClients {
  ALNWebTestHarness *harness = [self csrfHarnessWithToken:NULL];
  ALNResponse *response = [harness dispatchMethod:@"POST"
                                             path:@"/submit"
                                      queryString:@""
                                          headers:@{ @"accept" : @"application/json" }
                                             body:nil];
  ALNAssertResponseStatus(response, 403);
  ALNAssertResponseContentType(response, @"application/json");
  NSDictionary *json = [self jsonFromResponse:response];
  XCTAssertEqualObjects(@"csrf_invalid", json[@"error"][@"code"]);
  XCTAssertEqualObjects(@(403), json[@"error"][@"status"]);
  XCTAssertTrue([json[@"error"][@"message"] length] > 0);
  XCTAssertNotNil(json[@"error"][@"request_id"]);
}

- (void)testCSRFRejectionKeepsPlainTextForHTMLClients {
  ALNWebTestHarness *harness = [self csrfHarnessWithToken:NULL];
  ALNResponse *response = [harness dispatchMethod:@"POST"
                                             path:@"/submit"
                                      queryString:@""
                                          headers:@{ @"accept" : @"text/html" }
                                             body:nil];
  ALNAssertResponseStatus(response, 403);
  ALNAssertResponseContentType(response, @"text/plain");
  XCTAssertEqualObjects(@"csrf verification failed\n", ALNTestStringFromResponse(response));
}

- (void)testCSRFRejectsPrefixAndExtendedTokens {
  NSString *token = nil;
  ALNWebTestHarness *harness = [self csrfHarnessWithToken:&token];
  XCTAssertTrue([token length] > 1);
  NSArray *candidates = @[
    [token substringToIndex:[token length] - 1],
    [token stringByAppendingString:@"0"],
    [token uppercaseString],
  ];
  for (NSString *candidate in candidates) {
    if ([candidate isEqualToString:token]) {
      continue;
    }
    ALNResponse *response = [harness dispatchMethod:@"POST"
                                               path:@"/submit"
                                        queryString:@""
                                            headers:@{ @"x-csrf-token" : candidate }
                                               body:nil];
    ALNAssertResponseStatus(response, 403);
  }
  ALNResponse *accepted = [harness dispatchMethod:@"POST"
                                             path:@"/submit"
                                      queryString:@""
                                          headers:@{ @"x-csrf-token" : token ?: @"" }
                                             body:nil];
  ALNAssertResponseStatus(accepted, 200);
}

- (void)testConstantTimeDataEqualsHandlesEqualAndUnequalLengths {
  NSData *token = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertTrue(ALNConstantTimeDataEquals(token, [@"abc" dataUsingEncoding:NSUTF8StringEncoding]));
  XCTAssertFalse(ALNConstantTimeDataEquals(token, [@"abd" dataUsingEncoding:NSUTF8StringEncoding]));
  XCTAssertFalse(ALNConstantTimeDataEquals(token, [@"ab" dataUsingEncoding:NSUTF8StringEncoding]));
  XCTAssertFalse(ALNConstantTimeDataEquals(token, [@"abcd" dataUsingEncoding:NSUTF8StringEncoding]));
  XCTAssertFalse(ALNConstantTimeDataEquals(token, [NSData data]));
  XCTAssertTrue(ALNConstantTimeDataEquals([NSData data], [NSData data]));

  // Lengths differing by a multiple of 256 with zero padding must not compare equal.
  NSMutableData *padded = [token mutableCopy];
  [padded increaseLengthBy:256];
  XCTAssertFalse(ALNConstantTimeDataEquals(token, padded));
  XCTAssertFalse(ALNConstantTimeDataEquals(padded, token));
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

- (ALNWebTestHarness *)rateLimitHarnessAllowing:(NSUInteger)requests {
  return [ALNWebTestHarness harnessWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"rateLimit" : @{
      @"enabled" : @(YES),
      @"requests" : @(requests),
      @"windowSeconds" : @(60),
    }
  }
                                  routeMethod:@"GET"
                                         path:@"/ping"
                                    routeName:@"ping"
                              controllerClass:[MiddlewareFormController class]
                                       action:@"ping"
                                  middlewares:nil];
}

// The server sets effectiveRemoteAddress, which the limiter keys on, from the
// right-most untrusted X-Forwarded-For hop. A client rotating the left-most
// value behind an appending proxy stays one client.
- (void)testRateLimitHoldsWhenClientRotatesLeftMostForwardedHop {
  ALNWebTestHarness *harness = [self rateLimitHarnessAllowing:3];
  NSMutableArray *statuses = [NSMutableArray array];
  for (NSUInteger idx = 0; idx < 6; idx++) {
    NSString *header = [NSString stringWithFormat:@"10.0.0.%lu, 203.0.113.9", (unsigned long)idx];
    ALNRequest *request = [self requestWithMethod:@"GET" path:@"/ping" headers:@{ @"X-Forwarded-For" : header }];
    request.remoteAddress = @"127.0.0.1";
    request.effectiveRemoteAddress = ALNClientAddressFromForwardedHops(
        request.remoteAddress, ALNClientAddressXForwardedForHops(header), @[ @"127.0.0.1/32" ], NULL);
    XCTAssertEqualObjects(@"203.0.113.9", request.effectiveRemoteAddress);
    [statuses addObject:@([harness dispatchRequest:request recycleCookies:NO].statusCode)];
  }
  XCTAssertEqualObjects((@[ @200, @200, @200, @429, @429, @429 ]), statuses);
}

- (BOOL)rateLimiter:(ALNRateLimitMiddleware *)limiter
    allowsRemoteAddress:(NSString *)address
                 logger:(ALNLogger *)logger {
  ALNRequest *request = [self requestWithMethod:@"GET" path:@"/ping" headers:@{}];
  request.remoteAddress = address;
  ALNContext *context = [[ALNContext alloc] initWithRequest:request
                                                   response:[[ALNResponse alloc] init]
                                                     params:@{}
                                                      stash:[NSMutableDictionary dictionary]
                                                     logger:logger
                                                  perfTrace:[[ALNPerfTrace alloc] initWithEnabled:NO]
                                                  routeName:@"ping"
                                             controllerName:@"MiddlewareFormController"
                                                 actionName:@"ping"];
  return [limiter processContext:context error:NULL];
}

- (void)testRateLimitEntryTableIsBounded {
  ALNRateLimitMiddleware *limiter = [[ALNRateLimitMiddleware alloc] initWithMaxRequests:1 windowSeconds:60];
  [limiter setValue:@(8) forKey:@"maxEntries"];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  for (NSUInteger idx = 0; idx < 50; idx++) {
    NSString *address = [NSString stringWithFormat:@"198.51.100.%lu", (unsigned long)idx];
    XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:address logger:logger]);
  }
  XCTAssertLessThanOrEqual([[limiter valueForKey:@"entries"] count], (NSUInteger)8);
  // The oldest clients were evicted; the newest are still counted.
  XCTAssertFalse([self rateLimiter:limiter allowsRemoteAddress:@"198.51.100.49" logger:logger]);
  XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:@"198.51.100.0" logger:logger]);
}

// At the real cap, a stream of new clients (each one evicting the oldest) must
// cost a bounded amount per request: eviction never sorts or scans the table
// under the lock every request takes.
- (void)testRateLimitStaysFastWhenEveryRequestIsANewClientAtTheCap {
  ALNRateLimitMiddleware *limiter = [[ALNRateLimitMiddleware alloc] initWithMaxRequests:5
                                                                        windowSeconds:60
                                                                     ipv6PrefixLength:128];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  NSUInteger cap = 65536;
  NSUInteger total = cap + 4464;
  NSDate *started = [NSDate date];
  NSTimeInterval slowestOverflowBatch = 0;
  NSDate *batchStarted = nil;
  for (NSUInteger idx = 0; idx < total; idx++) {
    @autoreleasepool {
      if (idx >= cap && ((idx - cap) % 1000) == 0) {
        if (batchStarted != nil) {
          slowestOverflowBatch = MAX(slowestOverflowBatch, -[batchStarted timeIntervalSinceNow]);
        }
        batchStarted = [NSDate date];
      }
      NSString *address = [NSString stringWithFormat:@"2001:db8:%lx:%lx::1",
                                                     (unsigned long)(idx >> 16),
                                                     (unsigned long)(idx & 0xffff)];
      XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:address logger:logger]);
    }
  }
  NSTimeInterval elapsed = -[started timeIntervalSinceNow];
  XCTAssertEqual(cap, [[limiter valueForKey:@"entries"] count]);
  // Before the fix one overflow insert at this size took seconds.
  XCTAssertLessThan(slowestOverflowBatch, 1.0, @"1000 inserts at the cap took %.2fs", slowestOverflowBatch);
  XCTAssertLessThan(elapsed, 20.0, @"%lu inserts took %.2fs", (unsigned long)total, elapsed);
}

- (void)testRateLimitCountsIPv6ClientsPerSlash64ByDefault {
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  ALNRateLimitMiddleware *limiter = [[ALNRateLimitMiddleware alloc] initWithMaxRequests:2 windowSeconds:60];
  XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:@"2001:db8:1:2::1" logger:logger]);
  XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:@"2001:db8:1:2::2" logger:logger]);
  XCTAssertFalse([self rateLimiter:limiter allowsRemoteAddress:@"2001:db8:1:2:ffff::3" logger:logger]);
  XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:@"2001:db8:1:3::1" logger:logger]);
  // IPv4 and its IPv4-mapped spelling are one client.
  XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:@"10.1.1.1" logger:logger]);
  XCTAssertTrue([self rateLimiter:limiter allowsRemoteAddress:@"::ffff:10.1.1.1" logger:logger]);
  XCTAssertFalse([self rateLimiter:limiter allowsRemoteAddress:@"10.1.1.1" logger:logger]);

  ALNRateLimitMiddleware *perAddress = [[ALNRateLimitMiddleware alloc] initWithMaxRequests:1
                                                                           windowSeconds:60
                                                                        ipv6PrefixLength:128];
  XCTAssertTrue([self rateLimiter:perAddress allowsRemoteAddress:@"2001:db8:1:2::1" logger:logger]);
  XCTAssertTrue([self rateLimiter:perAddress allowsRemoteAddress:@"2001:db8:1:2::2" logger:logger]);
}

- (void)testRateLimitIPv6PrefixLengthComesFromConfig {
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"rateLimit" : @{
      @"enabled" : @(YES),
      @"requests" : @(1),
      @"windowSeconds" : @(60),
      @"ipv6PrefixLength" : @(48),
    }
  }
                                                     routeMethod:@"GET"
                                                            path:@"/ping"
                                                       routeName:@"ping"
                                                 controllerClass:[MiddlewareFormController class]
                                                          action:@"ping"
                                                     middlewares:nil];
  NSMutableArray *statuses = [NSMutableArray array];
  for (NSString *address in @[ @"2001:db8:1:2::1", @"2001:db8:1:ffff::1", @"2001:db8:2::1" ]) {
    ALNRequest *request = [self requestWithMethod:@"GET" path:@"/ping" headers:@{}];
    request.remoteAddress = address;
    request.effectiveRemoteAddress = address;
    [statuses addObject:@([harness dispatchRequest:request recycleCookies:NO].statusCode)];
  }
  XCTAssertEqualObjects((@[ @200, @429, @200 ]), statuses);
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
