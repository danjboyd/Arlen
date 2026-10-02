#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNRouter.h"

@interface RouterDummyController : NSObject
@end
@implementation RouterDummyController
- (id)index:(id)ctx { (void)ctx; return nil; }
@end

@interface RouterTests : XCTestCase
@end

@implementation RouterTests

- (void)testStaticRouteWinsOverParameterizedRoute {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/users/:id"
                    name:@"user_show"
         controllerClass:[RouterDummyController class]
                  action:@"index"];
  [router addRouteMethod:@"GET"
                    path:@"/users/me"
                    name:@"user_me"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  ALNRouteMatch *match = [router matchMethod:@"GET" path:@"/users/me"];
  XCTAssertNotNil(match);
  XCTAssertEqualObjects(match.route.name, @"user_me");
}

- (void)testParameterizedRouteExtractsParams {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/api/echo/:name"
                    name:@"api_echo"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  ALNRouteMatch *match = [router matchMethod:@"GET" path:@"/api/echo/hank"];
  XCTAssertNotNil(match);
  XCTAssertEqualObjects(match.params[@"name"], @"hank");
}

- (void)testDirectMatchAPIProvidesRouteAndParams {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/api/echo/:name"
                    name:@"api_echo"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  NSDictionary *params = nil;
  ALNRoute *route = [router matchMethod:@"GET"
                                   path:@"/api/echo/hank"
                                 format:nil
                                 params:&params];
  XCTAssertNotNil(route);
  XCTAssertEqualObjects(@"api_echo", route.name);
  XCTAssertEqualObjects(@"hank", params[@"name"]);
}

- (void)testParameterizedRouteFastPathHandlesTrailingSlashAndLongSegments {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/api/echo/:name"
                    name:@"api_echo"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  NSMutableString *segment = [NSMutableString string];
  for (NSUInteger idx = 0; idx < 1024; idx++) {
    [segment appendString:@"ab"];
  }
  NSString *path = [NSString stringWithFormat:@"/api/echo/%@/", segment];
  ALNRouteMatch *match = [router matchMethod:@"GET" path:path];
  XCTAssertNotNil(match);
  XCTAssertEqualObjects(segment, match.params[@"name"]);
}

- (void)testParameterizedRouteFastPathRejectsMissingTailSegment {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/api/echo/:name"
                    name:@"api_echo"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  ALNRouteMatch *match = [router matchMethod:@"GET" path:@"/api/echo/"];
  XCTAssertNil(match);
}

- (void)testWildcardRouteMatchesTail {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/assets/*path"
                    name:@"assets"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  ALNRouteMatch *match =
      [router matchMethod:@"GET" path:@"/assets/css/app/site.css"];
  XCTAssertNotNil(match);
  XCTAssertEqualObjects(match.params[@"path"], @"css/app/site.css");
}

- (void)testNestedRouteGroupAppliesPrefixGuardAndFormats {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router beginRouteGroupWithPrefix:@"/admin"
                        guardAction:@"requireAdmin"
                            formats:@[ @"json" ]];
  [router beginRouteGroupWithPrefix:@"/users" guardAction:nil formats:nil];
  [router addRouteMethod:@"GET"
                    path:@"/:id"
                    name:@"admin_user_show"
         controllerClass:[RouterDummyController class]
                  action:@"index"];
  [router endRouteGroup];
  [router endRouteGroup];

  ALNRouteMatch *jsonMatch =
      [router matchMethod:@"GET" path:@"/admin/users/42" format:@"json"];
  XCTAssertNotNil(jsonMatch);
  XCTAssertEqualObjects(jsonMatch.route.pathPattern, @"/admin/users/:id");
  XCTAssertEqualObjects(jsonMatch.route.guardActionName, @"requireAdmin");
  XCTAssertEqualObjects(jsonMatch.params[@"id"], @"42");

  ALNRouteMatch *htmlMatch =
      [router matchMethod:@"GET" path:@"/admin/users/42" format:@"html"];
  XCTAssertNil(htmlMatch);
}

- (void)testRoutePoliciesAttachAndAppearInRouteTable {
  ALNRouter *router = [[ALNRouter alloc] init];
  ALNRoute *route = [router addRouteMethod:@"GET"
                                      path:@"/admin"
                                      name:@"admin_index"
                                   formats:nil
                           controllerClass:[RouterDummyController class]
                               guardAction:nil
                                    action:@"index"
                                  policies:@[ @"admin", @" admin ", @"audit" ]];

  XCTAssertEqualObjects((@[ @"admin", @"audit" ]), route.policyNames);
  NSArray *table = [router routeTable];
  XCTAssertEqual((NSUInteger)1, [table count]);
  NSDictionary *entry = table[0];
  XCTAssertEqualObjects((@[ @"admin", @"audit" ]), entry[@"policies"]);
  XCTAssertEqualObjects(@"code", entry[@"source"]);
}

- (void)testFormatConditionSelectsMatchingRouteVariant {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/report"
                    name:@"report_html"
                 formats:@[ @"html" ]
         controllerClass:[RouterDummyController class]
             guardAction:nil
                  action:@"index"];
  [router addRouteMethod:@"GET"
                    path:@"/report"
                    name:@"report_json"
                 formats:@[ @"json" ]
         controllerClass:[RouterDummyController class]
             guardAction:nil
                  action:@"index"];

  ALNRouteMatch *htmlMatch = [router matchMethod:@"GET" path:@"/report" format:@"html"];
  XCTAssertNotNil(htmlMatch);
  XCTAssertEqualObjects(htmlMatch.route.name, @"report_html");

  ALNRouteMatch *jsonMatch = [router matchMethod:@"GET" path:@"/report" format:@"json"];
  XCTAssertNotNil(jsonMatch);
  XCTAssertEqualObjects(jsonMatch.route.name, @"report_json");
}

- (void)testAnyMethodFallbackStillMatchesWhenSpecificMethodMissing {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"ANY"
                    path:@"/status"
                    name:@"status_any"
         controllerClass:[RouterDummyController class]
                  action:@"index"];
  [router addRouteMethod:@"POST"
                    path:@"/status"
                    name:@"status_post"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  ALNRouteMatch *getMatch = [router matchMethod:@"GET" path:@"/status"];
  XCTAssertNotNil(getMatch);
  XCTAssertEqualObjects(@"status_any", getMatch.route.name);

  ALNRouteMatch *postMatch = [router matchMethod:@"POST" path:@"/status"];
  XCTAssertNotNil(postMatch);
  XCTAssertEqualObjects(@"status_post", postMatch.route.name);
}

- (void)testEmptyPathNormalizesToRootForMatching {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET"
                    path:@"/"
                    name:@"root"
         controllerClass:[RouterDummyController class]
                  action:@"index"];

  ALNRouteMatch *match = [router matchMethod:@"GET" path:@""];
  XCTAssertNotNil(match);
  XCTAssertEqualObjects(@"root", match.route.name);
}

- (void)testHeadFallsBackToGetRoutesWhenNoHeadRouteMatches {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET" path:@"/api/session" name:@"session" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"GET" path:@"/users/:id" name:@"user" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"GET" path:@"/files/*path" name:@"files" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"POST" path:@"/submit" name:@"submit" controllerClass:[RouterDummyController class] action:@"index"];

  XCTAssertEqualObjects(@"session", [router matchMethod:@"HEAD" path:@"/api/session"].route.name);
  ALNRouteMatch *user = [router matchMethod:@"head" path:@"/users/42"];
  XCTAssertEqualObjects(@"user", user.route.name);
  XCTAssertEqualObjects(@"42", user.params[@"id"]);
  ALNRouteMatch *files = [router matchMethod:@"HEAD" path:@"/files/a/b.txt"];
  XCTAssertEqualObjects(@"files", files.route.name);
  XCTAssertEqualObjects(@"a/b.txt", files.params[@"path"]);
  XCTAssertNil([router matchMethod:@"HEAD" path:@"/missing"]);
  XCTAssertNil([router matchMethod:@"HEAD" path:@"/submit"]);
  // Only HEAD borrows GET routes.
  XCTAssertNil([router matchMethod:@"OPTIONS" path:@"/api/session"]);
  XCTAssertNil([router matchMethod:@"POST" path:@"/api/session"]);
}

- (void)testExplicitHeadAndAnyRoutesWinOverGetFallback {
  ALNRouter *router = [[ALNRouter alloc] init];
  [router addRouteMethod:@"GET" path:@"/doc" name:@"doc_get" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"HEAD" path:@"/doc" name:@"doc_head" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"GET" path:@"/any" name:@"any_get" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"ANY" path:@"/any" name:@"any_any" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"GET" path:@"/static" name:@"static_get" controllerClass:[RouterDummyController class] action:@"index"];
  [router addRouteMethod:@"HEAD" path:@"/*rest" name:@"head_wildcard" controllerClass:[RouterDummyController class] action:@"index"];

  XCTAssertEqualObjects(@"doc_head", [router matchMethod:@"HEAD" path:@"/doc"].route.name);
  XCTAssertEqualObjects(@"doc_get", [router matchMethod:@"GET" path:@"/doc"].route.name);
  XCTAssertEqualObjects(@"any_any", [router matchMethod:@"HEAD" path:@"/any"].route.name);
  // Any explicit HEAD route, even a wildcard, takes precedence over the GET fallback.
  XCTAssertEqualObjects(@"head_wildcard", [router matchMethod:@"HEAD" path:@"/static"].route.name);
}

@end
