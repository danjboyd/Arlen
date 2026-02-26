#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNLogger.h"

@interface LoggerTests : XCTestCase
@end

@implementation LoggerTests

- (void)testShouldLogLevelRespectsMinimumLevel {
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  logger.minimumLevel = ALNLogLevelWarn;

  XCTAssertFalse([logger shouldLogLevel:ALNLogLevelDebug]);
  XCTAssertFalse([logger shouldLogLevel:ALNLogLevelInfo]);
  XCTAssertTrue([logger shouldLogLevel:ALNLogLevelWarn]);
  XCTAssertTrue([logger shouldLogLevel:ALNLogLevelError]);
}

- (void)testShouldLogLevelDefaultsToInfoThreshold {
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"text"];
  XCTAssertFalse([logger shouldLogLevel:ALNLogLevelDebug]);
  XCTAssertTrue([logger shouldLogLevel:ALNLogLevelInfo]);
}

@end
