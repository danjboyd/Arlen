#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPostgresSQLBuilder.h"
#import "ALNSQLBuilder.h"

@interface Phase3GTests : XCTestCase
@end

@implementation Phase3GTests

- (void)testNestedBooleanAndExpandedPredicatesSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users"
                                             columns:@[ @"id", @"name" ]];

  [builder whereAnyGroup:^(ALNSQLBuilder *group) {
    [group whereField:@"status" equals:@"active"];
    [group whereAllGroup:^(ALNSQLBuilder *nested) {
      [nested whereField:@"role" equals:@"admin"];
      [nested whereFieldNotIn:@"id" values:@[ @1, @2 ]];
    }];
  }];
  [builder whereField:@"created_at"
         betweenLower:@"2026-01-01"
                upper:@"2026-12-31"];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"SELECT \"id\", \"name\" FROM \"users\" WHERE (\"status\" = $1 OR (\"role\" = $2 AND \"id\" NOT IN ($3, $4))) AND \"created_at\" BETWEEN $5 AND $6",
      built[@"sql"]);
  NSArray *expectedParams = @[ @"active", @"admin", @1, @2, @"2026-01-01", @"2026-12-31" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testCTEJoinGroupHavingAndSubqueryCompositionSnapshot {
  ALNSQLBuilder *recentUsers = [ALNSQLBuilder selectFrom:@"events"
                                                 columns:@[ @"user_id" ]];
  [recentUsers whereField:@"tenant_id" equals:@44];
  [recentUsers groupByField:@"user_id"];

  ALNSQLBuilder *severeEvents = [ALNSQLBuilder selectFrom:@"audit_log"
                                                  columns:@[ @"user_id" ]];
  [severeEvents whereField:@"severity" operator:@">=" value:@3];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users"
                                               alias:@"u"
                                             columns:@[ @"u.id", @"u.name" ]];
  [builder withCTE:@"recent_users" builder:recentUsers];
  [builder joinTable:@"recent_users"
               alias:@"ru"
         onLeftField:@"u.id"
            operator:@"="
        onRightField:@"ru.user_id"];
  [builder leftJoinTable:@"profiles"
                   alias:@"p"
             onLeftField:@"u.id"
                operator:@"="
            onRightField:@"p.user_id"];
  [builder whereField:@"u.tenant_id" equals:@44];
  [builder whereField:@"u.id" inSubquery:severeEvents];
  [builder groupByFields:@[ @"u.id", @"u.name" ]];
  [builder havingField:@"u.id" operator:@">" value:@0];
  [builder orderByField:@"u.id" descending:NO];
  [builder limit:10];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"WITH \"recent_users\" AS (SELECT \"user_id\" FROM \"events\" WHERE \"tenant_id\" = $1 GROUP BY \"user_id\") SELECT \"u\".\"id\", \"u\".\"name\" FROM \"users\" AS \"u\" INNER JOIN \"recent_users\" AS \"ru\" ON \"u\".\"id\" = \"ru\".\"user_id\" LEFT JOIN \"profiles\" AS \"p\" ON \"u\".\"id\" = \"p\".\"user_id\" WHERE \"u\".\"tenant_id\" = $2 AND \"u\".\"id\" IN (SELECT \"user_id\" FROM \"audit_log\" WHERE \"severity\" >= $3) GROUP BY \"u\".\"id\", \"u\".\"name\" HAVING \"u\".\"id\" > $4 ORDER BY \"u\".\"id\" ASC LIMIT 10",
      built[@"sql"]);
  NSArray *expectedParams = @[ @44, @44, @3, @0 ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testReturningSnapshotForDML {
  NSError *error = nil;

  ALNSQLBuilder *insert = [ALNSQLBuilder insertInto:@"users"
                                             values:@{
                                               @"name" : @"hank",
                                               @"role" : @"admin",
                                             }];
  [insert returningFields:@[ @"id", @"name" ]];
  NSDictionary *insertBuilt = [insert build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(insertBuilt);
  XCTAssertEqualObjects(
      @"INSERT INTO \"users\" (\"name\", \"role\") VALUES ($1, $2) RETURNING \"id\", \"name\"",
      insertBuilt[@"sql"]);
  NSArray *expectedInsertParams = @[ @"hank", @"admin" ];
  XCTAssertEqualObjects(expectedInsertParams, insertBuilt[@"parameters"]);

  ALNSQLBuilder *update = [ALNSQLBuilder updateTable:@"users"
                                              values:@{
                                                @"name" : @"dale",
                                              }];
  [update whereField:@"id" equals:@9];
  [update returningField:@"id"];
  NSDictionary *updateBuilt = [update build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(updateBuilt);
  XCTAssertEqualObjects(
      @"UPDATE \"users\" SET \"name\" = $1 WHERE \"id\" = $2 RETURNING \"id\"",
      updateBuilt[@"sql"]);
  NSArray *expectedUpdateParams = @[ @"dale", @9 ];
  XCTAssertEqualObjects(expectedUpdateParams, updateBuilt[@"parameters"]);

  ALNSQLBuilder *deleteBuilder = [ALNSQLBuilder deleteFrom:@"users"];
  [deleteBuilder whereField:@"role" equals:@"guest"];
  [deleteBuilder returningField:@"*"];
  NSDictionary *deleteBuilt = [deleteBuilder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(deleteBuilt);
  XCTAssertEqualObjects(
      @"DELETE FROM \"users\" WHERE \"role\" = $1 RETURNING *",
      deleteBuilt[@"sql"]);
  NSArray *expectedDeleteParams = @[ @"guest" ];
  XCTAssertEqualObjects(expectedDeleteParams, deleteBuilt[@"parameters"]);
}

- (void)testSelectExpressionColumnsWithAliasesAndParameterShiftingSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                               alias:@"d"
                                             columns:@[ @"d.document_id" ]];
  [builder selectExpression:@"COALESCE(d.title, $1)"
                      alias:@"display_title"
                 parameters:@[ @"untitled" ]];
  [builder selectExpression:@"CASE WHEN d.is_active THEN $1 ELSE $2 END"
                      alias:@"state_label"
                 parameters:@[ @"active", @"inactive" ]];
  [builder selectExpression:@"d.updated_at::text" alias:@"updated_at_text" parameters:nil];
  [builder selectExpression:@"jsonb_object_agg(d.meta_key, d.meta_value)"
                      alias:@"meta_payload"
                 parameters:nil];
  [builder whereField:@"d.state_code" equals:@"TX"];
  [builder groupByField:@"d.document_id"];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"SELECT \"d\".\"document_id\", COALESCE(d.title, $1) AS \"display_title\", CASE WHEN d.is_active THEN $2 ELSE $3 END AS \"state_label\", d.updated_at::text AS \"updated_at_text\", jsonb_object_agg(d.meta_key, d.meta_value) AS \"meta_payload\" FROM \"documents\" AS \"d\" WHERE \"d\".\"state_code\" = $4 GROUP BY \"d\".\"document_id\"",
      built[@"sql"]);
  NSArray *expectedParams = @[ @"untitled", @"active", @"inactive", @"TX" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testExpressionAwareOrderingSupportsNullsAndParameterizedExpressionsSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                             columns:@[ @"id", @"priority", @"updated_at", @"created_at" ]];
  [builder orderByField:@"priority" descending:YES nulls:@"last"];
  [builder orderByExpression:@"COALESCE(updated_at, created_at)"
                  descending:NO
                       nulls:@"first"];
  [builder orderByExpression:@"COALESCE(rank, $1)"
                  descending:NO
                       nulls:nil
                  parameters:@[ @0 ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"SELECT \"id\", \"priority\", \"updated_at\", \"created_at\" FROM \"documents\" ORDER BY \"priority\" DESC NULLS LAST, COALESCE(updated_at, created_at) ASC NULLS FIRST, COALESCE(rank, $1) ASC",
      built[@"sql"]);
  NSArray *expectedParams = @[ @0 ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testSubqueryAndLateralJoinCompositionSnapshot {
  ALNSQLBuilder *recentDocs = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"docket_id" ]];
  [recentDocs whereField:@"state_code" equals:@"TX"];

  ALNSQLBuilder *latestEvent = [ALNSQLBuilder selectFrom:@"events" columns:@[ @"event_id" ]];
  [latestEvent whereExpression:@"events.docket_id = d.id" parameters:nil];
  [latestEvent orderByField:@"created_at" descending:YES];
  [latestEvent limit:1];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"dockets"
                                               alias:@"d"
                                             columns:@[ @"d.id", @"d.state_code" ]];
  [builder leftJoinSubquery:recentDocs
                      alias:@"rd"
               onExpression:@"d.id = rd.docket_id AND rd.rank >= $1"
                 parameters:@[ @0 ]];
  [builder leftJoinLateralSubquery:latestEvent
                             alias:@"le"
                      onExpression:@"TRUE"
                        parameters:nil];
  [builder whereField:@"d.state_code" equals:@"TX"];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"SELECT \"d\".\"id\", \"d\".\"state_code\" FROM \"dockets\" AS \"d\" LEFT JOIN (SELECT \"docket_id\" FROM \"documents\" WHERE \"state_code\" = $1) AS \"rd\" ON d.id = rd.docket_id AND rd.rank >= $2 LEFT JOIN LATERAL (SELECT \"event_id\" FROM \"events\" WHERE (events.docket_id = d.id) ORDER BY \"created_at\" DESC LIMIT 1) AS \"le\" ON TRUE WHERE \"d\".\"state_code\" = $3",
      built[@"sql"]);
  NSArray *expectedParams = @[ @"TX", @0, @"TX" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testCompositeTuplePredicateWithExpressionSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                             columns:@[ @"document_id", @"manifest_order" ]];
  [builder whereExpression:@"(COALESCE(manifest_order, 0), document_id) > ($1, $2)"
                parameters:@[ @8, @"doc-002" ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"SELECT \"document_id\", \"manifest_order\" FROM \"documents\" WHERE ((COALESCE(manifest_order, 0), document_id) > ($1, $2))",
      built[@"sql"]);
  NSArray *expectedParams = @[ @8, @"doc-002" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testPostgresConflictUpsertDialectSnapshots {
  NSError *error = nil;

  ALNPostgresSQLBuilder *doNothing =
      [ALNPostgresSQLBuilder insertInto:@"users"
                                 values:@{
                                   @"id" : @1,
                                   @"name" : @"hank",
                                 }];
  [doNothing onConflictDoNothing];
  NSDictionary *doNothingBuilt = [doNothing build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(doNothingBuilt);
  XCTAssertEqualObjects(
      @"INSERT INTO \"users\" (\"id\", \"name\") VALUES ($1, $2) ON CONFLICT DO NOTHING",
      doNothingBuilt[@"sql"]);
  NSArray *expectedDoNothingParams = @[ @1, @"hank" ];
  XCTAssertEqualObjects(expectedDoNothingParams, doNothingBuilt[@"parameters"]);

  ALNPostgresSQLBuilder *upsert =
      [ALNPostgresSQLBuilder insertInto:@"users"
                                 values:@{
                                   @"id" : @7,
                                   @"name" : @"Peggy",
                                 }];
  [[upsert onConflictColumns:@[ @"id" ] doUpdateSetFields:@[ @"name" ]]
      returningField:@"id"];
  NSDictionary *upsertBuilt = [upsert build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(upsertBuilt);
  XCTAssertEqualObjects(
      @"INSERT INTO \"users\" (\"id\", \"name\") VALUES ($1, $2) ON CONFLICT (\"id\") DO UPDATE SET \"name\" = EXCLUDED.\"name\" RETURNING \"id\"",
      upsertBuilt[@"sql"]);
  NSArray *expectedUpsertParams = @[ @7, @"Peggy" ];
  XCTAssertEqualObjects(expectedUpsertParams, upsertBuilt[@"parameters"]);
}

- (void)testPostgresConflictUpsertAdvancedAssignmentExpressionsSnapshot {
  NSError *error = nil;
  ALNPostgresSQLBuilder *upsert =
      [ALNPostgresSQLBuilder insertInto:@"queue_jobs"
                                 values:@{
                                   @"attempt_count" : @0,
                                   @"id" : @9,
                                   @"state" : @"queued",
                                   @"updated_at" : @"2026-01-01T00:00:00Z",
                                 }];
  [upsert onConflictColumns:@[ @"id" ]
        doUpdateAssignments:@{
          @"attempt_count" : @{
            @"expression" : @"\"queue_jobs\".\"attempt_count\" + $1",
            @"parameters" : @[ @1 ],
          },
          @"state" : @"EXCLUDED.state",
          @"updated_at" : @{
            @"expression" : @"GREATEST(\"queue_jobs\".\"updated_at\", EXCLUDED.\"updated_at\", $1::text)",
            @"parameters" : @[ @"2026-01-02T00:00:00Z" ],
          },
        }];
  [upsert onConflictDoUpdateWhereExpression:@"\"queue_jobs\".\"state\" <> $1"
                                 parameters:@[ @"done" ]];
  [upsert returningField:@"id"];

  NSDictionary *built = [upsert build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"INSERT INTO \"queue_jobs\" (\"attempt_count\", \"id\", \"state\", \"updated_at\") VALUES ($1, $2, $3, $4) ON CONFLICT (\"id\") DO UPDATE SET \"attempt_count\" = \"queue_jobs\".\"attempt_count\" + $5, \"state\" = EXCLUDED.state, \"updated_at\" = GREATEST(\"queue_jobs\".\"updated_at\", EXCLUDED.\"updated_at\", $6::text) WHERE \"queue_jobs\".\"state\" <> $7 RETURNING \"id\"",
      built[@"sql"]);
  NSArray *expectedParams = @[ @0, @9, @"queued", @"2026-01-01T00:00:00Z", @1, @"2026-01-02T00:00:00Z", @"done" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testPostgresConflictRejectedForNonInsert {
  ALNPostgresSQLBuilder *builder =
      [ALNPostgresSQLBuilder updateTable:@"users"
                                  values:@{
                                    @"name" : @"bobby",
                                  }];
  [builder onConflictDoNothing];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

@end
