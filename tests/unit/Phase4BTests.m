#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNSQLBuilder.h"

@interface Phase4BTests : XCTestCase
@end

@implementation Phase4BTests

- (void)testSetOperationsSnapshot {
  ALNSQLBuilder *active = [ALNSQLBuilder selectFrom:@"active_docs" columns:@[ @"doc_id" ]];
  [active whereField:@"state_code" equals:@"TX"];

  ALNSQLBuilder *archived = [ALNSQLBuilder selectFrom:@"archived_docs" columns:@[ @"doc_id" ]];
  [archived whereField:@"state_code" equals:@"TX"];

  ALNSQLBuilder *blocked = [ALNSQLBuilder selectFrom:@"blocked_docs" columns:@[ @"doc_id" ]];
  [blocked whereField:@"block_flag" equals:@1];

  [[active unionAllWith:archived] exceptWith:blocked];

  NSError *error = nil;
  NSDictionary *built = [active build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"(SELECT \"doc_id\" FROM \"active_docs\" WHERE \"state_code\" = $1) UNION ALL (SELECT \"doc_id\" FROM \"archived_docs\" WHERE \"state_code\" = $2) EXCEPT (SELECT \"doc_id\" FROM \"blocked_docs\" WHERE \"block_flag\" = $3)",
                        built[@"sql"]);
  NSArray *expectedParams = @[ @"TX", @"TX", @1 ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testNamedWindowClauseSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"scores"
                                               alias:@"s"
                                             columns:@[ @"s.user_id" ]];
  [builder selectExpression:@"ROW_NUMBER() OVER {{w}}"
                      alias:@"row_num"
         identifierBindings:@{ @"w" : @"w_rank" }
                 parameters:nil];
  [builder windowNamed:@"w_rank"
            expression:@"PARTITION BY {{team_col}} ORDER BY {{score_col}} DESC"
   identifierBindings:@{
     @"team_col" : @"s.team_id",
     @"score_col" : @"s.score",
   }
            parameters:nil];
  [builder orderByField:@"s.user_id" descending:NO nulls:nil];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"s\".\"user_id\", ROW_NUMBER() OVER \"w_rank\" AS \"row_num\" FROM \"scores\" AS \"s\" WINDOW \"w_rank\" AS (PARTITION BY \"s\".\"team_id\" ORDER BY \"s\".\"score\" DESC) ORDER BY \"s\".\"user_id\" ASC",
                        built[@"sql"]);
  XCTAssertEqualObjects(@[], built[@"parameters"]);
}

- (void)testExistsAnyAllPredicateSnapshot {
  ALNSQLBuilder *eventProbe = [ALNSQLBuilder selectFrom:@"events"
                                                  alias:@"e"
                                                columns:@[ @"e.id" ]];
  [eventProbe whereExpression:@"e.user_id = u.id" parameters:nil];

  ALNSQLBuilder *anyThreshold = [ALNSQLBuilder selectFrom:@"thresholds" columns:@[ @"value" ]];
  [anyThreshold whereField:@"category" equals:@"risk"];

  ALNSQLBuilder *allMinimums = [ALNSQLBuilder selectFrom:@"minima" columns:@[ @"min_score" ]];
  [allMinimums whereField:@"enabled" equals:@1];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users"
                                               alias:@"u"
                                             columns:@[ @"u.id" ]];
  [builder whereExistsSubquery:eventProbe];
  [builder whereField:@"u.score" operator:@">=" anySubquery:anyThreshold];
  [builder whereField:@"u.score" operator:@">=" allSubquery:allMinimums];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"u\".\"id\" FROM \"users\" AS \"u\" WHERE EXISTS (SELECT \"e\".\"id\" FROM \"events\" AS \"e\" WHERE (e.user_id = u.id)) AND \"u\".\"score\" >= ANY (SELECT \"value\" FROM \"thresholds\" WHERE \"category\" = $1) AND \"u\".\"score\" >= ALL (SELECT \"min_score\" FROM \"minima\" WHERE \"enabled\" = $2)",
                        built[@"sql"]);
  NSArray *expectedParams = @[ @"risk", @1 ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testJoinSurfaceCompletionSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users"
                                               alias:@"u"
                                             columns:@[ @"u.id", @"p.user_id", @"r.id", @"t.kind" ]];
  [builder joinTable:@"profiles" alias:@"p" usingFields:@[ @"user_id" ]];
  [builder fullJoinTable:@"roles"
                   alias:@"r"
             onLeftField:@"u.role_id"
                operator:@"="
            onRightField:@"r.id"];
  [builder crossJoinTable:@"tenants" alias:@"t"];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"u\".\"id\", \"p\".\"user_id\", \"r\".\"id\", \"t\".\"kind\" FROM \"users\" AS \"u\" INNER JOIN \"profiles\" AS \"p\" USING (\"user_id\") FULL JOIN \"roles\" AS \"r\" ON \"u\".\"role_id\" = \"r\".\"id\" CROSS JOIN \"tenants\" AS \"t\"",
                        built[@"sql"]);
  XCTAssertEqualObjects(@[], built[@"parameters"]);
}

- (void)testFullJoinSubquerySnapshot {
  ALNSQLBuilder *auditSubquery = [ALNSQLBuilder selectFrom:@"audit" columns:@[ @"user_id" ]];
  [auditSubquery whereField:@"severity" operator:@">=" value:@2];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users"
                                               alias:@"u"
                                             columns:@[ @"u.id" ]];
  [builder fullJoinSubquery:auditSubquery
                      alias:@"a"
               onExpression:@"a.user_id = u.id"
                 parameters:nil];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"u\".\"id\" FROM \"users\" AS \"u\" FULL JOIN (SELECT \"user_id\" FROM \"audit\" WHERE \"severity\" >= $1) AS \"a\" ON a.user_id = u.id",
                        built[@"sql"]);
  NSArray *expectedParams = @[ @2 ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testCTEColumnsAndRecursiveSnapshot {
  ALNSQLBuilder *recent = [ALNSQLBuilder selectFrom:@"events" columns:@[ @"user_id" ]];
  [recent whereField:@"state" equals:@"ready"];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"recent_ids"
                                             columns:@[ @"recent_ids.user_id" ]];
  [builder withRecursiveCTE:@"recent_ids" columns:@[ @"user_id" ] builder:recent];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"WITH RECURSIVE \"recent_ids\" (\"user_id\") AS (SELECT \"user_id\" FROM \"events\" WHERE \"state\" = $1) SELECT \"recent_ids\".\"user_id\" FROM \"recent_ids\"",
                        built[@"sql"]);
  NSArray *expectedParams = @[ @"ready" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testForUpdateSkipLockedSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"jobs"
                                               alias:@"j"
                                             columns:@[ @"j.id" ]];
  [builder whereField:@"j.state" equals:@"queued"];
  [builder orderByField:@"j.id" descending:NO nulls:nil];
  [builder limit:5];
  [builder forUpdateOfTables:@[ @"j" ]];
  [builder skipLocked];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"j\".\"id\" FROM \"jobs\" AS \"j\" WHERE \"j\".\"state\" = $1 ORDER BY \"j\".\"id\" ASC LIMIT 5 FOR UPDATE OF \"j\" SKIP LOCKED",
                        built[@"sql"]);
  NSArray *expectedParams = @[ @"queued" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testSkipLockedRequiresForUpdate {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"jobs" columns:@[ @"id" ]];
  [builder skipLocked];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

- (void)testSetOperationRejectedForNonSelectBuilders {
  ALNSQLBuilder *builder = [ALNSQLBuilder updateTable:@"jobs" values:@{ @"state" : @"done" }];
  ALNSQLBuilder *other = [ALNSQLBuilder selectFrom:@"jobs_archive" columns:@[ @"id" ]];
  [builder unionWith:other];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

@end
