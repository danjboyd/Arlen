#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"
#import "ALNTOTP.h"
#import "ALNTestClient.h"

@interface ALNAuthModuleRuntime (AuthMFALimitsTesting)
- (NSInteger)prunePasswordAttempts;
- (NSUInteger)dummyPasswordVerificationCount;
@end

// TOTP replay protection, the per-account MFA failure counter, and password
// sign-in delays (auth module migration 004). Needs ARLEN_PG_TEST_DSN.
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
  return [self applicationWithAttemptLimits:attemptLimits csrfEnabled:YES];
}

- (ALNApplication *)applicationWithAttemptLimits:(NSDictionary *)attemptLimits csrfEnabled:(BOOL)csrfEnabled {
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
      @"enabled" : @(csrfEnabled),
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

#pragma mark - Password sign-in delays

- (ALNResponse *)loginEmail:(NSString *)email
                   password:(NSString *)password
                fromAddress:(NSString *)address
                        app:(ALNApplication *)app {
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"email" : email, @"password" : password }
                                                 options:0
                                                   error:NULL];
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"POST"
                                                      path:@"/auth/api/login"
                                               queryString:@""
                                                   headers:@{
                                                     @"content-type" : @"application/json",
                                                     @"accept" : @"application/json",
                                                     // Ignored: the limiter uses the server's effective address.
                                                     @"x-forwarded-for" : @"203.0.113.250",
                                                   }
                                                      body:body];
  request.remoteAddress = @"10.255.0.1";
  request.effectiveRemoteAddress = address;
  return [app dispatchRequest:request];
}

- (NSString *)passwordKeyForEmail:(NSString *)email {
  NSData *digest = ALNSHA256([[email lowercaseString] dataUsingEncoding:NSUTF8StringEncoding]);
  return ALNLowercaseHexStringFromData(digest);
}

- (NSDictionary *)passwordRowForEmail:(NSString *)email address:(NSString *)address {
  NSArray *parameters = @[ [self passwordKeyForEmail:email], address ];
  NSArray *rows = [[self database] executeQuery:@"SELECT failure_count::text AS failure_count, "
                                                "COALESCE(CEIL(EXTRACT(EPOCH FROM (delayed_until - NOW()))), 0)::bigint::text "
                                                "AS delay_remaining "
                                                "FROM auth_password_attempts WHERE key_hash = $1 AND client_ip = $2"
                                     parameters:parameters
                                          error:NULL];
  return [rows firstObject] ?: @{};
}

- (void)expirePasswordDelayForEmail:(NSString *)email address:(NSString *)address {
  NSArray *parameters = @[ [self passwordKeyForEmail:email], address ];
  NSInteger updated = [[self database] executeCommand:@"UPDATE auth_password_attempts "
                                                      "SET delayed_until = NOW() - INTERVAL '1 second' "
                                                      "WHERE key_hash = $1 AND client_ip = $2"
                                           parameters:parameters
                                                error:NULL];
  XCTAssertEqual((NSInteger)1, updated);
}

- (NSString *)registeredEmailWithPassword:(NSString *)password app:(ALNApplication *)app {
  NSString *email = [self uniqueEmail];
  [self registerEmail:email password:password client:[self clientForApplication:app]];
  return email;
}

- (void)testPasswordDelayIsPerAddressDoublesAndResetsOnlyItsPair {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"password" : @{ @"maxFailures" : @3, @"delaySeconds" : @40 },
  }
                                               csrfEnabled:NO];
  NSString *password = @"mfa-limits-password-123";
  NSString *email = [self registeredEmailWithPassword:password app:app];
  NSString *first = @"198.51.100.10";
  NSString *second = @"198.51.100.20";

  for (NSUInteger attempt = 0; attempt < 3; attempt++) {
    XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password" fromAddress:first app:app].statusCode);
  }
  ALNResponse *delayed = [self loginEmail:email password:password fromAddress:first app:app];
  XCTAssertEqual((NSInteger)429, delayed.statusCode, @"%@", [delayed bodyText]);
  NSInteger retryAfter = [[delayed headerForName:@"Retry-After"] integerValue];
  XCTAssertTrue(retryAfter > 30 && retryAfter <= 40, @"Retry-After %ld", (long)retryAfter);
  XCTAssertTrue([[delayed bodyText] containsString:@"Too many failed attempts"], @"%@", [delayed bodyText]);
  // The forwarding header was not used as the client address.
  XCTAssertEqual((NSUInteger)0, [[self passwordRowForEmail:email address:@"203.0.113.250"] count]);

  // Another address is not held back by the first one's failures.
  XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password" fromAddress:second app:app].statusCode);
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password fromAddress:second app:app].statusCode);
  XCTAssertEqualObjects(@"0", [self passwordRowForEmail:email address:second][@"failure_count"]);
  XCTAssertEqualObjects(@"3", [self passwordRowForEmail:email address:first][@"failure_count"]);
  XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password" fromAddress:second app:app].statusCode);

  // After the wait, the next failure doubles it.
  [self expirePasswordDelayForEmail:email address:first];
  XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password" fromAddress:first app:app].statusCode);
  NSDictionary *row = [self passwordRowForEmail:email address:first];
  XCTAssertEqualObjects(@"4", row[@"failure_count"]);
  NSInteger remaining = [row[@"delay_remaining"] integerValue];
  XCTAssertTrue(remaining > 70 && remaining <= 80, @"delay %ld", (long)remaining);

  // A success clears only its own pair.
  [self expirePasswordDelayForEmail:email address:first];
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password fromAddress:first app:app].statusCode);
  XCTAssertEqualObjects(@"0", [self passwordRowForEmail:email address:first][@"failure_count"]);
  XCTAssertEqualObjects(@"1", [self passwordRowForEmail:email address:second][@"failure_count"]);
}

- (void)testPasswordAccountCeilingAppliesAcrossAddresses {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"password" : @{ @"maxFailures" : @10, @"accountMaxFailures" : @4, @"accountDelaySeconds" : @50 },
  }
                                               csrfEnabled:NO];
  NSString *password = @"mfa-limits-password-123";
  NSString *email = [self registeredEmailWithPassword:password app:app];

  for (NSUInteger index = 1; index <= 4; index++) {
    NSString *address = [NSString stringWithFormat:@"192.0.2.%lu", (unsigned long)index];
    XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password" fromAddress:address app:app].statusCode);
  }
  // Up to the ceiling, a new address still signs in.
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password fromAddress:@"192.0.2.90" app:app].statusCode);
  XCTAssertEqualObjects(@"4", [self passwordRowForEmail:email address:@"*"][@"failure_count"]);

  XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password" fromAddress:@"192.0.2.5" app:app].statusCode);
  ALNResponse *delayed = [self loginEmail:email password:password fromAddress:@"192.0.2.91" app:app];
  XCTAssertEqual((NSInteger)429, delayed.statusCode, @"%@", [delayed bodyText]);
  NSInteger retryAfter = [[delayed headerForName:@"Retry-After"] integerValue];
  XCTAssertTrue(retryAfter > 40 && retryAfter <= 50, @"Retry-After %ld", (long)retryAfter);
  // No single address reached its own limit.
  XCTAssertEqualObjects(@"0", [self passwordRowForEmail:email address:@"192.0.2.5"][@"delay_remaining"]);

  [self expirePasswordDelayForEmail:email address:@"*"];
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password fromAddress:@"192.0.2.91" app:app].statusCode);
}

- (void)testUnknownEmailGetsTheSameResponsesAndCountersAsAKnownOne {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"password" : @{ @"maxFailures" : @2, @"delaySeconds" : @30 },
  }
                                               csrfEnabled:NO];
  NSString *known = [self registeredEmailWithPassword:@"mfa-limits-password-123" app:app];
  NSString *unknown = [self uniqueEmail];
  NSString *address = @"198.51.100.77";
  NSUInteger dummyBefore = [[ALNAuthModuleRuntime sharedRuntime] dummyPasswordVerificationCount];

  for (NSUInteger attempt = 0; attempt < 3; attempt++) {
    ALNResponse *knownResponse = [self loginEmail:known password:@"wrong-password" fromAddress:address app:app];
    ALNResponse *unknownResponse = [self loginEmail:unknown password:@"wrong-password" fromAddress:address app:app];
    NSInteger expected = (attempt < 2) ? 401 : 429;
    XCTAssertEqual(expected, knownResponse.statusCode);
    XCTAssertEqual(expected, unknownResponse.statusCode);
    // Same body; a 429's "Try again in N seconds" may differ by a second.
    NSString *(^withoutDigits)(NSString *) = ^NSString *(NSString *text) {
      return [[text componentsSeparatedByCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]]
          componentsJoinedByString:@""];
    };
    if (expected == 401) {
      XCTAssertEqualObjects([knownResponse bodyText], [unknownResponse bodyText]);
    } else {
      XCTAssertEqualObjects(withoutDigits([knownResponse bodyText]), withoutDigits([unknownResponse bodyText]));
    }
    XCTAssertEqualObjects([knownResponse headerForName:@"Retry-After"] != nil ? @YES : @NO,
                          [unknownResponse headerForName:@"Retry-After"] != nil ? @YES : @NO);
  }
  for (NSString *rowAddress in @[ address, @"*" ]) {
    NSDictionary *knownRow = [self passwordRowForEmail:known address:rowAddress];
    NSDictionary *unknownRow = [self passwordRowForEmail:unknown address:rowAddress];
    XCTAssertEqualObjects(@"2", knownRow[@"failure_count"]);
    XCTAssertEqualObjects(knownRow[@"failure_count"], unknownRow[@"failure_count"]);
    XCTAssertTrue(ABS([knownRow[@"delay_remaining"] integerValue] - [unknownRow[@"delay_remaining"] integerValue]) <= 1);
  }
  // The unknown email still spends a (dummy) Argon2 verification per counted attempt.
  XCTAssertEqual(dummyBefore + 2U, [[ALNAuthModuleRuntime sharedRuntime] dummyPasswordVerificationCount]);
}

- (void)testPasswordAttemptPruningDropsExpiredRowsAndCapsGrowth {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithAttemptLimits:@{
    @"password" : @{ @"maxFailures" : @5, @"maxTrackedEntries" : @4 },
  }
                                               csrfEnabled:NO];
  ALNPg *database = [self database];
  NSString *suffix = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSString *staleKey = [@"stale-" stringByAppendingString:suffix];
  NSString *delayedKey = [@"delayed-" stringByAppendingString:suffix];
  XCTAssertEqual((NSInteger)1,
                 [database executeCommand:@"INSERT INTO auth_password_attempts "
                                          "(key_hash, client_ip, failure_count, updated_at) "
                                          "VALUES ($1, '192.0.2.1', 1, NOW() - INTERVAL '3 days')"
                               parameters:@[ staleKey ]
                                    error:NULL]);
  XCTAssertEqual((NSInteger)1,
                 [database executeCommand:@"INSERT INTO auth_password_attempts "
                                          "(key_hash, client_ip, failure_count, delayed_until, updated_at) "
                                          "VALUES ($1, '192.0.2.1', 9, NOW() + INTERVAL '1 hour', NOW() - INTERVAL '3 days')"
                               parameters:@[ delayedKey ]
                                    error:NULL]);

  for (NSUInteger index = 0; index < 4; index++) {
    XCTAssertEqual((NSInteger)401,
                   [self loginEmail:[self uniqueEmail] password:@"wrong-password" fromAddress:@"192.0.2.33" app:app]
                       .statusCode);
  }
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] prunePasswordAttempts] > 0);

  NSArray *countRows = [database executeQuery:@"SELECT COUNT(*)::text AS total FROM auth_password_attempts"
                                   parameters:@[]
                                        error:NULL];
  XCTAssertTrue([[countRows firstObject][@"total"] integerValue] <= 4, @"%@", countRows);
  NSString *existsSQL = @"SELECT COUNT(*)::text AS total FROM auth_password_attempts WHERE key_hash = $1";
  XCTAssertEqualObjects(@"0", [[database executeQuery:existsSQL parameters:@[ staleKey ] error:NULL] firstObject][@"total"]);
  // Rows that are still delaying sign-in are kept.
  XCTAssertEqualObjects(@"1", [[database executeQuery:existsSQL parameters:@[ delayedKey ] error:NULL] firstObject][@"total"]);
  XCTAssertTrue([database executeCommand:@"DELETE FROM auth_password_attempts WHERE key_hash = $1"
                              parameters:@[ delayedKey ]
                                   error:NULL] >= 0);
}

- (void)testVerificationKeepsWorkingWhenMigration004IsMissing {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  [self applyAuthMigrations];
  ALNPg *database = [self database];
  XCTAssertTrue([database executeCommand:@"DROP TABLE IF EXISTS auth_attempt_limits" parameters:@[] error:NULL] >= 0);
  XCTAssertTrue([database executeCommand:@"DROP TABLE IF EXISTS auth_password_attempts" parameters:@[] error:NULL] >= 0);
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
  for (NSUInteger attempt = 0; attempt < 7; attempt++) {
    XCTAssertEqual((NSInteger)401, [self loginEmail:email password:@"wrong-password-1" client:client].statusCode);
  }
  XCTAssertEqual((NSInteger)200, [self loginEmail:email password:password client:client].statusCode);
}

@end
