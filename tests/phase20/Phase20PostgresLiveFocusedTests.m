#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDatabaseTestSupport.h"
#import "../shared/ALNDataTestAssertions.h"
#import "ALNPg.h"

@interface Phase20PostgresLiveFocusedTests : XCTestCase
@end

@implementation Phase20PostgresLiveFocusedTests

- (NSString *)requiredPGTestDSNForSelector:(SEL)selector {
  return ALNTestRequiredEnvironmentString(@"ARLEN_PG_TEST_DSN",
                                          NSStringFromClass([self class]),
                                          NSStringFromSelector(selector),
                                          @"set ARLEN_PG_TEST_DSN to run focused PostgreSQL Phase 20 lanes");
}

- (void)testPostgresCommonScalarResultContractWhenExplicitTestDSNIsProvided {
  NSString *dsn = [self requiredPGTestDSNForSelector:_cmd];
  if (dsn == nil) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  ALNDatabaseResult *result =
      [database executeQueryResult:@"SELECT 42::integer AS age, "
                                   "TRUE AS is_active, "
                                   "19.75::numeric AS balance, "
                                   "'2026-03-26T12:34:56Z'::timestamptz AS created_at, "
                                   "decode('6869', 'hex')::bytea AS payload"
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

- (void)testPostgresDisposableSchemaHarnessProvidesDeterministicNamespaceAndOrderedResultContractWhenExplicitTestDSNIsProvided {
  NSString *dsn = [self requiredPGTestDSNForSelector:_cmd];
  if (dsn == nil) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  __block NSString *schemaName = nil;
  BOOL ok = ALNTestWithDisposableSchema(database, @"phase20pg", ^BOOL(NSString *schema, NSError **blockError) {
    schemaName = [schema copy];
    NSString *tableName = [NSString stringWithFormat:@"%@.phase20_rows", schema];

    NSInteger createAffected =
        [database executeCommand:[NSString stringWithFormat:@"CREATE TABLE %@ (name TEXT NOT NULL, total INTEGER NOT NULL, payload BYTEA NOT NULL)",
                                                            tableName]
                      parameters:@[]
                           error:blockError];
    XCTAssertGreaterThanOrEqual(createAffected, (NSInteger)0);
    XCTAssertNil(*blockError);

    BOOL transactionOK =
        [database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
          NSInteger batchAffected = ALNDatabaseExecuteCommandBatch(
              (id<ALNDatabaseConnection>)connection,
              [NSString stringWithFormat:@"INSERT INTO %@ (name, total, payload) VALUES ($1, $2, $3)",
                                         tableName],
              @[ @[ @"hank", @7, [@"hi" dataUsingEncoding:NSUTF8StringEncoding] ],
                 @[ @"dale", @9, [@"yo" dataUsingEncoding:NSUTF8StringEncoding] ] ],
              txError);
          XCTAssertEqual((NSInteger)2, batchAffected);
          XCTAssertNil(*txError);

          NSError *savepointError = nil;
          BOOL savepointOK = ALNDatabaseWithSavepoint((id<ALNDatabaseConnection>)connection,
                                                      @"phase20_inner",
                                                      ^BOOL(NSError **innerError) {
                                                        NSInteger innerAffected =
                                                            [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name, total, payload) VALUES ($1, $2, $3)",
                                                                                                                  tableName]
                                                                            parameters:@[
                                                                              @"bill",
                                                                              @11,
                                                                              [@"no" dataUsingEncoding:NSUTF8StringEncoding]
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
        [database executeQueryResult:[NSString stringWithFormat:@"SELECT name, total, payload FROM %@ ORDER BY total ASC",
                                                                tableName]
                          parameters:@[]
                               error:blockError];
    XCTAssertNotNil(result);
    XCTAssertNil(*blockError);
    ALNAssertResultColumns(result, (@[ @"name", @"total", @"payload" ]));
    ALNAssertRowOrderedValues(result.first,
                              (@[ @"hank", @7, [@"hi" dataUsingEncoding:NSUTF8StringEncoding] ]));
    return YES;
  }, &error);

  XCTAssertTrue(ok);
  XCTAssertNil(error);
  XCTAssertNotNil(schemaName);

  NSArray<NSDictionary *> *rows =
      [database executeQuery:@"SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1"
                  parameters:@[ schemaName ?: @"" ]
                       error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)0, [rows count]);
}

@end
