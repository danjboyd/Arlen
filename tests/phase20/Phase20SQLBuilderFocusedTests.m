#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDataTestAssertions.h"
#import "ALNMSSQLDialect.h"
#import "ALNSQLBuilder.h"

@interface Phase20SQLBuilderFocusedTests : XCTestCase
@end

@implementation Phase20SQLBuilderFocusedTests

- (void)testMSSQLDialectCompilesPaginationAndOutputReturningContracts {
  NSError *error = nil;

  ALNSQLBuilder *selectBuilder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id", @"name" ]];
  [[selectBuilder orderByField:@"id" descending:NO] limit:10];
  [selectBuilder offset:5];
  NSDictionary *selectBuilt = [selectBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  ALNAssertBuiltSQLAndParameters(
      selectBuilt,
      @"SELECT [id], [name] FROM [users] ORDER BY [id] ASC OFFSET 5 ROWS FETCH NEXT 10 ROWS ONLY",
      (@[]));

  ALNSQLBuilder *insertBuilder = [[ALNSQLBuilder insertInto:@"users"
                                                     values:@{ @"name" : @"hank" }]
      returningField:@"id"];
  NSDictionary *insertBuilt = [insertBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  ALNAssertBuiltSQLAndParameters(insertBuilt,
                                 @"INSERT INTO [users] ([name]) OUTPUT INSERTED.[id] VALUES (?)",
                                 (@[ @"hank" ]));

  ALNSQLBuilder *updateBuilder = [[ALNSQLBuilder updateTable:@"users"
                                                      values:@{ @"name" : @"dale" }]
      returningField:@"id"];
  [updateBuilder whereField:@"id" equals:@7];
  NSDictionary *updateBuilt = [updateBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(error);
  ALNAssertBuiltSQLAndParameters(
      updateBuilt,
      @"UPDATE [users] SET [name] = ? OUTPUT INSERTED.[id] WHERE [id] = ?",
      (@[ @"dale", @7 ]));
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
  ALNAssertBuiltSQLAndParameters(
      built,
      @"SELECT [id] FROM [users] WHERE [id] IN (SELECT [user_id] FROM [events] ORDER BY [created_at] DESC OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY)",
      (@[]));
}

- (void)testMSSQLDialectRejectsUnsupportedFeaturesWithSharedDiagnosticsAssertions {
  NSError *error = nil;
  ALNSQLBuilder *paginationWithoutOrder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]];
  [paginationWithoutOrder limit:5];
  NSDictionary *built =
      [paginationWithoutOrder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  ALNAssertErrorDetails(error, ALNSQLBuilderErrorDomain, NSNotFound, @"requires an explicit ORDER BY");

  error = nil;
  ALNSQLBuilder *lockBuilder = [[ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]] forUpdate];
  built = [lockBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  ALNAssertErrorDetails(error, ALNSQLBuilderErrorDomain, NSNotFound, @"FOR UPDATE");

  error = nil;
  ALNSQLBuilder *subquery = [ALNSQLBuilder selectFrom:@"events" columns:@[ @"user_id" ]];
  [subquery whereField:@"title" operator:@"ilike" value:@"%ops%"];

  ALNSQLBuilder *nestedBuilder = [ALNSQLBuilder selectFrom:@"users" columns:@[ @"id" ]];
  [nestedBuilder whereField:@"id" inSubquery:subquery];
  built = [nestedBuilder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:&error];
  XCTAssertNil(built);
  ALNAssertErrorDetails(error, ALNSQLBuilderErrorDomain, NSNotFound, @"ILIKE");
}

@end
