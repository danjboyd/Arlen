#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNPostgresSQLBuilder.h"
#import "ALNSQLBuilder.h"

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

- (void)testSQLBuilderAdvancedExpressionsAndLateralJoinsExecuteAgainstPostgres {
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

  NSString *docketsTable = [self uniqueNameWithPrefix:@"arlen_pg_dockets"];
  NSString *documentsTable = [self uniqueNameWithPrefix:@"arlen_pg_documents"];
  NSString *eventsTable = [self uniqueNameWithPrefix:@"arlen_pg_events"];

  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  NSString *createDocketsSQL =
      [NSString stringWithFormat:@"CREATE TABLE %@ (id TEXT PRIMARY KEY, state_code TEXT NOT NULL)", docketsTable];
  NSString *createDocumentsSQL = [NSString
      stringWithFormat:@"CREATE TABLE %@ (docket_id TEXT NOT NULL, document_id TEXT NOT NULL, manifest_order INTEGER, title TEXT)",
                       documentsTable];
  NSString *createEventsSQL = [NSString stringWithFormat:
                                           @"CREATE TABLE %@ (docket_id TEXT NOT NULL, event_id TEXT NOT NULL, created_rank INTEGER NOT NULL)",
                                           eventsTable];
  XCTAssertGreaterThanOrEqual([connection executeCommand:createDocketsSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);
  XCTAssertGreaterThanOrEqual([connection executeCommand:createDocumentsSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);
  XCTAssertGreaterThanOrEqual([connection executeCommand:createEventsSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);

  NSString *insertDocketSQL =
      [NSString stringWithFormat:@"INSERT INTO %@ (id, state_code) VALUES ($1, $2)", docketsTable];
  NSInteger insertedDocket =
      [connection executeCommand:insertDocketSQL parameters:@[ @"d1", @"TX" ] error:&error];
  XCTAssertEqual((NSInteger)1, insertedDocket);
  XCTAssertNil(error);
  insertedDocket = [connection executeCommand:insertDocketSQL parameters:@[ @"d2", @"TX" ] error:&error];
  XCTAssertEqual((NSInteger)1, insertedDocket);
  XCTAssertNil(error);

  NSArray *documentRows = @[
    @[ @"d1", @"doc-a", @1, @"alpha" ],
    @[ @"d1", @"doc-b", @2, [NSNull null] ],
    @[ @"d2", @"doc-c", @3, @"charlie" ],
  ];
  NSString *insertDocumentSQL = [NSString stringWithFormat:
                                               @"INSERT INTO %@ (docket_id, document_id, manifest_order, title) "
                                                "VALUES ($1, $2, $3, $4)",
                                               documentsTable];
  for (NSArray *row in documentRows) {
    XCTAssertEqual((NSInteger)1,
                   [connection executeCommand:insertDocumentSQL parameters:row error:&error]);
    XCTAssertNil(error);
  }

  NSArray *eventRows = @[
    @[ @"d1", @"ev-1", @1 ],
    @[ @"d1", @"ev-2", @2 ],
    @[ @"d2", @"ev-3", @1 ],
  ];
  NSString *insertEventSQL =
      [NSString stringWithFormat:@"INSERT INTO %@ (docket_id, event_id, created_rank) VALUES ($1, $2, $3)",
                                 eventsTable];
  for (NSArray *row in eventRows) {
    XCTAssertEqual((NSInteger)1,
                   [connection executeCommand:insertEventSQL parameters:row error:&error]);
    XCTAssertNil(error);
  }

  ALNSQLBuilder *recentDocs = [ALNSQLBuilder selectFrom:documentsTable columns:@[ @"docket_id" ]];
  [recentDocs whereField:@"manifest_order" operator:@">=" value:@1];
  [recentDocs groupByField:@"docket_id"];

  ALNSQLBuilder *latestEvent = [ALNSQLBuilder selectFrom:eventsTable columns:@[ @"event_id" ]];
  [latestEvent whereExpression:@"e.docket_id = d.id" parameters:nil];
  [latestEvent orderByField:@"created_rank" descending:YES];
  [latestEvent limit:1];
  [latestEvent fromAlias:@"e"];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:docketsTable
                                               alias:@"d"
                                             columns:@[ @"d.id" ]];
  [builder selectExpression:@"COALESCE(le.event_id, $1)"
                      alias:@"latest_event"
                 parameters:@[ @"none" ]];
  [builder leftJoinSubquery:recentDocs
                      alias:@"rd"
               onExpression:@"d.id = rd.docket_id"
                 parameters:nil];
  [builder leftJoinLateralSubquery:latestEvent
                             alias:@"le"
                      onExpression:@"TRUE"
                        parameters:nil];
  [builder whereField:@"d.state_code" equals:@"TX"];
  [builder orderByField:@"d.id" descending:NO nulls:nil];

  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  if (built == nil) {
    (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", eventsTable]
                          parameters:@[]
                               error:nil];
    (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", documentsTable]
                          parameters:@[]
                               error:nil];
    (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", docketsTable]
                          parameters:@[]
                               error:nil];
    [database releaseConnection:connection];
    return;
  }

  NSArray *rows = [connection executeQuery:built[@"sql"] parameters:built[@"parameters"] error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [rows count]);
  XCTAssertEqualObjects(@"d1", rows[0][@"id"]);
  XCTAssertEqualObjects(@"ev-2", rows[0][@"latest_event"]);
  XCTAssertEqualObjects(@"d2", rows[1][@"id"]);
  XCTAssertEqualObjects(@"ev-3", rows[1][@"latest_event"]);

  ALNSQLBuilder *cursorBuilder = [ALNSQLBuilder selectFrom:documentsTable
                                                     alias:@"doc"
                                                   columns:@[ @"doc.document_id" ]];
  [cursorBuilder whereExpression:@"(COALESCE(doc.manifest_order, 0), doc.document_id) > ($1, $2)"
                      parameters:@[ @1, @"doc-a" ]];
  [cursorBuilder orderByExpression:@"COALESCE(doc.manifest_order, 0)"
                        descending:NO
                             nulls:@"LAST"];
  [cursorBuilder orderByField:@"doc.document_id" descending:NO nulls:nil];
  NSDictionary *cursorBuilt = [cursorBuilder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(cursorBuilt);
  NSArray *cursorRows =
      [connection executeQuery:cursorBuilt[@"sql"] parameters:cursorBuilt[@"parameters"] error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [cursorRows count]);
  XCTAssertEqualObjects(@"doc-b", cursorRows[0][@"document_id"]);
  XCTAssertEqualObjects(@"doc-c", cursorRows[1][@"document_id"]);

  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", eventsTable]
                        parameters:@[]
                             error:nil];
  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", documentsTable]
                        parameters:@[]
                             error:nil];
  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", docketsTable]
                        parameters:@[]
                             error:nil];
  [database releaseConnection:connection];
}

- (void)testSQLBuilderExpressionTemplatesWithIdentifierBindingsExecuteAgainstPostgres {
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

  NSString *table = [self uniqueNameWithPrefix:@"arlen_pg_expr_template"];
  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  NSString *createSQL = [NSString
      stringWithFormat:@"CREATE TABLE %@ (id TEXT PRIMARY KEY, state_code TEXT NOT NULL, title TEXT, updated_at TEXT, created_at TEXT)",
                       table];
  XCTAssertGreaterThanOrEqual([connection executeCommand:createSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);

  NSString *insertSQL = [NSString
      stringWithFormat:@"INSERT INTO %@ (id, state_code, title, updated_at, created_at) VALUES ($1, $2, $3, $4, $5)",
                       table];
  NSArray *insertParams = @[ @"doc-1", @"TX", @"Texas Notice", @"2026-01-02", @"2026-01-01" ];
  NSInteger inserted = [connection executeCommand:insertSQL parameters:insertParams error:&error];
  XCTAssertEqual((NSInteger)1, inserted);
  XCTAssertNil(error);

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:table
                                               alias:@"d"
                                             columns:@[ @"d.id" ]];
  [builder selectExpression:@"COALESCE({{title_col}}, $1)"
                      alias:@"display_title"
         identifierBindings:@{ @"title_col" : @"d.title" }
                 parameters:@[ @"untitled" ]];
  [builder whereExpression:@"{{state_col}} = $1 AND {{id_col}} = $2"
        identifierBindings:@{
          @"state_col" : @"d.state_code",
          @"id_col" : @"d.id",
        }
                parameters:@[ @"TX", @"doc-1" ]];
  [builder orderByExpression:@"COALESCE({{updated_col}}, {{created_col}})"
                  descending:NO
                       nulls:nil
          identifierBindings:@{
            @"updated_col" : @"d.updated_at",
            @"created_col" : @"d.created_at",
          }
                  parameters:nil];

  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  if (built != nil) {
    NSArray *rows = [connection executeQuery:built[@"sql"] parameters:built[@"parameters"] error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)1, [rows count]);
    XCTAssertEqualObjects(@"doc-1", rows[0][@"id"]);
    XCTAssertEqualObjects(@"Texas Notice", rows[0][@"display_title"]);
  }

  (void)[connection executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                        parameters:@[]
                             error:nil];
  [database releaseConnection:connection];
}

- (void)testPostgresSQLBuilderAdvancedUpsertAssignmentsAndWhereExecute {
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

  NSString *table = [self uniqueNameWithPrefix:@"arlen_pg_upsert_expr"];
  ALNPgConnection *connection = [database acquireConnection:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(connection);
  if (connection == nil) {
    return;
  }

  NSString *createSQL = [NSString stringWithFormat:
                                       @"CREATE TABLE %@ (id TEXT PRIMARY KEY, state TEXT NOT NULL, attempt_count INTEGER NOT NULL, updated_at TEXT NOT NULL)",
                                       table];
  XCTAssertGreaterThanOrEqual([connection executeCommand:createSQL parameters:@[] error:&error], 0);
  XCTAssertNil(error);

  NSString *seedSQL = [NSString stringWithFormat:
                                     @"INSERT INTO %@ (id, state, attempt_count, updated_at) VALUES ($1, $2, $3, $4)",
                                     table];
  NSInteger seeded = [connection executeCommand:seedSQL
                                     parameters:@[ @"job-1", @"running", @2, @"2026-01-01T00:00:00Z" ]
                                          error:&error];
  XCTAssertEqual((NSInteger)1, seeded);
  XCTAssertNil(error);

  ALNPostgresSQLBuilder *upsert =
      [ALNPostgresSQLBuilder insertInto:table
                                 values:@{
                                   @"attempt_count" : @0,
                                   @"id" : @"job-1",
                                   @"state" : @"done",
                                   @"updated_at" : @"2026-01-02T00:00:00Z",
                                 }];
  [upsert onConflictColumns:@[ @"id" ]
        doUpdateAssignments:@{
          @"attempt_count" : @{
            @"expression" : [NSString stringWithFormat:@"\"%@\".\"attempt_count\" + $1", table],
            @"parameters" : @[ @1 ],
          },
          @"state" : @"EXCLUDED.state",
          @"updated_at" : @{
            @"expression" : [NSString stringWithFormat:
                                                @"GREATEST(\"%@\".\"updated_at\", EXCLUDED.\"updated_at\", $1::text)",
                                                table],
            @"parameters" : @[ @"2026-01-03T00:00:00Z" ],
          },
        }];
  [upsert onConflictDoUpdateWhereExpression:[NSString stringWithFormat:@"\"%@\".\"state\" <> $1", table]
                                 parameters:@[ @"done" ]];
  NSDictionary *built = [upsert build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqual((NSInteger)1,
                 [connection executeCommand:built[@"sql"] parameters:built[@"parameters"] error:&error]);
  XCTAssertNil(error);

  NSDictionary *first =
      [connection executeQueryOne:[NSString stringWithFormat:
                                                     @"SELECT state, attempt_count, updated_at FROM %@ WHERE id = $1",
                                                     table]
                        parameters:@[ @"job-1" ]
                             error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"done", first[@"state"]);
  XCTAssertEqualObjects(@"3", first[@"attempt_count"]);
  XCTAssertEqualObjects(@"2026-01-03T00:00:00Z", first[@"updated_at"]);

  NSDictionary *secondBuilt = [upsert build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(secondBuilt);
  XCTAssertEqual((NSInteger)0,
                 [connection executeCommand:secondBuilt[@"sql"]
                                parameters:secondBuilt[@"parameters"]
                                     error:&error]);
  XCTAssertNil(error);

  NSDictionary *second =
      [connection executeQueryOne:[NSString stringWithFormat:
                                                     @"SELECT state, attempt_count, updated_at FROM %@ WHERE id = $1",
                                                     table]
                        parameters:@[ @"job-1" ]
                             error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"done", second[@"state"]);
  XCTAssertEqualObjects(@"3", second[@"attempt_count"]);
  XCTAssertEqualObjects(@"2026-01-03T00:00:00Z", second[@"updated_at"]);

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
