#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseQuery.h"
#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"

static NSDate *ALNTestDataverseUTCDate(NSInteger year,
                                       NSInteger month,
                                       NSInteger day,
                                       NSInteger hour,
                                       NSInteger minute,
                                       NSInteger second) {
  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  NSDateComponents *components = [[NSDateComponents alloc] init];
  components.year = year;
  components.month = month;
  components.day = day;
  components.hour = hour;
  components.minute = minute;
  components.second = second;
  return [calendar dateFromComponents:components];
}

@interface DataverseQueryTests : ALNDataverseTestCase
@end

@implementation DataverseQueryTests

- (void)testQueryFilterFixtureCases {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_query_cases.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSArray *cases = [fixture[@"filter_cases"] isKindOfClass:[NSArray class]] ? fixture[@"filter_cases"] : @[];
  for (NSDictionary *caseDefinition in cases) {
    NSString *caseID = caseDefinition[@"id"] ?: @"unknown_case";
    NSError *caseError = nil;
    NSString *filter = [ALNDataverseQuery filterStringFromPredicate:caseDefinition[@"predicate"] error:&caseError];
    XCTAssertNil(caseError, @"%@", caseID);
    XCTAssertEqualObjects(filter, caseDefinition[@"expected_filter"], @"%@", caseID);
  }
}

- (void)testQueryParametersFixtureCases {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_query_cases.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSArray *cases = [fixture[@"query_cases"] isKindOfClass:[NSArray class]] ? fixture[@"query_cases"] : @[];
  for (NSDictionary *caseDefinition in cases) {
    NSString *caseID = caseDefinition[@"id"] ?: @"unknown_case";
    NSError *caseError = nil;
    NSDictionary<NSString *, NSString *> *parameters =
        [ALNDataverseQuery queryParametersWithSelectFields:caseDefinition[@"select_fields"]
                                                     where:caseDefinition[@"predicate"]
                                                   orderBy:caseDefinition[@"order_by"]
                                                       top:caseDefinition[@"top"]
                                                      skip:caseDefinition[@"skip"]
                                                 countFlag:[caseDefinition[@"count"] boolValue]
                                                    expand:caseDefinition[@"expand"]
                                                     error:&caseError];
    XCTAssertNil(caseError, @"%@", caseID);
    XCTAssertEqualObjects(parameters, caseDefinition[@"expected_parameters"], @"%@", caseID);
  }
}

- (void)testQueryErrorFixtureCases {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_query_cases.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSArray *cases = [fixture[@"error_cases"] isKindOfClass:[NSArray class]] ? fixture[@"error_cases"] : @[];
  for (NSDictionary *caseDefinition in cases) {
    NSString *caseID = caseDefinition[@"id"] ?: @"unknown_case";
    NSError *caseError = nil;
    NSDictionary<NSString *, NSString *> *parameters =
        [ALNDataverseQuery queryParametersWithSelectFields:caseDefinition[@"select_fields"]
                                                     where:caseDefinition[@"predicate"]
                                                   orderBy:nil
                                                       top:nil
                                                      skip:nil
                                                 countFlag:NO
                                                    expand:nil
                                                     error:&caseError];
    XCTAssertNil(parameters, @"%@", caseID);
    XCTAssertNotNil(caseError, @"%@", caseID);
    XCTAssertEqual((NSInteger)[caseDefinition[@"expected_error_code"] integerValue], caseError.code, @"%@", caseID);
  }
}

- (void)testQueryFilterSupportsNSDateNSUUIDAndBooleanLiterals {
  NSUUID *currencyID =
      [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-0000000000AA"];
  NSDate *createdOn = ALNTestDataverseUTCDate(2024, 2, 3, 4, 5, 6);

  NSError *error = nil;
  NSString *filter = [ALNDataverseQuery
      filterStringFromPredicate:@{
        @"createdon" : @{ @">=" : createdOn },
        @"isactive" : @YES,
        @"ownerid" : [NSNull null],
        @"transactioncurrencyid" : currencyID,
      }
                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(filter,
                        @"createdon ge 2024-02-03T04:05:06Z and isactive eq true and ownerid eq null and transactioncurrencyid eq 00000000-0000-0000-0000-0000000000AA");
}

@end
