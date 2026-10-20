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

#pragma mark - Writes and transactions

- (ALNPgConnection *)adminConnection {
  NSError *error = nil;
  ALNPgConnection *admin = [[ALNPgConnection alloc] initWithConnectionString:[self pgTestDSN] error:&error];
  XCTAssertNotNil(admin, @"%@", error);
  return admin;
}

- (void)terminateBackend:(NSString *)pid admin:(ALNPgConnection *)admin {
  XCTAssertNotNil([admin executeQuery:@"SELECT pg_terminate_backend($1::integer)::text AS terminated"
                           parameters:@[ pid ]
                                error:NULL]);
  XCTAssertTrue(ALNTestWaitUntil(10.0, 0.05, ^BOOL {
    NSArray *rows = [admin executeQuery:@"SELECT COUNT(*)::text AS total FROM pg_stat_activity WHERE pid = $1::integer"
                             parameters:@[ pid ]
                                  error:NULL];
    return [[rows firstObject][@"total"] isEqualToString:@"0"];
  }));
}

- (NSString *)scratchTableWithAdmin:(ALNPgConnection *)admin {
  NSString *table = [NSString stringWithFormat:@"aln_retry_%@",
                                               [[[[NSUUID UUID] UUIDString] lowercaseString]
                                                   stringByReplacingOccurrencesOfString:@"-"
                                                                             withString:@""]];
  NSString *create = [NSString stringWithFormat:@"CREATE TABLE %@ (id INTEGER NOT NULL, used BOOLEAN NOT NULL DEFAULT FALSE)", table];
  XCTAssertTrue([admin executeCommand:create parameters:@[] error:NULL] >= 0);
  NSString *dsn = [self pgTestDSN];
  [self addTeardownBlock:^{
    ALNPgConnection *cleanup = [[ALNPgConnection alloc] initWithConnectionString:dsn error:NULL];
    (void)[cleanup executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table] parameters:@[] error:NULL];
    [cleanup close];
  }];
  return table;
}

- (NSString *)scalar:(NSString *)sql admin:(ALNPgConnection *)admin {
  return [[admin executeQuery:sql parameters:@[] error:NULL] firstObject][@"value"];
}

- (NSString *)tokenUsedInTable:(NSString *)table admin:(ALNPgConnection *)admin {
  NSString *sql =
      [NSString stringWithFormat:@"SELECT CASE WHEN used THEN 't' ELSE 'f' END AS value FROM %@ WHERE id = 1", table];
  return [self scalar:sql admin:admin];
}

- (NSString *)countInTable:(NSString *)table where:(NSString *)condition admin:(ALNPgConnection *)admin {
  NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*)::text AS value FROM %@ WHERE %@", table, condition];
  return [self scalar:sql admin:admin];
}

- (void)testWriteSentBeforeTheConnectionDiesIsNotRetried {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNPgConnection *admin = [self adminConnection];
  NSString *table = [self scratchTableWithAdmin:admin];
  ALNPg *pool = [self warmPoolWithConnections:1];
  NSString *sql = [NSString stringWithFormat:@"WITH s AS (SELECT pg_sleep(2)) INSERT INTO %@ (id) SELECT 1 FROM s", table];

  __block NSInteger affected = 0;
  __block NSError *writeError = nil;
  dispatch_group_t group = dispatch_group_create();
  dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *localError = nil;
    affected = [pool executeCommand:sql parameters:@[] error:&localError];
    writeError = localError;
  });
  __block NSString *pid = nil;
  XCTAssertTrue(ALNTestWaitUntil(10.0, 0.02, ^BOOL {
    NSArray *rows = [admin executeQuery:@"SELECT pid::text AS pid FROM pg_stat_activity "
                                        "WHERE state = 'active' AND query LIKE $1"
                             parameters:@[ [NSString stringWithFormat:@"%%pg_sleep(2)%%%@%%", table] ]
                                  error:NULL];
    pid = [rows firstObject][@"pid"];
    return [pid length] > 0;
  }));
  [self terminateBackend:pid admin:admin];
  XCTAssertEqual(0L, dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC))));

  XCTAssertEqual((NSInteger)-1, affected);
  XCTAssertEqual((NSInteger)ALNPgErrorConnectionFailed, writeError.code);
  XCTAssertEqualObjects(@YES, writeError.userInfo[ALNPgErrorConnectionLostKey]);
  XCTAssertNil(writeError.userInfo[ALNPgErrorStatementNotSentKey]);
  NSString *count = [self countInTable:table where:@"TRUE" admin:admin];
  XCTAssertTrue([count isEqualToString:@"0"] || [count isEqualToString:@"1"], @"%@", count);
  XCTAssertEqualObjects(@0, [pool poolDiagnostics][@"connection_retry_count"]);
  [admin close];
}

- (void)testWriteOnAConnectionClosedBeforeSendIsRetriedOnce {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNPgConnection *setup = [self adminConnection];
  NSString *table = [self scratchTableWithAdmin:setup];
  ALNPg *pool = [self warmPoolWithConnections:1];
  [self terminateOtherBackends];
  ALNPgConnection *admin = [self adminConnection];
  NSError *error = nil;
  NSString *insert = [NSString stringWithFormat:@"INSERT INTO %@ (id) VALUES (7)", table];
  XCTAssertEqual((NSInteger)1, [pool executeCommand:insert parameters:@[] error:&error], @"%@", error);
  XCTAssertEqualObjects(@"1", [self countInTable:table where:@"TRUE" admin:admin]);
  XCTAssertEqualObjects(@1, [pool poolDiagnostics][@"connection_retry_count"]);
  [admin close];
}

- (void)testConnectionLostInsideATransactionIsNotRetried {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNPgConnection *admin = [self adminConnection];
  NSString *table = [self scratchTableWithAdmin:admin];
  NSString *seed = [NSString stringWithFormat:@"INSERT INTO %@ (id) VALUES (1)", table];
  XCTAssertEqual((NSInteger)1, [admin executeCommand:seed parameters:@[] error:NULL]);
  ALNPg *pool = [self warmPoolWithConnections:2];
  NSString *consume = [NSString stringWithFormat:@"UPDATE %@ SET used = TRUE WHERE id = 1 AND used = FALSE", table];
  NSString *record = [NSString stringWithFormat:@"INSERT INTO %@ (id) VALUES (2)", table];

  __block NSUInteger runs = 0;
  NSError *error = nil;
  BOOL ok = [pool withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    runs += 1;
    NSString *pid = [[connection executeQuery:@"SELECT pg_backend_pid()::text AS pid" parameters:@[] error:txError]
        firstObject][@"pid"];
    if ([connection executeCommand:consume parameters:@[] error:txError] != 1) {
      return NO;
    }
    [self terminateBackend:pid admin:admin];
    return [connection executeCommand:record parameters:@[] error:txError] == 1;
  } error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual((NSUInteger)1, runs);
  XCTAssertEqualObjects(@YES, error.userInfo[ALNPgErrorConnectionLostKey]);
  // The first statement was rolled back with the transaction; nothing ran twice.
  XCTAssertEqualObjects(@"f", [self tokenUsedInTable:table admin:admin]);
  XCTAssertEqualObjects(@"0", [self countInTable:table where:@"id = 2" admin:admin]);
  XCTAssertEqualObjects(@0, [pool poolDiagnostics][@"connection_retry_count"]);
  XCTAssertNotNil([pool executeQuery:@"SELECT 1 AS one" parameters:@[] error:&error], @"%@", error);

  // A connection the caller acquired and opened a transaction on by hand.
  ALNPgConnection *manual = [pool acquireConnection:&error];
  XCTAssertNotNil(manual, @"%@", error);
  XCTAssertTrue([manual executeCommand:@"BEGIN" parameters:@[] error:&error] >= 0);
  XCTAssertEqual((NSInteger)1, [manual executeCommand:consume parameters:@[] error:&error]);
  NSString *manualPid = [[manual executeQuery:@"SELECT pg_backend_pid()::text AS pid" parameters:@[] error:&error]
      firstObject][@"pid"];
  [self terminateBackend:manualPid admin:admin];
  error = nil;
  XCTAssertEqual((NSInteger)-1, [manual executeCommand:record parameters:@[] error:&error]);
  XCTAssertEqualObjects(@YES, error.userInfo[ALNPgErrorConnectionLostKey]);
  [pool releaseConnection:manual];
  XCTAssertEqualObjects(@"f", [self tokenUsedInTable:table admin:admin]);
  XCTAssertEqualObjects(@"0", [self countInTable:table where:@"id = 2" admin:admin]);
  XCTAssertNotNil([pool executeQuery:@"SELECT 1 AS one" parameters:@[] error:&error], @"%@", error);
  [admin close];
}

- (void)testOptInReplayRunsTheWholeTransactionAgainOnce {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNPgConnection *admin = [self adminConnection];
  NSString *table = [self scratchTableWithAdmin:admin];
  NSString *seed = [NSString stringWithFormat:@"INSERT INTO %@ (id) VALUES (1)", table];
  XCTAssertEqual((NSInteger)1, [admin executeCommand:seed parameters:@[] error:NULL]);
  ALNPg *pool = [self warmPoolWithConnections:2];
  NSString *consume = [NSString stringWithFormat:@"UPDATE %@ SET used = TRUE WHERE id = 1 AND used = FALSE", table];
  NSString *record = [NSString stringWithFormat:@"INSERT INTO %@ (id) VALUES (2)", table];

  __block NSUInteger runs = 0;
  NSError *error = nil;
  BOOL ok = [pool withTransactionReplayingOnConnectionLoss:^BOOL(ALNPgConnection *connection, NSError **txError) {
    runs += 1;
    NSString *pid = [[connection executeQuery:@"SELECT pg_backend_pid()::text AS pid" parameters:@[] error:txError]
        firstObject][@"pid"];
    if ([connection executeCommand:consume parameters:@[] error:txError] != 1) {
      return NO;
    }
    if (runs == 1) {
      [self terminateBackend:pid admin:admin];
    }
    return [connection executeCommand:record parameters:@[] error:txError] == 1;
  } error:&error];
  XCTAssertTrue(ok, @"%@", error);
  XCTAssertEqual((NSUInteger)2, runs);
  XCTAssertEqualObjects(@"t", [self tokenUsedInTable:table admin:admin]);
  XCTAssertEqualObjects(@"1", [self countInTable:table where:@"id = 2" admin:admin]);
  XCTAssertEqualObjects(@1, [pool poolDiagnostics][@"connection_retry_count"]);
  [admin close];
}

- (void)testPlainReadClassification {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  // A read sent before the connection died is retried; an INSERT ... RETURNING
  // through executeQuery is treated as a write and is not.
  ALNPgConnection *admin = [self adminConnection];
  NSString *table = [self scratchTableWithAdmin:admin];
  ALNPg *pool = [self warmPoolWithConnections:1];
  NSString *sql = [NSString stringWithFormat:@"WITH s AS (SELECT pg_sleep(2)) INSERT INTO %@ (id) SELECT 1 FROM s RETURNING id", table];
  __block NSArray *rows = @[];
  __block NSError *writeError = nil;
  dispatch_group_t group = dispatch_group_create();
  dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *localError = nil;
    rows = [pool executeQuery:sql parameters:@[] error:&localError];
    writeError = localError;
  });
  __block NSString *pid = nil;
  XCTAssertTrue(ALNTestWaitUntil(10.0, 0.02, ^BOOL {
    pid = [[admin executeQuery:@"SELECT pid::text AS pid FROM pg_stat_activity WHERE state = 'active' AND query LIKE $1"
                    parameters:@[ [NSString stringWithFormat:@"%%RETURNING id%%"] ]
                         error:NULL] firstObject][@"pid"];
    return [pid length] > 0;
  }));
  [self terminateBackend:pid admin:admin];
  XCTAssertEqual(0L, dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC))));
  XCTAssertNil(rows);
  XCTAssertEqualObjects(@YES, writeError.userInfo[ALNPgErrorConnectionLostKey]);
  XCTAssertEqualObjects(@0, [pool poolDiagnostics][@"connection_retry_count"]);
  [admin close];
}

@end
