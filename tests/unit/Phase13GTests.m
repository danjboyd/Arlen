#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>

#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNRoute.h"
#import "ALNRouter.h"

@interface Phase13GTests : XCTestCase
@end

@implementation Phase13GTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (ALNApplication *)applicationWithConfig:(NSDictionary *)extraConfig {
  NSString *dsn = [self pgTestDSN];
  NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @YES,
      @"secret" : @"phase13g-session-secret-0123456789abcdef",
    },
    @"csrf" : @{
      @"enabled" : @YES,
      @"allowQueryParamFallback" : @YES,
    },
    @"database" : @{
      @"connectionString" : dsn ?: @"",
    },
  }];
  [config addEntriesFromDictionary:extraConfig ?: @{}];
  return [[ALNApplication alloc] initWithConfig:config];
}

- (void)testDefaultMountConfigurationIsDeterministic {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self applicationWithConfig:nil];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  NSDictionary *summary = [runtime resolvedConfigSummary];
  XCTAssertEqualObjects(@"/admin", runtime.mountPrefix);
  XCTAssertEqualObjects(@"/api", runtime.apiPrefix);
  XCTAssertEqualObjects(@"Arlen Admin", runtime.dashboardTitle);
  XCTAssertEqualObjects(@"/admin", summary[@"mountPrefix"]);
  XCTAssertNotNil(runtime.mountedApplication);
}

- (void)testHTMLAndJSONContractsReflectRoleAndStepUpRequirements {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{
      @"paths" : @{
        @"prefix" : @"/identity",
      },
    },
    @"adminUI" : @{
      @"title" : @"Backoffice",
      @"paths" : @{
        @"prefix" : @"/backoffice",
        @"apiPrefix" : @"/v1",
      },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  ALNApplication *mounted = runtime.mountedApplication;
  XCTAssertNotNil(mounted);

  ALNRoute *htmlRoute = [mounted.router routeNamed:@"admin_dashboard"];
  XCTAssertNotNil(htmlRoute);
  XCTAssertEqualObjects(@"requireAdminHTML", htmlRoute.guardActionName);

  ALNRoute *apiRoute = [mounted.router routeNamed:@"admin_api_session"];
  XCTAssertNotNil(apiRoute);
  XCTAssertEqualObjects((@[ @"admin" ]), apiRoute.requiredRoles);
  XCTAssertEqual((NSUInteger)2, apiRoute.minimumAuthAssuranceLevel);
  XCTAssertEqualObjects(@"/identity/mfa/totp", apiRoute.stepUpPath);

  XCTAssertEqualObjects(@"/backoffice", runtime.mountPrefix);
  XCTAssertEqualObjects(@"/v1", runtime.apiPrefix);
  XCTAssertEqualObjects(@"Backoffice", runtime.dashboardTitle);
}

@end
