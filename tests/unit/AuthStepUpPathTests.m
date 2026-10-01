#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAuthModule.h"

// GitHub issue 97: authModule.paths.stepUp, the target module surfaces send a
// user to when a route needs higher assurance.
@interface AuthStepUpPathTests : XCTestCase
@end

@implementation AuthStepUpPathTests

- (void)tearDown {
  // The runtime is process-wide and other suites expect the default paths.
  [[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:NULL];
  [super tearDown];
}

- (ALNAuthModuleRuntime *)runtimeWithPaths:(NSDictionary *)paths error:(NSError **)error {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  BOOL configured = [runtime configureHooksWithModuleConfig:@{ @"paths" : paths ?: @{} } error:error];
  return configured ? runtime : nil;
}

- (void)testStepUpPathDefaultsToTheTOTPPath {
  NSError *error = nil;
  ALNAuthModuleRuntime *runtime = [self runtimeWithPaths:@{} error:&error];
  XCTAssertNotNil(runtime, @"%@", error);
  XCTAssertEqualObjects(@"/auth/mfa/totp", runtime.stepUpPath);
}

- (void)testStepUpPathFollowsThePrefixAndACustomTOTPPath {
  NSError *error = nil;
  ALNAuthModuleRuntime *runtime = [self runtimeWithPaths:@{ @"prefix" : @"/identity" } error:&error];
  XCTAssertNotNil(runtime, @"%@", error);
  XCTAssertEqualObjects(@"/identity/mfa/totp", runtime.stepUpPath);

  runtime = [self runtimeWithPaths:@{ @"totp" : @"/two-factor" } error:&error];
  XCTAssertNotNil(runtime, @"%@", error);
  XCTAssertEqualObjects(@"/two-factor", runtime.stepUpPath);
}

- (void)testConfiguredStepUpPathMayPointAtAProviderLoginWithAQuery {
  NSError *error = nil;
  ALNAuthModuleRuntime *runtime =
      [self runtimeWithPaths:@{ @"stepUp" : @"/auth/provider/entra/login?prompt=login" } error:&error];
  XCTAssertNotNil(runtime, @"%@", error);
  XCTAssertEqualObjects(@"/auth/provider/entra/login?prompt=login", runtime.stepUpPath);
  XCTAssertEqualObjects(@"/auth/mfa/totp", runtime.totpPath);

  runtime = [self runtimeWithPaths:@{ @"prefix" : @"/identity", @"stepUp" : @"provider/entra/login" } error:&error];
  XCTAssertNotNil(runtime, @"%@", error);
  XCTAssertEqualObjects(@"/identity/provider/entra/login", runtime.stepUpPath);
}

- (void)testStepUpPathMustBeALocalPath {
  NSArray *rejected = @[
    @"https://evil.example/step-up",
    @"//evil.example/step-up",
    @"/\\evil.example",
    @"/step up",
    @"/step-up#fragment",
  ];
  for (NSString *value in rejected) {
    NSError *error = nil;
    XCTAssertNil([self runtimeWithPaths:@{ @"stepUp" : value } error:&error], @"accepted %@", value);
    XCTAssertTrue([error.localizedDescription containsString:@"authModule.paths.stepUp"], @"%@: %@", value, error);
  }
}

@end
