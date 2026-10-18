#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPg.h"
#import "../shared/ALNTestWait.h"

// A pooled connection that the server closed while it sat idle (restart,
// failover, idle timeout; here pg_terminate_backend) is discarded and the
// statement retried once on a new connection. Needs ARLEN_PG_TEST_DSN.
@interface PgConnectionLossTests : XCTestCase
@end

@implementation PgConnectionLossTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

// Terminates every other backend of the test database and waits until they
// are gone.
- (void)terminateOtherBackends {
  NSError *error = nil;
  ALNPgConnection *admin = [[ALNPgConnection alloc] initWithConnectionString:[self pgTestDSN] error:&error];
  XCTAssertNotNil(admin, @"%@", error);
  NSArray *rows = [admin executeQuery:@"SELECT pg_terminate_backend(pid)::text AS terminated FROM pg_stat_activity "
                                      "WHERE datname = current_database() AND pid <> pg_backend_pid() "
                                      "AND backend_type = 'client backend'"
                           parameters:@[]
                                error:&error];
  XCTAssertNotNil(rows, @"%@", error);
  BOOL gone = ALNTestWaitUntil(10.0, 0.05, ^BOOL {
    NSArray *remaining = [admin executeQuery:@"SELECT COUNT(*)::text AS total FROM pg_stat_activity "
                                             "WHERE datname = current_database() AND pid <> pg_backend_pid() "
                                             "AND backend_type = 'client backend'"
                                  parameters:@[]
                                       error:NULL];
    return [[remaining firstObject][@"total"] isEqualToString:@"0"];
  });
  XCTAssertTrue(gone);
  [admin close];
}

- (ALNPg *)warmPoolWithConnections:(NSUInteger)count {
  NSError *error = nil;
  ALNPg *pool = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:count error:&error];
  XCTAssertNotNil(pool, @"%@", error);
  pool.acquireTimeout = 2.0;
  NSMutableArray *held = [NSMutableArray array];
  for (NSUInteger index = 0; index < count; index++) {
    ALNPgConnection *connection = [pool acquireConnection:&error];
    XCTAssertNotNil(connection, @"%@", error);
    XCTAssertNotNil([connection executeQuery:@"SELECT 1 AS one" parameters:@[] error:&error]);
    [held addObject:connection];
  }
  for (ALNPgConnection *connection in held) {
    [pool releaseConnection:connection];
  }
  XCTAssertEqualObjects(@(count), [pool poolDiagnostics][@"idle_connections"]);
  return pool;
}

- (void)testTerminatedConnectionReportsConnectionLoss {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSError *error = nil;
  ALNPgConnection *connection = [[ALNPgConnection alloc] initWithConnectionString:[self pgTestDSN] error:&error];
  XCTAssertNotNil(connection, @"%@", error);
  XCTAssertNotNil([connection executeQuery:@"SELECT 1 AS one" parameters:@[] error:&error]);
  [self terminateOtherBackends];

  error = nil;
  XCTAssertNil([connection executeQuery:@"SELECT 1 AS one" parameters:@[] error:&error]);
  XCTAssertEqualObjects(ALNPgErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNPgErrorConnectionFailed, error.code);
  XCTAssertEqualObjects(@YES, error.userInfo[ALNPgErrorConnectionLostKey]);
  XCTAssertFalse(connection.isOpen);
}

- (void)testPoolReplacesTerminatedConnectionsAndRetriesTheStatement {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNPg *pool = [self warmPoolWithConnections:3];
  [self terminateOtherBackends];

  NSError *error = nil;
  NSArray *rows = [pool executeQuery:@"SELECT 1::text AS one" parameters:@[] error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"1", [rows firstObject][@"one"]);
  XCTAssertEqualObjects(@1, [pool poolDiagnostics][@"connection_retry_count"]);

  // Commands and transactions recover the same way.
  [self terminateOtherBackends];
  XCTAssertEqual((NSInteger)1, [pool executeCommand:@"SELECT 1" parameters:@[] error:&error], @"%@", error);
  [self terminateOtherBackends];
  __block BOOL ran = NO;
  XCTAssertTrue([pool withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    ran = ([connection executeQuery:@"SELECT 1 AS one" parameters:@[] error:txError] != nil);
    return ran;
  } error:&error], @"%@", error);
  XCTAssertTrue(ran);
  XCTAssertEqualObjects(@3, [pool poolDiagnostics][@"connection_retry_count"]);
}

- (void)testFreshConnectionFailureIsNotRetried {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  NSError *error = nil;
  ALNPg *pool = [[ALNPg alloc] initWithConnectionString:@"postgresql://postgres@127.0.0.1:1/unreachable"
                                          maxConnections:2
                                                   error:&error];
  XCTAssertNotNil(pool, @"%@", error);
  error = nil;
  XCTAssertNil([pool executeQuery:@"SELECT 1" parameters:@[] error:&error]);
  XCTAssertEqual((NSInteger)ALNPgErrorConnectionFailed, error.code);
  XCTAssertEqualObjects(@0, [pool poolDiagnostics][@"connection_retry_count"]);
}

@end
