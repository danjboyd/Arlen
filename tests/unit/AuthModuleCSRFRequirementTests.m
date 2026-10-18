#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"

// Generated app.plist files used to pin csrf.enabled = NO, which left the auth
// module's session-backed forms open to cross-site posts. The module now
// refuses that combination at startup unless the app opts out.
@interface AuthModuleCSRFRequirementTests : XCTestCase
@end

@implementation AuthModuleCSRFRequirementTests

- (void)tearDown {
  // The runtime is process-wide and other suites expect the default paths.
  [[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:NULL];
  [super tearDown];
}

- (NSError *)configureErrorWithConfig:(NSDictionary *)config {
  NSMutableDictionary *full = [NSMutableDictionary dictionaryWithDictionary:config];
  full[@"environment"] = @"test";
  ALNApplication *application = [[ALNApplication alloc] initWithConfig:full];
  NSError *error = nil;
  BOOL configured = [[ALNAuthModuleRuntime sharedRuntime] configureWithApplication:application error:&error];
  XCTAssertFalse(configured);
  return error;
}

- (void)testSessionsWithCSRFPinnedOffFailStartup {
  NSError *error = [self configureErrorWithConfig:@{
    @"session" : @{ @"enabled" : @YES },
    @"csrf" : @{ @"enabled" : @NO },
  }];
  XCTAssertEqualObjects(ALNAuthModuleErrorDomain, error.domain);
  XCTAssertEqual(ALNAuthModuleErrorInvalidConfiguration, error.code);
  XCTAssertEqualObjects(@"csrf.enabled", error.userInfo[@"key_path"]);
  XCTAssertTrue([error.localizedDescription containsString:@"allowWithoutCSRF"]);
}

// Past the CSRF check, startup stops at the next requirement (the database),
// which shows the CSRF check passed.
- (void)testCSRFOnOrOptedOutPassesTheCheck {
  NSArray<NSDictionary *> *configs = @[
    @{ @"session" : @{ @"enabled" : @YES }, @"csrf" : @{ @"enabled" : @YES } },
    @{ @"session" : @{ @"enabled" : @YES } },
    @{
      @"session" : @{ @"enabled" : @YES },
      @"csrf" : @{ @"enabled" : @NO },
      @"authModule" : @{ @"allowWithoutCSRF" : @YES },
    },
  ];
  for (NSDictionary *config in configs) {
    NSError *error = [self configureErrorWithConfig:config];
    XCTAssertEqualObjects(@"database.connectionString", error.userInfo[@"key_path"], @"%@", config);
  }
}

@end
