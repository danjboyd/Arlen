#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNMigrationRunner.h"
#import "ALNPg.h"

@interface PgTests : XCTestCase
@end

@implementation PgTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (NSString *)uniqueNameWithPrefix:(NSString *)prefix {
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"%@_%@", prefix, uuid];
}

- (NSString *)createTempDirectory {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-migrations-XXXXXX"];
  const char *templateCString = [templatePath fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
}

- (void)testConnectionAndPreparedStatements {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:4 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  NSArray *rows = [database executeQuery:@"SELECT 1::int AS value" parameters:@[] error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [rows count]);
  XCTAssertEqualObjects(@"1", rows[0][@"value"]);

  NSString *table = [self uniqueNameWithPrefix:@"arlen_pg_test"];
  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  NSString *createSQL =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, name TEXT NOT NULL)", table];
  XCTAssertGreaterThanOrEqual([connection executeCommand:createSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);

  NSString *insertSQL =
      [NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES ($1)", table];
  BOOL prepared = [connection prepareStatementNamed:@"insert_name"
                                                sql:insertSQL
                                     parameterCount:1
                                              error:&error];
  XCTAssertTrue(prepared);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1,
                 [connection executePreparedCommandNamed:@"insert_name"
                                               parameters:@[ @"hank" ]
                                                    error:&error]);
  XCTAssertNil(error);

  NSArray *namedRows = [connection executeQuery:[NSString stringWithFormat:@"SELECT name FROM %@ WHERE name = $1",
                                                                           table]
                                     parameters:@[ @"hank" ]
                                          error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [namedRows count]);
  XCTAssertEqualObjects(@"hank", namedRows[0][@"name"]);

  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                        parameters:@[]
                             error:nil];
  [database releaseConnection:connection];
}

- (void)testTransactionHelperCommitAndRollback {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  NSString *table = [self uniqueNameWithPrefix:@"arlen_tx_test"];
  NSString *createSQL =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, name TEXT)", table];
  NSInteger createResult = [database executeCommand:createSQL parameters:@[] error:&error];
  XCTAssertGreaterThanOrEqual(createResult, (NSInteger)0);
  XCTAssertNil(error);

  BOOL committed = [database withTransaction:^BOOL(ALNPgConnection *connection, NSError **blockError) {
    return [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES ($1)", table]
                           parameters:@[ @"peggy" ]
                                error:blockError] >= 0;
  } error:&error];
  XCTAssertTrue(committed);
  XCTAssertNil(error);

  __block NSError *expectedError = nil;
  BOOL rolledBack = [database withTransaction:^BOOL(ALNPgConnection *connection, NSError **blockError) {
    NSInteger inserted =
        [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES ($1)", table]
                        parameters:@[ @"bobby" ]
                             error:blockError];
    if (inserted < 0) {
      return NO;
    }
    expectedError = [NSError errorWithDomain:@"PgTests" code:99 userInfo:nil];
    if (blockError != NULL) {
      *blockError = expectedError;
    }
    return NO;
  } error:&error];
  XCTAssertFalse(rolledBack);
  XCTAssertEqualObjects(expectedError, error);

  NSDictionary *countRow = [[database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@",
                                                                             table]
                                        parameters:@[]
                                             error:&error] firstObject];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"1", countRow[@"count"]);

  (void)[database executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                      parameters:@[]
                           error:nil];
}

- (void)testParameterizedSelectRegressionCoversDirectAndPreparedQueries {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  NSArray *rows = [database executeQuery:@"SELECT COALESCE($1::text, 'missing') AS text_value, "
                                         "$2::int + 5 AS int_value, "
                                         "($3::text IS NULL)::int AS is_null"
                              parameters:@[ @"hank", @7, [NSNull null] ]
                                   error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [rows count]);
  NSDictionary *row = [rows firstObject];
  XCTAssertEqualObjects(@"hank", row[@"text_value"]);
  XCTAssertEqualObjects(@"12", row[@"int_value"]);
  XCTAssertEqualObjects(@"1", row[@"is_null"]);

  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  BOOL prepared = [connection prepareStatementNamed:@"phase3f_select"
                                                sql:@"SELECT $1::text AS token, $2::int * 2 AS doubled"
                                     parameterCount:2
                                              error:&error];
  XCTAssertTrue(prepared);
  XCTAssertNil(error);

  NSArray *preparedRows = [connection executePreparedQueryNamed:@"phase3f_select"
                                                     parameters:@[ @"select-ok", @21 ]
                                                          error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [preparedRows count]);
  NSDictionary *preparedRow = [preparedRows firstObject];
  XCTAssertEqualObjects(@"select-ok", preparedRow[@"token"]);
  XCTAssertEqualObjects(@"42", preparedRow[@"doubled"]);

  [database releaseConnection:connection];
}

- (void)testQueryErrorsIncludeSQLStateDiagnostics {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  NSArray *rows =
      [database executeQuery:@"SELECT * FROM phase3f_missing_table"
                  parameters:@[]
                       error:&error];
  XCTAssertNil(rows);
  XCTAssertNotNil(error);

  NSString *sqlState = [error.userInfo[ALNPgErrorSQLStateKey] isKindOfClass:[NSString class]]
                           ? error.userInfo[ALNPgErrorSQLStateKey]
                           : @"";
  XCTAssertEqual((NSUInteger)5, [sqlState length]);
  XCTAssertNotNil(error.userInfo[ALNPgErrorDiagnosticsKey]);
}

- (void)testMigrationRunnerAppliesPendingFiles {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(database);
  if (database == nil) {
    return;
  }

  NSString *table = [self uniqueNameWithPrefix:@"arlen_mig_test"];
  NSString *root = [self createTempDirectory];
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }

  NSString *migrationsDir = [root stringByAppendingPathComponent:@"db/migrations"];
  NSError *fsError = nil;
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:migrationsDir
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&fsError]);
  XCTAssertNil(fsError);

  NSString *file1 =
      [migrationsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"2026021801_create_%@.sql",
                                                                               table]];
  NSString *file2 =
      [migrationsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"2026021802_seed_%@.sql",
                                                                               table]];
  NSString *createMigration =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, name TEXT)", table];
  XCTAssertTrue([createMigration writeToFile:file1
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:&fsError]);
  XCTAssertNil(fsError);
  NSString *seedMigration =
      [NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES ('dale')", table];
  XCTAssertTrue([seedMigration writeToFile:file2
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&fsError]);
  XCTAssertNil(fsError);

  NSArray *applied = nil;
  XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrationsDir
                                                 database:database
                                                   dryRun:NO
                                             appliedFiles:&applied
                                                    error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [applied count]);

  NSArray *none = nil;
  XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrationsDir
                                                 database:database
                                                   dryRun:NO
                                             appliedFiles:&none
                                                    error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)0, [none count]);

  NSDictionary *countRow = [[database executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@",
                                                                             table]
                                        parameters:@[]
                                             error:&error] firstObject];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"1", countRow[@"count"]);

  (void)[database executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                      parameters:@[]
                           error:nil];
}

@end
