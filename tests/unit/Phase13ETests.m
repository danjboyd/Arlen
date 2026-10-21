#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#import "ALNApplication.h"
#import "ALNController.h"
#import "ALNAuthModule.h"
#import "ALNJobsModule.h"
#import "ALNPostgresJobAdapter.h"
#import "ALNContext.h"
#import "ALNEOCRuntime.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRouter.h"
#import "ALNSecurityPrimitives.h"
#import "ALNServices.h"
#import "../shared/ALNTestSupport.h"

static NSUInteger gPhase13EPasswordPolicyCalls = 0;
static NSUInteger gPhase13EProvisioningCalls = 0;
static NSUInteger gPhase13ESessionDescriptorCalls = 0;
static NSUInteger gPhase13EPostLoginRedirectCalls = 0;
static NSUInteger gPhase15UIContextCalls = 0;

static NSString *Phase13ERegistrationResult(id context, NSError **error) {
  (void)error;
  return [context isKindOfClass:[NSDictionary class]] ? context[@"message"] : @"";
}

static NSString *Phase13ERegistrationLayout(id context, NSError **error) {
  (void)error;
  return [context isKindOfClass:[NSDictionary class]] ? context[@"content"] : @"";
}

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

@interface Phase16TrustedEmailClaimController : ALNController
@end

@implementation Phase16TrustedEmailClaimController

- (id)claim:(ALNContext *)ctx {
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:ctx.request.body options:0 error:NULL];
  payload = [payload isKindOfClass:[NSDictionary class]] ? payload : @{};
  NSError *error = nil;
  NSDictionary *result = [[ALNAuthModuleRuntime sharedRuntime]
      claimTrustedEmail:payload[@"email"]
            displayName:payload[@"display_name"]
                 source:payload[@"source"]
 sendPasswordSetupEmail:[payload[@"send_password_setup_email"] boolValue]
                baseURL:@"http://claim.example.test"
                context:ctx
                  error:&error];
  if (result == nil) {
    NSInteger status = (error.code == ALNAuthModuleErrorInvalidConfiguration) ? 500 : 422;
    [self setStatus:status];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"claim failed",
    };
  }
  return @{
    @"status" : @"ok",
    @"result" : result,
  };
}

@end

@interface Phase13EFailingJobAdapter : ALNPostgresJobAdapter
@property(nonatomic, assign) BOOL failEnqueue;
@end

@implementation Phase13EFailingJobAdapter
- (NSString *)enqueueJobNamed:(NSString *)name payload:(NSDictionary *)payload options:(NSDictionary *)options
                onConnection:(id<ALNDatabaseConnection>)connection error:(NSError **)error {
  if (self.failEnqueue) {
    if (error != NULL) *error = [NSError errorWithDomain:@"Phase13E.Queue" code:1
                                                userInfo:@{ NSLocalizedDescriptionKey : @"test enqueue failure" }];
    return nil;
  }
  return [super enqueueJobNamed:name payload:payload options:options onConnection:connection error:error];
}
@end

@interface ALNAuthModuleRuntime (Phase13ETokenAccess)
- (nullable NSDictionary *)userForEmail:(NSString *)email error:(NSError **)error;
- (nullable NSDictionary *)createLocalUserWithEmail:(NSString *)email
                                        displayName:(NSString *)displayName
                                           password:(NSString *)password
                                             source:(NSString *)source
                                              error:(NSError **)error;
- (nullable NSString *)issueVerificationTokenForUserID:(NSString *)userID error:(NSError **)error;
- (nullable NSString *)issuePasswordResetTokenForUserID:(NSString *)userID error:(NSError **)error;
- (BOOL)consumeVerificationToken:(NSString *)token user:(NSDictionary **)user error:(NSError **)error;
- (BOOL)consumePasswordResetToken:(NSString *)token
                         password:(NSString *)password
                             user:(NSDictionary **)user
                            error:(NSError **)error;
- (BOOL)updateLocalPasswordHash:(NSString *)encodedHash forUserID:(NSString *)userID error:(NSError **)error;
- (nullable NSDictionary *)authenticateLocalEmail:(NSString *)email password:(NSString *)password error:(NSError **)error;
@end

@interface ALNAuthModuleRuntime (Phase13EQueuedMailTesting)
- (BOOL)dispatchQueuedMailPayload:(NSDictionary *)payload error:(NSError **)error;
@end

@interface Phase13EQueuedMailRuntime : ALNAuthModuleRuntime
@property(nonatomic, copy) NSString *sentBaseURL;
@end

@implementation Phase13EQueuedMailRuntime
- (NSDictionary *)userForEmail:(NSString *)email error:(NSError **)error {
  (void)error;
  return @{ @"id" : @"user-1", @"email" : email ?: @"" };
}
- (NSString *)issuePasswordResetTokenForUserID:(NSString *)userID error:(NSError **)error {
  (void)userID; (void)error;
  return @"test-token";
}
- (BOOL)sendNotificationEvent:(NSString *)event user:(NSDictionary *)user
                        token:(NSString *)token baseURL:(NSString *)baseURL error:(NSError **)error {
  (void)event; (void)user; (void)token; (void)error;
  self.sentBaseURL = baseURL;
  return YES;
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
  if ([dsn length] > 0) {
    [self ensureAuthModuleMigrationsAppliedForDSN:dsn];
  }
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

- (void)ensureAuthModuleMigrationsAppliedForDSN:(NSString *)dsn {
  static NSString *gPhase13EPreparedDSN = nil;

  if ([dsn length] == 0) {
    return;
  }
  if ([gPhase13EPreparedDSN isEqualToString:dsn]) {
    return;
  }

  NSString *migrationsPath = [[self repoRoot] stringByAppendingPathComponent:@"modules/auth/Migrations"];
  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:1 error:&error];
  XCTAssertNotNil(database);
  XCTAssertNil(error);

  NSArray<NSString *> *appliedFiles = nil;
  XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrationsPath
                                                 database:database
                                                   dryRun:NO
                                             appliedFiles:&appliedFiles
                                                    error:&error]);
  XCTAssertNil(error);
  gPhase13EPreparedDSN = [dsn copy];
}

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)shellQuoted:(NSString *)value {
  NSString *string = value ?: @"";
  return [NSString stringWithFormat:@"'%@'", [string stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]];
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  return ALNTestTemporaryDirectory(prefix ?: @"phase15");
}

// Kept with the test's results (saved only if the test fails).
- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  int status = 0;
  NSString *output = [self runShellCaptureUnattached:command exitCode:&status];
  if (exitCode != NULL) {
    *exitCode = status;
  }
  ALNTestAttachCommandOutput(self, command, output, status);
  return output;
}

- (NSString *)runShellCaptureUnattached:(NSString *)command exitCode:(int *)exitCode {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = ALNTestBashPath();
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
  NSError *error = nil;
  NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (payload == nil) {
    NSUInteger startIndex = NSNotFound;
    NSUInteger depth = 0;
    BOOL inString = NO;
    BOOL escaping = NO;
    for (NSUInteger idx = 0; idx < [trimmed length]; idx++) {
      unichar ch = [trimmed characterAtIndex:idx];
      if (escaping) {
        escaping = NO;
        continue;
      }
      if (ch == '\\') {
        escaping = YES;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (ch == '{') {
        if (depth == 0) {
          startIndex = idx;
        }
        depth += 1;
        continue;
      }
      if (ch == '}' && depth > 0) {
        depth -= 1;
        if (depth == 0 && startIndex != NSNotFound) {
          NSString *candidate =
              [trimmed substringWithRange:NSMakeRange(startIndex, idx - startIndex + 1)];
          data = [candidate dataUsingEncoding:NSUTF8StringEncoding];
          error = nil;
          payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
          break;
        }
      }
    }
  }
  XCTAssertNil(error, @"invalid JSON: %@\n%@", error.localizedDescription, output);
  XCTAssertTrue([payload isKindOfClass:[NSDictionary class]]);
  return payload ?: @{};
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:@""
                                   headers:headers ?: @{}
                                      body:body ?: [NSData data]];
}

- (NSDictionary *)JSONResponseBody:(ALNResponse *)response {
  NSString *body = [[NSString alloc] initWithData:response.bodyData encoding:NSUTF8StringEncoding] ?: @"";
  return [self parseJSONDictionary:body];
}

- (void)setUp {
  [super setUp];
  gPhase13EPasswordPolicyCalls = 0;
  gPhase13EProvisioningCalls = 0;
  gPhase13ESessionDescriptorCalls = 0;
  gPhase13EPostLoginRedirectCalls = 0;
  gPhase15UIContextCalls = 0;
  NSError *error = nil;
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} environment:@"test" error:&error]);
  XCTAssertNil(error);
}

- (void)tearDown {
  // The runtime is process-wide; leave it in the test environment for other suites.
  [[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} environment:@"test" error:NULL];
  [super tearDown];
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
  XCTAssertEqualObjects(@"/auth/mfa", runtime.mfaManagePath);
  XCTAssertEqualObjects(@"/auth/mfa/totp", runtime.totpPath);
  XCTAssertEqualObjects(@"/auth/mfa/totp/verify", runtime.totpVerifyPath);
  XCTAssertEqualObjects(@"/auth/mfa/sms", runtime.smsPath);
  XCTAssertEqualObjects(@"/auth/mfa/sms/start", runtime.smsStartPath);
  XCTAssertEqualObjects(@"/auth/mfa/sms/verify", runtime.smsVerifyPath);
  XCTAssertEqualObjects(@"/auth/mfa/sms/resend", runtime.smsResendPath);
  XCTAssertEqualObjects(@"/auth/mfa/sms/remove", runtime.smsRemovePath);
  XCTAssertFalse(runtime.smsEnabled);
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
  XCTAssertEqualObjects(@"modules/auth/fragments/mfa_challenge_form",
                        [runtime fragmentTemplatePathForIdentifier:@"mfa_challenge_form" defaultPath:@""]);
  XCTAssertEqualObjects(@"/modules/auth/auth_totp_qr.js", [runtime authUIAssetPathForFilename:@"auth_totp_qr.js"]);
  XCTAssertEqualObjects(@NO, summary[@"mfa"][@"sms"][@"enabled"]);
  XCTAssertEqualObjects(@NO, summary[@"mfa"][@"sms"][@"allowPrimaryFactor"]);
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

- (void)testSMSConfigurationRequiresProviderSeamWhenEnabled {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *config = @{
    @"mfa" : @{
      @"sms" : @{
        @"enabled" : @YES,
      },
    },
  };
  XCTAssertFalse([runtime configureHooksWithModuleConfig:config error:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorInvalidConfiguration, error.code);
}

- (void)testSMSConfigurationAcceptsTestVerificationCodeOverride {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *config = @{
    @"mfa" : @{
      @"sms" : @{
        @"enabled" : @YES,
        @"allowPrimaryFactor" : @YES,
        @"testVerificationCode" : @"123456",
      },
    },
  };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue(runtime.smsEnabled);
  XCTAssertEqualObjects(@YES, [runtime resolvedHookSummary][@"mfa"][@"sms"][@"enabled"]);
  XCTAssertEqualObjects(@YES, [runtime resolvedHookSummary][@"mfa"][@"sms"][@"allowPrimaryFactor"]);
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
  XCTAssertEqualObjects(@"accounts/auth/mfa/manage", [runtime pageTemplatePathForIdentifier:@"mfa_manage" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/mfa/sms", [runtime pageTemplatePathForIdentifier:@"sms_challenge" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/partials/bodies/login_body",
                        [runtime bodyTemplatePathForIdentifier:@"login" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/partials/bodies/mfa_manage_body",
                        [runtime bodyTemplatePathForIdentifier:@"mfa_manage" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/fragments/mfa_enrollment_panel",
                        [runtime fragmentTemplatePathForIdentifier:@"mfa_enrollment_panel" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/fragments/mfa_factor_inventory_panel",
                        [runtime fragmentTemplatePathForIdentifier:@"mfa_factor_inventory_panel" defaultPath:@""]);
  XCTAssertEqualObjects(@"auth/partials/custom_page_wrapper",
                        [runtime partialTemplatePathForIdentifier:@"page_wrapper" defaultPath:@""]);
  XCTAssertEqualObjects(@"accounts/auth/partials/provider_row",
                        [runtime partialTemplatePathForIdentifier:@"provider_row" defaultPath:@""]);
  XCTAssertEqualObjects(@"/accounts/auth/auth.css", [runtime authUIAssetPathForFilename:@"auth.css"]);
  XCTAssertEqualObjects(@"/accounts/auth/auth_totp_qr.js", [runtime authUIAssetPathForFilename:@"auth_totp_qr.js"]);

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
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
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

static ALNContext *ALNTestStandInContext(void) {
  // The runtime only forwards the context to the session-policy hook, and these
  // cases configure none, so a stand-in keeps the nonnull contract satisfied.
  return (ALNContext *)(id)[NSObject new];
}

/// An unvalidated `return_to` made every successful sign-in an open redirect.
/// The post-login target must stay same-origin.
- (void)testPostLoginRedirectRejectsOffOriginTargets_OPEN_REDIRECT {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{ @"defaultRedirect" : @"/dashboard" },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];

  NSArray *hostile = @[
    @"https://evil.example/",           // absolute, its own origin
    @"http://evil.example/",
    @"//evil.example/",                 // protocol-relative
    @"/\\evil.example",                 // backslash normalizes to a slash in browsers
    @"\\\\evil.example",
    @"javascript:alert(1)",             // not a path at all
    @"dashboard",                       // unrooted relative
    @"https:/evil.example",
  ];
  for (NSString *target in hostile) {
    NSString *resolved = [runtime postLoginRedirectForContext:ALNTestStandInContext() user:@{} defaultRedirect:target];
    XCTAssertEqualObjects(@"/dashboard", resolved, @"should have refused %@", target);
  }
}

- (void)testPostLoginRedirectKeepsSameOriginTargets_OPEN_REDIRECT {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{ @"defaultRedirect" : @"/dashboard" },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];

  // Ordinary in-app returns must survive untouched, query and fragment included.
  for (NSString *target in @[ @"/tickets", @"/tickets/42?tab=notes", @"/a/b#section", @"/" ]) {
    XCTAssertEqualObjects(target,
                          [runtime postLoginRedirectForContext:ALNTestStandInContext() user:@{} defaultRedirect:target]);
  }
}

- (void)testPostLoginRedirectFallsBackWhenTargetIsEmpty_OPEN_REDIRECT {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{ @"defaultRedirect" : @"/dashboard" },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  XCTAssertEqualObjects(@"/dashboard",
                        [runtime postLoginRedirectForContext:ALNTestStandInContext() user:@{} defaultRedirect:@""]);
  XCTAssertEqualObjects(@"/dashboard",
                        [runtime postLoginRedirectForContext:ALNTestStandInContext() user:@{} defaultRedirect:@"   "]);
}

/// CR/LF in a redirect target is header splitting, not just an odd path.
- (void)testPostLoginRedirectRejectsControlCharacters_OPEN_REDIRECT {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{ @"defaultRedirect" : @"/dashboard" },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  for (NSString *target in @[ @"/a\r\nSet-Cookie: x=1", @"/a\tb", @"/a\x7F" ]) {
    XCTAssertEqualObjects(@"/dashboard",
                          [runtime postLoginRedirectForContext:ALNTestStandInContext() user:@{} defaultRedirect:target]);
  }
}

- (void)testSMSRoutesAreNotRegisteredWhenSMSIsDisabled {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{}];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  XCTAssertNotNil([app.router routeNamed:@"auth_mfa_manage"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_mfa"]);
  XCTAssertNil([app.router routeNamed:@"auth_sms_form"]);
  XCTAssertNil([app.router routeNamed:@"auth_sms_start"]);
  XCTAssertNil([app.router routeNamed:@"auth_sms_verify"]);
  XCTAssertNil([app.router routeNamed:@"auth_sms_resend"]);
  XCTAssertNil([app.router routeNamed:@"auth_sms_remove"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_sms"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_sms_start"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_sms_verify"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_sms_resend"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_sms_remove"]);
}

- (void)testSMSRoutesRegisterWhenEnabled {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{
    @"authModule" : @{
      @"mfa" : @{
        @"sms" : @{
          @"enabled" : @YES,
          @"testVerificationCode" : @"123456",
        },
      },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  XCTAssertNotNil([app.router routeNamed:@"auth_sms_form"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_sms_start"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_sms_verify"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_sms_resend"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_sms_remove"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_sms"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_sms_start"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_sms_verify"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_sms_resend"]);
  XCTAssertNotNil([app.router routeNamed:@"auth_api_sms_remove"]);
}

- (void)testHeadlessModeDoesNotRegisterInteractiveHTMLRoutes {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
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

- (void)testTrustedEmailClaimCreatesSessionAndDeliversReusableSignInEmail {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  // The test posts to its own claim route without a token, so it opts out of
  // the auth module's CSRF requirement explicitly.
  ALNApplication *app = [self applicationWithConfig:@{
    @"csrf" : @{ @"enabled" : @NO },
    @"authModule" : @{ @"allowWithoutCSRF" : @YES },
  }];
  ALNInMemoryMailAdapter *mailAdapter =
      [[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"phase13e_claim_mail"];
  [app setMailAdapter:mailAdapter];

  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  [app registerRouteMethod:@"POST"
                      path:@"/claim"
                      name:@"phase13e_claim"
           controllerClass:[Phase16TrustedEmailClaimController class]
                     action:@"claim"];

  NSString *email = [NSString stringWithFormat:@"claimed-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{
    @"email" : email,
    @"display_name" : @"Claimed Musician",
    @"send_password_setup_email" : @YES,
  }
                                             options:0
                                               error:NULL];
  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"POST"
                                                                  path:@"/claim"
                                                               headers:@{
                                                                 @"Accept" : @"application/json",
                                                                 @"Content-Type" : @"application/json",
                                                               }
                                                                  body:body]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSDictionary *payload = [self JSONResponseBody:response];
  XCTAssertEqualObjects(@"ok", payload[@"status"]);
  NSDictionary *result = [payload[@"result"] isKindOfClass:[NSDictionary class]] ? payload[@"result"] : @{};
  NSDictionary *session = [result[@"session"] isKindOfClass:[NSDictionary class]] ? result[@"session"] : @{};
  NSDictionary *user = [result[@"user"] isKindOfClass:[NSDictionary class]] ? result[@"user"] : @{};
  XCTAssertEqualObjects(@YES, result[@"created_user"]);
  XCTAssertEqualObjects(@YES, result[@"email_verified"]);
  XCTAssertEqualObjects(@YES, result[@"password_setup_issued"]);
  XCTAssertEqualObjects(@YES, session[@"authenticated"]);
  XCTAssertEqualObjects(@"email_link", session[@"provider"]);
  XCTAssertEqualObjects((@[ @"email_link" ]), session[@"methods"]);
  XCTAssertEqualObjects(email, [user[@"email"] lowercaseString]);
  XCTAssertTrue([((NSString *)user[@"email_verified_at"]) length] > 0);

  NSArray *deliveries = [mailAdapter deliveriesSnapshot];
  XCTAssertEqual((NSUInteger)1, [deliveries count]);
  NSDictionary *delivery = [deliveries[0] isKindOfClass:[NSDictionary class]] ? deliveries[0] : @{};
  NSDictionary *message = [delivery[@"message"] isKindOfClass:[NSDictionary class]] ? delivery[@"message"] : @{};
  XCTAssertEqualObjects(@"Reset your password", message[@"subject"]);
  XCTAssertTrue([message[@"textBody"] containsString:@"/auth/password/reset?token="]);
}

- (void)testTrustedEmailClaimUsesConfiguredPublicBaseURLOverCallerBaseURL {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithConfig:@{
    @"csrf" : @{ @"enabled" : @NO },
    // This controller test isolates trusted email URL selection from CSRF.
    @"authModule" : @{ @"publicBaseURL" : @"https://public.example.test", @"allowWithoutCSRF" : @YES },
  }];
  ALNInMemoryMailAdapter *mailAdapter =
      [[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"phase13e_claim_public_mail"];
  [app setMailAdapter:mailAdapter];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  [app registerRouteMethod:@"POST"
                      path:@"/claim"
                      name:@"phase13e_claim_public"
           controllerClass:[Phase16TrustedEmailClaimController class]
                     action:@"claim"];

  NSString *email = [NSString stringWithFormat:@"claimed-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"email" : email, @"send_password_setup_email" : @YES }
                                                 options:0
                                                   error:NULL];
  ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"POST"
                                                                  path:@"/claim"
                                                               headers:@{
                                                                 @"Accept" : @"application/json",
                                                                 @"Content-Type" : @"application/json",
                                                               }
                                                                  body:body]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSArray *deliveries = [mailAdapter deliveriesSnapshot];
  XCTAssertEqual((NSUInteger)1, [deliveries count]);
  NSDictionary *delivery = [deliveries.firstObject isKindOfClass:[NSDictionary class]] ? deliveries.firstObject : @{};
  NSDictionary *message = [delivery[@"message"] isKindOfClass:[NSDictionary class]] ? delivery[@"message"] : @{};
  NSString *text = [message[@"textBody"] isKindOfClass:[NSString class]] ? message[@"textBody"] : @"";
  XCTAssertTrue([text containsString:@"https://public.example.test/auth/password/reset?token="], @"%@", text);
  XCTAssertFalse([text containsString:@"claim.example.test"], @"%@", text);
}

- (void)testAuthStylesheetNormalizesSharedActionTypography {
  NSString *repoRoot = [self repoRoot];
  NSString *stylesheetPath =
      [repoRoot stringByAppendingPathComponent:@"modules/auth/Resources/Public/auth.css"];
  NSError *error = nil;
  NSString *stylesheet = [NSString stringWithContentsOfFile:stylesheetPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(stylesheet);
  XCTAssertTrue([stylesheet containsString:@".auth-button,\n.auth-link {"]);
  XCTAssertTrue([stylesheet containsString:@"font-family: inherit;"]);
  XCTAssertTrue([stylesheet containsString:@"font-size: 1rem;"]);
  XCTAssertTrue([stylesheet containsString:@"line-height: 1.2;"]);
}

- (void)testModuleEjectAuthUIScaffoldsGeneratedTemplatesAndConfig {
  NSString *ldPreload = [[[NSProcessInfo processInfo] environment] objectForKey:@"LD_PRELOAD"];
  if ([ldPreload length] > 0) {
    return;
  }
  NSString *repoRoot = [self repoRoot];
  NSString *arlenPath =
#if defined(__APPLE__)
      [repoRoot stringByAppendingPathComponent:@"bin/arlen"];
#else
      [repoRoot stringByAppendingPathComponent:@"build/arlen"];
#endif
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

  int exitCode = 0;
#if defined(__APPLE__)
  NSString *buildCommand = [NSString stringWithFormat:@"cd %@ && ./bin/build-apple >/dev/null",
                                                      [self shellQuoted:repoRoot]];
#else
  NSString *buildCommand = [NSString stringWithFormat:
                                               @"%@ && cd %@ && rm -f build/arlen && LD_PRELOAD='' make arlen >/dev/null && chmod 755 build/arlen",
                                               ALNTestGNUstepSourceCommandForRepoRoot(repoRoot),
                                               [self shellQuoted:repoRoot]];
#endif
  NSString *buildOutput = [self runShellCapture:buildCommand exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", buildOutput);

  NSString *command = [NSString stringWithFormat:@"cd %@ && LD_PRELOAD='' ARLEN_FRAMEWORK_ROOT=%@ %@ module eject auth-ui --json",
                                                 [self shellQuoted:tempApp],
                                                 [self shellQuoted:repoRoot],
                                                 [self shellQuoted:arlenPath]];
  NSString *output = [self runShellCapture:command exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", output);

  NSDictionary *payload = [self parseJSONDictionary:output];
  XCTAssertEqualObjects(@"ok", payload[@"status"]);
  XCTAssertEqualObjects(@"eject", payload[@"workflow"]);
  XCTAssertEqualObjects(@"auth-ui", payload[@"target"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/login.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"public/auth/auth.css"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/mfa/manage.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/mfa/sms.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/fragments/mfa_factor_inventory_panel.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/fragments/mfa_enrollment_panel.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/fragments/mfa_sms_enrollment_panel.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/fragments/mfa_sms_challenge_form.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"templates/auth/mfa/totp_enrollment.html.eoc"]);
  XCTAssertTrue([payload[@"created_files"] containsObject:@"public/auth/auth_totp_qr.js"]);
  XCTAssertTrue([payload[@"updated_files"] containsObject:@"config/app.plist"]);

  NSString *configPath = [tempApp stringByAppendingPathComponent:@"config/app.plist"];
  // Not +dataWithContentsOfFile:options:error:, which Windows gnustep-base 1.31 lacks.
  NSData *configData = [NSData dataWithContentsOfFile:configPath];
  XCTAssertNotNil(configData);
  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  NSDictionary *config = [NSPropertyListSerialization propertyListWithData:configData
                                                                   options:NSPropertyListMutableContainersAndLeaves
                                                                    format:&format
                                                                     error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([config isKindOfClass:[NSDictionary class]]);
  NSDictionary *authModule = [config[@"authModule"] isKindOfClass:[NSDictionary class]] ? config[@"authModule"] : @{};
  NSDictionary *ui = [authModule[@"ui"] isKindOfClass:[NSDictionary class]] ? authModule[@"ui"] : @{};
  XCTAssertEqualObjects(@"generated-app-ui", ui[@"mode"]);
  XCTAssertEqualObjects(@"layouts/auth_generated", ui[@"layout"]);
  XCTAssertEqualObjects(@"auth", ui[@"generatedPagePrefix"]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/auth/partials/page_wrapper.html.eoc"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/auth/fragments/mfa_challenge_form.html.eoc"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/auth/partials/bodies/mfa_manage_body.html.eoc"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/auth/partials/bodies/sms_challenge_body.html.eoc"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/auth/mfa/totp_recovery_codes.html.eoc"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[tempApp stringByAppendingPathComponent:@"templates/layouts/auth_generated.html.eoc"]]);
}

#pragma mark - Stub provider environment gating

- (void)testStubProviderDefaultsOnOnlyInDevelopmentAndTest {
  for (NSString *environment in @[ @"development", @"test", @"production", @"staging", @"qa" ]) {
    ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
    NSError *error = nil;
    XCTAssertTrue([runtime configureHooksWithModuleConfig:@{} environment:environment error:&error], @"%@ %@",
                  environment, error);
    BOOL expected = [environment isEqualToString:@"development"] || [environment isEqualToString:@"test"];
    XCTAssertEqual(expected, [runtime isProviderEnabled:@"stub"], @"%@", environment);
    XCTAssertEqual((NSUInteger)(expected ? 1 : 0), runtime.loginProviders.count, @"%@", environment);
  }
}

- (void)testStubProviderExplicitEnableIsRefusedOutsideDevelopmentAndTest {
  NSDictionary *config = @{ @"providers" : @{ @"stub" : @{ @"enabled" : @YES } } };
  for (NSString *environment in @[ @"production", @"staging" ]) {
    NSError *error = nil;
    XCTAssertFalse([[ALNAuthModuleRuntime new] configureHooksWithModuleConfig:config
                                                                  environment:environment
                                                                        error:&error],
                   @"%@", environment);
    XCTAssertEqual((NSInteger)ALNAuthModuleErrorInvalidConfiguration, error.code, @"%@", environment);
    XCTAssertEqualObjects(@"authModule.providers.stub.enabled", error.userInfo[@"key_path"]);
    XCTAssertTrue([error.localizedDescription containsString:environment], @"%@", error);
  }
  for (NSString *environment in @[ @"development", @"test" ]) {
    ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
    XCTAssertTrue([runtime configureHooksWithModuleConfig:config environment:environment error:NULL], @"%@", environment);
    XCTAssertTrue([runtime isProviderEnabled:@"stub"], @"%@", environment);
  }

  // Registration (application startup) fails the same way.
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"production",
    @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule" : config,
  }];
  NSError *error = nil;
  XCTAssertFalse([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorInvalidConfiguration, error.code);
}

- (void)testStubProviderRoutesAreAbsentInProductionByDefault {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"production",
    @"csrf" : @{ @"enabled" : @NO },
    @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule" : @{ @"localPassword" : @{ @"enabled" : @NO } },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertFalse([[ALNAuthModuleRuntime sharedRuntime] isProviderEnabled:@"stub"]);
  XCTAssertNil([app.router routeNamed:@"auth_provider_stub_login"]);
  XCTAssertNil([app.router routeNamed:@"auth_provider_stub_callback"]);
  XCTAssertNil([app.router routeNamed:@"auth_api_provider_stub_login"]);
  for (NSString *path in @[ @"/auth/provider/stub/login", @"/auth/provider/stub/callback",
                            @"/auth/api/provider/stub/login" ]) {
    ALNResponse *response = [app dispatchRequest:[self requestWithMethod:@"GET"
                                                                    path:path
                                                                 headers:@{ @"Accept" : @"application/json" }
                                                                    body:nil]];
    XCTAssertEqual((NSInteger)404, response.statusCode, @"%@", path);
  }
}

- (void)testUnsafeRegistrationAndMailModesFailStartupOutsideDevelopmentAndTest {
  NSDictionary *autoLogin = @{ @"registration" : @{ @"autoLogin" : @YES } };
  for (NSString *environment in @[ @"production", @"staging", @"qa" ]) {
    NSError *error = nil;
    XCTAssertFalse([[ALNAuthModuleRuntime new] configureHooksWithModuleConfig:autoLogin
                                                                  environment:environment error:&error]);
    XCTAssertEqualObjects(@"authModule.registration.autoLogin", error.userInfo[@"key_path"]);

    ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
      @"environment" : environment,
      @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
      @"authModule" : @{ @"mailDispatch" : @{ @"mode" : @"synchronous" },
                         @"publicBaseURL" : @"https://app.example.test" },
    }];
    error = nil;
    XCTAssertFalse([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
    XCTAssertEqualObjects(@"authModule.mailDispatch.mode", error.userInfo[@"key_path"]);
  }
  for (NSString *environment in @[ @"development", @"test" ]) {
    XCTAssertTrue([[ALNAuthModuleRuntime new] configureHooksWithModuleConfig:autoLogin
                                                                 environment:environment error:NULL]);
  }
}

- (void)testStubIdentityIsNotResolvedOutsideDevelopmentAndTest {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{} environment:@"production" error:NULL]);
  NSError *error = nil;
  NSDictionary *descriptor =
      [runtime resolveSessionDescriptorForNormalizedIdentity:@{
        @"provider_subject" : @"stub:stub-user@example.test",
        @"email" : @"stub-user@example.test",
      }
                                       providerConfiguration:@{ @"identifier" : @"stub" }
                                                       error:&error];
  XCTAssertNil(descriptor);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorPolicyRejected, error.code);
}

#pragma mark - Single-use tokens

- (void)testBearerLinksStoreOnlyTokenDigests {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSDictionary *user = nil;
  ALNAuthModuleRuntime *runtime = [self configuredRuntimeWithTokenUser:&user email:NULL];
  NSString *verificationToken = [runtime issueVerificationTokenForUserID:user[@"id"] error:NULL];
  NSString *resetToken = [runtime issuePasswordResetTokenForUserID:user[@"id"] error:NULL];
  XCTAssertTrue([verificationToken length] > 0 && [resetToken length] > 0);

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:1 error:&error];
  XCTAssertNotNil(database, @"%@", error);
  NSDictionary *verification = [[database executeQuery:@"SELECT token FROM auth_verification_tokens "
                                                        "WHERE user_id = $1 ORDER BY id DESC LIMIT 1"
                                             parameters:@[ user[@"id"] ] error:&error] firstObject];
  NSDictionary *reset = [[database executeQuery:@"SELECT token FROM auth_password_reset_tokens "
                                                 "WHERE user_id = $1 ORDER BY id DESC LIMIT 1"
                                      parameters:@[ user[@"id"] ] error:&error] firstObject];
  for (NSArray *pair in @[ @[ verificationToken, verification[@"token"] ?: @"" ],
                          @[ resetToken, reset[@"token"] ?: @"" ] ]) {
    NSString *raw = pair[0];
    NSString *stored = pair[1];
    NSString *digest = ALNLowercaseHexStringFromData(ALNSHA256([raw dataUsingEncoding:NSUTF8StringEncoding]));
    XCTAssertNotEqualObjects(raw, stored);
    XCTAssertEqualObjects([@"sha256:" stringByAppendingString:digest], stored);
  }

  NSString *legacyToken = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSInteger inserted = [database executeCommand:@"INSERT INTO auth_password_reset_tokens (user_id, token, expires_at) "
                                                "VALUES ($1, $2, NOW() + INTERVAL '30 minutes')"
                                     parameters:@[ user[@"id"], legacyToken ] error:&error];
  XCTAssertTrue(inserted >= 0, @"%@", error);
  XCTAssertFalse([runtime consumePasswordResetToken:legacyToken password:@"new-password" user:NULL error:NULL]);
}

- (ALNAuthModuleRuntime *)configuredRuntimeWithTokenUser:(NSDictionary **)user email:(NSString **)email {
  ALNApplication *app = [self applicationWithConfig:@{}];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSString *address = [NSString stringWithFormat:@"tokens-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSDictionary *created = [runtime createLocalUserWithEmail:address
                                                displayName:@"Token User"
                                                   password:@"original-password"
                                                     source:@"test"
                                                      error:&error];
  XCTAssertNotNil(created, @"%@", error);
  if (user != NULL) *user = created;
  if (email != NULL) *email = address;
  return runtime;
}

- (void)testPasswordResetTokenIsSingleUseAndRetiresOlderTokens {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSDictionary *user = nil;
  NSString *email = nil;
  ALNAuthModuleRuntime *runtime = [self configuredRuntimeWithTokenUser:&user email:&email];
  NSString *userID = user[@"id"];
  NSError *error = nil;
  NSString *older = [runtime issuePasswordResetTokenForUserID:userID error:&error];
  NSString *newer = [runtime issuePasswordResetTokenForUserID:userID error:&error];
  XCTAssertTrue([older length] > 0 && [newer length] > 0, @"%@", error);

  XCTAssertTrue([runtime consumePasswordResetToken:newer password:@"first-new-password" user:NULL error:&error], @"%@", error);
  XCTAssertNotNil([runtime authenticateLocalEmail:email password:@"first-new-password" error:NULL]);

  error = nil;
  XCTAssertFalse([runtime consumePasswordResetToken:newer password:@"second-new-password" user:NULL error:&error]);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorNotFound, error.code);
  error = nil;
  XCTAssertFalse([runtime consumePasswordResetToken:older password:@"third-new-password" user:NULL error:&error]);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorNotFound, error.code);
  XCTAssertNotNil([runtime authenticateLocalEmail:email password:@"first-new-password" error:NULL]);
  XCTAssertNil([runtime authenticateLocalEmail:email password:@"second-new-password" error:NULL]);
  XCTAssertNil([runtime authenticateLocalEmail:email password:@"third-new-password" error:NULL]);
}

- (void)testConcurrentPasswordResetConsumptionHasExactlyOneWinner {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSDictionary *user = nil;
  NSString *email = nil;
  ALNAuthModuleRuntime *runtime = [self configuredRuntimeWithTokenUser:&user email:&email];
  NSString *token = [runtime issuePasswordResetTokenForUserID:user[@"id"] error:NULL];
  XCTAssertTrue([token length] > 0);

  const size_t attempts = 6;
  __block NSInteger successes = 0;
  NSMutableArray *winners = [NSMutableArray array];
  NSLock *lock = [[NSLock alloc] init];
  dispatch_apply(attempts, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    NSString *password = [NSString stringWithFormat:@"concurrent-password-%zu", index];
    BOOL ok = [runtime consumePasswordResetToken:token password:password user:NULL error:NULL];
    if (ok) {
      [lock lock];
      successes += 1;
      [winners addObject:password];
      [lock unlock];
    }
  });
  XCTAssertEqual((NSInteger)1, successes);
  if ([winners count] == 1) {
    XCTAssertNotNil([runtime authenticateLocalEmail:email password:winners[0] error:NULL]);
  }
}

- (void)testPasswordChangeRetiresOutstandingResetTokens {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSDictionary *user = nil;
  ALNAuthModuleRuntime *runtime = [self configuredRuntimeWithTokenUser:&user email:NULL];
  NSString *token = [runtime issuePasswordResetTokenForUserID:user[@"id"] error:NULL];
  XCTAssertTrue([token length] > 0);
  NSError *error = nil;
  XCTAssertTrue([runtime updateLocalPasswordHash:@"$argon2id$placeholder" forUserID:user[@"id"] error:&error], @"%@", error);
  error = nil;
  XCTAssertFalse([runtime consumePasswordResetToken:token password:@"after-change-password" user:NULL error:&error]);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorNotFound, error.code);
}

- (void)testVerificationTokenIsSingleUse {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSDictionary *user = nil;
  ALNAuthModuleRuntime *runtime = [self configuredRuntimeWithTokenUser:&user email:NULL];
  NSString *token = [runtime issueVerificationTokenForUserID:user[@"id"] error:NULL];
  XCTAssertTrue([token length] > 0);

  __block NSInteger successes = 0;
  NSLock *lock = [[NSLock alloc] init];
  dispatch_apply(4, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    (void)index;
    if ([runtime consumeVerificationToken:token user:NULL error:NULL]) {
      [lock lock];
      successes += 1;
      [lock unlock];
    }
  });
  XCTAssertEqual((NSInteger)1, successes);
  NSError *error = nil;
  XCTAssertFalse([runtime consumeVerificationToken:token user:NULL error:&error]);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorNotFound, error.code);
}

#pragma mark - Email link base URL

- (void)testPublicBaseURLIsValidatedAndNormalized {
  for (NSString *invalid in @[ @"app.example.test", @"ftp://app.example.test", @"https://app.example.test/?next=1",
                               @"https://app.example.test/#frag", @"https://user@app.example.test", @"https://",
                               @"https://app.example.test:99999", @"https://app.example.test:0",
                               @"https://app.example.test:70000", @"https://app.example.test:", @"https://app.example.test:8x",
                               @"https://[::1", @"https://[::1]x", @"https://app example.test",
                               @"https://user:pw@app.example.test", @"https://app.example.test/../x",
                               @"https://app.example.test/a/./b", @"https://app.example.test/..",
                               @"https://app.example.test/%2e%2e/x", @"https://app.example.test/%2E./x",
                               @"https://app.example.test/a/%2e/b", @"https://app.example.test/%zz",
                               @"https://app.example.test/a%2", @"https://app.example.test/%G1", @"https://app.example.test/%",
                               @"https://app.example.test/%00", @"https://app.example.test/%C0%AF",
                               @"https://app.example.test/%ED%A0%80" ]) {
    NSError *error = nil;
    XCTAssertFalse([[ALNAuthModuleRuntime new] configureHooksWithModuleConfig:@{ @"publicBaseURL" : invalid }
                                                                  environment:@"production"
                                                                        error:&error],
                   @"%@", invalid);
    XCTAssertEqualObjects(@"authModule.publicBaseURL", error.userInfo[@"key_path"], @"%@", invalid);
  }
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{ @"publicBaseURL" : @" https://app.example.test/accounts/ " }
                                            environment:@"production"
                                                  error:NULL]);
  XCTAssertEqualObjects(@"https://app.example.test/accounts", runtime.publicBaseURL);
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{ @"publicBaseURL" : @"HTTPS://App.Example.TEST:8443/Accounts/" }
                                            environment:@"production"
                                                  error:NULL]);
  XCTAssertEqualObjects(@"https://app.example.test:8443/Accounts", runtime.publicBaseURL);
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{ @"publicBaseURL" : @"https://app.example.test/my%20app" }
                                            environment:@"production"
                                                  error:NULL]);
  XCTAssertEqualObjects(@"https://app.example.test/my%20app", runtime.publicBaseURL);
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{ @"publicBaseURL" : @"https://[::1]:8443/x/" }
                                            environment:@"production"
                                                  error:NULL]);
  XCTAssertEqualObjects(@"https://[::1]:8443/x", runtime.publicBaseURL);
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{ @"publicBaseURL" : @"http://[FE80::1]" }
                                            environment:@"production"
                                                  error:NULL]);
  XCTAssertEqualObjects(@"http://[fe80::1]", runtime.publicBaseURL);
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{} environment:@"production" error:NULL]);
  XCTAssertEqualObjects(@"", runtime.publicBaseURL);
}

- (void)testQueuedAuthMailUsesConfiguredPublicBaseURL {
  Phase13EQueuedMailRuntime *runtime = [Phase13EQueuedMailRuntime new];
  NSError *error = nil;
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{ @"publicBaseURL" : @"https://app.example.test" }
                                            environment:@"production" error:&error]);
  XCTAssertNil(error);
  NSDictionary *payload = @{
    @"eligible" : @YES,
    @"event" : @"password_reset",
    @"email" : @"user@example.test",
    @"baseURL" : @"https://attacker.example.test",
  };
  XCTAssertTrue([runtime dispatchQueuedMailPayload:payload error:&error]);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"https://app.example.test", runtime.sentBaseURL);
}

- (ALNApplication *)mailingApplicationWithEnvironment:(NSString *)environment
                                          authModule:(NSDictionary *)authModule
                                         mailAdapter:(ALNInMemoryMailAdapter **)mailAdapter {
  // Link-policy fixtures use an explicit CSRF opt-out and legacy synchronous mail.
  NSMutableDictionary *authConfig = [NSMutableDictionary dictionaryWithDictionary:authModule ?: @{}];
  authConfig[@"allowWithoutCSRF"] = @YES;
  if ([environment isEqualToString:@"production"]) {
    authConfig[@"mailDispatch"] = @{ @"mode" : @"synchronous" };
  }
  authConfig[@"attemptLimits"] = @{ @"mail" : @{ @"maxPerAddress" : @10000 } };
  ALNApplication *app = [self applicationWithConfig:@{
    @"environment" : environment,
    @"csrf" : @{ @"enabled" : @NO },
    @"authModule" : authConfig,
  }];
  ALNInMemoryMailAdapter *adapter = [[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"phase13e_link_mail"];
  [app setMailAdapter:adapter];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  if (mailAdapter != NULL) *mailAdapter = adapter;
  return app;
}

- (NSString *)createLinkUserEmail {
  NSString *email = [NSString stringWithFormat:@"links-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSError *error = nil;
  XCTAssertNotNil([[ALNAuthModuleRuntime sharedRuntime] createLocalUserWithEmail:email
                                                                     displayName:@"Link User"
                                                                        password:@"original-password"
                                                                          source:@"test"
                                                                           error:&error],
                  @"%@", error);
  return email;
}

- (ALNResponse *)postJSON:(NSDictionary *)payload to:(NSString *)path app:(ALNApplication *)app host:(NSString *)host {
  NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
  return [app dispatchRequest:[self requestWithMethod:@"POST"
                                                 path:path
                                              headers:@{
                                                @"Accept" : @"application/json",
                                                @"Content-Type" : @"application/json",
                                                @"Host" : host ?: @"",
                                              }
                                                 body:body]];
}

- (NSArray<NSString *> *)deliveredTextBodies:(ALNInMemoryMailAdapter *)adapter {
  NSMutableArray *bodies = [NSMutableArray array];
  for (NSDictionary *delivery in [adapter deliveriesSnapshot]) {
    NSDictionary *message = [delivery[@"message"] isKindOfClass:[NSDictionary class]] ? delivery[@"message"] : @{};
    [bodies addObject:message[@"textBody"] ?: @""];
  }
  return bodies;
}

- (void)testProductionAuthMailRequiresDurableQueueUnlessCompatibilityModeIsExplicit {
  ALNApplication *app = [self applicationWithConfig:@{
    @"environment" : @"production",
    @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule" : @{ @"publicBaseURL" : @"https://app.example.test" },
  }];
  [app setMailAdapter:[[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"auth_mail_guard"]];
  NSError *error = nil;
  XCTAssertFalse([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertEqualObjects(@"authModule.mailDispatch.mode", error.userInfo[@"key_path"]);
  ALNApplication *explicitDurable = [self applicationWithConfig:@{
    @"environment" : @"test",
    @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule" : @{ @"mailDispatch" : @{ @"mode" : @"durable" } },
  }];
  error = nil;
  XCTAssertFalse([[[ALNAuthModule alloc] init] registerWithApplication:explicitDurable error:&error]);
  XCTAssertEqualObjects(@"authModule.mailDispatch.mode", error.userInfo[@"key_path"]);
}

- (void)testDurableAuthMailQueuesBeforeSendingAndKeepsUnknownAddressesGeneric {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:4 error:&error];
  XCTAssertNotNil(database, @"%@", error);
  ALNPostgresJobAdapter *jobs = [[ALNPostgresJobAdapter alloc] initWithDatabase:database
                                                                      namespace:[NSString stringWithFormat:@"auth-mail-%@", [[NSUUID UUID] UUIDString]]
                                                           leaseDurationSeconds:30 error:&error];
  XCTAssertNotNil(jobs, @"%@", error);
  XCTAssertTrue([jobs installSchemaWithError:&error], @"%@", error);
  NSString *jobsStateDirectory = ALNTestTemporaryDirectory(@"arlen-auth-jobs-success");
  XCTAssertNotNil(jobsStateDirectory);
  ALNApplication *app = [self applicationWithConfig:@{
    @"environment" : @"production",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"persistence" : @{ @"path" : [jobsStateDirectory stringByAppendingPathComponent:@"state.plist"] } },
    @"authModule" : @{ @"publicBaseURL" : @"https://app.example.test",
                       @"allowWithoutCSRF" : @YES,
                       @"attemptLimits" : @{ @"mail" : @{ @"maxPerAddress" : @10000 } } },
  }];
  ALNInMemoryMailAdapter *mail = [[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"durable_auth_mail"];
  [app setMailAdapter:mail];
  [app setJobsAdapter:jobs];
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);

  NSString *email = [NSString stringWithFormat:@"durable-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSDictionary *registration = @{ @"email" : email, @"display_name" : @"Durable User", @"password" : @"durable-password" };
  ALNResponse *created = [self postJSON:registration to:@"/auth/api/register" app:app host:@"evil.example"];
  ALNResponse *existing = [self postJSON:registration to:@"/auth/api/register" app:app host:@"evil.example"];
  XCTAssertEqual((NSInteger)200, created.statusCode);
  XCTAssertEqualObjects([self JSONResponseBody:created], [self JSONResponseBody:existing]);
  XCTAssertEqual((NSUInteger)0, [[mail deliveriesSnapshot] count]);
  XCTAssertEqual((NSUInteger)2, [[jobs jobsWithState:@"pending" error:&error] count]);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)1, [[mail deliveriesSnapshot] count]);
  XCTAssertTrue([[[self deliveredTextBodies:mail] firstObject] containsString:@"https://app.example.test/auth/verify?token="]);

  NSString *unknown = [NSString stringWithFormat:@"unknown-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  ALNResponse *knownReset = [self postJSON:@{ @"email" : email } to:@"/auth/api/password/forgot" app:app host:@"evil.example"];
  ALNResponse *unknownReset = [self postJSON:@{ @"email" : unknown } to:@"/auth/api/password/forgot" app:app host:@"evil.example"];
  ALNResponse *emptyReset = [self postJSON:@{ @"email" : @"" } to:@"/auth/api/password/forgot" app:app host:@"evil.example"];
  XCTAssertEqual((NSInteger)200, knownReset.statusCode);
  XCTAssertEqualObjects([self JSONResponseBody:knownReset], [self JSONResponseBody:unknownReset]);
  XCTAssertEqualObjects([self JSONResponseBody:knownReset], [self JSONResponseBody:emptyReset]);
  XCTAssertEqual((NSUInteger)1, [[mail deliveriesSnapshot] count]);
  XCTAssertEqual((NSUInteger)3, [[jobs jobsWithState:@"pending" error:&error] count]);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)2, [[mail deliveriesSnapshot] count]);
  XCTAssertTrue([[[self deliveredTextBodies:mail] lastObject] containsString:@"https://app.example.test/auth/password/reset?token="]);
}

- (void)testDurableAuthMailQueueFailureRollsBackRegistrationAndKeepsResetResponsesGeneric {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:4 error:&error];
  Phase13EFailingJobAdapter *jobs = [[Phase13EFailingJobAdapter alloc] initWithDatabase:database
                                                                               namespace:[NSString stringWithFormat:@"auth-failure-%@", [[NSUUID UUID] UUIDString]]
                                                                    leaseDurationSeconds:30 error:&error];
  XCTAssertNotNil(jobs, @"%@", error);
  XCTAssertTrue([jobs installSchemaWithError:&error], @"%@", error);
  NSString *jobsStateDirectory = ALNTestTemporaryDirectory(@"arlen-auth-jobs-failure");
  XCTAssertNotNil(jobsStateDirectory);
  ALNApplication *app = [self applicationWithConfig:@{
    @"environment" : @"production",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"persistence" : @{ @"path" : [jobsStateDirectory stringByAppendingPathComponent:@"state.plist"] } },
    @"authModule" : @{ @"publicBaseURL" : @"https://app.example.test", @"allowWithoutCSRF" : @YES,
                       @"attemptLimits" : @{ @"mail" : @{ @"maxPerAddress" : @10000 } } },
  }];
  ALNInMemoryMailAdapter *mail = [[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"failing_auth_mail"];
  [app setMailAdapter:mail];
  [app setJobsAdapter:jobs];
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);

  NSString *newEmail = [NSString stringWithFormat:@"rollback-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSString *existingEmail = [self createLinkUserEmail];
  jobs.failEnqueue = YES;
  NSDictionary *payload = @{ @"email" : newEmail, @"display_name" : @"Rollback", @"password" : @"rollback-password" };
  ALNResponse *registration = [self postJSON:payload to:@"/auth/api/register" app:app host:@"app.example.test"];
  XCTAssertEqual((NSInteger)503, registration.statusCode);
  XCTAssertNil([[ALNAuthModuleRuntime sharedRuntime] userForEmail:newEmail error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)0, [[mail deliveriesSnapshot] count]);
  ALNResponse *existingRegistration = [self postJSON:@{ @"email" : existingEmail, @"display_name" : @"Existing",
                                                       @"password" : @"rollback-password" }
                                                   to:@"/auth/api/register" app:app host:@"app.example.test"];
  XCTAssertEqual((NSInteger)503, existingRegistration.statusCode);
  XCTAssertEqualObjects([self JSONResponseBody:registration], [self JSONResponseBody:existingRegistration]);

  NSString *unknownEmail = [NSString stringWithFormat:@"missing-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  ALNResponse *knownReset = [self postJSON:@{ @"email" : existingEmail } to:@"/auth/api/password/forgot"
                                      app:app host:@"app.example.test"];
  ALNResponse *unknownReset = [self postJSON:@{ @"email" : unknownEmail } to:@"/auth/api/password/forgot"
                                        app:app host:@"app.example.test"];
  XCTAssertEqual((NSInteger)503, knownReset.statusCode);
  XCTAssertEqualObjects([self JSONResponseBody:knownReset], [self JSONResponseBody:unknownReset]);
  XCTAssertEqual((NSUInteger)0, [[mail deliveriesSnapshot] count]);
}

- (void)testPasswordResetLinkUsesConfiguredPublicBaseURLNotHostHeader {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  for (NSString *environment in @[ @"test", @"development" ]) {
    ALNInMemoryMailAdapter *adapter = nil;
    ALNApplication *app = [self mailingApplicationWithEnvironment:environment
                                                       authModule:@{ @"publicBaseURL" : @"https://app.example.test/" }
                                                      mailAdapter:&adapter];
    NSString *email = [self createLinkUserEmail];
    ALNResponse *response = [self postJSON:@{ @"email" : email } to:@"/auth/api/password/forgot" app:app host:@"evil.example"];
    XCTAssertEqual((NSInteger)200, response.statusCode, @"%@", environment);
    NSArray *bodies = [self deliveredTextBodies:adapter];
    XCTAssertEqual((NSUInteger)1, [bodies count], @"%@", environment);
    XCTAssertTrue([[bodies firstObject] containsString:@"https://app.example.test/auth/password/reset?token="], @"%@ %@",
                  environment, bodies);
    XCTAssertFalse([[bodies firstObject] containsString:@"evil.example"], @"%@ %@", environment, bodies);
  }
}

- (void)testRegistrationVerificationLinkUsesConfiguredPublicBaseURL {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNInMemoryMailAdapter *adapter = nil;
  ALNApplication *app = [self mailingApplicationWithEnvironment:@"test"
                                                     authModule:@{ @"publicBaseURL" : @"https://app.example.test" }
                                                    mailAdapter:&adapter];
  NSString *email = [NSString stringWithFormat:@"register-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  ALNResponse *response = [self postJSON:@{ @"email" : email, @"display_name" : @"Registrant", @"password" : @"register-password" }
                                      to:@"/auth/api/register"
                                     app:app
                                    host:@"evil.example"];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSArray *bodies = [self deliveredTextBodies:adapter];
  XCTAssertEqual((NSUInteger)1, [bodies count]);
  XCTAssertTrue([[bodies firstObject] containsString:@"https://app.example.test/auth/verify?token="], @"%@", bodies);
  XCTAssertFalse([[bodies firstObject] containsString:@"evil.example"], @"%@", bodies);
}

- (void)testRegistrationDoesNotRevealExistingAddressOrStartSessionByDefault {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNInMemoryMailAdapter *adapter = nil;
  ALNApplication *app = [self mailingApplicationWithEnvironment:@"test"
                                                     authModule:@{ @"publicBaseURL" : @"https://app.example.test" }
                                                    mailAdapter:&adapter];
  NSString *email = [NSString stringWithFormat:@"registration-privacy-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSDictionary *payload = @{ @"email" : email, @"display_name" : @"Registrant", @"password" : @"register-password" };
  ALNResponse *created = [self postJSON:payload to:@"/auth/api/register" app:app host:@"app.example.test"];
  XCTAssertEqual((NSInteger)200, created.statusCode);
  XCTAssertEqual((NSUInteger)1, [[adapter deliveriesSnapshot] count]);
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:1 error:NULL];
  NSString *countSQL = @"SELECT COUNT(*)::text AS users, "
                        "(SELECT COUNT(*)::text FROM auth_verification_tokens t JOIN auth_users v ON v.id = t.user_id "
                        "WHERE lower(v.email) = $1) AS tokens FROM auth_users WHERE lower(email) = $1";
  NSDictionary *before = [[database executeQuery:countSQL parameters:@[ email ] error:NULL] firstObject];
  ALNResponse *existing = [self postJSON:payload to:@"/auth/api/register" app:app host:@"app.example.test"];
  XCTAssertEqual(created.statusCode, existing.statusCode);
  XCTAssertEqualObjects([self JSONResponseBody:created], [self JSONResponseBody:existing]);
  XCTAssertEqualObjects([created headerForName:@"Set-Cookie"], [existing headerForName:@"Set-Cookie"]);
  XCTAssertNil([self JSONResponseBody:created][@"authenticated"]);
  XCTAssertNil([self JSONResponseBody:created][@"user"]);
  XCTAssertEqual((NSUInteger)1, [[adapter deliveriesSnapshot] count]);
  NSDictionary *after = [[database executeQuery:countSQL parameters:@[ email ] error:NULL] firstObject];
  XCTAssertEqualObjects(@"1", before[@"users"]);
  XCTAssertEqualObjects(before, after);
  ALNEOCRegisterTemplate(@"modules/auth/result/index.html.eoc", Phase13ERegistrationResult);
  ALNEOCRegisterTemplate(@"modules/auth/layouts/main.html.eoc", Phase13ERegistrationLayout);
  NSString *htmlEmail = [NSString stringWithFormat:@"registration-html-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSData *htmlBody = [NSJSONSerialization dataWithJSONObject:@{
    @"email" : htmlEmail, @"display_name" : @"Registrant", @"password" : @"register-password",
  } options:0 error:NULL];
  NSDictionary *htmlHeaders = @{ @"Accept" : @"text/html", @"Content-Type" : @"application/json",
                                 @"Host" : @"app.example.test" };
  ALNResponse *newHTML = [app dispatchRequest:[self requestWithMethod:@"POST" path:@"/auth/register"
                                                       headers:htmlHeaders body:htmlBody]];
  ALNResponse *existingHTML = [app dispatchRequest:[self requestWithMethod:@"POST" path:@"/auth/register"
                                                            headers:htmlHeaders body:htmlBody]];
  XCTAssertEqual((NSInteger)200, newHTML.statusCode);
  XCTAssertEqual(newHTML.statusCode, existingHTML.statusCode);
  XCTAssertEqualObjects(newHTML.bodyData, existingHTML.bodyData);
  XCTAssertEqualObjects([newHTML headerForName:@"Set-Cookie"], [existingHTML headerForName:@"Set-Cookie"]);
  ALNEOCClearTemplateRegistry();
}

- (void)testEmailLinksWithoutPublicBaseURLUseHostOnlyInDevelopmentAndTest {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNInMemoryMailAdapter *adapter = nil;
  ALNApplication *app = [self mailingApplicationWithEnvironment:@"test" authModule:nil mailAdapter:&adapter];
  NSString *email = [self createLinkUserEmail];
  XCTAssertEqual((NSInteger)200, [self postJSON:@{ @"email" : email } to:@"/auth/api/password/forgot" app:app
                                           host:@"localhost:3000"].statusCode);
  NSArray *bodies = [self deliveredTextBodies:adapter];
  XCTAssertEqual((NSUInteger)1, [bodies count]);
  XCTAssertTrue([[bodies firstObject] containsString:@"http://localhost:3000/auth/password/reset?token="], @"%@", bodies);

  // Production now rejects synchronous mail, even when no public base URL is
  // configured. The startup validation test covers that path.
}

@end
