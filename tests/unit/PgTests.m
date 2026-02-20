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

- (void)testLongProjectionParameterizedSelectPreservesUTF8Parameters {
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

  NSString *table = [self uniqueNameWithPrefix:@"arlen_pg_long_select"];
  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  NSString *createSQL = [NSString stringWithFormat:
                                       @"CREATE TABLE %@("
                                        "state_code TEXT NOT NULL, "
                                        "docket_id TEXT NOT NULL, "
                                        "document_id TEXT NOT NULL, "
                                        "filename TEXT NOT NULL, "
                                        "doc_type TEXT NOT NULL, "
                                        "file_date TEXT NOT NULL, "
                                        "fetched_at TEXT NOT NULL, "
                                        "source_url TEXT NOT NULL, "
                                        "content_type TEXT NOT NULL, "
                                        "size_bytes INTEGER NOT NULL, "
                                        "pdf_sha256 TEXT NOT NULL, "
                                        "pdf_path TEXT NOT NULL, "
                                        "ocr_strategy TEXT NOT NULL, "
                                        "ocr_engine TEXT NOT NULL, "
                                        "ocr_language TEXT NOT NULL, "
                                        "ocr_extracted_at TEXT NOT NULL, "
                                        "ocr_text_sha256 TEXT NOT NULL, "
                                        "text_path TEXT NOT NULL, "
                                        "respondent_count INTEGER NOT NULL, "
                                        "respondent_extracted_at TEXT NOT NULL, "
                                        "respondent_extractor_version TEXT NOT NULL, "
                                        "respondent_has_llm_vision INTEGER NOT NULL, "
                                        "manifest_order INTEGER NOT NULL, "
                                        "created_at TEXT NOT NULL, "
                                        "updated_at TEXT NOT NULL, "
                                        "is_active INTEGER NOT NULL"
                                        ")",
                                       table];
  XCTAssertGreaterThanOrEqual([connection executeCommand:createSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);

  NSString *stateCode = @"ZZ";
  NSString *docketID = @"CD_2024-000001_ñ";
  NSString *documentID =
      [NSString stringWithFormat:@"DOC_%@_%@", [self uniqueNameWithPrefix:@"fixture"], @"abcdef0123456789"];

  NSString *insertSQL = [NSString stringWithFormat:
                                       @"INSERT INTO %@ "
                                        "(state_code, docket_id, document_id, filename, doc_type, file_date, "
                                        "fetched_at, source_url, content_type, size_bytes, pdf_sha256, pdf_path, "
                                        "ocr_strategy, ocr_engine, ocr_language, ocr_extracted_at, ocr_text_sha256, text_path, "
                                        "respondent_count, respondent_extracted_at, respondent_extractor_version, "
                                        "respondent_has_llm_vision, manifest_order, created_at, updated_at, is_active) "
                                        "VALUES "
                                        "($1, $2, $3, $4, $5, $6, "
                                        "$7, $8, $9, $10, $11, $12, "
                                        "$13, $14, $15, $16, $17, $18, "
                                        "$19, $20, $21, $22, $23, $24, $25, $26)",
                                       table];
  NSArray *insertParams = @[
    stateCode,
    docketID,
    documentID,
    @"fixture.pdf",
    @"order",
    @"2024-01-03",
    @"2024-01-03T00:00:00Z",
    @"https://example.invalid/doc.pdf",
    @"application/pdf",
    @1234,
    @"sha256-fixture",
    @"/tmp/doc.pdf",
    @"tesseract",
    @"tesseract5",
    @"en",
    @"2024-01-03T00:00:10Z",
    @"sha256-text",
    @"/tmp/doc.txt",
    @2,
    @"2024-01-03T00:00:20Z",
    @"extractor-v1",
    @0,
    @1,
    @"2024-01-03T00:00:30Z",
    @"2024-01-03T00:00:40Z",
    @1,
  ];
  XCTAssertEqual((NSInteger)1, [connection executeCommand:insertSQL parameters:insertParams error:&error]);
  XCTAssertNil(error);

  NSString *selectSQL = [NSString stringWithFormat:
                                       @"SELECT \"state_code\", \"docket_id\", \"document_id\", \"filename\", "
                                        "\"doc_type\", \"file_date\", \"fetched_at\", \"source_url\", "
                                        "\"content_type\", \"size_bytes\", \"pdf_sha256\", \"pdf_path\", "
                                        "\"ocr_strategy\", \"ocr_engine\", \"ocr_language\", \"ocr_extracted_at\", "
                                        "\"ocr_text_sha256\", \"text_path\", \"respondent_count\", "
                                        "\"respondent_extracted_at\", \"respondent_extractor_version\", "
                                        "\"respondent_has_llm_vision\", \"manifest_order\", \"created_at\", "
                                        "\"updated_at\", \"is_active\" "
                                        "FROM \"%@\" "
                                        "WHERE \"state_code\" = $1 AND \"docket_id\" = $2 AND \"document_id\" = $3",
                                       table];
  NSArray *queryParams = @[ stateCode, docketID, documentID ];

  for (NSInteger idx = 0; idx < 120; idx++) {
    NSArray *rows = [connection executeQuery:selectSQL parameters:queryParams error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)1, [rows count]);
    NSDictionary *row = [rows firstObject];
    XCTAssertEqualObjects(stateCode, row[@"state_code"]);
    XCTAssertEqualObjects(docketID, row[@"docket_id"]);
    XCTAssertEqualObjects(documentID, row[@"document_id"]);
  }

  NSString *preparedName = [self uniqueNameWithPrefix:@"arlen_long_select"];
  BOOL prepared = [connection prepareStatementNamed:preparedName
                                                sql:selectSQL
                                     parameterCount:3
                                              error:&error];
  XCTAssertTrue(prepared);
  XCTAssertNil(error);

  for (NSInteger idx = 0; idx < 120; idx++) {
    NSArray *rows = [connection executePreparedQueryNamed:preparedName
                                               parameters:queryParams
                                                    error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)1, [rows count]);
    NSDictionary *row = [rows firstObject];
    XCTAssertEqualObjects(stateCode, row[@"state_code"]);
    XCTAssertEqualObjects(docketID, row[@"docket_id"]);
    XCTAssertEqualObjects(documentID, row[@"document_id"]);
  }

  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                        parameters:@[]
                             error:nil];
  [database releaseConnection:connection];
}

- (void)testPreparedCommandUTF8ParameterStressRemainsStable {
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

  NSString *table = [self uniqueNameWithPrefix:@"arlen_pg_utf8_stress"];
  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  NSString *createSQL =
      [NSString stringWithFormat:@"CREATE TABLE %@ (id SERIAL PRIMARY KEY, token TEXT NOT NULL, note TEXT NOT NULL)",
                                 table];
  XCTAssertGreaterThanOrEqual([connection executeCommand:createSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);

  NSString *insertSQL = [NSString stringWithFormat:@"INSERT INTO %@ (token, note) VALUES ($1, $2)", table];
  NSString *insertName = [self uniqueNameWithPrefix:@"arlen_utf8_insert"];
  BOOL insertPrepared = [connection prepareStatementNamed:insertName
                                                      sql:insertSQL
                                           parameterCount:2
                                                    error:&error];
  XCTAssertTrue(insertPrepared);
  XCTAssertNil(error);

  NSInteger total = 180;
  NSMutableArray *tokens = [NSMutableArray arrayWithCapacity:(NSUInteger)total];
  for (NSInteger idx = 0; idx < total; idx++) {
    NSString *token = [NSString stringWithFormat:@"tok-%03ld-ñ-Ω-漢字", (long)idx];
    NSMutableString *note = [NSMutableString stringWithCapacity:256];
    [note appendFormat:@"note-%03ld-", (long)idx];
    for (NSInteger rep = 0; rep < 8; rep++) {
      [note appendString:@"αλφα-ñ-漢字-"];
    }
    [tokens addObject:token];

    NSInteger affected = [connection executePreparedCommandNamed:insertName
                                                      parameters:@[ token, note ]
                                                           error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSInteger)1, affected);
  }

  NSDictionary *countRow = [connection executeQueryOne:[NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@", table]
                                            parameters:@[]
                                                 error:&error];
  XCTAssertNil(error);
  NSString *expectedCount = [NSString stringWithFormat:@"%ld", (long)total];
  XCTAssertEqualObjects(expectedCount, countRow[@"count"]);

  NSString *probeSQL = [NSString stringWithFormat:@"SELECT token, note FROM %@ WHERE token = $1", table];
  NSString *probeName = [self uniqueNameWithPrefix:@"arlen_utf8_probe"];
  BOOL probePrepared = [connection prepareStatementNamed:probeName
                                                     sql:probeSQL
                                          parameterCount:1
                                                   error:&error];
  XCTAssertTrue(probePrepared);
  XCTAssertNil(error);

  NSArray *probeIndexes = @[ @0, @53, @179 ];
  for (NSNumber *indexValue in probeIndexes) {
    NSInteger idx = [indexValue integerValue];
    NSString *token = tokens[(NSUInteger)idx];

    NSArray *rows = [connection executeQuery:probeSQL parameters:@[ token ] error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)1, [rows count]);
    XCTAssertEqualObjects(token, rows[0][@"token"]);

    NSArray *preparedRows = [connection executePreparedQueryNamed:probeName
                                                       parameters:@[ token ]
                                                            error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)1, [preparedRows count]);
    XCTAssertEqualObjects(token, preparedRows[0][@"token"]);
    XCTAssertTrue([preparedRows[0][@"note"] containsString:@"漢字"]);
  }

  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                        parameters:@[]
                             error:nil];
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
