#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

// GitHub issue 90: /readyz reports and (by default in production) fails on
// pending schema migrations.
@interface ReadinessMigrationTests : XCTestCase
@property(nonatomic, copy) NSString *appRoot;
@end

@implementation ReadinessMigrationTests

- (void)setUp {
  [super setUp];
  self.appRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                             [@"arlen-readiness-" stringByAppendingString:[NSUUID UUID].UUIDString]];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:[self.appRoot stringByAppendingPathComponent:@"db/migrations"]
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:NULL]);
}

- (void)tearDown {
  [[NSFileManager defaultManager] removeItemAtPath:self.appRoot error:NULL];
  [super tearDown];
}

- (void)writeMigration:(NSString *)name into:(NSString *)directory {
  NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingString:@".sql"]];
  XCTAssertTrue([@"SELECT 1;\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

- (ALNApplication *)appWithEnvironment:(NSString *)environment extra:(NSDictionary *)extra {
  NSMutableDictionary *config = [@{ @"environment" : environment, @"logLevel" : @"error", @"appRoot" : self.appRoot } mutableCopy];
  [config addEntriesFromDictionary:extra ?: @{}];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  NSError *error = nil;
  XCTAssertTrue([app startWithError:&error], @"%@", error);
  return app;
}

- (ALNResponse *)readyz:(ALNApplication *)app {
  return [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"GET" path:@"/readyz" queryString:@""
                                                        headers:@{ @"accept" : @"application/json" }
                                                           body:[NSData data]]];
}

- (NSDictionary *)migrationCheck:(ALNResponse *)response {
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:NULL];
  return payload[@"checks"][@"schema_migrations"];
}

- (void)testProductionWithoutADatabaseIsReadyAndDevelopmentDoesNotCheck {
  [self writeMigration:@"001_init" into:[self.appRoot stringByAppendingPathComponent:@"db/migrations"]];
  ALNResponse *production = [self readyz:[self appWithEnvironment:@"production" extra:nil]];
  XCTAssertEqual(200, production.statusCode);
  NSDictionary *check = [self migrationCheck:production];
  XCTAssertEqualObjects(@YES, check[@"required_for_readyz"]);
  XCTAssertEqualObjects(@"no_database_configured", check[@"skipped"]);

  ALNResponse *development = [self readyz:[self appWithEnvironment:@"development" extra:nil]];
  XCTAssertEqual(200, development.statusCode);
  XCTAssertEqualObjects(@NO, [self migrationCheck:development][@"checked"]);
}

- (void)testUnreadableDatabaseFailsReadinessWithoutCrashing {
  [self writeMigration:@"001_init" into:[self.appRoot stringByAppendingPathComponent:@"db/migrations"]];
  ALNApplication *app = [self appWithEnvironment:@"development" extra:@{
    @"observability" : @{ @"readinessRequiresMigrations" : @YES },
    @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
  }];
  ALNResponse *response = [self readyz:app];
  XCTAssertEqual(503, response.statusCode);
  NSDictionary *check = [self migrationCheck:response];
  XCTAssertEqualObjects(@NO, check[@"ok"]);
  XCTAssertTrue([check[@"error"] length] > 0, @"%@", check);
  // Liveness and health are unaffected.
  XCTAssertEqual(200, [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"GET" path:@"/healthz" queryString:@""
                                                                       headers:@{} body:[NSData data]]].statusCode);
}

- (void)testPendingMigrationsFailReadinessUntilApplied {
  const char *dsnValue = getenv("ARLEN_PG_TEST_DSN");
  if (dsnValue == NULL || dsnValue[0] == '\0') {
    return;  // Needs PostgreSQL; CI sets ARLEN_PG_TEST_DSN.
  }
  NSString *dsn = [NSString stringWithUTF8String:dsnValue];
  NSString *migrations = [self.appRoot stringByAppendingPathComponent:@"db/migrations"];
  NSString *prefix = [NSString stringWithFormat:@"9%010u", arc4random_uniform(1000000000)];
  NSString *first = [prefix stringByAppendingString:@"1_first"];
  NSString *second = [prefix stringByAppendingString:@"2_second"];
  NSString *firstOnly = [self.appRoot stringByAppendingPathComponent:@"first-only"];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:firstOnly withIntermediateDirectories:YES attributes:nil error:NULL]);
  [self writeMigration:first into:firstOnly];
  [self writeMigration:first into:migrations];
  [self writeMigration:second into:migrations];

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:1 error:&error];
  XCTAssertNotNil(database, @"%@", error);
  @try {
    XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:firstOnly database:database dryRun:NO appliedFiles:NULL error:&error], @"%@", error);
    ALNApplication *app = [self appWithEnvironment:@"production" extra:@{
      @"database" : @{ @"connectionString" : dsn },
      @"observability" : @{ @"readinessMigrationRecheckSeconds" : @0 },
    }];
    ALNResponse *pending = [self readyz:app];
    XCTAssertEqual(503, pending.statusCode);
    NSDictionary *check = [self migrationCheck:pending];
    XCTAssertEqualObjects(@[ [ALNMigrationRunner versionForMigrationFile:second] ], check[@"pending"]);

    XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrations database:database dryRun:NO appliedFiles:NULL error:&error], @"%@", error);
    ALNResponse *ready = [self readyz:app];
    XCTAssertEqual(200, ready.statusCode);
    XCTAssertEqualObjects(@[], [self migrationCheck:ready][@"pending"]);
  } @finally {
    NSString *like = [prefix stringByAppendingString:@"%"];
    (void)[database executeCommand:@"DELETE FROM arlen_schema_migrations WHERE version LIKE $1" parameters:@[ like ] error:NULL];
  }
}

@end
