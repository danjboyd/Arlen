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

- (id)validate:(ALNContext *)ctx {
  (void)ctx;
  NSString *name = nil;
  NSInteger count = 0;
  [self requireStringParam:@"name" value:&name];
  [self requireIntegerParam:@"count" value:&count];
  if ([[self validationErrors] count] > 0) {
    [self renderValidationErrors];
    return nil;
  }
  return @{
    @"name" : name ?: @"",
    @"count" : @(count),
  };
}

- (id)explode:(ALNContext *)ctx {
  (void)ctx;
  [NSException raise:@"AppJSONControllerException"
              format:@"boom from controller"];
  return nil;
}

- (BOOL)requireAdmin:(ALNContext *)ctx {
  NSString *role = [ctx stringParamForName:@"role"];
  return [role isEqualToString:@"admin"];
}

- (id)guarded:(ALNContext *)ctx {
  return @{
    @"ok" : @(YES),
    @"route" : ctx.routeName ?: @"",
  };
}

- (id)report:(ALNContext *)ctx {
  return @{
    @"route" : ctx.routeName ?: @"",
    @"format" : [ctx requestFormat] ?: @"",
  };
}

@end

@interface ApplicationTests : XCTestCase
@end

@implementation ApplicationTests

- (ALNApplication *)buildAppWithHaltingMiddleware:(BOOL)useHalting {
  return [self buildAppWithHaltingMiddleware:useHalting performanceLogging:YES environment:@"test"];
}

- (ALNApplication *)buildAppWithHaltingMiddleware:(BOOL)useHalting
                               performanceLogging:(BOOL)performanceLogging
                                      environment:(NSString *)environment {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : environment ?: @"test",
    @"logFormat" : @"json",
    @"performanceLogging" : @(performanceLogging),
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
  [app registerRouteMethod:@"GET"
                      path:@"/validate"
                      name:@"validate"
           controllerClass:[AppJSONController class]
                    action:@"validate"];
  [app registerRouteMethod:@"GET"
                      path:@"/explode"
                      name:@"explode"
           controllerClass:[AppJSONController class]
                    action:@"explode"];
  [app beginRouteGroupWithPrefix:@"/admin"
                     guardAction:@"requireAdmin"
                         formats:@[ @"json" ]];
  [app registerRouteMethod:@"GET"
                      path:@"/audit"
                      name:@"admin_audit"
           controllerClass:[AppJSONController class]
                    action:@"guarded"];
  [app endRouteGroup];
  [app registerRouteMethod:@"GET"
                      path:@"/report"
                      name:@"report_html"
                   formats:@[ @"html" ]
           controllerClass:[AppJSONController class]
               guardAction:nil
                    action:@"report"];
  [app registerRouteMethod:@"GET"
                      path:@"/report"
                      name:@"report_json"
                   formats:@[ @"json" ]
           controllerClass:[AppJSONController class]
               guardAction:nil
                    action:@"report"];

  if (useHalting) {
    [app addMiddleware:[[AppHaltingMiddleware alloc] init]];
  } else {
    [app addMiddleware:[[AppHeaderMiddleware alloc] init]];
  }
  return app;
}

- (ALNRequest *)requestForPath:(NSString *)path {
  return [self requestForPath:path queryString:@"" headers:@{}];
}

- (ALNRequest *)requestForPath:(NSString *)path
                   queryString:(NSString *)queryString
                       headers:(NSDictionary *)headers {
  return [[ALNRequest alloc] initWithMethod:@"GET"
                                      path:path
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
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

- (void)testBuiltInReadinessAndLivenessEndpoints {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];

  ALNResponse *ready = [app dispatchRequest:[self requestForPath:@"/readyz"]];
  XCTAssertEqual((NSInteger)200, ready.statusCode);
  NSString *readyBody = [[NSString alloc] initWithData:ready.bodyData
                                              encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(@"ready\n", readyBody);

  ALNResponse *live = [app dispatchRequest:[self requestForPath:@"/livez"]];
  XCTAssertEqual((NSInteger)200, live.statusCode);
  NSString *liveBody = [[NSString alloc] initWithData:live.bodyData
                                             encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(@"live\n", liveBody);
}

- (void)testRouteGuardRejectsWhenConditionFails {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/admin/audit.json"
                                                         queryString:@""
                                                             headers:@{}]];
  XCTAssertEqual((NSInteger)403, response.statusCode);
}

- (void)testRouteGuardAllowsWhenConditionPasses {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/admin/audit.json"
                                                         queryString:@"role=admin"
                                                             headers:@{}]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"admin_audit", json[@"route"]);
}

- (void)testFormatConditionSelectsJSONRouteWhenRequested {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/report"
                                                         queryString:@""
                                                             headers:@{ @"accept" : @"application/json" }]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"report_json", json[@"route"]);
  XCTAssertEqualObjects(@"json", json[@"format"]);
}

- (void)testAPIOnlyModeReturnsJSONNotFoundByDefault {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"apiOnly" : @(YES),
    @"host" : @"127.0.0.1",
    @"port" : @(3000),
  }];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/missing"]];
  XCTAssertEqual((NSInteger)404, response.statusCode);
  XCTAssertEqualObjects(@"application/json; charset=utf-8",
                        [response headerForName:@"Content-Type"]);
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"not_found", json[@"error"][@"code"]);
}

- (void)testValidationErrorsReturnStandardized422Shape {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/validate"
                                                         queryString:@"count=nope"
                                                             headers:@{ @"accept" : @"application/json" }]];
  XCTAssertEqual((NSInteger)422, response.statusCode);
  XCTAssertEqualObjects(@"application/json; charset=utf-8",
                        [response headerForName:@"Content-Type"]);

  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"validation_failed", json[@"error"][@"code"]);
  XCTAssertEqualObjects(@"Validation failed", json[@"error"][@"message"]);
  XCTAssertTrue([json[@"error"][@"request_id"] length] > 0);
  NSArray *details = json[@"details"];
  XCTAssertEqual((NSUInteger)2, [details count]);
}

- (void)testValidationSuccessUsesUnifiedParams {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/validate"
                                                         queryString:@"name=peggy&count=7"
                                                             headers:@{}]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"peggy", json[@"name"]);
  XCTAssertEqualObjects(@7, json[@"count"]);
}

- (void)testProductionStructuredErrorIncludesCorrelationID {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO
                                         performanceLogging:YES
                                                environment:@"production"];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/explode"
                                                         queryString:@""
                                                             headers:@{ @"accept" : @"application/json" }]];
  XCTAssertEqual((NSInteger)500, response.statusCode);
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"controller_exception", json[@"error"][@"code"]);
  XCTAssertEqualObjects(@"Internal Server Error", json[@"error"][@"message"]);
  XCTAssertTrue([json[@"error"][@"correlation_id"] length] > 0);
  XCTAssertNil(json[@"details"]);
}

- (void)testDevelopmentHTMLErrorPageForBrowserRequests {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/explode"
                                                         queryString:@""
                                                             headers:@{ @"accept" : @"text/html" }]];
  XCTAssertEqual((NSInteger)500, response.statusCode);
  XCTAssertEqualObjects(@"text/html; charset=utf-8",
                        [response headerForName:@"Content-Type"]);
  NSString *body = [[NSString alloc] initWithData:response.bodyData
                                         encoding:NSUTF8StringEncoding];
  XCTAssertTrue([body containsString:@"Arlen Development Exception"]);
  XCTAssertTrue([body containsString:@"Request ID"]);
}

- (void)testPerformanceHeadersCanBeDisabled {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO
                                         performanceLogging:NO
                                                environment:@"test"];
  ALNRequest *request = [self requestForPath:@"/dict" queryString:@"" headers:@{}];
  request.parseDurationMilliseconds = 12.0;
  ALNResponse *response = [app dispatchRequest:request];
  XCTAssertNil([response headerForName:@"X-Arlen-Total-Ms"]);
  XCTAssertNil([response headerForName:@"X-Arlen-Parse-Ms"]);
  XCTAssertNil([response headerForName:@"X-Arlen-Response-Write-Ms"]);
}

- (void)testPerformanceHeadersIncludeParseAndResponseWriteWhenEnabled {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO
                                         performanceLogging:YES
                                                environment:@"test"];
  ALNRequest *request = [self requestForPath:@"/dict" queryString:@"" headers:@{}];
  request.parseDurationMilliseconds = 34.5;
  ALNResponse *response = [app dispatchRequest:request];
  XCTAssertNotNil([response headerForName:@"X-Arlen-Total-Ms"]);
  XCTAssertEqualObjects(@"34.500", [response headerForName:@"X-Arlen-Parse-Ms"]);
  XCTAssertNotNil([response headerForName:@"X-Arlen-Response-Write-Ms"]);
}

- (void)testStartFailsFastWhenSessionEnabledWithoutSecret {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"",
    },
  }];

  NSError *startError = nil;
  BOOL started = [app startWithError:&startError];
  XCTAssertFalse(started);
  XCTAssertNotNil(startError);
  XCTAssertEqualObjects(@"Arlen.Application.Error", startError.domain);
  XCTAssertEqual((NSInteger)330, startError.code);
  XCTAssertTrue([startError.localizedDescription containsString:@"session.enabled requires session.secret"]);
}

- (void)testStartFailsFastWhenCSRFEnabledWithoutSession {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(NO),
      @"secret" : @"",
    },
    @"csrf" : @{
      @"enabled" : @(YES),
    },
  }];

  NSError *startError = nil;
  BOOL started = [app startWithError:&startError];
  XCTAssertFalse(started);
  XCTAssertNotNil(startError);
  XCTAssertEqualObjects(@"Arlen.Application.Error", startError.domain);
  XCTAssertEqual((NSInteger)331, startError.code);
  XCTAssertTrue([startError.localizedDescription containsString:@"csrf.enabled requires session.enabled"]);
}

- (void)testStartFailsFastWhenAuthEnabledWithoutBearerSecret {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"auth" : @{
      @"enabled" : @(YES),
      @"bearerSecret" : @"",
    },
  }];

  NSError *startError = nil;
  BOOL started = [app startWithError:&startError];
  XCTAssertFalse(started);
  XCTAssertNotNil(startError);
  XCTAssertEqualObjects(@"Arlen.Application.Error", startError.domain);
  XCTAssertEqual((NSInteger)332, startError.code);
  XCTAssertTrue([startError.localizedDescription containsString:@"auth.enabled requires auth.bearerSecret"]);
}

- (void)testStartSucceedsForStrictProfileWhenRequiredSecretsConfigured {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"securityProfile" : @"strict",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"strict-profile-secret",
    },
    @"csrf" : @{
      @"enabled" : @(YES),
    },
  }];

  NSError *startError = nil;
  BOOL started = [app startWithError:&startError];
  XCTAssertTrue(started);
  XCTAssertNil(startError);
  XCTAssertTrue(app.isStarted);
  [app shutdown];
}

@end
