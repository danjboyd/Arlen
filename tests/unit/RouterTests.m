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

@end
