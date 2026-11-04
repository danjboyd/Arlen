#import <XCTest/XCTest.h>
#import "Arlen.h"

@interface SSEReaderTests : XCTestCase
@end

@implementation SSEReaderTests

- (BOOL)feed:(NSString *)text reader:(ALNSSEReader *)reader events:(NSMutableArray *)events error:(NSError **)error {
  return [reader consumeData:[text dataUsingEncoding:NSUTF8StringEncoding]
                    onEvent:^BOOL(ALNSSEEvent *event) { [events addObject:event]; return YES; }
                      error:error];
}

- (void)testEveryByteAndEveryTwoChunkSplitPreservesUTF8BOMAndCRLF {
  NSData *wire = [@"\uFEFF: heartbeat\r\nid: α\r\nevent: delta\r\ndata: café 😀\r\ndata: second\r\n\r\ndata: tail\r\n\r\n"
      dataUsingEncoding:NSUTF8StringEncoding];
  for (NSUInteger split = 0; split <= [wire length] + 1; split++) {
    ALNSSEReader *reader = [ALNSSEReader new];
    NSMutableArray *events = [NSMutableArray array];
    NSError *error = nil;
    ALNSSEEventHandler handler = ^BOOL(ALNSSEEvent *event) { [events addObject:event]; return YES; };
    if (split > [wire length]) {
      for (NSUInteger i = 0; i < [wire length]; i++) {
        XCTAssertTrue([reader consumeData:[wire subdataWithRange:NSMakeRange(i, 1)] onEvent:handler error:&error]);
      }
    } else {
      XCTAssertTrue([reader consumeData:[wire subdataWithRange:NSMakeRange(0, split)] onEvent:handler error:&error]);
      XCTAssertTrue([reader consumeData:[wire subdataWithRange:NSMakeRange(split, [wire length] - split)] onEvent:handler error:&error]);
    }
    XCTAssertTrue([reader finishWithError:&error]);
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)2, [events count], @"split %lu", (unsigned long)split);
    if ([events count] != 2) continue;
    ALNSSEEvent *first = events[0];
    ALNSSEEvent *second = events[1];
    XCTAssertEqualObjects(@"delta", first.eventType);
    XCTAssertEqualObjects(@"café 😀\nsecond", first.data);
    XCTAssertEqualObjects(@"α", first.lastEventID);
    XCTAssertEqualObjects(@"message", second.eventType);
    XCTAssertEqualObjects(@"tail", second.data);
    XCTAssertEqualObjects(@"α", second.lastEventID);
  }
}

- (void)testLineEndingsAndDispatchBeforeConsumeReturns {
  for (NSString *ending in @[@"\n", @"\r", @"\r\n"]) {
    ALNSSEReader *reader = [ALNSSEReader new];
    __block NSUInteger count = 0;
    NSData *wire = [[NSString stringWithFormat:@"data: x%@%@", ending, ending] dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([reader consumeData:wire onEvent:^BOOL(ALNSSEEvent *event) {
      count++;
      XCTAssertEqualObjects(@"x", event.data);
      return YES;
    } error:NULL]);
    XCTAssertEqual((NSUInteger)1, count);
  }
}

- (void)testEmptyDataWhitespaceUnknownFieldsAndEventReset {
  ALNSSEReader *reader = [ALNSSEReader new];
  NSMutableArray *events = [NSMutableArray array];
  XCTAssertTrue([self feed:@"event: unused\n: comment\nretry: 1\nData: ignored\nunknown\n\ndata\n\ndata:  spaced:colon\ndata:\n\nevent: custom\nevent:\ndata: final\n\n"
                   reader:reader events:events error:NULL]);
  XCTAssertEqual((NSUInteger)3, [events count]);
  if ([events count] != 3) return;
  XCTAssertEqualObjects(@"", [events[0] data]);
  XCTAssertEqualObjects(@"message", [events[0] eventType]);
  XCTAssertEqualObjects(@" spaced:colon\n", [events[1] data]);
  XCTAssertEqualObjects(@"message", [events[2] eventType]);
}

- (void)testIDsPersistResetAndIgnoreNUL {
  ALNSSEReader *reader = [ALNSSEReader new];
  NSMutableArray *events = [NSMutableArray array];
  unichar nul = 0;
  NSString *wire = [NSString stringWithFormat:@"id: one\n\ndata: first\n\nid: bad%Cvalue\ndata: second\n\nid\ndata: third\n\n", nul];
  XCTAssertTrue([self feed:wire reader:reader events:events error:NULL]);
  XCTAssertEqual((NSUInteger)3, [events count]);
  if ([events count] != 3) return;
  XCTAssertEqualObjects(@"one", [events[0] lastEventID]);
  XCTAssertEqualObjects(@"one", [events[1] lastEventID]);
  XCTAssertEqualObjects(@"", [events[2] lastEventID]);
}

- (void)testOnlyInitialBOMIsRemoved {
  ALNSSEReader *reader = [ALNSSEReader new];
  NSMutableArray *events = [NSMutableArray array];
  XCTAssertTrue([self feed:@"\uFEFFdata: first\n\n\uFEFFdata: ignored\ndata: \uFEFFkept\n\n" reader:reader events:events error:NULL]);
  XCTAssertEqual((NSUInteger)2, [events count]);
  if ([events count] != 2) return;
  XCTAssertEqualObjects(@"first", [events[0] data]);
  XCTAssertEqualObjects(@"\uFEFFkept", [events[1] data]);
}

- (void)testEOFDiscardsUnterminatedLineAndUndispatchedEvent {
  for (NSString *tail in @[@"data: lost", @"data: lost\n", @"event: lost\ndata: lost\r\n", @"id: pending\n"]) {
    ALNSSEReader *reader = [ALNSSEReader new];
    NSMutableArray *events = [NSMutableArray array];
    XCTAssertTrue([self feed:[@"data: complete\n\n" stringByAppendingString:tail] reader:reader events:events error:NULL]);
    XCTAssertTrue([reader finishWithError:NULL]);
    XCTAssertTrue([reader finishWithError:NULL]);
    XCTAssertEqual((NSUInteger)1, [events count]);
    XCTAssertEqualObjects(@"complete", [events[0] data]);
  }
  // EOF also discards a partial UTF-8 sequence in an unterminated line.
  ALNSSEReader *reader = [ALNSSEReader new];
  const unsigned char incomplete[] = {'d', 'a', 't', 'a', ':', 0xf0, 0x9f};
  XCTAssertTrue([reader consumeData:[NSData dataWithBytes:incomplete length:sizeof(incomplete)]
                          onEvent:^BOOL(ALNSSEEvent *event) { XCTFail(@"No EOF dispatch"); return YES; } error:NULL]);
  XCTAssertTrue([reader finishWithError:NULL]);
}

- (void)testLineBoundCheckedAcrossChunksIncludingIgnoredFields {
  for (NSString *prefix in @[@"data: ", @":     ", @"other:"]) {
    ALNSSEReader *reader = [[ALNSSEReader alloc] initWithMaxLineBytes:8 maxEventBytes:20 error:NULL];
    NSMutableArray *events = [NSMutableArray array];
    NSError *error = nil;
    XCTAssertTrue([self feed:[prefix stringByAppendingString:@"ab"] reader:reader events:events error:&error]);
    XCTAssertFalse([self feed:@"c\n\n" reader:reader events:events error:&error]);
    XCTAssertEqualObjects(ALNSSEReaderErrorDomain, error.domain);
    XCTAssertEqual(ALNSSEReaderErrorLineTooLarge, error.code);
    XCTAssertEqual((NSUInteger)0, [events count]);
  }
}

- (void)testExactLineAndEventByteLimitsAllowDispatchAndReset {
  ALNSSEReader *reader = [[ALNSSEReader alloc] initWithMaxLineBytes:8 maxEventBytes:3 error:NULL];
  NSMutableArray *events = [NSMutableArray array];
  XCTAssertTrue([self feed:@"data: é\n\ndata: ab\r\n\r\n" reader:reader events:events error:NULL]);
  XCTAssertEqual((NSUInteger)2, [events count]);
  if ([events count] != 2) return;
  XCTAssertEqualObjects(@"é", [events[0] data]);
  XCTAssertEqualObjects(@"ab", [events[1] data]);
}

- (void)testMultilineEventBudgetCountsUTF8AndAppendedNewlines {
  for (NSString *wire in @[@"data: é\ndata: x\n\n", @"data: abcde\n\n", @"data\ndata\ndata\ndata\ndata\ndata\n\n"]) {
    ALNSSEReader *reader = [[ALNSSEReader alloc] initWithMaxLineBytes:32 maxEventBytes:5 error:NULL];
    NSMutableArray *events = [NSMutableArray array];
    NSError *error = nil;
    // For the first case, 3 + 2 bytes is exactly allowed; add one more data field.
    NSString *input = [wire hasPrefix:@"data: é"] ? @"data: é\ndata: x\ndata\n\n" : wire;
    XCTAssertFalse([self feed:input reader:reader events:events error:&error]);
    XCTAssertEqual(ALNSSEReaderErrorEventTooLarge, error.code);
    XCTAssertEqual((NSUInteger)0, [events count]);
  }
}

- (void)testMalformedCompletedUTF8LineFailsWithoutLeakingContent {
  const unsigned char invalid[] = {'d', 'a', 't', 'a', ':', ' ', 0xff, '\n', '\n'};
  ALNSSEReader *reader = [ALNSSEReader new];
  NSError *error = nil;
  XCTAssertFalse([reader consumeData:[NSData dataWithBytes:invalid length:sizeof(invalid)]
                            onEvent:^BOOL(ALNSSEEvent *event) { XCTFail(@"Invalid UTF-8 must not dispatch"); return YES; }
                              error:&error]);
  XCTAssertEqual(ALNSSEReaderErrorInvalidUTF8, error.code);
  XCTAssertEqualObjects(@"SSE line is not valid UTF-8", error.localizedDescription);
  NSError *again = nil;
  XCTAssertFalse([reader finishWithError:&again]);
  XCTAssertEqualObjects(error, again);
}

- (void)testStrictUTF8RejectsOverlongSurrogateOutOfRangeAndTruncatedSequences {
  const unsigned char bad[][4] = {{0xc0, 0xaf, 0, 0}, {0xed, 0xa0, 0x80, 0},
                                {0xf4, 0x90, 0x80, 0x80}, {0xf0, 0x9f, 0, 0},
                                {0x80, 0, 0, 0}};
  const NSUInteger lengths[] = {2, 3, 4, 2, 1};
  for (NSUInteger i = 0; i < sizeof(lengths) / sizeof(lengths[0]); i++) {
    ALNSSEReader *reader = [ALNSSEReader new];
    NSMutableData *wire = [[@"data: " dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [wire appendBytes:bad[i] length:lengths[i]];
    [wire appendBytes:"\n\n" length:2];
    NSError *error = nil;
    XCTAssertFalse([reader consumeData:wire onEvent:^BOOL(ALNSSEEvent *event) {
      XCTFail(@"Malformed sequence must not dispatch"); return YES;
    } error:&error], @"sequence %lu", (unsigned long)i);
    XCTAssertEqual(ALNSSEReaderErrorInvalidUTF8, error.code);
  }
}

- (void)testStoppingIsPermanentAndPreservesAlreadyDeliveredEvents {
  ALNSSEReader *reader = [ALNSSEReader new];
  __block NSUInteger count = 0;
  NSError *error = nil;
  XCTAssertFalse([reader consumeData:[@"data: first\n\ndata: second\n\n" dataUsingEncoding:NSUTF8StringEncoding]
      onEvent:^BOOL(ALNSSEEvent *event) { count++; return NO; } error:&error]);
  XCTAssertEqual((NSUInteger)1, count);
  XCTAssertEqual(ALNSSEReaderErrorStopped, error.code);
  NSError *again = nil;
  XCTAssertFalse([reader consumeData:[NSData data] onEvent:^BOOL(ALNSSEEvent *event) { count++; return YES; } error:&again]);
  XCTAssertEqualObjects(error, again);
  XCTAssertFalse([reader finishWithError:NULL]);
  XCTAssertEqual((NSUInteger)1, count);
}

- (void)testInitializationAndClosedState {
  NSError *error = nil;
  XCTAssertNil([[ALNSSEReader alloc] initWithMaxLineBytes:0 maxEventBytes:1 error:&error]);
  XCTAssertEqual(ALNSSEReaderErrorInvalidArgument, error.code);
  XCTAssertNil([[ALNSSEReader alloc] initWithMaxLineBytes:1 maxEventBytes:0 error:NULL]);
  ALNSSEReader *reader = [ALNSSEReader new];
  XCTAssertEqual((NSUInteger)65536, reader.maxLineBytes);
  XCTAssertEqual((NSUInteger)1048576, reader.maxEventBytes);
  XCTAssertTrue([reader finishWithError:NULL]);
  XCTAssertFalse([self feed:@"data: later\n\n" reader:reader events:[NSMutableArray array] error:&error]);
  XCTAssertEqual(ALNSSEReaderErrorInvalidState, error.code);
}

- (void)testReentrantCallsPermanentlyFailOuterConsume {
  for (NSNumber *finish in @[@NO, @YES]) {
    ALNSSEReader *reader = [ALNSSEReader new];
    __block NSUInteger count = 0;
    NSError *error = nil;
    XCTAssertFalse([reader consumeData:[@"data: first\n\ndata: second\n\n" dataUsingEncoding:NSUTF8StringEncoding]
        onEvent:^BOOL(ALNSSEEvent *event) {
          count++;
          if ([finish boolValue]) {
            XCTAssertFalse([reader finishWithError:NULL]);
          } else {
            XCTAssertFalse([reader consumeData:[NSData data] onEvent:^BOOL(ALNSSEEvent *nested) { return YES; } error:NULL]);
          }
          return YES;
        } error:&error]);
    XCTAssertEqual((NSUInteger)1, count);
    XCTAssertEqual(ALNSSEReaderErrorInvalidState, error.code);
  }
}

- (void)testHandlerExceptionPropagatesAndStopsReader {
  ALNSSEReader *reader = [ALNSSEReader new];
  XCTAssertThrows([reader consumeData:[@"data: x\n\n" dataUsingEncoding:NSUTF8StringEncoding]
      onEvent:^BOOL(ALNSSEEvent *event) { [NSException raise:@"AppFailure" format:@"private detail"]; return YES; } error:NULL]);
  NSError *error = nil;
  XCTAssertFalse([reader finishWithError:&error]);
  XCTAssertEqual(ALNSSEReaderErrorStopped, error.code);
  XCTAssertEqualObjects(@"SSE event handler stopped parsing", error.localizedDescription);
}

- (void)testLargeChunkDispatchesWithoutReaderAccumulatingAnEventQueue {
  ALNSSEReader *reader = [[ALNSSEReader alloc] initWithMaxLineBytes:8 maxEventBytes:2 error:NULL];
  NSMutableData *wire = [NSMutableData data];
  NSData *event = [@"data: x\n\n" dataUsingEncoding:NSUTF8StringEncoding];
  for (NSUInteger i = 0; i < 10000; i++) [wire appendData:event];
  __block NSUInteger count = 0;
  XCTAssertTrue([reader consumeData:wire onEvent:^BOOL(ALNSSEEvent *value) {
    XCTAssertEqualObjects(@"x", value.data);
    count++;
    return YES;
  } error:NULL]);
  XCTAssertEqual((NSUInteger)10000, count);
}
@end
