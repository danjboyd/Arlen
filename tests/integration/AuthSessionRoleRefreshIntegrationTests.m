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
#import "ALNTOTP.h"
#import "ALNTestClient.h"

// Session roles follow the auth_users row on every request: module API guards
// (admin-ui, jobs, ops) see the current roles, not the ones stored in the signed
// session cookie at sign-in. Runs in-process against ARLEN_PG_TEST_DSN.
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
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{ @"enabled" : @YES, @"secret" : @"auth-role-refresh-session-secret-0123456789abcdef" },
    @"csrf" : @{ @"enabled" : @YES },
    @"database" : @{ @"connectionString" : dsn },
    @"authModule" : @{ @"bootstrapAdminEmails" : emails ?: @[] },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
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
  ALNResponse *registered = [client post:@"/auth/api/register"
                                    JSON:@{ @"email" : email, @"display_name" : @"Roles", @"password" : @"role-refresh-password" }];
  XCTAssertEqual((NSInteger)200, registered.statusCode, @"%@", [registered bodyText]);
  NSString *subject = [registered JSONObject][@"subject"];
  XCTAssertTrue([subject length] > 0);

  ALNResponse *enrollment = [client get:@"/auth/api/mfa/totp"];
  XCTAssertEqual((NSInteger)200, enrollment.statusCode, @"%@", [enrollment bodyText]);
  NSString *secret = [self scalar:@"SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
                                   "WHERE u.subject = $1 ORDER BY m.id DESC LIMIT 1"
                       parameters:@[ subject ?: @"" ]];
  XCTAssertTrue([secret length] > 0);
  NSString *code = [ALNTOTP codeForSecret:secret ?: @"" atDate:[NSDate date] error:NULL];
  ALNResponse *verified = [client post:@"/auth/api/mfa/totp/verify" JSON:@{ @"code" : code ?: @"" }];
  XCTAssertEqual((NSInteger)200, verified.statusCode, @"%@", [verified bodyText]);
  return subject ?: @"";
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
    NSString *separator = [dsn containsString:@"?"] ? @"&" : @"?";
    NSString *schemaDSN = [NSString stringWithFormat:@"%@%@options=-csearch_path%%3D%@", dsn, separator, schema];
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

    // A deleted user is still signed out.
    [self execute:@"DELETE FROM auth_users WHERE subject = $1 RETURNING id" parameters:@[ targetSubject ]];
    XCTAssertEqualObjects(@NO, [self sessionState:targetClient][@"authenticated"]);
  } @finally {
    self.database = nil;
    [admin executeCommand:[NSString stringWithFormat:@"DROP SCHEMA IF EXISTS %@ CASCADE", schema] parameters:noParameters error:NULL];
  }
}

@end
