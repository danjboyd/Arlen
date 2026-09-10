#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNMCPModule.h"
#import "ALNMCPSchema.h"
#import "ALNApplication.h"
#import "ALNAuth.h"
#import "ALNAuthSession.h"
#import "ALNResponseEnvelopeMiddleware.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRouter.h"

static NSUInteger Calls;
static NSDictionary *Annotations(void) {
  return @{ @"readOnlyHint": @YES, @"destructiveHint": @NO, @"idempotentHint": @YES, @"openWorldHint": @NO };
}
static NSDictionary *ObjectSchema(void) { return @{ @"type": @"object", @"properties": @{} }; }
@interface MCPTestController : ALNController
@end
@implementation MCPTestController
- (id)item:(ALNContext *)context {
  Calls++;
  return @{ @"id": context.params[@"id"] ?: @"none", @"q": [context queryValueForName:@"q"] ?: @"", @"subject": [context authSubject] ?: @"anonymous" };
}
- (BOOL)guard:(ALNContext *)context {
  if ([[context headerValueForName:@"x-deny-guard"] isEqual:@"yes"]) {
    context.response.statusCode = 403; context.response.committed = YES; return NO;
  }
  return YES;
}
- (id)body:(ALNContext *)context { Calls++; return @{ @"title": [context validatedValueForName:@"title"] ?: @"" }; }
- (id)sessionFixture:(ALNContext *)context {
  [ALNAuthSession establishAuthenticatedSessionForSubject:@"reader" provider:@"fixture" methods:@[@"password"] scopes:@[@"catalog:read"] roles:@[@"reader"] assuranceLevel:1 authenticatedAt:[NSDate date] context:context error:NULL];
  return @{@"csrf":[context csrfToken] ?: @""};
}
- (id)explode:(ALNContext *)context { [NSException raise:@"Test" format:@"secret must not leak"]; return nil; }
@end
@interface MCPTestAuth : NSObject <ALNMiddleware>
@property(nonatomic, assign) NSUInteger visits;
@property(nonatomic, assign) BOOL endpointOnly;
@end
@implementation MCPTestAuth
- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  self.visits++;
  if (self.endpointOnly && ![context.request.path isEqual:@"/mcp"]) return YES;
  NSString *credential = [context headerValueForName:@"authorization"];
  if ([credential isEqual:@"Bearer reader"]) [ALNAuth applyClaims:@{@"sub": @"reader", @"scope": @"catalog:read", @"roles": @[@"reader"]} toContext:context];
  if ([credential isEqual:@"Bearer visitor"]) [ALNAuth applyClaims:@{@"sub": @"visitor"} toContext:context];
  if ([[context headerValueForName:@"x-deny-middleware"] isEqual:context.routeName]) {
    context.response.statusCode = 429; context.response.committed = YES; return NO;
  }
  return YES;
}
@end
@interface MCPModuleTests : XCTestCase
@property(nonatomic, strong) ALNApplication *app;
@property(nonatomic, strong) ALNMCPModule *module;
@property(nonatomic, strong) MCPTestAuth *auth;
@end
@implementation MCPModuleTests
- (void)setUp { [super setUp]; Calls = 0; [self configure:@{}]; }
- (void)configure:(NSDictionary *)extra {
  NSMutableDictionary *config = [@{ @"environment": @"test", @"logLevel": @"error", @"csrf": @{@"enabled": @NO}, @"mcp": @{@"enabled": @YES} } mutableCopy];
  [config addEntriesFromDictionary:extra];
  self.app = [[ALNApplication alloc] initWithConfig:config];
  self.auth = [MCPTestAuth new]; [self.app addMiddleware:self.auth];
  ALNRoute *route = [self.app registerRouteMethod:@"GET" path:@"/catalog/:id" name:@"catalog_item" formats:nil controllerClass:[MCPTestController class] guardAction:@"guard" action:@"item"];
  route.operationID = @"catalog.get"; route.summary = @"Read catalog item";
  route.requiredScopes = @[@"catalog:read"]; route.requiredRoles = @[@"reader"];
  route.requestSchema = @{ @"type": @"object", @"properties": @{
      @"id": @{@"type": @"string", @"source": @"path", @"required": @YES},
      @"q": @{@"type": @"string", @"source": @"query"} } };
  [self.app registerRouteMethod:@"GET" path:@"/unlisted" name:@"unlisted" controllerClass:[MCPTestController class] action:@"item"];
  self.module = [ALNMCPModule new];
}
- (void)routeTool {
  XCTAssertTrue(([self.module registerRouteTool:@{@"routeName": @"catalog_item", @"annotations": Annotations()} transform:nil error:NULL]));
}
- (void)install {
  NSError *error = nil;
  XCTAssertTrue([self.module registerWithApplication:self.app error:&error], @"%@", error);
  XCTAssertTrue([self.app startWithError:&error], @"%@", error);
}
- (ALNResponse *)send:(id)message headers:(NSDictionary *)overrides method:(NSString *)method path:(NSString *)path {
  NSMutableDictionary *headers = [@{@"content-type": @"application/json", @"accept": @"application/json, text/event-stream", @"authorization": @"Bearer reader", @"mcp-protocol-version": @"2025-11-25"} mutableCopy];
  [headers addEntriesFromDictionary:overrides ?: @{}];
  NSData *body = [message isKindOfClass:[NSData class]] ? message : [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
  ALNRequest *req = [[ALNRequest alloc] initWithMethod:method path:path queryString:@"" headers:headers body:body];
  req.remoteAddress = @"203.0.113.5";
  return [self.app dispatchRequest:req];
}
- (NSDictionary *)decode:(ALNResponse *)response {
  return [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:NULL];
}
- (NSDictionary *)rpc:(NSString *)method params:(NSDictionary *)params headers:(NSDictionary *)headers {
  return [self decode:[self send:@{@"jsonrpc": @"2.0", @"id": @7, @"method": method, @"params": params ?: @{}}
                                headers:headers method:@"POST" path:@"/mcp"]];
}
- (NSDictionary *)call:(NSString *)name arguments:(NSDictionary *)args headers:(NSDictionary *)headers {
  return [self rpc:@"tools/call" params:@{@"name":name, @"arguments":args} headers:headers];
}
- (void)testDisabledByDefaultAndExplicitExposure {
  [self configure:@{@"mcp":@{}}]; [self routeTool]; [self install];
  XCTAssertEqual(404, [self send:@{} headers:nil method:@"POST" path:@"/mcp"].statusCode);
  [self configure:@{}]; [self routeTool]; [self install];
  NSArray *tools = [self rpc:@"tools/list" params:nil headers:nil][@"result"][@"tools"];
  XCTAssertEqual(1u, tools.count);
  XCTAssertEqualObjects(@"catalog.get", tools[0][@"name"]);
  XCTAssertEqualObjects(@"Read catalog item", tools[0][@"description"]);
  XCTAssertNil(tools[0][@"inputSchema"][@"properties"][@"id"][@"source"]);
  XCTAssertEqualObjects((@[@"id"]), tools[0][@"inputSchema"][@"required"]);
}
- (void)testInitializationVersionNegotiationAndNotifications {
  [self routeTool]; [self install];
  NSDictionary *reply = [self rpc:@"initialize" params:@{@"protocolVersion":@"future", @"capabilities":@{@"sampling":@{}}, @"clientInfo":@{@"name":@"test", @"version":@"1"}} headers:@{@"mcp-protocol-version":@""}];
  XCTAssertEqualObjects(@"2025-11-25", reply[@"result"][@"protocolVersion"]);
  XCTAssertEqualObjects((@{@"tools":@{}}), reply[@"result"][@"capabilities"]);
  for (NSString *method in @[@"notifications/initialized", @"notifications/cancelled", @"unknown", @"tools/call"]) {
    ALNResponse *r = [self send:@{@"jsonrpc":@"2.0", @"method":method, @"params":@{@"name":@"catalog.get", @"arguments":@{@"id":@"1"}}} headers:nil method:@"POST" path:@"/mcp"];
    XCTAssertEqual(202, r.statusCode); XCTAssertEqual(0u, r.bodyLength);
  }
  XCTAssertEqual(0u, Calls);
  XCTAssertEqualObjects(@{}, [self rpc:@"ping" params:nil headers:nil][@"result"]);
  XCTAssertEqualObjects(@(-32602), [self rpc:@"initialize" params:@{} headers:nil][@"error"][@"code"]);
}
- (void)testTransportHeadersOriginAndAuthentication {
  [self routeTool]; [self install];
  NSArray *cases = @[
    @[@{@"authorization":@""}, @401],
    @[@{@"authorization":@"Bearer forged", @"x-user-id":@"reader"}, @401],
    @[@{@"origin":@"https://evil.example"}, @403],
    @[@{@"mcp-protocol-version":@"2026-07-28"}, @400],
    @[@{@"mcp-protocol-version":@""}, @400],
    @[@{@"content-type":@"text/plain"}, @415],
    @[@{@"accept":@"application/json"}, @406]
  ];
  for (NSArray *item in cases) {
    ALNResponse *r = [self send:@{@"jsonrpc":@"2.0", @"id":@1, @"method":@"tools/list"} headers:item[0] method:@"POST" path:@"/mcp"];
    XCTAssertEqual([item[1] integerValue], r.statusCode, @"%@", item);
  }
  for (NSString *method in @[@"GET", @"DELETE", @"PUT"]) XCTAssertEqual(405, [self send:@{} headers:nil method:method path:@"/mcp"].statusCode);
  XCTAssertEqual(0u, Calls);
}
- (void)testProtocolErrorsAreSeparateFromExecutionErrors {
  [self routeTool]; [self install];
  XCTAssertEqualObjects(@(-32601), [self rpc:@"resources/list" params:nil headers:nil][@"error"][@"code"]);
  XCTAssertEqualObjects(@(-32602), [self call:@"missing" arguments:@{} headers:nil][@"error"][@"code"]);
  XCTAssertEqualObjects(@(-32602), [self rpc:@"tools/list" params:@{@"cursor":@"bad"} headers:nil][@"error"][@"code"]);
  for (id message in @[@[], @{@"jsonrpc":@"2.0", @"id":[NSNull null], @"method":@"ping"}, @{@"jsonrpc":@"2.0", @"id":@YES, @"method":@"ping"}]) {
    XCTAssertEqualObjects(@(-32600), [self decode:[self send:message headers:nil method:@"POST" path:@"/mcp"]][@"error"][@"code"]);
  }
  XCTAssertEqualObjects(@(-32700), [self decode:[self send:[@"{" dataUsingEncoding:NSUTF8StringEncoding] headers:nil method:@"POST" path:@"/mcp"]][@"error"][@"code"]);
  for (NSDictionary *args in @[@{}, @{@"id":@1}, @{@"id":@"1", @"identity":@"admin"}, @{@"id":@"../admin"}]) {
    NSDictionary *r = [self call:@"catalog.get" arguments:args headers:nil];
    XCTAssertNil(r[@"error"]); XCTAssertEqualObjects(@YES, r[@"result"][@"isError"]);
  }
  XCTAssertEqual(0u, Calls);
}
- (void)testRouteDispatchReauthenticatesAndPreservesGuardAndMiddleware {
  [self routeTool]; [self install];
  NSDictionary *r = [self call:@"catalog.get" arguments:@{@"id":@"42", @"q":@"a&b=é"} headers:nil][@"result"];
  XCTAssertEqualObjects(@NO, r[@"isError"]);
  XCTAssertEqualObjects((@{@"id":@"42", @"q":@"a&b=é", @"subject":@"reader"}), r[@"structuredContent"]);
  XCTAssertEqual(2u, self.auth.visits); XCTAssertEqual(1u, Calls);
  XCTAssertTrue([r[@"content"] count] > 0);
  for (NSDictionary *headers in @[@{@"authorization":@"Bearer visitor"}, @{@"x-deny-guard":@"yes"}, @{@"x-deny-middleware":@"catalog_item"}]) {
    XCTAssertEqualObjects(@YES, [self call:@"catalog.get" arguments:@{@"id":@"42"} headers:headers][@"result"][@"isError"]);
  }
  XCTAssertEqual(1u, Calls);
}
- (void)testSourceIPPolicyParityIncludingForwardedHeaderSpoofing {
  [self configure:@{@"security":@{@"routePolicies":@{@"catalog":@{@"pathPrefixes":@[@"/catalog"], @"sourceIPAllowlist":@[@"127.0.0.1/32"]}}}}];
  [self routeTool]; [self install];
  NSDictionary *headers = @{@"x-forwarded-for":@"127.0.0.1"};
  ALNResponse *direct = [self send:@{} headers:headers method:@"GET" path:@"/catalog/42"];
  XCTAssertEqual(403, direct.statusCode);
  NSDictionary *result = [self call:@"catalog.get" arguments:@{@"id":@"42"} headers:headers][@"result"];
  XCTAssertEqualObjects(@YES, result[@"isError"]);
  XCTAssertTrue([result[@"content"][0][@"text"] containsString:@"403"]);
  XCTAssertEqual(0u, Calls);
}
- (void)testCustomServiceToolPermissionsPrivateGateAndStructuredLinks {
  XCTAssertTrue(([self.module registerTool:@{@"name":@"service.summary", @"annotations":Annotations(), @"inputSchema":ObjectSchema(), @"requiredScopes":@[@"catalog:read"], @"requiredRoles":@[@"reader"], @"outputSchema":@{@"type":@"object", @"properties":@{@"count":@{@"type":@"integer"}}, @"required":@[@"count"]}}
      handler:^NSDictionary *(NSDictionary *args, ALNContext *ctx, NSError **error) {
        Calls++; return @{@"structuredContent":@{@"count":@3}, @"content":@[@{@"type":@"resource_link", @"uri":@"https://example.org/catalog", @"name":@"Catalog"}]};
      } error:NULL]));
  [self install];
  NSDictionary *result = [self call:@"service.summary" arguments:@{} headers:nil][@"result"];
  XCTAssertEqualObjects(@NO, result[@"isError"]);
  XCTAssertEqualObjects(@3, result[@"structuredContent"][@"count"]);
  XCTAssertEqual(2u, [result[@"content"] count]);
  XCTAssertEqualObjects(@YES, [self call:@"service.summary" arguments:@{} headers:@{@"authorization":@"Bearer visitor"}][@"result"][@"isError"]);
  XCTAssertEqual(404, [self send:@{} headers:nil method:@"POST" path:@"/mcp/_tools/mcp.private.0"].statusCode);
  XCTAssertEqual(1u, Calls);
}
- (void)testOutputValidationBoundsAndSafeFailure {
  [self configure:@{@"mcp":@{@"enabled":@YES, @"maxOutputBytes":@1024}}];
  for (NSString *name in @[@"bad.schema", @"too.big", @"throws"]) {
    [self.module registerTool:@{@"name":name, @"annotations":Annotations(), @"inputSchema":ObjectSchema(), @"outputSchema":ObjectSchema()}
       handler:^NSDictionary *(NSDictionary *args, ALNContext *ctx, NSError **error) {
         if ([name isEqual:@"throws"]) [NSException raise:@"Secret" format:@"private password"];
         if ([name isEqual:@"too.big"]) return @{@"content":@[@{@"type":@"text", @"text":[@"x" stringByPaddingToLength:2000 withString:@"x" startingAtIndex:0]}]};
         return @{@"structuredContent":@{@"unexpected":@1}};
       } error:NULL];
  }
  [self install];
  for (NSString *name in @[@"bad.schema", @"too.big", @"throws"]) {
    NSDictionary *result = [self call:name arguments:@{} headers:nil][@"result"];
    XCTAssertEqualObjects(@YES, result[@"isError"]);
    XCTAssertFalse([[result description] containsString:@"private password"]);
  }
}
- (void)testExplicitNameMappingAndResponseTransformation {
  [self.module registerRouteTool:@{@"routeName":@"catalog_item", @"name":@"stable.v1", @"description":@"Stable contract", @"annotations":Annotations(),
      @"inputSchema":@{@"type":@"object", @"properties":@{@"item":@{@"type":@"string"}}, @"required":@[@"item"]},
      @"argumentMapping":@{@"item":@{@"source":@"path", @"name":@"id"}}, @"outputSchema":ObjectSchema()}
      transform:^NSDictionary *(ALNResponse *response, NSError **error) { return @{@"structuredContent":@{}}; } error:NULL];
  [self install];
  XCTAssertEqualObjects(@{}, [self call:@"stable.v1" arguments:@{@"item":@"7"} headers:nil][@"result"][@"structuredContent"]);
  XCTAssertEqual(1u, Calls);
}
- (void)testStartupRejectsCollisionsUnsupportedSchemasAndMappings {
  NSArray *overrides = @[
    @{@"name":@"bad name"}, @{@"annotations":@{}}, @{@"routeName":@"missing"},
    @{@"inputSchema":@{@"type":@"object", @"nullable":@YES}},
    @{@"argumentMapping":@{@"id":@{@"source":@"header", @"name":@"authorization"}, @"q":@{@"source":@"query", @"name":@"q"}}}
  ];
  for (NSDictionary *override in overrides) {
    [self configure:@{}];
    NSMutableDictionary *definition = [@{@"routeName":@"catalog_item", @"annotations":Annotations()} mutableCopy];
    [definition addEntriesFromDictionary:override];
    [self.module registerRouteTool:definition transform:nil error:NULL];
    XCTAssertTrue([self.module registerWithApplication:self.app error:NULL]);
    NSError *error = nil; XCTAssertFalse([self.app startWithError:&error]); XCTAssertNotNil(error);
  }
  [self configure:@{}]; [self routeTool]; [self routeTool];
  XCTAssertTrue([self.module registerWithApplication:self.app error:NULL]);
  XCTAssertFalse([self.app startWithError:NULL]);
}
- (void)testSchemaSubsetRejectsUnsupportedKeywordsAndValidatesTypes {
  for (NSString *key in @[@"$ref", @"nullable", @"oneOf", @"format", @"default", @"coerce", @"transformer"]) {
    XCTAssertNil(ALNMCPSchema(@{@"type":@"object", key:@"unsupported"}, NO, NULL));
  }
  NSDictionary *schema = ALNMCPSchema(@{@"type":@"object", @"properties":@{
      @"n":@{@"type":@"integer", @"minimum":@1, @"maximum":@3}, @"b":@{@"type":@"boolean"},
      @"s":@{@"type":@"string", @"minLength":@1, @"maxLength":@1},
      @"a":@{@"type":@"array", @"items":@{@"type":@"string", @"enum":@[@"x"]}, @"maxItems":@1}}}, NO, NULL);
  XCTAssertNotNil(schema);
  XCTAssertTrue(ALNMCPValidate(@{@"n":@2, @"b":@YES, @"s":@"😀", @"a":@[@"x"]}, schema));
  for (NSDictionary *bad in @[@{@"n":@YES}, @{@"n":@4}, @{@"b":@1}, @{@"s":@"ab"}, @{@"a":@[@"y"]}, @{@"extra":@1}]) XCTAssertFalse(ALNMCPValidate(bad, schema), @"%@", bad);
}
- (void)testConstrainedDispatchRejectsAlternateRouteAndMountedApplication {
  [self routeTool]; [self install];
  ALNRoute *expected = [self.app.router routeNamed:@"catalog_item"];
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET" path:@"/unlisted" queryString:@"" headers:@{} body:[NSData data]];
  XCTAssertEqual(409, [self.app dispatchRequest:request requiringRoute:expected].statusCode);
  ALNApplication *mounted = [[ALNApplication alloc] initWithConfig:@{@"csrf":@{@"enabled":@NO}}];
  [mounted registerRouteMethod:@"GET" path:@"/:id" name:@"other" controllerClass:[MCPTestController class] action:@"item"];
  XCTAssertTrue([self.app mountApplication:mounted atPrefix:@"/catalog"]);
  XCTAssertEqualObjects(@YES, [self call:@"catalog.get" arguments:@{@"id":@"42"} headers:nil][@"result"][@"isError"]);
  XCTAssertEqual(0u, Calls);
}
- (void)testSessionAuthenticationAndCSRFRemainRequired {
  [self configure:@{@"session":@{@"enabled":@YES, @"secret":@"mcp-test-session-secret-0123456789abcdef", @"secure":@NO}, @"csrf":@{@"enabled":@YES}}];
  [self.app registerRouteMethod:@"GET" path:@"/session-fixture" name:@"session_fixture" controllerClass:[MCPTestController class] action:@"sessionFixture"];
  [self routeTool]; [self install];
  ALNResponse *bootstrap = [self send:@{} headers:nil method:@"GET" path:@"/session-fixture"];
  NSString *cookie = [[[bootstrap headerForName:@"Set-Cookie"] componentsSeparatedByString:@";"] firstObject];
  NSString *csrf = [self decode:bootstrap][@"csrf"];
  XCTAssertTrue(cookie.length > 0); XCTAssertTrue(csrf.length > 0);
  NSDictionary *headers = @{@"authorization":@"", @"cookie":cookie ?: @"", @"x-csrf-token":csrf ?: @""};
  NSDictionary *result = [self call:@"catalog.get" arguments:@{@"id":@"42"} headers:headers][@"result"];
  XCTAssertEqualObjects(@NO, result[@"isError"]);
  XCTAssertEqualObjects(@"reader", result[@"structuredContent"][@"subject"]);
  ALNResponse *denied = [self send:@{@"jsonrpc":@"2.0", @"id":@1, @"method":@"tools/list"} headers:@{@"authorization":@"", @"cookie":cookie ?: @""} method:@"POST" path:@"/mcp"];
  XCTAssertEqual(403, denied.statusCode);
  XCTAssertEqual(1u, Calls);
}
- (void)testBodyMappingAndEnvelopeCompatibility {
  [self.app addMiddleware:[ALNResponseEnvelopeMiddleware new]];
  ALNRoute *route = [self.app registerRouteMethod:@"POST" path:@"/echo" name:@"echo" controllerClass:[MCPTestController class] action:@"body"];
  route.requiredScopes = @[@"catalog:read"];
  route.requestSchema = @{@"type":@"object", @"properties":@{@"title":@{@"type":@"string", @"source":@"body", @"required":@YES}}};
  [self.module registerRouteTool:@{@"routeName":@"echo", @"annotations":Annotations(), @"inputSchema":@{@"type":@"object", @"properties":@{@"label":@{@"type":@"string"}}, @"required":@[@"label"]}, @"argumentMapping":@{@"label":@{@"source":@"body", @"name":@"title"}}}
      transform:^NSDictionary *(ALNResponse *response, NSError **error) {
        NSDictionary *envelope = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:error];
        return @{@"structuredContent":envelope[@"data"] ?: @{}};
      } error:NULL];
  [self.module registerTool:@{@"name":@"custom", @"annotations":Annotations()} handler:^NSDictionary *(NSDictionary *args, ALNContext *ctx, NSError **error) { return @{@"structuredContent":@{}}; } error:NULL];
  [self install];
  NSDictionary *reply = [self call:@"echo" arguments:@{@"label":@"hello"} headers:nil];
  XCTAssertEqualObjects(@"2.0", reply[@"jsonrpc"]); XCTAssertNil(reply[@"data"]);
  XCTAssertEqualObjects(@"hello", reply[@"result"][@"structuredContent"][@"title"]);
  XCTAssertEqualObjects(@NO, [self call:@"custom" arguments:@{} headers:nil][@"result"][@"isError"]);
}
- (void)testCustomAssurancePolicyAndTransportRateLimit {
  [self configure:@{@"mcp":@{@"enabled":@YES, @"requestsPerMinute":@2}, @"security":@{@"routePolicies":@{@"local":@{@"sourceIPAllowlist":@[@"127.0.0.1/32"]}}}}];
  for (NSDictionary *extra in @[@{@"name":@"assurance", @"minimumAuthAssuranceLevel":@2}, @{@"name":@"policy", @"policies":@[@"local"]}]) {
    NSMutableDictionary *d = [@{@"annotations":Annotations()} mutableCopy]; [d addEntriesFromDictionary:extra];
    [self.module registerTool:d handler:^NSDictionary *(NSDictionary *args, ALNContext *ctx, NSError **error) { Calls++; return @{@"structuredContent":@{}}; } error:NULL];
  }
  [self install];
  for (NSString *name in @[@"assurance", @"policy"]) XCTAssertEqualObjects(@YES, [self call:name arguments:@{} headers:nil][@"result"][@"isError"]);
  XCTAssertEqual(0u, Calls);
  ALNResponse *limited = [self send:@{@"jsonrpc":@"2.0", @"id":@1, @"method":@"tools/list"} headers:nil method:@"POST" path:@"/mcp"];
  XCTAssertEqual(429, limited.statusCode);
}
- (void)testOuterIdentityCannotSubstituteForInnerAuthentication {
  self.auth.endpointOnly = YES;
  [self.module registerTool:@{@"name":@"identity", @"annotations":Annotations()}
      handler:^NSDictionary *(NSDictionary *args, ALNContext *ctx, NSError **error) {
        Calls++; return @{@"structuredContent":@{}};
      } error:NULL];
  [self install];
  XCTAssertEqualObjects(@YES, [self call:@"identity" arguments:@{} headers:nil][@"result"][@"isError"]);
  XCTAssertEqual(0u, Calls);
}
@end
