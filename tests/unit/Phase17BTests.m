#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAdapterConformance.h"
#import "ALNMSSQL.h"
#import "ALNMSSQLDialect.h"
#import "ALNSQLBuilder.h"

@interface Phase17BTests : XCTestCase
@end

@implementation Phase17BTests

- (NSString *)mssqlTestDSN {
  const char *value = getenv("ARLEN_MSSQL_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (NSString *)uniqueTempTableName {
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"#arlen_%@", uuid];
}

- (void)testMSSQLDialectCompilesPaginationAndOutputReturning {
  NSError *error = nil;

  ALNSQLBuilder *selectBuilder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id", @"name" ]];
  [[selectBuilder orderByField:@"id" descending:NO] limit:10];
  [selectBuilder offset:5];
  NSDictionary *selectBuilt = [selectBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"SELECT [id], [name] FROM [users] ORDER BY [id] ASC OFFSET 5 ROWS FETCH NEXT 10 ROWS ONLY",
                        selectBuilt[@"sql"]);
  XCTAssertEqualObjects((@[]), selectBuilt[@"parameters"]);

  ALNSQLBuilder *insertBuilder = [[ALNSQLBuilder insertInto:@"users"
                                                     values:@{ @"name" : @"hank" }]
      returningField:@"id"];
  NSDictionary *insertBuilt = [insertBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"INSERT INTO [users] ([name]) OUTPUT INSERTED.[id] VALUES (?)",
                        insertBuilt[@"sql"]);
  XCTAssertEqualObjects((@[ @"hank" ]), insertBuilt[@"parameters"]);

  ALNSQLBuilder *updateBuilder = [[ALNSQLBuilder updateTable:@"users"
                                                      values:@{ @"name" : @"dale" }]
      returningField:@"id"];
  [updateBuilder whereField:@"id" equals:@7];
  NSDictionary *updateBuilt = [updateBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"UPDATE [users] SET [name] = ? OUTPUT INSERTED.[id] WHERE [id] = ?",
                        updateBuilt[@"sql"]);
  XCTAssertEqualObjects((@[ @"dale", @7 ]), updateBuilt[@"parameters"]);
}

- (void)testMSSQLDialectRejectsUnsupportedPostgresOnlyFeatures {
  NSError *error = nil;

  ALNSQLBuilder *paginationWithoutOrder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]];
  [paginationWithoutOrder limit:5];
  NSDictionary *built =
      [paginationWithoutOrder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertTrue([[error localizedDescription] containsString:@"requires an explicit ORDER BY"]);

  error = nil;
  ALNSQLBuilder *lockBuilder = [[ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]] forUpdate];
  built = [lockBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertTrue([[error localizedDescription] containsString:@"FOR UPDATE"]);

  error = nil;
  ALNSQLBuilder *ilikeBuilder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]];
  [ilikeBuilder whereField:@"name" operator:@"ilike" value:@"%bo%"];
  built = [ilikeBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertTrue([[error localizedDescription] containsString:@"ILIKE"]);
}

- (void)testMSSQLDialectAppliesNestedPaginationRecursively {
  NSError *error = nil;
  ALNSQLBuilder *latestEvent = [ALNSQLBuilder selectFrom:@"events" columns:@[ @"user_id" ]];
  [latestEvent orderByField:@"created_at" descending:YES];
  [latestEvent limit:1];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]];
  [builder whereField:@"id" inSubquery:latestEvent];

  NSDictionary *built = [builder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(
      @"SELECT [id] FROM [users] WHERE [id] IN (SELECT [user_id] FROM [events] ORDER BY [created_at] DESC OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY)",
      built[@"sql"]);
  XCTAssertEqualObjects((@[]), built[@"parameters"]);
}

- (void)testMSSQLDialectRejectsUnsupportedNestedFeatures {
  NSError *error = nil;
  ALNSQLBuilder *subquery = [ALNSQLBuilder selectFrom:@"events" columns:@[ @"user_id" ]];
  [subquery whereField:@"title" operator:@"ilike" value:@"%ops%"];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]];
  [builder whereField:@"id" inSubquery:subquery];

  NSDictionary *built = [builder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertTrue([[error localizedDescription] containsString:@"ILIKE"]);
}

- (void)testMSSQLAdapterCapabilityMetadataAndInitializationFailureAreExplicit {
  NSDictionary *metadata = [ALNMSSQL capabilityMetadata];
  XCTAssertEqualObjects(@"mssql", metadata[@"adapter"]);
  XCTAssertEqualObjects(@"mssql", metadata[@"dialect"]);
  XCTAssertEqualObjects([metadata[@"transport_available"] boolValue] ? @"supported_subset"
                                                                     : @"unavailable_at_build_time",
                        metadata[@"support_tier"]);
  XCTAssertEqualObjects(@"output", metadata[@"returning_mode"]);
  XCTAssertEqualObjects(@"offset_fetch", metadata[@"pagination_syntax"]);
  XCTAssertEqualObjects(@(NO), metadata[@"supports_upsert"]);
  XCTAssertEqualObjects(@(YES), metadata[@"supports_result_wrappers"]);
  XCTAssertEqualObjects([metadata[@"transport_available"] boolValue] ? @(YES) : @(NO),
                        metadata[@"supports_connection_liveness_checks"]);

  NSError *error = nil;
  ALNMSSQL *adapter = [[ALNMSSQL alloc]
      initWithConnectionString:@"Driver={Definitely Missing Driver};Server=localhost;Database=master;"
                 maxConnections:1
                          error:&error];
  if ([metadata[@"transport_available"] boolValue]) {
    XCTAssertNotNil(adapter);
    XCTAssertNil(error);

    ALNMSSQLConnection *connection = [adapter acquireConnection:&error];
    XCTAssertNil(connection);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(ALNMSSQLErrorDomain, error.domain);
    XCTAssertEqual((NSInteger)ALNMSSQLErrorConnectionFailed, error.code);
  } else {
    XCTAssertNil(adapter);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(ALNMSSQLErrorDomain, error.domain);
    XCTAssertEqual((NSInteger)ALNMSSQLErrorTransportUnavailable, error.code);
  }
}

- (void)testMSSQLAdapterConformanceSuiteRunsWhenExplicitTestDSNIsProvided {
  NSString *dsn = [self mssqlTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNMSSQL *adapter = [[ALNMSSQL alloc] initWithConnectionString:dsn
                                                   maxConnections:2
                                                            error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(adapter);
  if (adapter == nil) {
    return;
  }

  NSDictionary *report = ALNAdapterConformanceReport(adapter, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@(YES), report[@"success"]);
  XCTAssertEqualObjects(@"mssql", report[@"adapter"]);
}

- (void)testMSSQLAdapterMaterializesTypedCommonScalarsWhenExplicitTestDSNIsProvided {
  NSString *dsn = [self mssqlTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNMSSQL *adapter = [[ALNMSSQL alloc] initWithConnectionString:dsn
                                                   maxConnections:2
                                                            error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(adapter);
  if (adapter == nil) {
    return;
  }

  NSUUID *actorID = [NSUUID UUID];
  NSArray<NSDictionary *> *rows =
      [adapter executeQuery:@"SELECT CAST(42 AS INT) AS age, "
                             "CAST(1 AS BIT) AS is_active, "
                             "CAST(19.75 AS DECIMAL(10,2)) AS balance, "
                             "CAST('2026-03-26 12:34:56.123' AS DATETIME2) AS created_at, "
                             "CAST(? AS BIGINT) AS total, "
                             "CAST(? AS BIT) AS enabled, "
                             "CAST(? AS UNIQUEIDENTIFIER) AS actor_id"
                 parameters:@[ @7, @YES, actorID ]
                      error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [rows count]);
  NSDictionary *row = rows.firstObject;
  XCTAssertTrue([row[@"age"] isKindOfClass:[NSNumber class]]);
  XCTAssertEqualObjects(@42, row[@"age"]);
  XCTAssertTrue([row[@"is_active"] isKindOfClass:[NSNumber class]]);
  XCTAssertEqualObjects(@YES, row[@"is_active"]);
  XCTAssertTrue([row[@"balance"] isKindOfClass:[NSNumber class]]);
  XCTAssertEqualObjects([NSDecimalNumber decimalNumberWithString:@"19.75"], row[@"balance"]);
  XCTAssertTrue([row[@"created_at"] isKindOfClass:[NSDate class]]);
  XCTAssertEqualObjects(@7, row[@"total"]);
  XCTAssertEqualObjects(@YES, row[@"enabled"]);
  XCTAssertEqualObjects([[actorID UUIDString] uppercaseString], [row[@"actor_id"] uppercaseString]);
}

- (void)testMSSQLResultWrappersBatchExecutionAndSavepointsWhenExplicitTestDSNIsProvided {
  NSString *dsn = [self mssqlTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNMSSQL *adapter = [[ALNMSSQL alloc] initWithConnectionString:dsn
                                                   maxConnections:2
                                                            error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(adapter);
  if (adapter == nil) {
    return;
  }

  ALNDatabaseResult *result =
      [adapter executeQueryResult:@"SELECT CAST(7 AS INT) AS total, CAST('hank' AS NVARCHAR(32)) AS name"
                       parameters:@[]
                            error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(@7, [result scalarValueForColumn:@"total" error:&error]);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"hank", [[result first] objectForColumn:@"name"]);

  NSString *tempTable = [self uniqueTempTableName];
  BOOL succeeded = [adapter withTransaction:^BOOL(ALNMSSQLConnection *connection, NSError **txError) {
    XCTAssertTrue(ALNDatabaseConnectionSupportsSavepoints((id<ALNDatabaseConnection>)connection));

    NSInteger createAffected =
        [connection executeCommand:[NSString stringWithFormat:@"CREATE TABLE %@ (name NVARCHAR(64) NOT NULL)",
                                                              tempTable]
                        parameters:@[]
                             error:txError];
    XCTAssertGreaterThanOrEqual(createAffected, (NSInteger)0);
    XCTAssertNil(*txError);

    NSInteger batchAffected = ALNDatabaseExecuteCommandBatch((id<ALNDatabaseConnection>)connection,
                                                             [NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES (?)",
                                                                                        tempTable],
                                                             @[ @[ @"hank" ], @[ @"dale" ] ],
                                                             txError);
    XCTAssertEqual((NSInteger)2, batchAffected);
    XCTAssertNil(*txError);

    NSError *savepointError = nil;
    BOOL savepointOK = ALNDatabaseWithSavepoint((id<ALNDatabaseConnection>)connection,
                                                @"phase20_inner",
                                                ^BOOL(NSError **blockError) {
                                                  NSInteger innerAffected =
                                                      [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES (?)",
                                                                                                        tempTable]
                                                                      parameters:@[ @"bill" ]
                                                                           error:blockError];
                                                  XCTAssertEqual((NSInteger)1, innerAffected);
                                                  if (blockError != NULL) {
                                                    *blockError = ALNDatabaseAdapterMakeError(
                                                        ALNDatabaseAdapterErrorInvalidResult,
                                                        @"intentional savepoint rollback",
                                                        nil);
                                                  }
                                                  return NO;
                                                },
                                                &savepointError);
    XCTAssertFalse(savepointOK);
    XCTAssertNotNil(savepointError);

    NSInteger finalAffected =
        [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES (?)", tempTable]
                        parameters:@[ @"boomhauer" ]
                             error:txError];
    XCTAssertEqual((NSInteger)1, finalAffected);
    XCTAssertNil(*txError);

    ALNDatabaseResult *countResult =
        ALNDatabaseExecuteQueryResult((id<ALNDatabaseConnection>)connection,
                                      [NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@", tempTable],
                                      @[],
                                      txError);
    XCTAssertNotNil(countResult);
    XCTAssertEqualObjects(@3, [countResult scalarValueForColumn:@"count" error:txError]);
    XCTAssertNil(*txError);
    return YES;
  } error:&error];

  XCTAssertTrue(succeeded);
  XCTAssertNil(error);
}

@end
