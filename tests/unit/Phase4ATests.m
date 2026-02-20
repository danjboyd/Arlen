#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNSQLBuilder.h"

@interface Phase4ATests : XCTestCase
@end

@implementation Phase4ATests

- (void)testExpressionTemplateIdentifierBindingsAndParameterShiftingSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                               alias:@"d"
                                             columns:@[ @"d.id" ]];
  [builder selectExpression:@"COALESCE({{title_col}}, $1)"
                      alias:@"display_title"
         identifierBindings:@{ @"title_col" : @"d.title" }
                 parameters:@[ @"untitled" ]];
  [builder whereExpression:@"{{state_col}} = $1"
        identifierBindings:@{ @"state_col" : @"d.state_code" }
                parameters:@[ @"TX" ]];
  [builder orderByExpression:@"COALESCE({{updated_col}}, {{created_col}})"
                  descending:NO
                       nulls:@"LAST"
          identifierBindings:@{
            @"updated_col" : @"d.updated_at",
            @"created_col" : @"d.created_at",
          }
                  parameters:nil];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(
      @"SELECT \"d\".\"id\", COALESCE(\"d\".\"title\", $1) AS \"display_title\" FROM \"documents\" AS \"d\" WHERE (\"d\".\"state_code\" = $2) ORDER BY COALESCE(\"d\".\"updated_at\", \"d\".\"created_at\") ASC NULLS LAST",
      built[@"sql"]);
  NSArray *expectedParams = @[ @"untitled", @"TX" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

- (void)testExpressionTemplateRequiresIdentifierBindingsForTokens {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"{{state_col}} = $1" parameters:@[ @"TX" ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

- (void)testExpressionTemplateRejectsUnusedIdentifierBindings {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"1 = 1"
        identifierBindings:@{ @"state_col" : @"state_code" }
                parameters:nil];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

- (void)testExpressionTemplateRejectsUnsafeIdentifierBindings {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"{{state_col}} = $1"
        identifierBindings:@{ @"state_col" : @"state_code; DROP TABLE users" }
                parameters:@[ @"TX" ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidIdentifier, error.code);
}

- (void)testExpressionTemplateRejectsPlaceholderContractMismatch {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"{{state_col}} = $2"
        identifierBindings:@{ @"state_col" : @"state_code" }
                parameters:@[ @"TX" ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

- (void)testExpressionTemplateRejectsNonArrayParametersType {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"{{state_col}} = $1"
        identifierBindings:@{ @"state_col" : @"state_code" }
                parameters:(NSArray *)@{ @"bad" : @"type" }];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

- (void)testExpressionTemplateRejectsNonDictionaryIdentifierBindingsType {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"{{state_col}} = $1"
        identifierBindings:(NSDictionary<NSString *,NSString *> *)@[ @"bad" ]
                parameters:@[ @"TX" ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorInvalidArgument, error.code);
}

- (void)testExpressionIRRejectsUnsupportedKind {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  NSDictionary *malformedColumn = @{
    @"kind" : @"expression",
    @"expressionIR" : @{
      @"kind" : @"unsupported-v99",
      @"template" : @"1 = 1",
      @"parameters" : @[],
      @"identifierBindings" : @{},
    },
    @"alias" : @"expr_alias",
  };
  [builder setValue:@[ malformedColumn ] forKey:@"selectColumns"];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(built);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSQLBuilderErrorDomain, error.domain);
  XCTAssertEqual(ALNSQLBuilderErrorCompileFailed, error.code);
}

- (void)testLegacyExpressionAPIRemainsCompatible {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents" columns:@[ @"id" ]];
  [builder whereExpression:@"state_code = $1" parameters:@[ @"TX" ]];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"id\" FROM \"documents\" WHERE (state_code = $1)", built[@"sql"]);
  NSArray *expectedParams = @[ @"TX" ];
  XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
}

@end
