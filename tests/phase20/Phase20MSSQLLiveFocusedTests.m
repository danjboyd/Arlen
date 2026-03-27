#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../ALNTestRequirements.h"
#import "../shared/ALNDatabaseTestSupport.h"
#import "../shared/ALNDataTestAssertions.h"
#import "ALNMSSQL.h"

@interface Phase20MSSQLLiveFocusedTests : XCTestCase
@end

@implementation Phase20MSSQLLiveFocusedTests

- (BOOL)requireMSSQLTransportForSelector:(SEL)selector {
  NSDictionary *metadata = [ALNMSSQL capabilityMetadata];
  return ALNTestRequireCondition([metadata[@"transport_available"] boolValue],
                                 NSStringFromClass([self class]),
                                 NSStringFromSelector(selector),
                                 @"mssql_transport_available",
                                 @"this build lacks ODBC transport support for focused MSSQL Phase 20 lanes");
}

- (NSString *)requiredMSSQLTestDSNForSelector:(SEL)selector {
  return ALNTestRequiredEnvironmentString(@"ARLEN_MSSQL_TEST_DSN",
                                          NSStringFromClass([self class]),
                                          NSStringFromSelector(selector),
                                          @"set ARLEN_MSSQL_TEST_DSN to run focused MSSQL Phase 20 lanes");
}

- (void)testMSSQLCommonScalarResultContractWhenExplicitTestDSNIsProvided {
  if (![self requireMSSQLTransportForSelector:_cmd]) {
    return;
  }
  NSString *dsn = [self requiredMSSQLTestDSNForSelector:_cmd];
  if (dsn == nil) {
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
      [adapter executeQueryResult:@"SELECT CAST(42 AS INT) AS age, "
                                  "CAST(1 AS BIT) AS is_active, "
                                  "CAST(19.75 AS DECIMAL(10,2)) AS balance, "
                                  "CAST('2026-03-26 12:34:56.123' AS DATETIME2) AS created_at, "
                                  "CAST(0x6869 AS VARBINARY(16)) AS payload"
                       parameters:@[]
                            error:&error];
  XCTAssertNil(error);
  ALNAssertResultContract(result,
                          (@[ @"age", @"is_active", @"balance", @"created_at", @"payload" ]),
                          (@{
                            @"age" : [NSNumber class],
                            @"is_active" : [NSNumber class],
                            @"balance" : [NSNumber class],
                            @"payload" : [NSData class],
                          }),
                          (@{
                            @"age" : @42,
                            @"is_active" : @YES,
                            @"balance" : [NSDecimalNumber decimalNumberWithString:@"19.75"],
                            @"payload" : [@"hi" dataUsingEncoding:NSUTF8StringEncoding],
                          }));
  XCTAssertTrue([result.first.dictionaryRepresentation[@"created_at"] isKindOfClass:[NSDate class]]);
}

- (void)testMSSQLDisposableSchemaHarnessProvidesDeterministicNamespaceAndOrderedResultContractWhenExplicitTestDSNIsProvided {
  if (![self requireMSSQLTransportForSelector:_cmd]) {
    return;
  }
  NSString *dsn = [self requiredMSSQLTestDSNForSelector:_cmd];
  if (dsn == nil) {
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

  __block NSString *schemaName = nil;
  BOOL ok = ALNTestWithDisposableSchema(adapter, @"phase20ms", ^BOOL(NSString *schema, NSError **blockError) {
    schemaName = [schema copy];
    NSString *tableName = [NSString stringWithFormat:@"%@.phase20_rows", schema];

    NSInteger createAffected =
        [adapter executeCommand:[NSString stringWithFormat:@"CREATE TABLE %@ (payload VARBINARY(16) NOT NULL, name NVARCHAR(64) NOT NULL, total INT NOT NULL)",
                                                            tableName]
                      parameters:@[]
                           error:blockError];
    XCTAssertGreaterThanOrEqual(createAffected, (NSInteger)0);
    XCTAssertNil(*blockError);

    BOOL transactionOK =
        [adapter withTransaction:^BOOL(ALNMSSQLConnection *connection, NSError **txError) {
          NSInteger batchAffected = ALNDatabaseExecuteCommandBatch(
              (id<ALNDatabaseConnection>)connection,
              [NSString stringWithFormat:@"INSERT INTO %@ (payload, name, total) VALUES (?, ?, ?)",
                                         tableName],
              @[ @[ [@"hi" dataUsingEncoding:NSUTF8StringEncoding], @"hank", @7 ],
                 @[ [@"yo" dataUsingEncoding:NSUTF8StringEncoding], @"dale", @9 ] ],
              txError);
          XCTAssertEqual((NSInteger)2, batchAffected);
          XCTAssertNil(*txError);

          NSError *savepointError = nil;
          BOOL savepointOK = ALNDatabaseWithSavepoint((id<ALNDatabaseConnection>)connection,
                                                      @"phase20_inner",
                                                      ^BOOL(NSError **innerError) {
                                                        NSInteger innerAffected =
                                                            [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (payload, name, total) VALUES (?, ?, ?)",
                                                                                                                  tableName]
                                                                            parameters:@[
                                                                              [@"no" dataUsingEncoding:NSUTF8StringEncoding],
                                                                              @"bill",
                                                                              @11
                                                                            ]
                                                                                 error:innerError];
                                                        XCTAssertEqual((NSInteger)1, innerAffected);
                                                        if (innerError != NULL) {
                                                          *innerError = ALNDatabaseAdapterMakeError(
                                                              ALNDatabaseAdapterErrorInvalidResult,
                                                              @"intentional savepoint rollback",
                                                              nil);
                                                        }
                                                        return NO;
                                                      },
                                                      &savepointError);
          XCTAssertFalse(savepointOK);
          XCTAssertNotNil(savepointError);
          return YES;
        } error:blockError];
    XCTAssertTrue(transactionOK);
    XCTAssertNil(*blockError);

    ALNDatabaseResult *result =
        [adapter executeQueryResult:[NSString stringWithFormat:@"SELECT payload, name, total FROM %@ ORDER BY total ASC",
                                                                tableName]
                         parameters:@[]
                              error:blockError];
    XCTAssertNotNil(result);
    XCTAssertNil(*blockError);
    ALNAssertResultColumns(result, (@[ @"payload", @"name", @"total" ]));
    ALNAssertRowOrderedValues(result.first,
                              (@[ [@"hi" dataUsingEncoding:NSUTF8StringEncoding], @"hank", @7 ]));

    NSInteger dropAffected =
        [adapter executeCommand:[NSString stringWithFormat:@"DROP TABLE %@", tableName]
                      parameters:@[]
                           error:blockError];
    XCTAssertGreaterThanOrEqual(dropAffected, (NSInteger)0);
    XCTAssertNil(*blockError);
    return YES;
  }, &error);

  XCTAssertTrue(ok);
  XCTAssertNil(error);
  XCTAssertNotNil(schemaName);

  NSArray<NSDictionary *> *rows =
      [adapter executeQuery:@"SELECT COUNT(*) AS count FROM sys.schemas WHERE name = ?"
                 parameters:@[ schemaName ?: @"" ]
                      error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@0, [rows.firstObject objectForKey:@"count"]);
}

@end
