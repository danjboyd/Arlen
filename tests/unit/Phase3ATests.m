#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <openssl/evp.h>
#import <openssl/hmac.h>

#import "ALNApplication.h"
#import "ALNAuth.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSInteger gPhase3APluginRegisterCount = 0;
static NSInteger gPhase3APluginStartCount = 0;
static NSInteger gPhase3APluginStopCount = 0;

@interface Phase3AHeaderMiddleware : NSObject <ALNMiddleware>
@end

@implementation Phase3AHeaderMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  [context.response setHeader:@"X-Phase3A-Plugin" value:@"active"];
  return YES;
}

@end

@interface Phase3ATestPlugin : NSObject <ALNPlugin, ALNLifecycleHook>
@end

@implementation Phase3ATestPlugin

- (NSString *)pluginName {
  return @"phase3a_test_plugin";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)application;
  (void)error;
  gPhase3APluginRegisterCount += 1;
  return YES;
}

- (NSArray *)middlewaresForApplication:(ALNApplication *)application {
  (void)application;
  return @[ [[Phase3AHeaderMiddleware alloc] init] ];
}

- (void)applicationDidStart:(ALNApplication *)application {
  (void)application;
  gPhase3APluginStartCount += 1;
}

- (void)applicationWillStop:(ALNApplication *)application {
  (void)application;
  gPhase3APluginStopCount += 1;
}

@end

@interface Phase3AController : ALNController
@end

@implementation Phase3AController

- (id)userShow:(ALNContext *)ctx {
  (void)ctx;
  id coercedID = [self validatedValueForName:@"id"] ?: @0;
  id verbose = [self validatedValueForName:@"verbose"] ?: @(NO);
  return @{
    @"id" : coercedID,
    @"verbose" : verbose,
    @"subject" : [self authSubject] ?: @"",
  };
}

- (id)ping:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"pong\n"];
  return nil;
}

@end

@interface Phase3ATests : XCTestCase
@end

@implementation Phase3ATests

- (void)setUp {
  [super setUp];
  gPhase3APluginRegisterCount = 0;
  gPhase3APluginStartCount = 0;
  gPhase3APluginStopCount = 0;
}

- (NSString *)base64URLEncode:(NSData *)data {
  NSString *base64 = [data base64EncodedStringWithOptions:0];
  NSString *url = [[base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
      stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  while ([url hasSuffix:@"="]) {
    url = [url substringToIndex:[url length] - 1];
  }
  return url;
}

- (NSString *)jwtTokenWithScopes:(NSArray *)scopes
                           roles:(NSArray *)roles
                          secret:(NSString *)secret {
  NSDictionary *header = @{
    @"alg" : @"HS256",
    @"typ" : @"JWT",
  };
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:@{
    @"sub" : @"user-42",
    @"iat" : @((NSInteger)now),
    @"exp" : @((NSInteger)(now + 3600)),
  }];
  NSArray *normalizedScopes = [scopes isKindOfClass:[NSArray class]] ? scopes : @[];
  if ([normalizedScopes count] > 0) {
    payload[@"scope"] = [normalizedScopes componentsJoinedByString:@" "];
  }
  if ([roles isKindOfClass:[NSArray class]] && [roles count] > 0) {
    payload[@"roles"] = roles;
  }

  NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  NSString *headerPart = [self base64URLEncode:headerData];
  NSString *payloadPart = [self base64URLEncode:payloadData];
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, payloadPart];

  NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
  NSData *inputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

  unsigned int digestLength = EVP_MAX_MD_SIZE;
  unsigned char digest[EVP_MAX_MD_SIZE];
  HMAC(EVP_sha256(),
       [secretData bytes],
       (int)[secretData length],
       [inputData bytes],
       [inputData length],
       digest,
       &digestLength);
  NSData *signature = [NSData dataWithBytes:digest length:digestLength];
  NSString *signaturePart = [self base64URLEncode:signature];
  return [NSString stringWithFormat:@"%@.%@.%@", headerPart, payloadPart, signaturePart];
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers {
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:[NSData data]];
}

- (NSDictionary *)jsonFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  if (error != nil || ![parsed isKindOfClass:[NSDictionary class]]) {
    NSString *body = [[NSString alloc] initWithData:response.bodyData
                                           encoding:NSUTF8StringEncoding] ?: @"";
    XCTFail(@"expected JSON dictionary, error=%@ body=%@", error.localizedDescription ?: @"", body);
  }
  return parsed ?: @{};
}

- (ALNApplication *)buildAppWithPluginConfig:(BOOL)usePluginConfig {
  return [self buildAppWithPluginConfig:usePluginConfig docsStyle:nil];
}

- (ALNApplication *)buildAppWithPluginConfig:(BOOL)usePluginConfig
                                   docsStyle:(NSString *)docsStyle {
  NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"apiOnly" : @(YES),
    @"auth" : @{
      @"enabled" : @(YES),
      @"bearerSecret" : @"phase3a-secret",
      @"issuer" : @"",
      @"audience" : @"",
    },
    @"openapi" : @{
      @"enabled" : @(YES),
      @"docsUIEnabled" : @(YES),
      @"title" : @"Phase3A API",
      @"version" : @"3a-test",
    },
  }];
  if ([docsStyle length] > 0) {
    NSMutableDictionary *openapi =
        [NSMutableDictionary dictionaryWithDictionary:config[@"openapi"] ?: @{}];
    openapi[@"docsUIStyle"] = [docsStyle lowercaseString];
    config[@"openapi"] = openapi;
  }
  if (usePluginConfig) {
    config[@"plugins"] = @{
      @"classes" : @[ @"Phase3ATestPlugin" ]
    };
  }

  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  [app registerRouteMethod:@"GET"
                      path:@"/api/users/:id"
                      name:@"user_show"
           controllerClass:[Phase3AController class]
                    action:@"userShow"];
  [app registerRouteMethod:@"GET"
                      path:@"/plugin/ping"
                      name:@"plugin_ping"
           controllerClass:[Phase3AController class]
                    action:@"ping"];

  NSError *routeError = nil;
  BOOL configured = [app configureRouteNamed:@"user_show"
                               requestSchema:@{
                                 @"type" : @"object",
                                 @"properties" : @{
                                   @"id" : @{
                                     @"type" : @"integer",
                                     @"source" : @"path",
                                     @"required" : @(YES),
                                   },
                                   @"verbose" : @{
                                     @"type" : @"boolean",
                                     @"source" : @"query",
                                     @"default" : @(NO),
                                   },
                                 },
                               }
                              responseSchema:@{
                                @"type" : @"object",
                                @"properties" : @{
                                  @"id" : @{ @"type" : @"integer" },
                                  @"verbose" : @{ @"type" : @"boolean" },
                                  @"subject" : @{ @"type" : @"string" },
                                },
                                @"required" : @[ @"id", @"verbose" ]
                              }
                                     summary:@"Fetch a user"
                                 operationID:@"fetchUser"
                                        tags:@[ @"users" ]
                               requiredScopes:@[ @"users:read" ]
                                requiredRoles:nil
                              includeInOpenAPI:YES
                                        error:&routeError];
  XCTAssertTrue(configured);
  XCTAssertNil(routeError);
  return app;
}

- (void)testRequestContractAndAuthScopeHappyPath {
  ALNApplication *app = [self buildAppWithPluginConfig:NO];
  NSString *token = [self jwtTokenWithScopes:@[ @"users:read" ]
                                       roles:@[ @"admin" ]
                                      secret:@"phase3a-secret"];
  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                  path:@"/api/users/42"
                                                           queryString:@"verbose=true"
                                                               headers:@{
                                                                 @"authorization" :
                                                                     [NSString stringWithFormat:@"Bearer %@", token],
                                                                 @"accept" : @"application/json",
                                                               }]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSDictionary *json = [self jsonFromResponse:response];
  XCTAssertEqualObjects(@42, json[@"id"]);
  XCTAssertEqualObjects(@(YES), json[@"verbose"]);
  XCTAssertEqualObjects(@"user-42", json[@"subject"]);
}

- (void)testRequestContractValidationFailureReturns422 {
  ALNApplication *app = [self buildAppWithPluginConfig:NO];
  NSString *token = [self jwtTokenWithScopes:@[ @"users:read" ]
                                       roles:@[]
                                      secret:@"phase3a-secret"];
  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                  path:@"/api/users/not-an-int"
                                                           queryString:@"verbose=true"
                                                               headers:@{
                                                                 @"authorization" :
                                                                     [NSString stringWithFormat:@"Bearer %@", token],
                                                                 @"accept" : @"application/json",
                                                               }]];
  XCTAssertEqual((NSInteger)422, response.statusCode);
  NSDictionary *json = [self jsonFromResponse:response];
  XCTAssertEqualObjects(@"validation_failed", json[@"error"][@"code"]);
  NSArray *details = json[@"details"];
  XCTAssertTrue([details count] > 0);
}

- (void)testAuthScopeRejectionReturns403 {
  ALNApplication *app = [self buildAppWithPluginConfig:NO];
  NSString *token = [self jwtTokenWithScopes:@[ @"users:write" ]
                                       roles:@[]
                                      secret:@"phase3a-secret"];
  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                  path:@"/api/users/7"
                                                           queryString:@""
                                                               headers:@{
                                                                 @"authorization" :
                                                                     [NSString stringWithFormat:@"Bearer %@", token],
                                                                 @"accept" : @"application/json",
                                                               }]];
  XCTAssertEqual((NSInteger)403, response.statusCode);
  NSDictionary *json = [self jsonFromResponse:response];
  XCTAssertEqualObjects(@"forbidden", json[@"error"][@"code"]);
}

- (void)testMissingBearerTokenReturns401 {
  ALNApplication *app = [self buildAppWithPluginConfig:NO];
  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                  path:@"/api/users/7"
                                                           queryString:@""
                                                               headers:@{
                                                                 @"accept" : @"application/json",
                                                               }]];
  XCTAssertEqual((NSInteger)401, response.statusCode);
  XCTAssertTrue([[response headerForName:@"WWW-Authenticate"] containsString:@"Bearer"]);
}

- (void)testBuiltInMetricsAndOpenAPIEndpoints {
  ALNApplication *app = [self buildAppWithPluginConfig:NO];
  NSString *token = [self jwtTokenWithScopes:@[ @"users:read" ]
                                       roles:@[]
                                      secret:@"phase3a-secret"];
  (void)[app dispatchRequest:[self requestWithMethod:@"GET"
                                                path:@"/api/users/9"
                                         queryString:@""
                                             headers:@{
                                               @"authorization" :
                                                   [NSString stringWithFormat:@"Bearer %@", token],
                                               @"accept" : @"application/json",
                                             }]];

  ALNResponse *metrics = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                 path:@"/metrics"
                                                          queryString:@""
                                                              headers:@{}]];
  XCTAssertEqual((NSInteger)200, metrics.statusCode);
  NSString *metricsBody = [[NSString alloc] initWithData:metrics.bodyData
                                                encoding:NSUTF8StringEncoding];
  XCTAssertTrue([metricsBody containsString:@"aln_http_requests_total"]);

  ALNResponse *openapi = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                 path:@"/openapi.json"
                                                          queryString:@""
                                                              headers:@{
                                                                @"accept" : @"application/json",
                                                              }]];
  XCTAssertEqual((NSInteger)200, openapi.statusCode);
  NSDictionary *spec = [self jsonFromResponse:openapi];
  NSDictionary *paths = spec[@"paths"];
  XCTAssertNotNil(paths[@"/api/users/{id}"]);

  ALNResponse *docs = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                              path:@"/openapi"
                                                       queryString:@""
                                                           headers:@{}]];
  XCTAssertEqual((NSInteger)200, docs.statusCode);
  XCTAssertEqualObjects(@"text/html; charset=utf-8", [docs headerForName:@"Content-Type"]);
  NSString *docsBody = [[NSString alloc] initWithData:docs.bodyData
                                              encoding:NSUTF8StringEncoding];
  XCTAssertTrue([docsBody containsString:@"Arlen OpenAPI Explorer"]);
  XCTAssertTrue([docsBody containsString:@"Try It Out"]);

  ALNResponse *viewer = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                path:@"/openapi/viewer"
                                                         queryString:@""
                                                             headers:@{}]];
  XCTAssertEqual((NSInteger)200, viewer.statusCode);
  NSString *viewerBody = [[NSString alloc] initWithData:viewer.bodyData
                                               encoding:NSUTF8StringEncoding];
  XCTAssertTrue([viewerBody containsString:@"Arlen OpenAPI Viewer"]);

  NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"phase3a-openapi.json"];
  NSError *exportError = nil;
  BOOL exported = [app writeOpenAPISpecToPath:tmp pretty:YES error:&exportError];
  XCTAssertTrue(exported);
  XCTAssertNil(exportError);
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:tmp];
  XCTAssertTrue(exists);
}

- (void)testSwaggerDocsStyleServesSwaggerUIAndDedicatedPath {
  ALNApplication *app = [self buildAppWithPluginConfig:NO docsStyle:@"swagger"];

  ALNResponse *docs = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                              path:@"/openapi"
                                                       queryString:@""
                                                           headers:@{}]];
  XCTAssertEqual((NSInteger)200, docs.statusCode);
  NSString *docsBody = [[NSString alloc] initWithData:docs.bodyData
                                              encoding:NSUTF8StringEncoding];
  XCTAssertTrue([docsBody containsString:@"Arlen Swagger UI"]);
  XCTAssertTrue([docsBody containsString:@"Try It Out"]);
  XCTAssertTrue([docsBody containsString:@"fetch('/openapi.json')"]);

  ALNResponse *swagger = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                 path:@"/openapi/swagger"
                                                          queryString:@""
                                                              headers:@{}]];
  XCTAssertEqual((NSInteger)200, swagger.statusCode);
  NSString *swaggerBody = [[NSString alloc] initWithData:swagger.bodyData
                                                encoding:NSUTF8StringEncoding];
  XCTAssertTrue([swaggerBody containsString:@"Arlen Swagger UI"]);
}

- (void)testPluginLoadingAndLifecycleHooks {
  ALNApplication *app = [self buildAppWithPluginConfig:YES];
  XCTAssertEqual((NSInteger)1, [app.plugins count]);
  XCTAssertEqual((NSInteger)1, gPhase3APluginRegisterCount);

  NSError *startError = nil;
  BOOL started = [app startWithError:&startError];
  XCTAssertTrue(started);
  XCTAssertNil(startError);
  XCTAssertEqual((NSInteger)1, gPhase3APluginStartCount);

  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                  path:@"/plugin/ping"
                                                           queryString:@""
                                                               headers:@{}]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects(@"active", [response headerForName:@"X-Phase3A-Plugin"]);

  [app shutdown];
  XCTAssertEqual((NSInteger)1, gPhase3APluginStopCount);
}

@end
