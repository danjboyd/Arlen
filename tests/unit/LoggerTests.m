#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <fcntl.h>
#include <unistd.h>

#import "ALNLogger.h"

@interface LoggerTests : XCTestCase
@end

@implementation LoggerTests

- (NSString *)captureStandardErrorForBlock:(void (^)(void))block {
  int saved = dup(STDERR_FILENO);
  XCTAssertTrue(saved >= 0);
  if (saved < 0) {
    return @"";
  }

  int pipeFDs[2] = { -1, -1 };
  XCTAssertEqual(0, pipe(pipeFDs));
  if (pipeFDs[0] < 0 || pipeFDs[1] < 0) {
    (void)close(saved);
    return @"";
  }

  fflush(stderr);
  XCTAssertTrue(dup2(pipeFDs[1], STDERR_FILENO) >= 0);
  (void)close(pipeFDs[1]);

  if (block != nil) {
    block();
  }

  fflush(stderr);
  XCTAssertTrue(dup2(saved, STDERR_FILENO) >= 0);
  (void)close(saved);

  NSMutableData *captured = [NSMutableData data];
  unsigned char buffer[1024];
  ssize_t readBytes = 0;
  while ((readBytes = read(pipeFDs[0], buffer, sizeof(buffer))) > 0) {
    [captured appendBytes:buffer length:(NSUInteger)readBytes];
  }
  (void)close(pipeFDs[0]);
  return [[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] ?: @"";
}

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

- (void)testTextLoggerEscapesControlCharactersInFields {
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"text"];

  NSString *captured = [self captureStandardErrorForBlock:^{
    [logger info:@"line1\nline2"
          fields:@{
            @"bad\tkey" : @"alpha\tbeta\r\ngamma",
            @"control" : [NSString stringWithFormat:@"x%C", (unichar)0x01],
          }];
  }];

  XCTAssertTrue([captured containsString:@"message=line1\\nline2"], @"%@", captured);
  XCTAssertTrue([captured containsString:@"bad\\tkey=alpha\\tbeta\\r\\ngamma"], @"%@", captured);
  XCTAssertTrue([captured containsString:@"control=x\\u0001"], @"%@", captured);
  XCTAssertFalse([captured containsString:@"line1\nline2"], @"%@", captured);
  XCTAssertFalse([captured containsString:@"alpha\tbeta"], @"%@", captured);
  XCTAssertFalse([captured containsString:@"\r"], @"%@", captured);
}

@end
