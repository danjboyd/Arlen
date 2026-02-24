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

@interface AppTraceCaptureExporter : NSObject <ALNTraceExporter>

@property(nonatomic, strong) NSDictionary *lastTrace;
@property(nonatomic, copy) NSString *lastRouteName;
@property(nonatomic, copy) NSString *lastControllerName;
@property(nonatomic, copy) NSString *lastActionName;

@end

@implementation AppTraceCaptureExporter

- (instancetype)init {
  self = [super init];
  if (self) {
    _lastTrace = @{};
    _lastRouteName = @"";
    _lastControllerName = @"";
    _lastActionName = @"";
  }
  return self;
}

- (void)exportTrace:(NSDictionary *)trace
            request:(ALNRequest *)request
           response:(ALNResponse *)response
          routeName:(NSString *)routeName
     controllerName:(NSString *)controllerName
         actionName:(NSString *)actionName {
  (void)request;
  (void)response;
  self.lastTrace = [trace isKindOfClass:[NSDictionary class]] ? trace : @{};
  self.lastRouteName = [routeName copy] ?: @"";
  self.lastControllerName = [controllerName copy] ?: @"";
  self.lastActionName = [actionName copy] ?: @"";
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

- (NSString *)traceIDFromTraceparent:(NSString *)traceparent {
  if (![traceparent isKindOfClass:[NSString class]]) {
    return @"";
  }
  NSArray *segments = [traceparent componentsSeparatedByString:@"-"];
  if ([segments count] != 4) {
    return @"";
  }
  return [segments[1] isKindOfClass:[NSString class]] ? segments[1] : @"";
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
  for (id entryValue in details) {
    XCTAssertTrue([entryValue isKindOfClass:[NSDictionary class]]);
    NSDictionary *entry = (NSDictionary *)entryValue;
    XCTAssertTrue([entry[@"field"] isKindOfClass:[NSString class]]);
    XCTAssertTrue([entry[@"code"] isKindOfClass:[NSString class]]);
    XCTAssertTrue([entry[@"message"] isKindOfClass:[NSString class]]);
    XCTAssertTrue([entry[@"code"] length] > 0);
    XCTAssertTrue([entry[@"message"] length] > 0);
  }
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

- (void)testDevelopmentJSONStructuredErrorIncludesNormalizedDetails {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
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
  NSArray *details = json[@"details"];
  XCTAssertEqual((NSUInteger)1, [details count]);
  NSDictionary *entry =
      [[details firstObject] isKindOfClass:[NSDictionary class]] ? [details firstObject] : @{};
  XCTAssertEqualObjects(@"", entry[@"field"]);
  XCTAssertEqualObjects(@"controller_exception", entry[@"code"]);
  XCTAssertTrue([entry[@"message"] length] > 0);
  NSDictionary *meta = [entry[@"meta"] isKindOfClass:[NSDictionary class]] ? entry[@"meta"] : @{};
  XCTAssertEqualObjects(@"AppJSONControllerException", meta[@"name"]);
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

- (void)testResponseIncludesTracePropagationHeadersAndCorrelationByDefault {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  NSString *incomingTraceparent =
      @"00-0123456789abcdef0123456789abcdef-1111111111111111-01";
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/dict"
                                                         queryString:@""
                                                             headers:@{
                                                               @"traceparent" : incomingTraceparent,
                                                             }]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSString *requestID = [response headerForName:@"X-Request-Id"];
  NSString *correlationID = [response headerForName:@"X-Correlation-Id"];
  NSString *traceID = [response headerForName:@"X-Trace-Id"];
  NSString *traceparent = [response headerForName:@"traceparent"];
  XCTAssertTrue([requestID length] > 0);
  XCTAssertEqualObjects(requestID, correlationID);
  XCTAssertEqualObjects(@"0123456789abcdef0123456789abcdef", traceID);
  XCTAssertEqualObjects(traceID, [self traceIDFromTraceparent:traceparent]);
  XCTAssertNotEqualObjects(incomingTraceparent, traceparent);
}

- (void)testTracePropagationCanBeDisabledByConfig {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"observability" : @{
      @"tracePropagationEnabled" : @(NO),
    },
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/dict"
                      name:@"dict"
           controllerClass:[AppJSONController class]
                    action:@"dict"];

  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/dict"
                                                         queryString:@""
                                                             headers:@{
                                                               @"traceparent" :
                                                                   @"00-0123456789abcdef0123456789abcdef-1111111111111111-01",
                                                             }]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertTrue([[response headerForName:@"X-Correlation-Id"] length] > 0);
  XCTAssertNil([response headerForName:@"X-Trace-Id"]);
  XCTAssertNil([response headerForName:@"traceparent"]);
}

- (void)testHealthzJSONPayloadIncludesDeterministicSignalChecks {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/healthz"
                                                         queryString:@""
                                                             headers:@{
                                                               @"accept" : @"application/json",
                                                             }]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects(@"application/json; charset=utf-8",
                        [response headerForName:@"Content-Type"]);

  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                       options:0
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"health", json[@"signal"]);
  XCTAssertEqualObjects(@"ok", json[@"status"]);
  XCTAssertEqualObjects(@(YES), json[@"ok"]);
  NSDictionary *checks = [json[@"checks"] isKindOfClass:[NSDictionary class]] ? json[@"checks"] : @{};
  XCTAssertEqualObjects(@(YES), checks[@"request_dispatch"][@"ok"]);
  XCTAssertNotNil(checks[@"active_requests"][@"value"]);
}

- (void)testReadyzJSONCanRequireStartedStateAndReturnDeterministic503 {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"observability" : @{
      @"readinessRequiresStartup" : @(YES),
    },
  }];

  ALNResponse *notReady = [app dispatchRequest:[self requestForPath:@"/readyz"
                                                         queryString:@""
                                                             headers:@{
                                                               @"accept" : @"application/json",
                                                             }]];
  XCTAssertEqual((NSInteger)503, notReady.statusCode);
  NSError *jsonError = nil;
  NSDictionary *notReadyJSON = [NSJSONSerialization JSONObjectWithData:notReady.bodyData
                                                                options:0
                                                                  error:&jsonError];
  XCTAssertNil(jsonError);
  XCTAssertEqualObjects(@"ready", notReadyJSON[@"signal"]);
  XCTAssertEqualObjects(@"not_ready", notReadyJSON[@"status"]);
  XCTAssertEqualObjects(@(NO), notReadyJSON[@"ready"]);
  XCTAssertEqualObjects(@(YES), notReadyJSON[@"checks"][@"startup"][@"required_for_readyz"]);

  NSError *startError = nil;
  XCTAssertTrue([app startWithError:&startError]);
  XCTAssertNil(startError);

  ALNResponse *ready = [app dispatchRequest:[self requestForPath:@"/readyz"
                                                      queryString:@""
                                                          headers:@{
                                                            @"accept" : @"application/json",
                                                          }]];
  XCTAssertEqual((NSInteger)200, ready.statusCode);
  jsonError = nil;
  NSDictionary *readyJSON = [NSJSONSerialization JSONObjectWithData:ready.bodyData
                                                             options:0
                                                               error:&jsonError];
  XCTAssertNil(jsonError);
  XCTAssertEqualObjects(@(YES), readyJSON[@"ready"]);
  [app shutdown];
}

- (void)testReadyzJSONCanRequireClusterQuorumAndReturnDeterministic503 {
  ALNApplication *degraded = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"observability" : @{
      @"readinessRequiresClusterQuorum" : @(YES),
    },
    @"cluster" : @{
      @"enabled" : @(YES),
      @"name" : @"alpha",
      @"nodeID" : @"node-a",
      @"expectedNodes" : @(3),
      @"observedNodes" : @(1),
    },
  }];

  ALNResponse *notReady = [degraded dispatchRequest:[self requestForPath:@"/readyz"
                                                              queryString:@""
                                                                  headers:@{
                                                                    @"accept" : @"application/json",
                                                                  }]];
  XCTAssertEqual((NSInteger)503, notReady.statusCode);
  NSError *jsonError = nil;
  NSDictionary *notReadyJSON = [NSJSONSerialization JSONObjectWithData:notReady.bodyData
                                                                options:0
                                                                  error:&jsonError];
  XCTAssertNil(jsonError);
  XCTAssertEqualObjects(@"ready", notReadyJSON[@"signal"]);
  XCTAssertEqualObjects(@"not_ready", notReadyJSON[@"status"]);
  XCTAssertEqualObjects(@(NO), notReadyJSON[@"ready"]);
  NSDictionary *quorumCheck =
      [notReadyJSON[@"checks"][@"cluster_quorum"] isKindOfClass:[NSDictionary class]]
          ? notReadyJSON[@"checks"][@"cluster_quorum"]
          : @{};
  XCTAssertEqualObjects(@(YES), quorumCheck[@"required_for_readyz"]);
  XCTAssertEqualObjects(@(NO), quorumCheck[@"ok"]);
  XCTAssertEqualObjects(@"degraded", quorumCheck[@"status"]);
  XCTAssertEqual((NSInteger)1, [quorumCheck[@"observed_nodes"] integerValue]);
  XCTAssertEqual((NSInteger)3, [quorumCheck[@"expected_nodes"] integerValue]);

  ALNApplication *nominal = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"observability" : @{
      @"readinessRequiresClusterQuorum" : @(YES),
    },
    @"cluster" : @{
      @"enabled" : @(YES),
      @"name" : @"alpha",
      @"nodeID" : @"node-a",
      @"expectedNodes" : @(3),
      @"observedNodes" : @(3),
    },
  }];
  ALNResponse *ready = [nominal dispatchRequest:[self requestForPath:@"/readyz"
                                                           queryString:@""
                                                               headers:@{
                                                                 @"accept" : @"application/json",
                                                               }]];
  XCTAssertEqual((NSInteger)200, ready.statusCode);
  jsonError = nil;
  NSDictionary *readyJSON = [NSJSONSerialization JSONObjectWithData:ready.bodyData
                                                             options:0
                                                               error:&jsonError];
  XCTAssertNil(jsonError);
  XCTAssertEqualObjects(@(YES), readyJSON[@"ready"]);
  NSDictionary *readyQuorumCheck =
      [readyJSON[@"checks"][@"cluster_quorum"] isKindOfClass:[NSDictionary class]]
          ? readyJSON[@"checks"][@"cluster_quorum"]
          : @{};
  XCTAssertEqualObjects(@"nominal", readyQuorumCheck[@"status"]);
  XCTAssertEqualObjects(@(YES), readyQuorumCheck[@"ok"]);
}

- (void)testClusterStatusPayloadIncludesQuorumAndCapabilityMatrix {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"cluster" : @{
      @"enabled" : @(YES),
      @"name" : @"alpha",
      @"nodeID" : @"node-a",
      @"expectedNodes" : @(4),
      @"observedNodes" : @(2),
    },
  }];

  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/clusterz"]];
  XCTAssertEqual((NSInteger)200, response.statusCode);

  NSError *jsonError = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                          options:0
                                                            error:&jsonError];
  XCTAssertNil(jsonError);
  NSDictionary *cluster =
      [payload[@"cluster"] isKindOfClass:[NSDictionary class]] ? payload[@"cluster"] : @{};
  XCTAssertEqual((NSInteger)4, [cluster[@"expected_nodes"] integerValue]);
  XCTAssertEqual((NSInteger)2, [cluster[@"observed_nodes"] integerValue]);
  NSDictionary *quorum =
      [cluster[@"quorum"] isKindOfClass:[NSDictionary class]] ? cluster[@"quorum"] : @{};
  XCTAssertEqualObjects(@"degraded", quorum[@"status"]);
  XCTAssertEqualObjects(@(NO), quorum[@"met"]);

  NSDictionary *coordination =
      [payload[@"coordination"] isKindOfClass:[NSDictionary class]] ? payload[@"coordination"] : @{};
  XCTAssertEqualObjects(@"degraded", coordination[@"state"]);
  NSDictionary *capabilityMatrix =
      [coordination[@"capability_matrix"] isKindOfClass:[NSDictionary class]]
          ? coordination[@"capability_matrix"]
          : @{};
  XCTAssertEqualObjects(@"external_load_balancer_required",
                        capabilityMatrix[@"cross_node_request_routing"]);
  XCTAssertEqualObjects(@"external_broker_required",
                        capabilityMatrix[@"cross_node_realtime_fanout"]);
}

- (void)testTraceExporterReceivesTraceContextMetadata {
  ALNApplication *app = [self buildAppWithHaltingMiddleware:NO];
  AppTraceCaptureExporter *exporter = [[AppTraceCaptureExporter alloc] init];
  app.traceExporter = exporter;

  NSString *incomingTraceID = @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/dict"
                                                         queryString:@""
                                                             headers:@{
                                                               @"x-trace-id" : incomingTraceID,
                                                             }]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSDictionary *trace = exporter.lastTrace;
  XCTAssertEqualObjects(@"http.request.trace", trace[@"event"]);
  XCTAssertEqualObjects(incomingTraceID, trace[@"trace_id"]);
  XCTAssertTrue([trace[@"request_id"] length] > 0);
  XCTAssertEqualObjects(trace[@"request_id"], trace[@"correlation_id"]);
  XCTAssertTrue([trace[@"span_id"] length] == 16);
  XCTAssertEqualObjects(@"dict", exporter.lastRouteName);
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
