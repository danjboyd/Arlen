#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNResponse.h"
#import "ALNTOTP.h"
#import "ALNTestClient.h"

// TOTP replay protection and the per-account MFA/password failure counters
// (auth module migration 004). Needs ARLEN_PG_TEST_DSN.
@interface AuthMFALimitsTests : XCTestCase
@end

@implementation AuthMFALimitsTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (ALNPg *)database {
  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:1 error:&error];
  XCTAssertNotNil(database, @"%@", error);
  return database;
}

- (void)applyAuthMigrations {
  NSString *migrationsPath = [[self repoRoot] stringByAppendingPathComponent:@"modules/auth/Migrations"];
  NSError *error = nil;
  XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrationsPath
                                                 database:[self database]
                                                   dryRun:NO
                                             appliedFiles:NULL
                                                    error:&error],
                @"%@", error);
}

// Re-runs migration 004's statements (they are idempotent), for tests that drop them.
- (void)reapplyMigration004 {
  NSString *path = [[self repoRoot] stringByAppendingPathComponent:@"modules/auth/Migrations/004_auth_totp_limits.sql"];
  NSString *sql = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertTrue([sql length] > 0);
  NSMutableArray *lines = [NSMutableArray array];
  for (NSString *line in [sql componentsSeparatedByString:@"\n"]) {
    if (![line hasPrefix:@"--"]) {
      [lines addObject:line];
    }
  }
  ALNPg *database = [self database];
  for (NSString *statement in [[lines componentsJoinedByString:@"\n"] componentsSeparatedByString:@";"]) {
    NSString *trimmed = [statement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] > 0) {
      NSError *error = nil;
      XCTAssertTrue([database executeCommand:trimmed parameters:@[] error:&error] >= 0, @"%@", error);
    }
  }
}

- (void)setUp {
  [super setUp];
  NSError *error = nil;
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:&error]);
}

- (ALNApplication *)applicationWithAttemptLimits:(NSDictionary *)attemptLimits {
  [self applyAuthMigrations];
  NSMutableDictionary *authModule = [NSMutableDictionary dictionary];
  if (attemptLimits != nil) {
    authModule[@"attemptLimits"] = attemptLimits;
  }
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @YES,
      @"secret" : @"auth-mfa-limits-session-secret-0123456789abcdef",
    },
    @"csrf" : @{
      @"enabled" : @YES,
      @"allowQueryParamFallback" : @YES,
    },
    @"database" : @{
      @"connectionString" : [self pgTestDSN] ?: @"",
    },
    @"authModule" : authModule,
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  return app;
}

- (ALNTestClient *)clientForApplication:(ALNApplication *)app {
  NSError *error = nil;
  ALNTestClient *client = [[ALNTestClient alloc] initWithApplication:app error:&error];
  XCTAssertNotNil(client, @"%@", error);
  return client;
}

- (NSString *)uniqueEmail {
  return [NSString stringWithFormat:@"mfa-limits-%@@example.test", [[[NSUUID UUID] UUIDString] lowercaseString]];
}

- (NSString *)userIDForEmail:(NSString *)email {
  NSArray *rows = [[self database] executeQuery:@"SELECT id::text AS id FROM auth_users WHERE lower(email) = $1"
                                     parameters:@[ [email lowercaseString] ]
                                          error:NULL];
  return [rows firstObject][@"id"];
}

- (NSDictionary *)attemptRowForEmail:(NSString *)email scope:(NSString *)scope {
  NSArray *rows = [[self database] executeQuery:@"SELECT failure_count::text AS failure_count, "
                                                "COALESCE(CEIL(EXTRACT(EPOCH FROM (locked_until - NOW()))), 0)::bigint::text "
                                                "AS lock_remaining "
                                                "FROM auth_attempt_limits WHERE user_id = $1::bigint AND scope = $2"
                                     parameters:@[ [self userIDForEmail:email] ?: @"0", scope ]
                                          error:NULL];
  return [rows firstObject] ?: @{};
}

- (void)expireLockForEmail:(NSString *)email scope:(NSString *)scope {
  NSArray *parameters = @[ [self userIDForEmail:email] ?: @"0", scope ];
  NSInteger updated = [[self database] executeCommand:@"UPDATE auth_attempt_limits SET locked_until = NOW() - INTERVAL '1 second' "
                                                      "WHERE user_id = $1::bigint AND scope = $2"
                                           parameters:parameters
                                                error:NULL];
  XCTAssertEqual((NSInteger)1, updated);
}

- (NSString *)codeForSecret:(NSString *)secret stepOffset:(NSInteger)offset {
  NSDate *date = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)(30 * offset)];
  NSString *code = [ALNTOTP codeForSecret:secret atDate:date error:NULL];
  XCTAssertEqual((NSUInteger)6, [code length]);
  return code;
}

- (void)registerEmail:(NSString *)email password:(NSString *)password client:(ALNTestClient *)client {
  ALNResponse *response = [client post:@"/auth/api/register"
                                  JSON:@{ @"email" : email, @"display_name" : @"MFA Limits", @"password" : password }];
  XCTAssertEqual((NSInteger)200, response.statusCode, @"%@", [response bodyText]);
}

- (ALNResponse *)loginEmail:(NSString *)email password:(NSString *)password client:(ALNTestClient *)client {
  return [client post:@"/auth/api/login" JSON:@{ @"email" : email, @"password" : password }];
}

- (ALNResponse *)verifyCode:(NSString *)code client:(ALNTestClient *)client {
  return [client post:@"/auth/api/mfa/totp/verify" JSON:@{ @"code" : code ?: @"" }];
}

- (NSUInteger)aalForResponse:(ALNResponse *)response {
  NSDictionary *json = [[response JSONObject] isKindOfClass:[NSDictionary class]] ? [response JSONObject] : @{};
  return (NSUInteger)[json[@"aal"] integerValue];
}

// Registers a user, enrolls TOTP with the previous step's code, and returns the
// secret. The recovery codes from enrollment are returned through `recoveryCodes`.
- (NSString *)enrolledUserWithEmail:(NSString *)email
                           password:(NSString *)password
                             client:(ALNTestClient *)client
                      recoveryCodes:(NSArray **)recoveryCodes {
  [self registerEmail:email password:password client:client];
  ALNResponse *provisioning = [client get:@"/auth/api/mfa/totp"];
  XCTAssertEqual((NSInteger)200, provisioning.statusCode, @"%@", [provisioning bodyText]);
  NSDictionary *json = [provisioning JSONObject];
  NSString *secret = json[@"mfa"][@"provisioning"][@"secret"];
  XCTAssertTrue([secret length] > 0, @"%@", [provisioning bodyText]);
  ALNResponse *enrolled = [self verifyCode:[self codeForSecret:secret stepOffset:-1] client:client];
  XCTAssertEqual((NSInteger)200, enrolled.statusCode, @"%@", [enrolled bodyText]);
  if (recoveryCodes != NULL) {
    *recoveryCodes = [enrolled JSONObject][@"mfa"][@"recovery_codes"];
  }
  return secret;
}

- (void)testTOTPCodeCannotBeReplayedInAnotherSession {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:nil];
  NSString *email = [self uniqueEmail];
  NSString *password = @"mfa-limits-password-123";
  ALNTestClient *first = [self clientForApplication:app];
  NSString *secret = [self enrolledUserWithEmail:email password:password client:first recoveryCodes:NULL];

  NSString *code = [self codeForSecret:secret stepOffset:0];
  ALNResponse *stepUp = [self verifyCode:code client:first];
  XCTAssertEqual((NSInteger)200, stepUp.statusCode, @"%@", [stepUp bodyText]);
  XCTAssertEqual((NSUInteger)2, [self aalForResponse:stepUp]);

  ALNTestClient *second = [self clientForApplication:app];
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password client:second].statusCode);
  ALNResponse *replayed = [self verifyCode:code client:second];
  XCTAssertEqual((NSInteger)422, replayed.statusCode, @"%@", [replayed bodyText]);
  XCTAssertTrue([[replayed bodyText] containsString:@"already used"], @"%@", [replayed bodyText]);
  NSDictionary *session = [[second get:@"/auth/api/session"] JSONObject];
  XCTAssertEqualObjects(@1, session[@"aal"]);

  // A later code in the window is still accepted.
  ALNResponse *nextCode = [self verifyCode:[self codeForSecret:secret stepOffset:1] client:second];
  XCTAssertEqual((NSInteger)200, nextCode.statusCode, @"%@", [nextCode bodyText]);
  XCTAssertEqual((NSUInteger)2, [self aalForResponse:nextCode]);
}

- (void)testTOTPLocksAfterRepeatedFailuresAndResetsOnSuccess {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"mfa" : @{ @"maxFailures" : @3, @"lockoutSeconds" : @60, @"maxLockoutSeconds" : @600 },
  }];
  NSString *email = [self uniqueEmail];
  ALNTestClient *client = [self clientForApplication:app];
  NSString *secret = [self enrolledUserWithEmail:email password:@"mfa-limits-password-123" client:client recoveryCodes:NULL];
  NSString *wrongCode = [[self codeForSecret:secret stepOffset:0] isEqualToString:@"000000"] ? @"111111" : @"000000";

  // Two failures, then a success, clears the count.
  XCTAssertEqual((NSInteger)422, [self verifyCode:wrongCode client:client].statusCode);
  XCTAssertEqual((NSInteger)422, [self verifyCode:wrongCode client:client].statusCode);
  XCTAssertEqualObjects(@"2", [self attemptRowForEmail:email scope:@"mfa"][@"failure_count"]);
  XCTAssertEqual((NSInteger)200, [self verifyCode:[self codeForSecret:secret stepOffset:0] client:client].statusCode);
  XCTAssertEqualObjects(@"0", [self attemptRowForEmail:email scope:@"mfa"][@"failure_count"]);

  // The third consecutive failure locks the account; even a valid code is refused.
  for (NSUInteger attempt = 0; attempt < 3; attempt++) {
    XCTAssertEqual((NSInteger)422, [self verifyCode:wrongCode client:client].statusCode);
  }
  ALNResponse *locked = [self verifyCode:[self codeForSecret:secret stepOffset:1] client:client];
  XCTAssertEqual((NSInteger)429, locked.statusCode, @"%@", [locked bodyText]);
  NSInteger retryAfter = [[locked headerForName:@"Retry-After"] integerValue];
  XCTAssertTrue(retryAfter > 50 && retryAfter <= 60, @"Retry-After %ld", (long)retryAfter);
  XCTAssertTrue([[locked bodyText] containsString:@"Too many failed attempts"], @"%@", [locked bodyText]);

  // After the lock expires, another failure locks for twice as long.
  [self expireLockForEmail:email scope:@"mfa"];
  XCTAssertEqual((NSInteger)422, [self verifyCode:wrongCode client:client].statusCode);
  NSDictionary *row = [self attemptRowForEmail:email scope:@"mfa"];
  XCTAssertEqualObjects(@"4", row[@"failure_count"]);
  NSInteger remaining = [row[@"lock_remaining"] integerValue];
  XCTAssertTrue(remaining > 110 && remaining <= 120, @"lock %ld", (long)remaining);

  // Once unlocked, a valid code succeeds and resets the counter.
  [self expireLockForEmail:email scope:@"mfa"];
  ALNResponse *success = [self verifyCode:[self codeForSecret:secret stepOffset:1] client:client];
  XCTAssertEqual((NSInteger)200, success.statusCode, @"%@", [success bodyText]);
  XCTAssertEqualObjects(@"0", [self attemptRowForEmail:email scope:@"mfa"][@"failure_count"]);
}

- (void)testRecoveryCodesAreSingleUseAndShareTheMFAFailureLimit {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"mfa" : @{ @"maxFailures" : @3, @"lockoutSeconds" : @60 },
  }];
  NSString *email = [self uniqueEmail];
  NSString *password = @"mfa-limits-password-123";
  ALNTestClient *client = [self clientForApplication:app];
  NSArray *recoveryCodes = nil;
  (void)[self enrolledUserWithEmail:email password:password client:client recoveryCodes:&recoveryCodes];
  XCTAssertEqual((NSUInteger)6, [recoveryCodes count]);

  ALNResponse *recovered = [self verifyCode:recoveryCodes[0] client:client];
  XCTAssertEqual((NSInteger)200, recovered.statusCode, @"%@", [recovered bodyText]);
  XCTAssertEqual((NSUInteger)2, [self aalForResponse:recovered]);
  XCTAssertTrue([[recovered JSONObject][@"methods"] containsObject:@"recovery_code"]);

  ALNTestClient *second = [self clientForApplication:app];
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password client:second].statusCode);
  ALNResponse *reused = [self verifyCode:recoveryCodes[0] client:second];
  XCTAssertEqual((NSInteger)422, reused.statusCode, @"%@", [reused bodyText]);

  // Wrong recovery codes count toward the same lockout as wrong TOTP codes.
  XCTAssertEqual((NSInteger)422, [self verifyCode:@"AAAAA-AAAAA" client:second].statusCode);
  XCTAssertEqual((NSInteger)422, [self verifyCode:@"BBBBB-BBBBB" client:second].statusCode);
  ALNResponse *locked = [self verifyCode:recoveryCodes[1] client:second];
  XCTAssertEqual((NSInteger)429, locked.statusCode, @"%@", [locked bodyText]);
  XCTAssertTrue([[locked headerForName:@"Retry-After"] integerValue] > 0);

  [self expireLockForEmail:email scope:@"mfa"];
  ALNResponse *unlocked = [self verifyCode:recoveryCodes[1] client:second];
  XCTAssertEqual((NSInteger)200, unlocked.statusCode, @"%@", [unlocked bodyText]);
}

- (void)testPasswordLoginLocksAfterRepeatedFailuresAndResetsOnSuccess {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"password" : @{ @"maxFailures" : @3, @"lockoutSeconds" : @45 },
  }];
  NSString *email = [self uniqueEmail];
  NSString *password = @"mfa-limits-password-123";
  ALNTestClient *client = [self clientForApplication:app];
  [self registerEmail:email password:password client:client];

  ALNTestClient *other = [self clientForApplication:app];
  XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password-1" client:other].statusCode);
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password client:other].statusCode);
  XCTAssertEqualObjects(@"0", [self attemptRowForEmail:email scope:@"password"][@"failure_count"]);

  for (NSUInteger attempt = 0; attempt < 3; attempt++) {
    XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password-1" client:other].statusCode);
  }
  ALNResponse *locked = [self loginEmail:email password:password client:other];
  XCTAssertEqual((NSInteger)429, locked.statusCode, @"%@", [locked bodyText]);
  NSInteger retryAfter = [[locked headerForName:@"Retry-After"] integerValue];
  XCTAssertTrue(retryAfter > 35 && retryAfter <= 45, @"Retry-After %ld", (long)retryAfter);

  [self expireLockForEmail:email scope:@"password"];
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password client:other].statusCode);
  XCTAssertEqualObjects(@"0", [self attemptRowForEmail:email scope:@"password"][@"failure_count"]);
}

- (void)testVerificationKeepsWorkingWhenMigration004IsMissing {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  [self applyAuthMigrations];
  ALNPg *database = [self database];
  XCTAssertTrue([database executeCommand:@"DROP TABLE IF EXISTS auth_attempt_limits" parameters:@[] error:NULL] >= 0);
  XCTAssertTrue([database executeCommand:@"ALTER TABLE auth_mfa_enrollments DROP COLUMN IF EXISTS last_used_step"
                              parameters:@[]
                                   error:NULL] >= 0);
  [self addTeardownBlock:^{
    [self reapplyMigration004];
  }];

  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{ @"enabled" : @YES, @"secret" : @"auth-mfa-limits-session-secret-0123456789abcdef" },
    @"csrf" : @{ @"enabled" : @YES },
    @"database" : @{ @"connectionString" : [self pgTestDSN] },
    @"authModule" : @{ @"attemptLimits" : @{ @"mfa" : @{ @"maxFailures" : @2 } } },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);

  NSString *email = [self uniqueEmail];
  NSString *password = @"mfa-limits-password-123";
  ALNTestClient *client = [self clientForApplication:app];
  NSString *secret = [self enrolledUserWithEmail:email password:password client:client recoveryCodes:NULL];
  NSString *wrongCode = [[self codeForSecret:secret stepOffset:0] isEqualToString:@"000000"] ? @"111111" : @"000000";

  // No counter without the table: failures stay 422, never 429 or 500.
  for (NSUInteger attempt = 0; attempt < 4; attempt++) {
    XCTAssertEqual((NSInteger)422, [self verifyCode:wrongCode client:client].statusCode);
  }
  NSString *code = [self codeForSecret:secret stepOffset:0];
  ALNResponse *stepUp = [self verifyCode:code client:client];
  XCTAssertEqual((NSInteger)200, stepUp.statusCode, @"%@", [stepUp bodyText]);
  XCTAssertEqual((NSUInteger)2, [self aalForResponse:stepUp]);
  XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password-1" client:client].statusCode);
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password client:client].statusCode);
}

@end
