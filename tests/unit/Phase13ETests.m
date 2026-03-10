#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNRouter.h"

static NSUInteger gPhase13EPasswordPolicyCalls = 0;
static NSUInteger gPhase13EProvisioningCalls = 0;
static NSUInteger gPhase13ESessionDescriptorCalls = 0;
static NSUInteger gPhase13EPostLoginRedirectCalls = 0;
static NSUInteger gPhase15UIContextCalls = 0;

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

@interface Phase15UIContextHook : NSObject <ALNAuthModuleUIContextHook>
@end

@implementation Phase15UIContextHook

- (NSString *)authModuleUILayoutForPage:(NSString *)pageIdentifier
                          defaultLayout:(NSString *)defaultLayout
                                context:(ALNContext *)context {
  (void)defaultLayout;
  (void)context;
  if ([pageIdentifier isEqualToString:@"login"]) {
    return @"layouts/test_guest";
  }
  return nil;
}

- (NSDictionary *)authModuleUIContextForPage:(NSString *)pageIdentifier
                              defaultContext:(NSDictionary *)defaultContext
                                     context:(ALNContext *)context {
  (void)defaultContext;
  (void)context;
  gPhase15UIContextCalls += 1;
  return @{
    @"phase15_page" : pageIdentifier ?: @"",
    @"brand_name" : @"Phase15 Brand",
  };
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

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)shellQuoted:(NSString *)value {
  NSString *string = value ?: @"";
  return [NSString stringWithFormat:@"'%@'", [string stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]];
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-XXXXXX", prefix ?: @"phase15"]];
  char *buffer = strdup([templatePath fileSystemRepresentation]);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
}

- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ?: @"" ];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  [task launch];
  [task waitUntilExit];
  if (exitCode != NULL) {
    *exitCode = task.terminationStatus;
  }
  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  NSMutableData *combined = [NSMutableData dataWithData:stdoutData ?: [NSData data]];
  if ([stderrData length] > 0) {
    [combined appendData:stderrData];
  }
  NSString *output = [[NSString alloc] initWithData:combined encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (NSDictionary *)parseJSONDictionary:(NSString *)output {
  NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error, @"invalid JSON: %@\n%@", error.localizedDescription, output);
  XCTAssertTrue([payload isKindOfClass:[NSDictionary class]]);
  return payload ?: @{};
}

- (void)setUp {
  [super setUp];
  gPhase13EPasswordPolicyCalls = 0;
  gPhase13EProvisioningCalls = 0;
  gPhase13ESessionDescriptorCalls = 0;
  gPhase13EPostLoginRedirectCalls = 0;
  gPhase15UIContextCalls = 0;
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
  XCTAssertEqualObjects(@"module-ui", summary[@"ui"][@"mode"]);
  XCTAssertEqualObjects(@"modules/auth/layouts/main", summary[@"ui"][@"layout"]);
  XCTAssertEqualObjects(@"auth", summary[@"ui"][@"generatedPagePrefix"]);
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

- (void)testAuthUIConfigurationResolvesGeneratedPathsAndContextHooks {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *config = @{
    @"ui" : @{
      @"mode" : @"generated-app-ui",
      @"layout" : @"layouts/guest",
      @"generatedPagePrefix" : @"accounts/auth",
      @"partials" : @{
        @"pageWrapper" : @"auth/partials/custom_page_wrapper",
      },
      @"contextClass" : @"Phase15UIContextHook",
    },
  };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:&error]);
  XCTAssertNil(error);

  XCTAssertEqualObjects(@"generated-app-ui", runtime.uiMode);
  XCTAssertEqualObjects(@"layouts/guest", runtime.layoutTemplate);
  XCTAssertEqualObjects(@"accounts/auth", runtime.generatedPagePrefix);
  XCTAssertFalse([runtime isHeadlessUIMode]);
  XCTAssertEqualObjects(@"accounts/auth/login", [runtime pageTemplatePathForIdentifier:@"login" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/password/reset",
                        [runtime pageTemplatePathForIdentifier:@"reset_password" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/partials/bodies/login_body",
                        [runtime bodyTemplatePathForIdentifier:@"login" defaultPath:@""]);
  XCTAssertEqualObjects(@"auth/partials/custom_page_wrapper",
                        [runtime partialTemplatePathForIdentifier:@"page_wrapper" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/partials/provider_row",
                        [runtime partialTemplatePathForIdentifier:@"provider_row" defaultPath:@""]);

  ALNContext *fakeContext = (ALNContext *)(id)[NSObject new];
  XCTAssertEqualObjects(@"layouts/test_guest", [runtime layoutTemplateForPage:@"login" context:fakeContext]);
  NSDictionary *uiContext = [runtime uiContextForPage:@"login"
                                       defaultContext:@{ @"existing" : @"ok" }
                                              context:fakeContext];
  XCTAssertEqualObjects(@"ok", uiContext[@"existing"]);
  XCTAssertEqualObjects(@"login", uiContext[@"phase15_page"]);
  XCTAssertEqualObjects(@"Phase15 Brand", uiContext[@"brand_name"]);
  XCTAssertEqual((NSUInteger)1, gPhase15UIContextCalls);
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

- (void)testHeadlessModeDoesNotRegisterInteractiveHTMLRoutes {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{
      @"ui" : @{
        @"mode" : @"headless",
      },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  XCTAssertNil([app.router routeNamed:@"auth_login_form"]);
  XCTAssertNil([app.router routeNamed:@"auth_register_form"]);
  XCTAssertNil([app.router routeNamed:@"auth_password_forgot_form"]);
  XCTAssertNil([app.router routeNamed:@"auth_password_reset_form"]);
  XCTAssertNil([app.router routeNamed:@"auth_totp_form"]);

  XCTAssertNotNil([app.router routeNamed:@"auth_login"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_register"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_session"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_verify"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_password_reset_form"]);
}

- (void)testModuleEjectAuthUIScaffoldsGeneratedTemplatesAndConfig {
  NSString *repoRoot = [self repoRoot];
  NSString *tempApp = [self createTempDirectoryWithPrefix:@"phase15-auth-eject"];
  XCTAssertNotNil(tempApp);

  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:[tempApp stringByAppendingPathComponent:@"config"]
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([@"{}\n" writeToFile:[tempApp stringByAppendingPathComponent:@"config/app.plist"]
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error]);
  XCTAssertNil(error);

  NSString *command = [NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && rm -f build/arlen && make arlen >/dev/null && cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module eject auth-ui --json",
                                                 [self shellQuoted:repoRoot],
                                                 [self shellQuoted:tempApp],
                                                 [self shellQuoted:repoRoot],
                                                 [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]]];
  int exitCode = 0;
  NSString *output = [self runShellCapture:command exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", output);

  NSDictionary *payload = [self parseJSONDictionary:output];
  XCTAssertEqualObjects(@"ok", payload[@"status"]);
  XCTAssertEqualObjects(@"eject", payload[@"workflow"]);
  XCTAssertEqualObjects(@"auth-ui", payload[@"target"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/login.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"public/auth/auth.css"]);
  XCTAssertTrue([payload[@"updated_files"] containsObject:@"config/app.plist"]);

  NSString *configText = [NSString stringWithContentsOfFile:[tempApp stringByAppendingPathComponent:@"config/app.plist"]
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([configText containsString:@"generated-app-ui"]);
  XCTAssertTrue([configText containsString:@"layouts/auth_generated"]);
  XCTAssertTrue([configText containsString:@"generatedPagePrefix = auth"]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/auth/partials/page_wrapper.html.eoc"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/layouts/auth_generated.html.eoc"]]);
}

@end
