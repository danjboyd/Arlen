#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import "../shared/ALNTestSupport.h"
#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNJobsModule.h"
#import "ALNOpsModule.h"
#import "ALNPg.h"
#import "ALNSearchModule.h"
#import "ALNSecurityPrimitives.h"
#import "ALNTOTP.h"
#import "ALNTestClient.h"

// Session roles follow the auth_users row on every request: module API guards
// (admin-ui, jobs, ops, search) see the current roles, not the ones stored in the
// signed session cookie at sign-in. Signing out, password changes and the
// absolute session lifetime end sessions server-side. Runs in-process against
// ARLEN_PG_TEST_DSN.
@interface AuthSessionRoleRefreshIntegrationTests : XCTestCase
@property(nonatomic, strong) ALNPg *database;
@end

@implementation AuthSessionRoleRefreshIntegrationTests

- (NSString *)pgTestDSN {
  return ALNTestEnvironmentString(@"ARLEN_PG_TEST_DSN");
}

- (void)tearDown {
  self.database = nil;
  [super tearDown];
}

- (BOOL)applyAuthMigrationsWithDSN:(NSString *)dsn {
  NSError *error = nil;
  self.database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:1 error:&error];
  XCTAssertNotNil(self.database, @"%@", error);
  if (self.database == nil) {
    return NO;
  }
  NSString *migrations = ALNTestPathFromRepoRoot(@"modules/auth/Migrations");
  NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:migrations error:NULL]
      sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *file in files) {
    if (![[file pathExtension] isEqualToString:@"sql"]) {
      continue;
    }
    NSString *sql = [NSString stringWithContentsOfFile:[migrations stringByAppendingPathComponent:file]
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [sql componentsSeparatedByString:@"\n"]) {
      if (![[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] hasPrefix:@"--"]) {
        [lines addObject:line];
      }
    }
    for (NSString *statement in [[lines componentsJoinedByString:@"\n"] componentsSeparatedByString:@";"]) {
      NSString *trimmed = [statement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([trimmed length] == 0) {
        continue;
      }
      if ([self.database executeCommand:trimmed parameters:@[] error:&error] < 0) {
        XCTFail(@"%@: %@", file, error);
        return NO;
      }
    }
  }
  return YES;
}

- (void)execute:(NSString *)sql parameters:(NSArray *)parameters {
  NSError *error = nil;
  XCTAssertNotNil([self.database executeQuery:sql parameters:parameters error:&error], @"%@", error);
}

- (NSString *)scalar:(NSString *)sql parameters:(NSArray *)parameters {
  NSError *error = nil;
  NSDictionary *row = [[self.database executeQuery:sql parameters:parameters error:&error] firstObject];
  XCTAssertNil(error);
  return [[row allValues] firstObject];
}

- (ALNTestClient *)clientWithDSN:(NSString *)dsn bootstrapAdmins:(NSArray *)emails {
  return [self clientWithDSN:dsn bootstrapAdmins:emails authConfig:nil search:NO];
}

- (ALNTestClient *)clientWithDSN:(NSString *)dsn
                 bootstrapAdmins:(NSArray *)emails
                      authConfig:(NSDictionary *)authConfig
                          search:(BOOL)search {
  return [self clientWithDSN:dsn bootstrapAdmins:emails authConfig:authConfig search:search security:nil];
}

- (ALNTestClient *)clientWithDSN:(NSString *)dsn
                 bootstrapAdmins:(NSArray *)emails
                      authConfig:(NSDictionary *)authConfig
                          search:(BOOL)search
                        security:(NSDictionary *)security {
  NSMutableDictionary *authModule = [NSMutableDictionary dictionaryWithDictionary:authConfig ?: @{}];
  if (authModule[@"registration"] == nil) {
    authModule[@"registration"] = @{ @"autoLogin" : @YES };
  }
  authModule[@"bootstrapAdminEmails"] = emails ?: @[];
  NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{ @"enabled" : @YES, @"secret" : @"auth-role-refresh-session-secret-0123456789abcdef" },
    @"csrf" : @{ @"enabled" : @YES },
    @"database" : @{ @"connectionString" : dsn },
    @"authModule" : authModule,
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
  }];
  if (security != nil) {
    config[@"security"] = security;
  }
  if (search) {
    config[@"searchModule"] = @{
      @"adminUI" : @{ @"autoResources" : @YES, @"resourceProviderClass" : @"ALNSearchAdminResourceProvider" },
    };
  }
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  if (search) {
    XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  }
  XCTAssertTrue([[[ALNOpsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  ALNTestClient *client = [[ALNTestClient alloc] initWithApplication:app error:&error];
  XCTAssertNotNil(client, @"%@", error);
  return client;
}

- (NSString *)uniqueEmail:(NSString *)label {
  return [NSString stringWithFormat:@"%@-%@@example.test", label, [[[NSUUID UUID] UUIDString] lowercaseString]];
}

// Registers, enrolls TOTP and verifies it, leaving an AAL2 session in the jar.
- (NSString *)registerAndStepUp:(ALNTestClient *)client email:(NSString *)email {
  NSString *subject = [self registerUser:client email:email];
  [self stepUp:client subject:subject];
  return subject;
}

// Registers, leaving an AAL1 session in the jar.
- (NSString *)registerUser:(ALNTestClient *)client email:(NSString *)email {
  ALNResponse *registered = [client post:@"/auth/api/register"
                                    JSON:@{ @"email" : email, @"display_name" : @"Roles", @"password" : @"role-refresh-password" }];
  XCTAssertEqual((NSInteger)200, registered.statusCode, @"%@", [registered bodyText]);
  NSString *subject = [registered JSONObject][@"subject"];
  XCTAssertTrue([subject length] > 0);
  return subject ?: @"";
}

- (void)stepUp:(ALNTestClient *)client subject:(NSString *)subject {
  ALNResponse *enrollment = [client get:@"/auth/api/mfa/totp"];
  XCTAssertEqual((NSInteger)200, enrollment.statusCode, @"%@", [enrollment bodyText]);
  NSString *secret = [self scalar:@"SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
                                   "WHERE u.subject = $1 ORDER BY m.id DESC LIMIT 1"
                       parameters:@[ subject ?: @"" ]];
  XCTAssertTrue([secret length] > 0);
  NSString *code = [ALNTOTP codeForSecret:secret ?: @"" atDate:[NSDate date] error:NULL];
  ALNResponse *verified = [client post:@"/auth/api/mfa/totp/verify" JSON:@{ @"code" : code ?: @"" }];
  XCTAssertEqual((NSInteger)200, verified.statusCode, @"%@", [verified bodyText]);
}

- (ALNTestClient *)signedInClientForApplication:(ALNApplication *)app email:(NSString *)email password:(NSString *)password {
  ALNTestClient *client = [[ALNTestClient alloc] initWithApplication:app error:NULL];
  ALNResponse *login = [client post:@"/auth/api/login" JSON:@{ @"email" : email, @"password" : password }];
  XCTAssertEqual((NSInteger)200, login.statusCode, @"%@", [login bodyText]);
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
  return client;
}

// The jar's cookies as a Cookie header, to replay later from another client.
- (NSString *)cookieHeader:(ALNTestClient *)client {
  NSMutableArray *pairs = [NSMutableArray array];
  NSDictionary *cookies = [client cookies];
  for (NSString *name in [[cookies allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, cookies[name]]];
  }
  return [pairs componentsJoinedByString:@"; "];
}

- (NSDictionary *)replayedSessionState:(NSString *)cookieHeader application:(ALNApplication *)app {
  ALNTestClient *replay = [[ALNTestClient alloc] initWithApplication:app error:NULL];
  ALNResponse *response = [replay requestWithMethod:@"GET"
                                               path:@"/auth/api/session"
                                              query:nil
                                            headers:@{ @"cookie" : cookieHeader ?: @"" }
                                               body:nil];
  XCTAssertEqual((NSInteger)200, response.statusCode, @"%@", [response bodyText]);
  id payload = [response JSONObject];
  return [payload isKindOfClass:[NSDictionary class]] ? payload : @{};
}

- (void)shiftAuthenticationTime:(ALNTestClient *)client bySeconds:(NSTimeInterval)seconds {
  NSError *error = nil;
  BOOL updated = [client updateSession:^(NSMutableDictionary *session) {
    NSMutableDictionary *state = [session[@"_auth"] mutableCopy];
    state[@"auth_time"] = @([state[@"auth_time"] doubleValue] + seconds);
    session[@"_auth"] = state;
  } error:&error];
  XCTAssertTrue(updated, @"%@", error);
}

// `dsn` with its search_path set to `schema`, for a URI
// (`postgresql://...`) or a keyword/value (`dbname=x host=y`) connection string.
- (NSString *)DSN:(NSString *)dsn withSearchPath:(NSString *)schema {
  NSString *trimmed = [dsn stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *lower = [trimmed lowercaseString];
  if ([lower hasPrefix:@"postgresql://"] || [lower hasPrefix:@"postgres://"]) {
    NSString *separator = [trimmed containsString:@"?"] ? @"&" : @"?";
    return [NSString stringWithFormat:@"%@%@options=-csearch_path%%3D%@", trimmed, separator, schema];
  }
  return [NSString stringWithFormat:@"%@ options='-csearch_path=%@'", trimmed, schema];
}

// Runs `block` against a fresh schema holding the auth migrations.
- (void)withIsolatedSchema:(NSString *)label block:(void (^)(NSString *schemaDSN))block {
  NSString *dsn = [self pgTestDSN];
  NSError *error = nil;
  ALNPg *admin = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:1 error:&error];
  XCTAssertNotNil(admin, @"%@", error);
  NSString *schema = [NSString stringWithFormat:@"%@_%@", label,
                      [[[[NSUUID UUID] UUIDString] lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
  NSArray *noParameters = @[];
  NSInteger created = [admin executeCommand:[NSString stringWithFormat:@"CREATE SCHEMA %@", schema]
                                 parameters:noParameters
                                      error:&error];
  XCTAssertTrue(created >= 0, @"%@", error);
  @try {
    NSString *schemaDSN = [self DSN:dsn withSearchPath:schema];
    XCTAssertTrue([self applyAuthMigrationsWithDSN:schemaDSN]);
    block(schemaDSN);
  } @finally {
    self.database = nil;
    [admin executeCommand:[NSString stringWithFormat:@"DROP SCHEMA IF EXISTS %@ CASCADE", schema] parameters:noParameters error:NULL];
  }
}

- (NSString *)encodedSubject:(NSString *)subject {
  NSMutableCharacterSet *allowed = [[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy];
  [allowed addCharactersInString:@":"];
  return [subject stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

- (void)assertModuleAPIsReturn:(NSInteger)status client:(ALNTestClient *)client {
  for (NSString *path in @[ @"/admin/api/session", @"/admin/api/users", @"/jobs/api/definitions", @"/ops/api/summary" ]) {
    ALNResponse *response = [client get:path];
    XCTAssertEqual(status, response.statusCode, @"%@: %@", path, [response bodyText]);
  }
}

- (NSDictionary *)sessionState:(ALNTestClient *)client {
  ALNResponse *response = [client get:@"/auth/api/session"];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  id payload = [response JSONObject];
  return [payload isKindOfClass:[NSDictionary class]] ? payload : @{};
}

- (void)testRevokedAdminRoleIsDeniedOnModuleAPIsAndCannotBeRegranted {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"revoked-admin"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[ email ]];
  NSString *subject = [self registerAndStepUp:client email:email];
  [self assertModuleAPIsReturn:200 client:client];

  [self execute:@"UPDATE auth_users SET roles_json = '[\"user\"]' WHERE subject = $1 RETURNING id"
     parameters:@[ subject ]];
  [self assertModuleAPIsReturn:403 client:client];

  NSString *grantPath = [NSString stringWithFormat:@"/admin/api/users/%@/actions/grant_admin",
                                                   [self encodedSubject:subject]];
  ALNResponse *grant = [client post:grantPath JSON:@{}];
  XCTAssertEqual((NSInteger)403, grant.statusCode, @"%@", [grant bodyText]);
  NSString *roles = [self scalar:@"SELECT roles_json FROM auth_users WHERE subject = $1" parameters:@[ subject ]];
  XCTAssertFalse([roles containsString:@"admin"], @"%@", roles);

  // Still signed in, with the current roles.
  NSDictionary *state = [self sessionState:client];
  XCTAssertEqualObjects(@YES, state[@"authenticated"]);
  XCTAssertEqualObjects(@[ @"user" ], state[@"roles"]);
}

- (void)testGrantedAdminRoleAppliesWithoutSigningInAgain {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[]];
  NSString *subject = [self registerAndStepUp:client email:[self uniqueEmail:@"granted-admin"]];
  [self assertModuleAPIsReturn:403 client:client];

  [self execute:@"UPDATE auth_users SET roles_json = '[\"user\",\"admin\"]' WHERE subject = $1 RETURNING id"
     parameters:@[ subject ]];
  [self assertModuleAPIsReturn:200 client:client];
}

- (void)testDeletedUserSessionIsSignedOut {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"deleted-admin"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[ email ]];
  NSString *subject = [self registerAndStepUp:client email:email];
  [self assertModuleAPIsReturn:200 client:client];

  [self execute:@"DELETE FROM auth_users WHERE subject = $1 RETURNING id" parameters:@[ subject ]];
  [self assertModuleAPIsReturn:401 client:client];
  XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);
}

- (void)testSessionStampBumpSignsOutExistingSessions {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"stamp-admin"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[ email ]];
  NSString *subject = [self registerAndStepUp:client email:email];
  [self assertModuleAPIsReturn:200 client:client];

  NSError *error = nil;
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] bumpSessionStampForSubject:subject error:&error], @"%@", error);
  XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);
  [self assertModuleAPIsReturn:401 client:client];

  // A new sign-in records the new stamp and stays signed in.
  ALNResponse *login = [client post:@"/auth/api/login"
                               JSON:@{ @"email" : email, @"password" : @"role-refresh-password" }];
  XCTAssertEqual((NSInteger)200, login.statusCode, @"%@", [login bodyText]);
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);

  XCTAssertFalse([[ALNAuthModuleRuntime sharedRuntime] bumpSessionStampForSubject:@"user:missing" error:&error]);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorNotFound, error.code);
}

- (void)testAdminAPIRevocationEndsTheTargetUsersSessions {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *operatorEmail = [self uniqueEmail:@"operator-admin"];
  NSString *targetEmail = [self uniqueEmail:@"target-admin"];
  ALNTestClient *operatorClient = [self clientWithDSN:dsn bootstrapAdmins:@[ operatorEmail, targetEmail ]];
  NSString *operatorSubject = [self registerAndStepUp:operatorClient email:operatorEmail];
  ALNTestClient *targetClient = [[ALNTestClient alloc] initWithApplication:operatorClient.application error:NULL];
  NSString *targetSubject = [self registerAndStepUp:targetClient email:targetEmail];
  [self assertModuleAPIsReturn:200 client:targetClient];

  NSString *revokePath = [NSString stringWithFormat:@"/admin/api/users/%@/actions/revoke_admin",
                                                    [self encodedSubject:targetSubject]];
  ALNResponse *revoke = [operatorClient post:revokePath JSON:@{}];
  XCTAssertEqual((NSInteger)200, revoke.statusCode, @"%@", [revoke bodyText]);

  XCTAssertEqualObjects(@NO, [self sessionState:targetClient][@"authenticated"]);
  XCTAssertEqualObjects(@YES, [self sessionState:operatorClient][@"authenticated"]);
  XCTAssertEqualObjects(@"1", [self scalar:@"SELECT session_stamp::text FROM auth_users WHERE subject = $1"
                                parameters:@[ targetSubject ]]);
  XCTAssertEqualObjects(@"0", [self scalar:@"SELECT session_stamp::text FROM auth_users WHERE subject = $1"
                                parameters:@[ operatorSubject ]]);
}

// Before migration 002 is applied (auth_users without session_stamp), roles are
// still read live, nothing fails, and revocation through the admin API succeeds.
- (void)testRolesStayLiveWithoutTheSessionStampColumn {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSError *error = nil;
  ALNPg *admin = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:1 error:&error];
  XCTAssertNotNil(admin, @"%@", error);
  NSString *schema = [NSString stringWithFormat:@"auth_no_stamp_%@",
                      [[[[NSUUID UUID] UUIDString] lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
  NSArray *noParameters = @[];
  NSInteger created = [admin executeCommand:[NSString stringWithFormat:@"CREATE SCHEMA %@", schema]
                                 parameters:noParameters
                                      error:&error];
  XCTAssertTrue(created >= 0, @"%@", error);
  @try {
    NSString *schemaDSN = [self DSN:dsn withSearchPath:schema];
    XCTAssertTrue([self applyAuthMigrationsWithDSN:schemaDSN]);
    XCTAssertTrue([self.database executeCommand:@"ALTER TABLE auth_users DROP COLUMN session_stamp"
                                     parameters:noParameters
                                          error:&error] >= 0, @"%@", error);

    NSString *operatorEmail = [self uniqueEmail:@"nostamp-operator"];
    NSString *targetEmail = [self uniqueEmail:@"nostamp-target"];
    ALNTestClient *operatorClient = [self clientWithDSN:schemaDSN bootstrapAdmins:@[ operatorEmail, targetEmail ]];
    [self registerAndStepUp:operatorClient email:operatorEmail];
    ALNTestClient *targetClient = [[ALNTestClient alloc] initWithApplication:operatorClient.application error:NULL];
    NSString *targetSubject = [self registerAndStepUp:targetClient email:targetEmail];
    [self assertModuleAPIsReturn:200 client:targetClient];

    // Revoked in the database: denied, still signed in, no server error.
    [self execute:@"UPDATE auth_users SET roles_json = '[\"user\"]' WHERE subject = $1 RETURNING id"
       parameters:@[ targetSubject ]];
    [self assertModuleAPIsReturn:403 client:targetClient];
    XCTAssertEqualObjects(@YES, [self sessionState:targetClient][@"authenticated"]);

    // Granted again: applies without signing in.
    [self execute:@"UPDATE auth_users SET roles_json = '[\"user\",\"admin\"]' WHERE subject = $1 RETURNING id"
       parameters:@[ targetSubject ]];
    [self assertModuleAPIsReturn:200 client:targetClient];

    // Revoked through the admin API: succeeds without the stamp; roles deny.
    NSString *revokePath = [NSString stringWithFormat:@"/admin/api/users/%@/actions/revoke_admin",
                                                      [self encodedSubject:targetSubject]];
    ALNResponse *revoke = [operatorClient post:revokePath JSON:@{}];
    XCTAssertEqual((NSInteger)200, revoke.statusCode, @"%@", [revoke bodyText]);
    [self assertModuleAPIsReturn:403 client:targetClient];
    XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] bumpSessionStampForSubject:targetSubject error:&error], @"%@", error);

    // A password change still succeeds and keeps the session signed in.
    ALNResponse *change = [targetClient post:@"/auth/api/password/change"
                                        JSON:@{ @"current_password" : @"role-refresh-password",
                                                @"new_password" : @"role-refresh-password-changed" }];
    XCTAssertEqual((NSInteger)200, change.statusCode, @"%@", [change bodyText]);
    XCTAssertEqualObjects(@YES, [self sessionState:targetClient][@"authenticated"]);

    // Sign-out-everywhere says it could end only this session.
    XCTAssertFalse([[ALNAuthModuleRuntime sharedRuntime] canEndOtherSessions]);
    ALNResponse *logoutAll = [operatorClient post:@"/auth/api/logout/all" JSON:@{}];
    XCTAssertEqual((NSInteger)200, logoutAll.statusCode, @"%@", [logoutAll bodyText]);
    NSDictionary *logoutAllBody = [[logoutAll JSONObject] isKindOfClass:[NSDictionary class]] ? [logoutAll JSONObject] : @{};
    XCTAssertEqualObjects(@"partial", logoutAllBody[@"status"]);
    XCTAssertEqualObjects(@"current_session", logoutAllBody[@"scope"]);
    XCTAssertEqualObjects(@NO, [self sessionState:operatorClient][@"authenticated"]);

    // A deleted user is still signed out.
    [self execute:@"DELETE FROM auth_users WHERE subject = $1 RETURNING id" parameters:@[ targetSubject ]];
    XCTAssertEqualObjects(@NO, [self sessionState:targetClient][@"authenticated"]);
  } @finally {
    self.database = nil;
    [admin executeCommand:[NSString stringWithFormat:@"DROP SCHEMA IF EXISTS %@ CASCADE", schema] parameters:noParameters error:NULL];
  }
}

#pragma mark - Ending sessions

- (void)testRoutePolicyRequiresFreshAuthSessionBeforeProtectedController {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSDictionary *security = @{ @"routePolicies" : @{
    @"session" : @{ @"pathPrefixes" : @[ @"/auth/api/session" ], @"requireAuth" : @YES }
  } };
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[] authConfig:nil
                                       search:NO security:security];
  [self registerUser:client email:[self uniqueEmail:@"policy-replay"]];
  NSString *cookie = [self cookieHeader:client];
  ALNResponse *before = [client get:@"/auth/api/session"];
  XCTAssertEqual((NSInteger)200, before.statusCode, @"%@", [before bodyText]);

  ALNResponse *logout = [client post:@"/auth/api/logout" JSON:@{}];
  XCTAssertEqual((NSInteger)200, logout.statusCode, @"%@", [logout bodyText]);
  ALNTestClient *replay = [[ALNTestClient alloc] initWithApplication:client.application error:NULL];
  ALNResponse *after = [replay requestWithMethod:@"GET" path:@"/auth/api/session" query:nil
                                        headers:@{ @"cookie" : cookie ?: @"" } body:nil];
  XCTAssertEqual((NSInteger)403, after.statusCode, @"%@", [after bodyText]);
  XCTAssertEqualObjects(@"authentication_required", [after headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

- (void)testReplayedCookieAfterLogoutIsSignedOutWhileOtherDevicesStaySignedIn {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"logout-replay"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[]];
  NSString *subject = [self registerUser:client email:email];
  NSString *beforeStepUp = [self cookieHeader:client];
  [self stepUp:client subject:subject];
  XCTAssertEqualObjects(@NO, [self replayedSessionState:beforeStepUp application:client.application][@"authenticated"]);
  NSString *beforeLogout = [self cookieHeader:client];
  ALNTestClient *otherDevice = [self signedInClientForApplication:client.application
                                                            email:email
                                                         password:@"role-refresh-password"];

  ALNResponse *logout = [client post:@"/auth/api/logout" JSON:@{}];
  XCTAssertEqual((NSInteger)200, logout.statusCode, @"%@", [logout bodyText]);
  XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);

  // Copies of the signed-out session, from before and after step-up, are refused.
  XCTAssertEqualObjects(@NO, [self replayedSessionState:beforeLogout application:client.application][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self replayedSessionState:beforeStepUp application:client.application][@"authenticated"]);
  // The user's other session is unaffected, and nothing bumped the stamp.
  XCTAssertEqualObjects(@YES, [self sessionState:otherDevice][@"authenticated"]);
  XCTAssertEqualObjects(@"0", [self scalar:@"SELECT session_stamp::text FROM auth_users WHERE subject = $1"
                                parameters:@[ subject ]]);
  XCTAssertEqualObjects(@"t", [self scalar:@"SELECT CASE WHEN COUNT(*) > 0 AND MIN(expires_at) > NOW() THEN 't' ELSE 'f' END "
                                            "FROM auth_revoked_sessions WHERE subject = $1"
                                parameters:@[ subject ]]);

  // Signing in again starts a new session that is not affected.
  ALNResponse *login = [client post:@"/auth/api/login" JSON:@{ @"email" : email, @"password" : @"role-refresh-password" }];
  XCTAssertEqual((NSInteger)200, login.statusCode, @"%@", [login bodyText]);
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
}

- (void)testSignOutEverywhereEndsEverySessionOfTheUser {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"logout-all"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[]];
  NSString *subject = [self registerUser:client email:email];
  NSString *saved = [self cookieHeader:client];
  ALNTestClient *otherDevice = [self signedInClientForApplication:client.application
                                                            email:email
                                                         password:@"role-refresh-password"];

  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] canEndOtherSessions]);
  ALNResponse *logoutAll = [client post:@"/auth/api/logout/all" JSON:@{}];
  XCTAssertEqual((NSInteger)200, logoutAll.statusCode, @"%@", [logoutAll bodyText]);
  XCTAssertEqualObjects(@"all_sessions", [logoutAll JSONObject][@"scope"]);
  XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self sessionState:otherDevice][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self replayedSessionState:saved application:client.application][@"authenticated"]);
  XCTAssertEqualObjects(@"1", [self scalar:@"SELECT session_stamp::text FROM auth_users WHERE subject = $1"
                                parameters:@[ subject ]]);

  ALNResponse *anonymous = [client post:@"/auth/api/logout/all" JSON:@{}];
  XCTAssertEqual((NSInteger)401, anonymous.statusCode, @"%@", [anonymous bodyText]);
}

- (void)testPasswordChangeEndsOtherSessionsButKeepsTheCurrentOne {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"password-change"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[]];
  NSString *subject = [self registerUser:client email:email];
  NSString *beforeChange = [self cookieHeader:client];
  ALNTestClient *otherDevice = [self signedInClientForApplication:client.application
                                                            email:email
                                                         password:@"role-refresh-password"];

  ALNResponse *change = [client post:@"/auth/api/password/change"
                                JSON:@{ @"current_password" : @"role-refresh-password",
                                        @"new_password" : @"role-refresh-password-changed" }];
  XCTAssertEqual((NSInteger)200, change.statusCode, @"%@", [change bodyText]);

  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self sessionState:otherDevice][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self replayedSessionState:beforeChange application:client.application][@"authenticated"]);
  XCTAssertEqualObjects(@"1", [self scalar:@"SELECT session_stamp::text FROM auth_users WHERE subject = $1"
                                parameters:@[ subject ]]);
  [self signedInClientForApplication:client.application email:email password:@"role-refresh-password-changed"];
}

- (void)testPasswordResetByTokenEndsExistingSessions {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"password-reset"];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[]];
  NSString *subject = [self registerUser:client email:email];
  ALNTestClient *otherDevice = [self signedInClientForApplication:client.application
                                                            email:email
                                                         password:@"role-refresh-password"];
  NSString *token = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSString *storedToken = [@"sha256:" stringByAppendingString:
      ALNLowercaseHexStringFromData(ALNSHA256([token dataUsingEncoding:NSUTF8StringEncoding]))];
  [self execute:@"INSERT INTO auth_password_reset_tokens (user_id, token, expires_at) "
                 "SELECT id, $2, NOW() + INTERVAL '1 hour' FROM auth_users WHERE subject = $1 RETURNING id"
     parameters:@[ subject, storedToken ]];

  ALNTestClient *resetting = [[ALNTestClient alloc] initWithApplication:client.application error:NULL];
  ALNResponse *reset = [resetting post:@"/auth/api/password/reset"
                                  JSON:@{ @"token" : token, @"password" : @"role-refresh-password-reset" }];
  XCTAssertEqual((NSInteger)200, reset.statusCode, @"%@", [reset bodyText]);

  // The resetting browser is signed in afresh; every earlier session has ended.
  XCTAssertEqualObjects(@YES, [self sessionState:resetting][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self sessionState:otherDevice][@"authenticated"]);
}

- (void)testRemovingAnSMSFactorEndsOtherSessionsButKeepsTheCurrentOne {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *email = [self uniqueEmail:@"sms-remove"];
  NSDictionary *authConfig = @{ @"mfa" : @{ @"sms" : @{ @"enabled" : @YES, @"testVerificationCode" : @"123456" } } };
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[] authConfig:authConfig search:NO];
  NSString *subject = [self registerAndStepUp:client email:email];
  ALNTestClient *otherDevice = [self signedInClientForApplication:client.application
                                                            email:email
                                                         password:@"role-refresh-password"];
  [self execute:@"INSERT INTO auth_mfa_enrollments (user_id, type, secret, recovery_codes_json, enabled, verified_at) "
                 "SELECT id, 'sms', '+15555550123', '[]', TRUE, NOW() FROM auth_users WHERE subject = $1 RETURNING id"
     parameters:@[ subject ]];

  ALNResponse *removed = [client post:@"/auth/api/mfa/sms/remove" JSON:@{}];
  XCTAssertEqual((NSInteger)200, removed.statusCode, @"%@", [removed bodyText]);
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
  XCTAssertEqualObjects(@NO, [self sessionState:otherDevice][@"authenticated"]);
}

- (void)testSessionsEndAfterTheAbsoluteLifetime {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  ALNTestClient *defaults = [self clientWithDSN:dsn bootstrapAdmins:@[]];
  XCTAssertNotNil(defaults);
  XCTAssertEqual((NSUInteger)1209600, [ALNAuthModuleRuntime sharedRuntime].absoluteSessionLifetimeSeconds);

  ALNTestClient *client = [self clientWithDSN:dsn
                              bootstrapAdmins:@[]
                                   authConfig:@{ @"session" : @{ @"absoluteLifetimeSeconds" : @3600 } }
                                       search:NO];
  XCTAssertEqual((NSUInteger)3600, [ALNAuthModuleRuntime sharedRuntime].absoluteSessionLifetimeSeconds);
  [self registerUser:client email:[self uniqueEmail:@"lifetime"]];

  [self shiftAuthenticationTime:client bySeconds:-1800];
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);
  // Renewed on every request, but older than the lifetime: signed out.
  [self shiftAuthenticationTime:client bySeconds:-3600];
  XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);

  // A session without a recorded sign-in time is treated as expired.
  ALNTestClient *untimed = [self clientWithDSN:dsn
                               bootstrapAdmins:@[]
                                    authConfig:@{ @"session" : @{ @"absoluteLifetimeSeconds" : @3600 } }
                                        search:NO];
  [self registerUser:untimed email:[self uniqueEmail:@"untimed"]];
  XCTAssertEqualObjects(@YES, [self sessionState:untimed][@"authenticated"]);
  NSError *error = nil;
  XCTAssertTrue([untimed updateSession:^(NSMutableDictionary *session) {
    NSMutableDictionary *state = [session[@"_auth"] mutableCopy];
    [state removeObjectForKey:@"auth_time"];
    session[@"_auth"] = state;
  } error:&error], @"%@", error);
  XCTAssertEqualObjects(@NO, [self sessionState:untimed][@"authenticated"]);
}

// Before migration 003 is applied, signing out still clears the session and
// nothing fails; only copies of the old cookie cannot be refused.
- (void)testSignOutWorksWithoutTheRevokedSessionsTable {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  [self withIsolatedSchema:@"auth_no_revoked" block:^(NSString *schemaDSN) {
    NSError *error = nil;
    NSArray *noParameters = @[];
    XCTAssertTrue([self.database executeCommand:@"DROP TABLE auth_revoked_sessions" parameters:noParameters error:&error] >= 0,
                  @"%@", error);
    NSString *email = [self uniqueEmail:@"norevoked"];
    ALNTestClient *client = [self clientWithDSN:schemaDSN bootstrapAdmins:@[]];
    NSString *subject = [self registerUser:client email:email];
    NSString *saved = [self cookieHeader:client];
    ALNTestClient *otherDevice = [self signedInClientForApplication:client.application
                                                              email:email
                                                           password:@"role-refresh-password"];

    ALNResponse *logout = [client post:@"/auth/api/logout" JSON:@{}];
    XCTAssertEqual((NSInteger)200, logout.statusCode, @"%@", [logout bodyText]);
    XCTAssertEqualObjects(@NO, [self sessionState:client][@"authenticated"]);
    XCTAssertEqualObjects(@YES, [self sessionState:otherDevice][@"authenticated"]);
    XCTAssertEqualObjects(@YES, [self replayedSessionState:saved application:client.application][@"authenticated"]);

    // Ending sessions by stamp still works.
    ALNResponse *logoutAll = [otherDevice post:@"/auth/api/logout/all" JSON:@{}];
    XCTAssertEqual((NSInteger)200, logoutAll.statusCode, @"%@", [logoutAll bodyText]);
    XCTAssertEqualObjects(@NO, [self replayedSessionState:saved application:client.application][@"authenticated"]);
    XCTAssertEqualObjects(@"1", [self scalar:@"SELECT session_stamp::text FROM auth_users WHERE subject = $1"
                                  parameters:@[ subject ]]);
  }];
}

#pragma mark - Search

- (void)testSearchGuardsAndRoleGatedResourcesFollowCurrentRoles {
  NSString *dsn = [self pgTestDSN];
  XCTSkipUnless([dsn length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  XCTAssertTrue([self applyAuthMigrationsWithDSN:dsn]);
  NSString *token = [[[[NSUUID UUID] UUIDString] lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *email = [NSString stringWithFormat:@"search-roles-%@@example.test", token];
  ALNTestClient *client = [self clientWithDSN:dsn bootstrapAdmins:@[ email ] authConfig:nil search:YES];
  NSString *subject = [self registerAndStepUp:client email:email];

  NSDictionary *metadata = [[ALNSearchModuleRuntime sharedRuntime] resourceMetadataForIdentifier:@"users"];
  XCTAssertEqualObjects(@"role_gated", metadata[@"queryPolicy"]);
  XCTAssertEqualObjects(@[ @"admin" ], metadata[@"queryRoles"]);

  ALNResponse *reindex = [client post:@"/search/api/resources/users/reindex" JSON:@{}];
  XCTAssertEqual((NSInteger)200, reindex.statusCode, @"%@", [reindex bodyText]);
  ALNResponse *worker = [client post:@"/jobs/api/run-worker" JSON:@{}];
  XCTAssertEqual((NSInteger)200, worker.statusCode, @"%@", [worker bodyText]);

  NSDictionary *query = @{ @"q" : token };
  NSDictionary *accept = @{ @"accept" : @"application/json" };
  ALNResponse *scoped = [client get:@"/search/api/resources/users/query" query:query headers:accept];
  XCTAssertEqual((NSInteger)200, scoped.statusCode, @"%@", [scoped bodyText]);
  XCTAssertTrue([[scoped bodyText] containsString:email], @"%@", [scoped bodyText]);
  ALNResponse *drilldown = [client get:@"/search/api/resources/users" query:nil headers:accept];
  XCTAssertEqual((NSInteger)200, drilldown.statusCode, @"%@", [drilldown bodyText]);
  ALNResponse *resources = [client get:@"/search/api/resources" query:nil headers:accept];
  XCTAssertTrue([[resources bodyText] containsString:@"\"users\""], @"%@", [resources bodyText]);

  // Revoked in the database; the session keeps its cookie and stamp.
  [self execute:@"UPDATE auth_users SET roles_json = '[\"user\"]' WHERE subject = $1 RETURNING id"
     parameters:@[ subject ]];
  XCTAssertEqualObjects(@YES, [self sessionState:client][@"authenticated"]);

  drilldown = [client get:@"/search/api/resources/users" query:nil headers:accept];
  XCTAssertEqual((NSInteger)403, drilldown.statusCode, @"%@", [drilldown bodyText]);
  ALNResponse *reindexAll = [client post:@"/search/api/reindex" JSON:@{}];
  XCTAssertEqual((NSInteger)403, reindexAll.statusCode, @"%@", [reindexAll bodyText]);
  ALNResponse *reindexHTML = [client post:@"/search/reindex" form:@{}];
  XCTAssertEqual((NSInteger)403, reindexHTML.statusCode, @"%@", [reindexHTML bodyText]);

  scoped = [client get:@"/search/api/resources/users/query" query:query headers:accept];
  XCTAssertEqual((NSInteger)403, scoped.statusCode, @"%@", [scoped bodyText]);
  XCTAssertFalse([[scoped bodyText] containsString:email]);
  ALNResponse *unscoped = [client get:@"/search/api/query" query:query headers:accept];
  XCTAssertFalse([[unscoped bodyText] containsString:email], @"%@", [unscoped bodyText]);
  resources = [client get:@"/search/api/resources" query:nil headers:accept];
  XCTAssertEqual((NSInteger)200, resources.statusCode, @"%@", [resources bodyText]);
  XCTAssertFalse([[resources bodyText] containsString:@"\"users\""], @"%@", [resources bodyText]);

  // Granted again: applies without signing in.
  [self execute:@"UPDATE auth_users SET roles_json = '[\"user\",\"admin\"]' WHERE subject = $1 RETURNING id"
     parameters:@[ subject ]];
  drilldown = [client get:@"/search/api/resources/users" query:nil headers:accept];
  XCTAssertEqual((NSInteger)200, drilldown.statusCode, @"%@", [drilldown bodyText]);
}

@end
