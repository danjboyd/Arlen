#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <errno.h>
#include <fcntl.h>
#include <string.h>
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

// Fill a pipe's kernel buffer so that further writes to it would block,
// mirroring the StateCompulsoryPoolingAPI failure where the test harness stops
// draining the server's stderr. Returns the number of bytes parked in the pipe.
- (size_t)fillPipeWriteEnd:(int)writeFD {
  int flags = fcntl(writeFD, F_GETFL);
  XCTAssertTrue(flags >= 0);
  XCTAssertEqual(0, fcntl(writeFD, F_SETFL, flags | O_NONBLOCK));

  unsigned char chunk[4096];
  memset(chunk, 'x', sizeof(chunk));
  size_t total = 0;
  ssize_t written = 0;
  while ((written = write(writeFD, chunk, sizeof(chunk))) > 0) {
    total += (size_t)written;
  }
  XCTAssertTrue(errno == EAGAIN || errno == EWOULDBLOCK);

  // Restore blocking mode: the logger must stay non-blocking via its own
  // bounded poll, not because the descriptor happens to be O_NONBLOCK.
  XCTAssertEqual(0, fcntl(writeFD, F_SETFL, flags));
  return total;
}

// ARLEN-BUG-033: a stalled/full log sink must not block the request path. The
// logger has to drop the line and return promptly instead of parking in
// pipe_write the way fprintf(stderr, ...) did.
- (void)testLoggerDropsAndDoesNotBlockWhenSinkIsFull_ARLEN_BUG_033 {
  int pipeFDs[2] = { -1, -1 };
  XCTAssertEqual(0, pipe(pipeFDs));
  if (pipeFDs[0] < 0 || pipeFDs[1] < 0) {
    return;
  }

  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"text"];
  logger.outputFileDescriptor = pipeFDs[1];
  logger.writeTimeoutMilliseconds = 0;  // never wait: drop the instant it would block

  (void)[self fillPipeWriteEnd:pipeFDs[1]];
  XCTAssertEqual([logger droppedMessageCount], (NSUInteger)0);

  NSDate *start = [NSDate date];
  for (NSUInteger i = 0; i < 5; i++) {
    [logger info:@"request" fields:@{ @"path" : @"/v1/states/ZZ/dockets", @"status" : @200 }];
  }
  NSTimeInterval elapsed = -[start timeIntervalSinceNow];

  XCTAssertLessThan(elapsed, 2.0, @"logger blocked on a full sink instead of dropping (took %.3fs)", elapsed);
  XCTAssertEqual([logger droppedMessageCount], (NSUInteger)5);

  (void)close(pipeFDs[0]);
  (void)close(pipeFDs[1]);
}

// Once the sink drains, emission resumes and nothing is counted as dropped.
- (void)testLoggerResumesWritingAfterSinkDrains_ARLEN_BUG_033 {
  int pipeFDs[2] = { -1, -1 };
  XCTAssertEqual(0, pipe(pipeFDs));
  if (pipeFDs[0] < 0 || pipeFDs[1] < 0) {
    return;
  }

  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"text"];
  logger.outputFileDescriptor = pipeFDs[1];
  logger.writeTimeoutMilliseconds = 250;

  size_t parked = [self fillPipeWriteEnd:pipeFDs[1]];

  // Sink is full: this line drops within the bounded timeout.
  [logger info:@"dropped" fields:@{ @"k" : @"v" }];
  XCTAssertEqual([logger droppedMessageCount], (NSUInteger)1);

  // Drain the pipe; subsequent emission must succeed and reach the reader.
  unsigned char scratch[8192];
  while (parked > 0) {
    ssize_t got = read(pipeFDs[0], scratch, sizeof(scratch));
    if (got <= 0) {
      break;
    }
    parked -= (size_t)got;
  }

  [logger info:@"delivered" fields:@{ @"k" : @"v" }];
  XCTAssertEqual([logger droppedMessageCount], (NSUInteger)1, @"a healthy sink must not drop");

  NSMutableData *captured = [NSMutableData data];
  unsigned char buffer[8192];
  ssize_t readBytes = 0;
  while ((readBytes = read(pipeFDs[0], buffer, sizeof(buffer))) > 0) {
    [captured appendBytes:buffer length:(NSUInteger)readBytes];
    if ([captured length] > 0) {
      break;
    }
  }
  NSString *text = [[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] ?: @"";
  XCTAssertTrue([text containsString:@"message=delivered"], @"%@", text);

  (void)close(pipeFDs[0]);
  (void)close(pipeFDs[1]);
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
