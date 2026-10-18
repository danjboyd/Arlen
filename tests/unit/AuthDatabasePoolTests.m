#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNTestClient.h"

// A busy or unreachable auth database answers 503 with Retry-After; it never
// turns a valid session into a 401 or signs the user out. Needs ARLEN_PG_TEST_DSN.
@interface AuthDatabasePoolTests : XCTestCase
@end

@implementation AuthDatabasePoolTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (ALNApplication *)applicationWithPoolSize:(NSUInteger)poolSize {
  NSString *migrationsPath = [[[NSFileManager defaultManager] currentDirectoryPath]
      stringByAppendingPathComponent:@"modules/auth/Migrations"];
  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:1 error:&error];
  XCTAssertNotNil(database, @"%@", error);
  XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrationsPath
                                                 database:database
                                                   dryRun:NO
                                             appliedFiles:NULL
                                                    error:&error],
                @"%@", error);
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:&error]);
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{ @"enabled" : @YES, @"secret" : @"auth-database-pool-secret-0123456789abcdef" },
    @"csrf" : @{ @"enabled" : @YES },
    @"database" : @{ @"connectionString" : [self pgTestDSN] ?: @"" },
    @"authModule" : @{
      @"database" : @{ @"maxConnections" : @(poolSize), @"acquireTimeoutSeconds" : @0.2 },
    },
  }];
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  return app;
}

- (ALNTestClient *)signedInClientForApplication:(ALNApplication *)app
                                          email:(NSString *)email
                                       password:(NSString *)password {
  NSError *error = nil;
  ALNTestClient *client = [[ALNTestClient alloc] initWithApplication:app error:&error];
  XCTAssertNotNil(client, @"%@", error);
  ALNResponse *registered = [client post:@"/auth/api/register"
                                    JSON:@{ @"email" : email, @"display_name" : @"Pool", @"password" : password }];
  XCTAssertEqual((NSInteger)200, registered.statusCode, @"%@", [registered bodyText]);
  return client;
}

- (NSString *)cookieHeaderForClient:(ALNTestClient *)client {
  NSMutableArray *pairs = [NSMutableArray array];
  NSDictionary *cookies = client.cookies;
  for (NSString *name in [[cookies allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, cookies[name]]];
  }
  return [pairs componentsJoinedByString:@"; "];
}

- (ALNPg *)authPool {
  return [[ALNAuthModuleRuntime sharedRuntime] valueForKey:@"database"];
}

- (void)testPoolSizeAndAcquireTimeoutComeFromConfig {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  (void)[self applicationWithPoolSize:3];
  XCTAssertEqual((NSUInteger)3, [self authPool].maxConnections);
  XCTAssertEqualWithAccuracy(0.2, [self authPool].acquireTimeout, 0.001);
}

- (void)testExhaustedPoolAnswers503AndKeepsTheSession {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithPoolSize:2];
  NSString *email = [NSString stringWithFormat:@"pool-%@@example.test", [[[NSUUID UUID] UUIDString] lowercaseString]];
  NSString *password = @"pool-password-123";
  ALNTestClient *client = [self signedInClientForApplication:app email:email password:password];
  NSString *subject = [client session][@"_auth"][@"subject"];
  XCTAssertTrue([subject length] > 0);

  ALNPg *pool = [self authPool];
  NSError *error = nil;
  ALNPgConnection *held1 = [pool acquireConnection:&error];
  ALNPgConnection *held2 = [pool acquireConnection:&error];
  XCTAssertNotNil(held1);
  XCTAssertNotNil(held2);

  ALNResponse *busy = [client get:@"/auth/api/mfa/totp"];
  XCTAssertEqual((NSInteger)503, busy.statusCode, @"%@", [busy bodyText]);
  XCTAssertEqualObjects(@"2", [busy headerForName:@"Retry-After"]);
  XCTAssertTrue([[busy bodyText] containsString:@"temporarily unavailable"], @"%@", [busy bodyText]);
  // A second client's password sign-in is also 503, not "invalid password".
  ALNTestClient *other = [[ALNTestClient alloc] initWithApplication:app error:NULL];
  ALNResponse *login = [other post:@"/auth/api/login" JSON:@{ @"email" : email, @"password" : password }];
  XCTAssertEqual((NSInteger)503, login.statusCode, @"%@", [login bodyText]);
  XCTAssertFalse([[login bodyText] containsString:@"pool"], @"%@", [login bodyText]);

  [pool releaseConnection:held1];
  [pool releaseConnection:held2];
  // The session survived and works again once connections are free.
  XCTAssertEqualObjects(subject, [client session][@"_auth"][@"subject"]);
  XCTAssertEqual((NSInteger)200, [client get:@"/auth/api/mfa/totp"].statusCode);
}

- (void)testConcurrencyBeyondPoolSizeNeverAnswers401ForAValidSession {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self applicationWithPoolSize:2];
  NSString *email = [NSString stringWithFormat:@"pool-%@@example.test", [[[NSUUID UUID] UUIDString] lowercaseString]];
  ALNTestClient *client = [self signedInClientForApplication:app email:email password:@"pool-password-123"];
  NSString *cookie = [self cookieHeaderForClient:client];

  ALNPg *pool = [self authPool];
  ALNPgConnection *held = [pool acquireConnection:NULL];
  XCTAssertNotNil(held);
  NSMutableArray *statuses = [NSMutableArray array];
  NSLock *lock = [[NSLock alloc] init];
  dispatch_apply(8, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    (void)index;
    ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                        path:@"/auth/api/mfa/totp"
                                                 queryString:@""
                                                     headers:@{ @"accept" : @"application/json", @"cookie" : cookie }
                                                        body:[NSData data]];
    request.remoteAddress = @"127.0.0.1";
    request.effectiveRemoteAddress = @"127.0.0.1";
    ALNResponse *response = [app dispatchRequest:request];
    [lock lock];
    [statuses addObject:@(response.statusCode)];
    [lock unlock];
  });
  [pool releaseConnection:held];

  XCTAssertEqual((NSUInteger)8, [statuses count]);
  for (NSNumber *status in statuses) {
    XCTAssertTrue([status integerValue] == 200 || [status integerValue] == 503, @"statuses %@", statuses);
  }
  XCTAssertTrue([statuses containsObject:@200], @"statuses %@", statuses);
  XCTAssertEqual((NSInteger)200, [client get:@"/auth/api/mfa/totp"].statusCode);
}

@end
