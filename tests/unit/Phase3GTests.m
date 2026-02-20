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
