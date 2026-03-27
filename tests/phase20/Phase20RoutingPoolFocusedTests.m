#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNMSSQL.h"
#import "ALNPg.h"

@interface ALNPg (Phase20RoutingPoolFocusedAccessors)

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite) NSUInteger maxConnections;
@property(nonatomic, strong) NSMutableArray *idleConnections;
@property(nonatomic, assign) NSUInteger inUseConnections;

@end

@interface ALNMSSQL (Phase20RoutingPoolFocusedAccessors)

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite) NSUInteger maxConnections;
@property(nonatomic, strong) NSMutableArray<ALNMSSQLConnection *> *idleConnections;
@property(nonatomic, assign) NSUInteger inUseConnections;

@end

@interface Phase20FakePgConnection : ALNPgConnection

@property(nonatomic, assign) BOOL fakeOpen;
@property(nonatomic, assign) BOOL fakeActiveTransaction;
@property(nonatomic, assign) BOOL livenessShouldSucceed;
@property(nonatomic, assign) BOOL rollbackShouldSucceed;
@property(nonatomic, assign) NSUInteger closeCount;
@property(nonatomic, assign) NSUInteger rollbackCount;

@end

@implementation Phase20FakePgConnection

- (BOOL)isOpen {
  return self.fakeOpen;
}

- (void)close {
  self.closeCount += 1;
  self.fakeOpen = NO;
}

- (BOOL)hasActiveTransaction {
  return self.fakeActiveTransaction;
}

- (BOOL)rollbackTransaction:(NSError **)error {
  self.rollbackCount += 1;
  if (self.rollbackShouldSucceed) {
    self.fakeActiveTransaction = NO;
    if (error != NULL) {
      *error = nil;
    }
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase20RoutingPoolFocusedTests" code:11 userInfo:nil];
  }
  return NO;
}

- (BOOL)checkConnectionLiveness:(NSError **)error {
  if (self.livenessShouldSucceed) {
    if (error != NULL) {
      *error = nil;
    }
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase20RoutingPoolFocusedTests" code:12 userInfo:nil];
  }
  return NO;
}

@end

@interface Phase20FakeMSSQLConnection : ALNMSSQLConnection

@property(nonatomic, assign) BOOL fakeOpen;
@property(nonatomic, assign) BOOL inTransaction;
@property(nonatomic, assign) BOOL livenessShouldSucceed;
@property(nonatomic, assign) BOOL rollbackShouldSucceed;
@property(nonatomic, assign) NSUInteger closeCount;
@property(nonatomic, assign) NSUInteger rollbackCount;

@end

@implementation Phase20FakeMSSQLConnection

- (BOOL)isOpen {
  return self.fakeOpen;
}

- (void)close {
  self.closeCount += 1;
  self.fakeOpen = NO;
}

- (BOOL)rollbackTransaction:(NSError **)error {
  self.rollbackCount += 1;
  if (self.rollbackShouldSucceed) {
    self.inTransaction = NO;
    if (error != NULL) {
      *error = nil;
    }
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase20RoutingPoolFocusedTests" code:21 userInfo:nil];
  }
  return NO;
}

- (BOOL)checkConnectionLiveness:(NSError **)error {
  if (self.livenessShouldSucceed) {
    if (error != NULL) {
      *error = nil;
    }
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase20RoutingPoolFocusedTests" code:22 userInfo:nil];
  }
  return NO;
}

@end

@interface Phase20RoutingPoolFocusedTests : XCTestCase
@end

@implementation Phase20RoutingPoolFocusedTests

- (ALNPg *)emptyPgPool {
  ALNPg *database = [[ALNPg alloc] init];
  database.connectionString = @"postgresql:///phase20-focused";
  database.maxConnections = 2;
  database.idleConnections = [NSMutableArray array];
  database.inUseConnections = 0;
  return database;
}

- (ALNMSSQL *)emptyMSSQLPool {
  ALNMSSQL *adapter = [[ALNMSSQL alloc] init];
  adapter.connectionString = @"Driver={focused};Server=phase20;";
  adapter.maxConnections = 2;
  adapter.idleConnections = [NSMutableArray array];
  adapter.inUseConnections = 0;
  return adapter;
}

- (void)testPostgresPoolRecyclesUnhealthyIdleConnectionsDeterministically {
  ALNPg *database = [self emptyPgPool];
  database.connectionLivenessChecksEnabled = YES;

  Phase20FakePgConnection *stale = [[Phase20FakePgConnection alloc] init];
  stale.fakeOpen = YES;
  stale.livenessShouldSucceed = NO;

  Phase20FakePgConnection *healthy = [[Phase20FakePgConnection alloc] init];
  healthy.fakeOpen = YES;
  healthy.livenessShouldSucceed = YES;

  database.idleConnections = [@[ healthy, stale ] mutableCopy];

  NSError *error = nil;
  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(healthy, connection);
  XCTAssertEqual((NSUInteger)1, stale.closeCount);
  XCTAssertFalse(stale.isOpen);
  XCTAssertEqual((NSUInteger)1, database.inUseConnections);
  XCTAssertEqual((NSUInteger)0, [database.idleConnections count]);
}

- (void)testPostgresReleaseConnectionRollsBackLeakedTransactionsBeforeRequeueing {
  ALNPg *database = [self emptyPgPool];
  database.inUseConnections = 1;

  Phase20FakePgConnection *connection = [[Phase20FakePgConnection alloc] init];
  connection.fakeOpen = YES;
  connection.fakeActiveTransaction = YES;
  connection.rollbackShouldSucceed = YES;

  [database releaseConnection:connection];

  XCTAssertEqual((NSUInteger)1, connection.rollbackCount);
  XCTAssertEqual((NSUInteger)0, connection.closeCount);
  XCTAssertEqual((NSUInteger)0, database.inUseConnections);
  XCTAssertEqual((NSUInteger)1, [database.idleConnections count]);
  XCTAssertEqualObjects(connection, [database.idleConnections lastObject]);
}

- (void)testMSSQLPoolRecyclesUnhealthyIdleConnectionsDeterministically {
  ALNMSSQL *adapter = [self emptyMSSQLPool];
  adapter.connectionLivenessChecksEnabled = YES;

  Phase20FakeMSSQLConnection *stale = [[Phase20FakeMSSQLConnection alloc] init];
  stale.fakeOpen = YES;
  stale.livenessShouldSucceed = NO;

  Phase20FakeMSSQLConnection *healthy = [[Phase20FakeMSSQLConnection alloc] init];
  healthy.fakeOpen = YES;
  healthy.livenessShouldSucceed = YES;

  adapter.idleConnections = [@[ healthy, stale ] mutableCopy];

  NSError *error = nil;
  ALNMSSQLConnection *connection = [adapter acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(healthy, connection);
  XCTAssertEqual((NSUInteger)1, stale.closeCount);
  XCTAssertFalse(stale.isOpen);
  XCTAssertEqual((NSUInteger)1, adapter.inUseConnections);
  XCTAssertEqual((NSUInteger)0, [adapter.idleConnections count]);
}

- (void)testMSSQLReleaseConnectionClosesConnectionsWhenRollbackFails {
  ALNMSSQL *adapter = [self emptyMSSQLPool];
  adapter.inUseConnections = 1;

  Phase20FakeMSSQLConnection *connection = [[Phase20FakeMSSQLConnection alloc] init];
  connection.fakeOpen = YES;
  connection.inTransaction = YES;
  connection.rollbackShouldSucceed = NO;

  [adapter releaseConnection:connection];

  XCTAssertEqual((NSUInteger)1, connection.rollbackCount);
  XCTAssertEqual((NSUInteger)2, connection.closeCount);
  XCTAssertEqual((NSUInteger)0, adapter.inUseConnections);
  XCTAssertEqual((NSUInteger)0, [adapter.idleConnections count]);
}

@end
