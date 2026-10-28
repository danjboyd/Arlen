#import "ALNSSEReader.h"

NSString *const ALNSSEReaderErrorDomain = @"ALNSSEReaderErrorDomain";

@interface ALNSSEEvent ()
- (instancetype)initWithType:(NSString *)type data:(NSString *)data lastEventID:(NSString *)eventID;
@end

@implementation ALNSSEEvent
- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use ALNSSEReader to obtain an event"];
  return nil;
}

- (instancetype)initWithType:(NSString *)type data:(NSString *)data lastEventID:(NSString *)eventID {
  self = [super init];
  if (self) {
    _eventType = [type copy];
    _data = [data copy];
    _lastEventID = [eventID copy];
  }
  return self;
}
@end

static NSError *ALNSSEError(ALNSSEReaderErrorCode code) {
  NSString *message = @"Invalid SSE reader argument";
  switch (code) {
    case ALNSSEReaderErrorLineTooLarge: message = @"SSE line exceeds byte limit"; break;
    case ALNSSEReaderErrorEventTooLarge: message = @"SSE event data exceeds byte limit"; break;
    case ALNSSEReaderErrorInvalidUTF8: message = @"SSE line is not valid UTF-8"; break;
    case ALNSSEReaderErrorStopped: message = @"SSE event handler stopped parsing"; break;
    case ALNSSEReaderErrorInvalidState: message = @"SSE reader is closed or already consuming"; break;
    default: break;
  }
  return [NSError errorWithDomain:ALNSSEReaderErrorDomain code:code
                        userInfo:@{NSLocalizedDescriptionKey : message}];
}

@implementation ALNSSEReader {
  NSMutableData *_line;
  NSMutableString *_data;
  NSString *_eventType;
  NSString *_lastEventID;
  NSUInteger _eventBytes;
  BOOL _firstLine;
  BOOL _skipLF;
  BOOL _consuming;
  BOOL _finished;
  NSError *_failure;
}

- (instancetype)init {
  return [self initWithMaxLineBytes:65536 maxEventBytes:1048576 error:NULL];
}

- (instancetype)initWithMaxLineBytes:(NSUInteger)maxLineBytes
                      maxEventBytes:(NSUInteger)maxEventBytes
                              error:(NSError **)error {
  if (maxLineBytes == 0 || maxEventBytes == 0) {
    if (error) *error = ALNSSEError(ALNSSEReaderErrorInvalidArgument);
    return nil;
  }
  self = [super init];
  if (self) {
    _maxLineBytes = maxLineBytes;
    _maxEventBytes = maxEventBytes;
    _line = [NSMutableData data];
    _data = [NSMutableString string];
    _eventType = @"";
    _lastEventID = @"";
    _firstLine = YES;
  }
  return self;
}

- (BOOL)fail:(ALNSSEReaderErrorCode)code error:(NSError **)error {
  if (!_failure) _failure = ALNSSEError(code);
  // Release buffered stream contents on any permanent failure.
  _line = [NSMutableData data];
  _data = [NSMutableString string];
  _eventType = @"";
  _lastEventID = @"";
  _eventBytes = 0;
  if (error) *error = _failure;
  return NO;
}

- (BOOL)processLine:(ALNSSEEventHandler)handler error:(NSError **)error {
  // Foundation may strip a BOM at the start of every decoded NSData. Decode
  // behind an ASCII sentinel so only our stream-level rule removes the BOM.
  NSMutableData *encoded = [NSMutableData dataWithBytes:"x" length:1];
  [encoded appendData:_line];
  NSString *decoded = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
  NSString *line = decoded ? [decoded substringFromIndex:1] : nil;
  [_line setLength:0];
  if (!line) return [self fail:ALNSSEReaderErrorInvalidUTF8 error:error];
  if (_firstLine) {
    _firstLine = NO;
    if ([line hasPrefix:@"\uFEFF"]) line = [line substringFromIndex:1];
  }
  if ([line length] == 0) {
    ALNSSEEvent *event = nil;
    if (_eventBytes > 0) {
      event = [[ALNSSEEvent alloc] initWithType:([_eventType length] ? _eventType : @"message")
                                         data:[_data substringToIndex:[_data length] - 1]
                                  lastEventID:_lastEventID];
    }
    _data = [NSMutableString string];
    _eventType = @"";
    _eventBytes = 0;
    if (event && !handler(event)) return [self fail:ALNSSEReaderErrorStopped error:error];
    return _failure == nil;
  }
  if ([line hasPrefix:@":"]) return YES;
  NSRange colon = [line rangeOfString:@":"];
  NSString *field = colon.location == NSNotFound ? line : [line substringToIndex:colon.location];
  NSString *value = colon.location == NSNotFound ? @"" : [line substringFromIndex:colon.location + 1];
  if ([value hasPrefix:@" "]) value = [value substringFromIndex:1];
  if ([field isEqualToString:@"data"]) {
    NSUInteger bytes = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    // Subtraction avoids overflow even with NSUIntegerMax limits.
    if (bytes >= _maxEventBytes - _eventBytes) {
      return [self fail:ALNSSEReaderErrorEventTooLarge error:error];
    }
    _eventBytes += bytes + 1;
    [_data appendString:value];
    [_data appendString:@"\n"];
  } else if ([field isEqualToString:@"event"]) {
    _eventType = [value copy];
  } else if ([field isEqualToString:@"id"]) {
    unichar nul = 0;
    if ([value rangeOfString:[NSString stringWithCharacters:&nul length:1]].location == NSNotFound) {
      _lastEventID = [value copy];
    }
  }
  // Unknown fields, including retry, have no effect in this framing-only API.
  return YES;
}

- (BOOL)consumeData:(NSData *)data onEvent:(ALNSSEEventHandler)onEvent error:(NSError **)error {
  if (_failure) { if (error) *error = _failure; return NO; }
  if (_finished || _consuming) return [self fail:ALNSSEReaderErrorInvalidState error:error];
  if (![data isKindOfClass:[NSData class]] || !onEvent) {
    return [self fail:ALNSSEReaderErrorInvalidArgument error:error];
  }
  _consuming = YES;
  @try {
    const unsigned char *bytes = [data bytes];
    NSUInteger length = [data length];
    NSUInteger index = 0;
    while (index < length && !_failure) {
      // Release per-line temporaries before continuing through a large chunk.
      @autoreleasepool {
        if (_skipLF) {
          _skipLF = NO;
          if (bytes[index] == '\n') { index++; continue; }
        }
        NSUInteger start = index;
        NSUInteger remaining = _maxLineBytes - [_line length];
        while (index < length && bytes[index] != '\r' && bytes[index] != '\n') {
          if (index - start >= remaining) {
            [self fail:ALNSSEReaderErrorLineTooLarge error:NULL];
            break;
          }
          index++;
        }
        if (!_failure) {
          [_line appendBytes:bytes + start length:index - start];
          if (index < length) {
            _skipLF = bytes[index++] == '\r';
            [self processLine:onEvent error:NULL];
          }
        }
      }
    }
    // _failure owns the error across each drained line pool. Publish through
    // the caller's autoreleasing output parameter only after leaving the pool.
    if (_failure) { if (error) *error = _failure; return NO; }
    return YES;
  } @catch (id exception) {
    [self fail:ALNSSEReaderErrorStopped error:NULL];
    @throw;
  } @finally {
    _consuming = NO;
  }
}

- (BOOL)finishWithError:(NSError **)error {
  if (_failure) { if (error) *error = _failure; return NO; }
  if (_consuming) return [self fail:ALNSSEReaderErrorInvalidState error:error];
  _finished = YES;
  _line = [NSMutableData data];
  _data = [NSMutableString string];
  _eventType = @"";
  _lastEventID = @"";
  _eventBytes = 0;
  return YES;
}
@end
