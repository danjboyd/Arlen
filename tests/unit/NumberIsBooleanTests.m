#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNJSONSerialization.h"
#import "ALNPlatform.h"

// ALNNumberIsBoolean must be exact on every Foundation: Apple arm64 encodes BOOL
// as "B" while @YES reports "c", and GNUstep encodes BOOL as "C".
@interface NumberIsBooleanTests : XCTestCase
@end

@implementation NumberIsBooleanTests

- (void)tearDown {
  [ALNJSONSerialization resetBackendForTesting];
  [super tearDown];
}

- (void)forEachBackend:(void (^)(ALNJSONBackend backend))block {
  NSMutableArray<NSNumber *> *backends = [NSMutableArray arrayWithObject:@(ALNJSONBackendFoundation)];
  if ([ALNJSONSerialization isYYJSONAvailable]) {
    [backends addObject:@(ALNJSONBackendYYJSON)];
  }
  for (NSNumber *entry in backends) {
    ALNJSONBackend backend = (ALNJSONBackend)[entry unsignedIntegerValue];
    [ALNJSONSerialization setBackendForTesting:backend];
    block(backend);
  }
  [ALNJSONSerialization resetBackendForTesting];
}

- (void)testBooleanNumbersAreBooleans {
  BOOL flag = YES;
  XCTAssertTrue(ALNNumberIsBoolean(@YES));
  XCTAssertTrue(ALNNumberIsBoolean(@NO));
  XCTAssertTrue(ALNNumberIsBoolean([NSNumber numberWithBool:YES]));
  XCTAssertTrue(ALNNumberIsBoolean([NSNumber numberWithBool:NO]));
  XCTAssertTrue(ALNNumberIsBoolean([[NSNumber alloc] initWithBool:YES]));
  XCTAssertTrue(ALNNumberIsBoolean(@(flag)));
}

- (void)testNonBooleanValuesAreNotBooleans {
  XCTAssertFalse(ALNNumberIsBoolean([NSNumber numberWithChar:1]));
  XCTAssertFalse(ALNNumberIsBoolean([NSNumber numberWithChar:0]));
  XCTAssertFalse(ALNNumberIsBoolean([NSNumber numberWithUnsignedChar:1]));
  XCTAssertFalse(ALNNumberIsBoolean(@1));
  XCTAssertFalse(ALNNumberIsBoolean(@0));
  XCTAssertFalse(ALNNumberIsBoolean(@1.0));
  XCTAssertFalse(ALNNumberIsBoolean(nil));
  XCTAssertFalse(ALNNumberIsBoolean([NSNull null]));
  XCTAssertFalse(ALNNumberIsBoolean(@"true"));
}

- (void)testDecodedJSONBooleansAreBooleansOnEveryBackend {
  NSData *data = [@"[true,false,1,0]" dataUsingEncoding:NSUTF8StringEncoding];
  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *error = nil;
    NSArray *values = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)4, [values count]);
    XCTAssertTrue(ALNNumberIsBoolean(values[0]), @"backend %lu", (unsigned long)backend);
    XCTAssertTrue(ALNNumberIsBoolean(values[1]), @"backend %lu", (unsigned long)backend);
    XCTAssertFalse(ALNNumberIsBoolean(values[2]), @"backend %lu", (unsigned long)backend);
    XCTAssertFalse(ALNNumberIsBoolean(values[3]), @"backend %lu", (unsigned long)backend);
  }];
}

- (void)testSerializedBooleansAndCharNumbersStayDistinct {
  NSArray *values = @[ @YES, @NO, [NSNumber numberWithChar:1] ];
  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *error = nil;
    NSData *data = [ALNJSONSerialization dataWithJSONObject:values options:0 error:&error];
    XCTAssertNil(error);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(@"[true,false,1]", text, @"backend %lu", (unsigned long)backend);
  }];
}

@end
