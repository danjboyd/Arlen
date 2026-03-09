#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNRouter.h"

static NSUInteger gPhase13EPasswordPolicyCalls = 0;
static NSUInteger gPhase13EProvisioningCalls = 0;
static NSUInteger gPhase13ESessionDescriptorCalls = 0;
static NSUInteger gPhase13EPostLoginRedirectCalls = 0;

@interface Phase13EPasswordPolicyHook : NSObject <ALNAuthModulePasswordPolicy>
@end

@implementation Phase13EPasswordPolicyHook

- (BOOL)authModuleValidatePassword:(NSString *)password
                      errorMessage:(NSString **)errorMessage {
  gPhase13EPasswordPolicyCalls += 1;
  if ([password isEqualToString:@"module-password-ok"]) {
    return YES;
  }
  if (errorMessage != NULL) {
    *errorMessage = @"Phase13E password policy rejected the candidate";
  }
  return NO;
}

@end

@interface Phase13EProvisioningHook : NSObject <ALNAuthModuleUserProvisioningHook>
@end

@implementation Phase13EProvisioningHook

- (NSDictionary *)authModuleUserValuesForEvent:(NSString *)event
                                proposedValues:(NSDictionary *)proposedValues {
  gPhase13EProvisioningCalls += 1;
  NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:proposedValues ?: @{}];
  values[@"display_name"] = [NSString stringWithFormat:@"hook:%@", event ?: @"unknown"];
  values[@"roles"] = @[ @"user", @"editor" ];
  return values;
}

@end

@interface Phase13ESessionPolicyHook : NSObject <ALNAuthModuleSessionPolicyHook>
@end

@implementation Phase13ESessionPolicyHook

- (NSDictionary *)authModuleSessionDescriptorForUser:(NSDictionary *)user
                                   defaultDescriptor:(NSDictionary *)defaultDescriptor {
  gPhase13ESessionDescriptorCalls += 1;
  NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:defaultDescriptor ?: @{}];
  descriptor[@"roles"] = @[ @"admin" ];
  descriptor[@"assuranceLevel"] = @2;
  return descriptor;
}

- (NSString *)authModulePostLoginRedirectForContext:(ALNContext *)context
                                               user:(NSDictionary *)user
                                    defaultRedirect:(NSString *)defaultRedirect {
  (void)context;
  (void)user;
  gPhase13EPostLoginRedirectCalls += 1;
  return @"/module/home";
}

@end

@interface Phase13ETests : XCTestCase
@end

@implementation Phase13ETests

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
      @"secret" : @"phase13e-session-secret-0123456789abcdef",
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

- (void)setUp {
  [super setUp];
  gPhase13EPasswordPolicyCalls = 0;
  gPhase13EProvisioningCalls = 0;
  gPhase13ESessionDescriptorCalls = 0;
  gPhase13EPostLoginRedirectCalls = 0;
  NSError *error = nil;
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:&error]);
  XCTAssertNil(error);
}

- (void)testDefaultAuthModuleConfigIsStableWithoutOverrides {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSDictionary *summary = [runtime resolvedHookSummary];

  XCTAssertEqualObjects(@"/auth", runtime.prefix);
  XCTAssertEqualObjects(@"/auth/api", runtime.apiPrefix);
  XCTAssertEqualObjects(@"/auth/login", runtime.loginPath);
  XCTAssertEqualObjects(@"/auth/register", runtime.registerPath);
  XCTAssertEqualObjects(@"/auth/logout", runtime.logoutPath);
  XCTAssertEqualObjects(@"/auth/session", runtime.sessionPath);
  XCTAssertEqualObjects(@"/auth/verify", runtime.verifyPath);
  XCTAssertEqualObjects(@"/auth/password/forgot", runtime.forgotPasswordPath);
  XCTAssertEqualObjects(@"/auth/password/reset", runtime.resetPasswordPath);
  XCTAssertEqualObjects(@"/auth/password/change", runtime.changePasswordPath);
  XCTAssertEqualObjects(@"/auth/mfa/totp", runtime.totpPath);
  XCTAssertEqualObjects(@"/auth/mfa/totp/verify", runtime.totpVerifyPath);
  XCTAssertEqualObjects(@"/auth/provider/stub/login", runtime.providerStubLoginPath);
  XCTAssertEqualObjects(@"/", runtime.defaultRedirect);
  XCTAssertEqualObjects(@"/auth/api", summary[@"apiPrefix"]);
  XCTAssertEqual((NSUInteger)1, runtime.loginProviders.count);
  XCTAssertEqualObjects(@"stub", runtime.loginProviders[0][@"identifier"]);
  XCTAssertTrue([runtime isProviderEnabled:@"stub"]);
  XCTAssertEqualObjects((@[ @{
                         @"identifier" : @"stub",
                         @"kind" : @"oidc",
                         @"ctaLabel" : @"Continue with Stub OIDC",
                         @"loginPath" : @"/auth/provider/stub/login",
                         @"apiLoginPath" : @"/auth/api/provider/stub/login",
                       } ]),
                       summary[@"loginProviders"]);
  XCTAssertEqualObjects(@"", summary[@"passwordPolicy"]);
  XCTAssertEqualObjects(@"", summary[@"userProvisioning"]);
  XCTAssertEqualObjects(@"", summary[@"sessionPolicy"]);

  NSString *errorMessage = nil;
  XCTAssertTrue([runtime validatePassword:@"long-enough" errorMessage:&errorMessage]);
  XCTAssertNil(errorMessage);

  NSDictionary *defaultDescriptor = @{
    @"subject" : @"user:test",
    @"provider" : @"local",
    @"methods" : @[ @"pwd" ],
    @"roles" : @[ @"user" ],
    @"scopes" : @[],
    @"assuranceLevel" : @1,
  };
  NSDictionary *resolved = [runtime sessionDescriptorForUser:@{ @"subject" : @"user:test" }
                                           defaultDescriptor:defaultDescriptor];
  XCTAssertEqualObjects(defaultDescriptor, resolved);

  NSDictionary *provisioned = [runtime provisionedUserValuesForEvent:@"register"
                                                      proposedValues:@{
                                                        @"subject" : @"user:test",
                                                        @"display_name" : @"Example",
                                                      }];
  XCTAssertEqualObjects(@"Example", provisioned[@"display_name"]);
}

- (void)testOverrideHooksAreInvokedDeterministically {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  BOOL configured = [runtime configureHooksWithModuleConfig:@{
    @"paths" : @{
      @"apiPrefix" : @"headless",
    },
    @"hooks" : @{
      @"passwordPolicyClass" : @"Phase13EPasswordPolicyHook",
      @"userProvisioningClass" : @"Phase13EProvisioningHook",
      @"sessionPolicyClass" : @"Phase13ESessionPolicyHook",
    },
  }
                                              error:&error];
  XCTAssertTrue(configured);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"/auth/headless", runtime.apiPrefix);

  NSString *errorMessage = nil;
  XCTAssertFalse([runtime validatePassword:@"short" errorMessage:&errorMessage]);
  XCTAssertEqualObjects(@"Phase13E password policy rejected the candidate", errorMessage);
  XCTAssertTrue([runtime validatePassword:@"module-password-ok" errorMessage:&errorMessage]);
  XCTAssertEqual((NSUInteger)2, gPhase13EPasswordPolicyCalls);

  NSDictionary *provisioned = [runtime provisionedUserValuesForEvent:@"registration"
                                                      proposedValues:@{
                                                        @"subject" : @"user:test",
                                                        @"display_name" : @"Original",
                                                        @"roles" : @[ @"user" ],
                                                      }];
  XCTAssertEqualObjects(@"hook:registration", provisioned[@"display_name"]);
  XCTAssertEqualObjects((@[ @"user", @"editor" ]), provisioned[@"roles"]);
  XCTAssertEqual((NSUInteger)1, gPhase13EProvisioningCalls);

  NSDictionary *defaultDescriptor = @{
    @"subject" : @"user:test",
    @"provider" : @"local",
    @"methods" : @[ @"pwd" ],
    @"roles" : @[ @"user" ],
    @"scopes" : @[],
    @"assuranceLevel" : @1,
  };
  NSDictionary *resolved = [runtime sessionDescriptorForUser:@{ @"subject" : @"user:test" }
                                           defaultDescriptor:defaultDescriptor];
  XCTAssertEqualObjects((@[ @"admin" ]), resolved[@"roles"]);
  XCTAssertEqualObjects(@2, resolved[@"assuranceLevel"]);
  XCTAssertEqual((NSUInteger)1, gPhase13ESessionDescriptorCalls);

  ALNContext *fakeContext = (ALNContext *)(id)[NSObject new];
  NSString *redirect = [runtime postLoginRedirectForContext:fakeContext
                                                       user:@{ @"subject" : @"user:test" }
                                            defaultRedirect:@"/"];
  XCTAssertEqualObjects(@"/module/home", redirect);
  XCTAssertEqual((NSUInteger)1, gPhase13EPostLoginRedirectCalls);
}

- (void)testDisabledProviderIsRemovedFromRuntimeLoginProviderList {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *config = @{
    @"providers" : @{
      @"stub" : @{
        @"enabled" : @NO,
      },
    },
  };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)0, runtime.loginProviders.count);
  XCTAssertFalse([runtime isProviderEnabled:@"stub"]);
  XCTAssertEqualObjects((@[]), [runtime resolvedHookSummary][@"loginProviders"]);
}

- (void)testDisabledProviderIsNotRegisteredAsRoute {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{
      @"providers" : @{
        @"stub" : @{
          @"enabled" : @NO,
        },
      },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  XCTAssertNil([app.router routeNamed:@"auth_provider_stub_login"]);
  XCTAssertNil([app.router routeNamed:@"auth_provider_stub_authorize"]);
  XCTAssertNil([app.router routeNamed:@"auth_provider_stub_callback"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_provider_stub_login"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_provider_stub_authorize"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_provider_stub_callback"]);
}

@end
