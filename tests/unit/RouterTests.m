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

@end
