#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPlatform.h"

// Apple's NSString has no -unsignedIntegerValue, so numeric request
// parameters and old-style plist values must go through
// ALNUnsignedIntegerFromValue rather than a respondsToSelector: check.
@interface UnsignedIntegerValueTests : XCTestCase
@end

@implementation UnsignedIntegerValueTests

- (void)testNumbersKeepUnsignedIntegerValueSemantics {
  NSUInteger value = 99;
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@0, &value));
  XCTAssertEqual((NSUInteger)0, value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@42, &value));
  XCTAssertEqual((NSUInteger)42, value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@(NSUIntegerMax), &value));
  XCTAssertEqual(NSUIntegerMax, value);
  NSNumber *negative = @(-1);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(negative, &value));
  XCTAssertEqual([negative unsignedIntegerValue], value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@7, NULL));
  XCTAssertEqual((NSUInteger)0, ALNUnsignedIntegerValueOrDefault(@0, 5));
}

- (void)testDecimalDigitStringsParse {
  NSUInteger value = 0;
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@"10", &value));
  XCTAssertEqual((NSUInteger)10, value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@"0", &value));
  XCTAssertEqual((NSUInteger)0, value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@"007", &value));
  XCTAssertEqual((NSUInteger)7, value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@"  25\n", &value));
  XCTAssertEqual((NSUInteger)25, value);
  XCTAssertTrue(ALNUnsignedIntegerFromValue(@"\t3 ", &value));
  XCTAssertEqual((NSUInteger)3, value);
  NSString *maximum = [NSString stringWithFormat:@"%llu", (unsigned long long)NSUIntegerMax];
  XCTAssertTrue(ALNUnsignedIntegerFromValue(maximum, &value));
  XCTAssertEqual(NSUIntegerMax, value);
  XCTAssertEqual((NSUInteger)12, ALNUnsignedIntegerValueOrDefault(@"12", 5));
  XCTAssertEqual((NSUInteger)0, ALNUnsignedIntegerValueOrDefault(@"0", 5));
}

- (void)testRejectedValuesLeaveOutputAndUseFallback {
  NSArray *rejected = @[
    @"-1",
    @"+1",
    @"1e3",
    @"1.5",
    @"abc",
    @"12abc",
    @"1 2",
    @"",
    @"   ",
    @"18446744073709551616",
    @"99999999999999999999999999999999",
    @"١٢",
    [NSNull null],
    @[ @1 ],
    @{ @"value" : @1 },
    [NSDate date],
  ];
  for (id candidate in rejected) {
    NSUInteger value = 77;
    XCTAssertFalse(ALNUnsignedIntegerFromValue(candidate, &value), @"%@", candidate);
    XCTAssertEqual((NSUInteger)77, value, @"%@", candidate);
    XCTAssertEqual((NSUInteger)5, ALNUnsignedIntegerValueOrDefault(candidate, 5), @"%@", candidate);
  }
  NSUInteger value = 77;
  XCTAssertFalse(ALNUnsignedIntegerFromValue(nil, &value));
  XCTAssertEqual((NSUInteger)77, value);
  XCTAssertEqual((NSUInteger)5, ALNUnsignedIntegerValueOrDefault(nil, 5));
}

- (void)testOverflowBoundaryIsRejectedOneAboveMaximum {
  NSString *maximum = [NSString stringWithFormat:@"%llu", (unsigned long long)NSUIntegerMax];
  NSString *lastDigit = [maximum substringFromIndex:[maximum length] - 1];
  NSString *prefix = [maximum substringToIndex:[maximum length] - 1];
  NSString *onePast = [prefix stringByAppendingFormat:@"%d", [lastDigit intValue] + 1];
  NSUInteger value = 1;
  XCTAssertFalse(ALNUnsignedIntegerFromValue(onePast, &value));
  XCTAssertEqual((NSUInteger)1, value);
  XCTAssertFalse(ALNUnsignedIntegerFromValue([maximum stringByAppendingString:@"0"], &value));
}

@end
