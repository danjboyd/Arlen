#import "ALNLogger.h"
#import "ALNJSONSerialization.h"
#import "ALNPlatform.h"

#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>

#if !defined(_WIN32)
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

// Largest chunk handed to a single write(). POSIX guarantees that a write of
// at most PIPE_BUF bytes into space that poll() just reported as writable will
// not block, so capping at the portable minimum (_POSIX_PIPE_BUF, 512) lets us
// drain a line into a pipe without ever blocking the calling thread, even when
// the underlying descriptor is left in blocking mode.
#define ALN_LOGGER_WRITE_CHUNK 512

static long ALNLoggerMonotonicMillis(void) {
  struct timespec ts;
#if defined(CLOCK_MONOTONIC)
  if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
    return (long)ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
  }
#endif
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (long)tv.tv_sec * 1000L + (long)tv.tv_usec / 1000L;
}

// A closed log reader otherwise delivers SIGPIPE and kills the process; ignore
// it once (without clobbering an app/server-installed handler) so a vanished
// consumer degrades to a dropped line instead of a crash.
static void ALNLoggerInstallSigpipeIgnore(void) {
  struct sigaction current;
  if (sigaction(SIGPIPE, NULL, &current) != 0) {
    return;
  }
  if (current.sa_handler == SIG_DFL) {
    struct sigaction ignore;
    memset(&ignore, 0, sizeof(ignore));
    ignore.sa_handler = SIG_IGN;
    sigemptyset(&ignore.sa_mask);
    (void)sigaction(SIGPIPE, &ignore, NULL);
  }
}

// Emit a fully-formed line to fd, waiting at most timeoutMs for a stalled sink
// before giving up. Returns YES only if every byte was written. The caller
// serializes calls per logger, so a partial chunked write cannot interleave
// with another thread's line.
static BOOL ALNLoggerEmitBytes(int fd, const char *bytes, size_t len, int timeoutMs) {
  if (fd < 0 || bytes == NULL) {
    return NO;
  }
  long deadline = ALNLoggerMonotonicMillis() + (timeoutMs > 0 ? timeoutMs : 0);
  size_t offset = 0;
  while (offset < len) {
    int remaining = (int)(deadline - ALNLoggerMonotonicMillis());
    if (remaining < 0) {
      remaining = 0;
    }
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLOUT;
    pfd.revents = 0;
    int ready = poll(&pfd, 1, remaining);
    if (ready < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (ready == 0) {
      return NO;  // sink not draining within the deadline; drop the rest
    }
    if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) {
      return NO;  // reader gone or descriptor invalid
    }
    if (!(pfd.revents & POLLOUT)) {
      return NO;
    }
    size_t chunk = len - offset;
    if (chunk > ALN_LOGGER_WRITE_CHUNK) {
      chunk = ALN_LOGGER_WRITE_CHUNK;
    }
    ssize_t written = write(fd, bytes + offset, chunk);
    if (written < 0) {
      if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
        continue;
      }
      return NO;  // EPIPE or other terminal error; drop the rest
    }
    offset += (size_t)written;
  }
  return YES;
}
#endif  // !_WIN32

static NSString *ALNLogLevelLabel(ALNLogLevel level) {
  switch (level) {
  case ALNLogLevelDebug:
    return @"DEBUG";
  case ALNLogLevelInfo:
    return @"INFO";
  case ALNLogLevelWarn:
    return @"WARN";
  case ALNLogLevelError:
    return @"ERROR";
  }
  return @"INFO";
}

static NSString *ALNISO8601Now(void) {
  return ALNPlatformISO8601Now();
}

static NSDictionary *ALNMergedFields(NSString *message, ALNLogLevel level,
                                     NSDictionary *fields) {
  NSMutableDictionary *merged =
      [NSMutableDictionary dictionaryWithDictionary:fields ?: @{}];
  merged[@"timestamp"] = ALNISO8601Now();
  merged[@"level"] = ALNLogLevelLabel(level);
  merged[@"message"] = message ?: @"";
  return merged;
}

static NSString *ALNEscapedTextLogComponent(NSString *value) {
  NSString *input = [value isKindOfClass:[NSString class]] ? value : @"";
  NSMutableString *escaped = [NSMutableString stringWithCapacity:[input length] + 8];
  for (NSUInteger idx = 0; idx < [input length]; idx++) {
    unichar ch = [input characterAtIndex:idx];
    switch (ch) {
    case '\\':
      [escaped appendString:@"\\\\"];
      break;
    case '\n':
      [escaped appendString:@"\\n"];
      break;
    case '\r':
      [escaped appendString:@"\\r"];
      break;
    case '\t':
      [escaped appendString:@"\\t"];
      break;
    default:
      if (ch < 0x20 || ch == 0x7F) {
        [escaped appendFormat:@"\\u%04x", ch];
      } else {
        [escaped appendFormat:@"%C", ch];
      }
      break;
    }
  }
  return escaped;
}

@implementation ALNLogger {
  NSLock *_writeLock;
  NSUInteger _droppedMessageCount;
}

- (instancetype)initWithFormat:(NSString *)format {
  self = [super init];
  if (self) {
    NSString *normalized = [[format ?: @"text" lowercaseString] copy];
    if (![normalized isEqualToString:@"json"]) {
      normalized = @"text";
    }
    _format = normalized;
    _minimumLevel = ALNLogLevelInfo;
    _writeLock = [[NSLock alloc] init];
    _droppedMessageCount = 0;
#if defined(_WIN32)
    _outputFileDescriptor = 2;  // STDERR_FILENO
#else
    _outputFileDescriptor = STDERR_FILENO;
    static pthread_once_t sigpipeOnce = PTHREAD_ONCE_INIT;
    pthread_once(&sigpipeOnce, ALNLoggerInstallSigpipeIgnore);
#endif
    _writeTimeoutMilliseconds = 100;
  }
  return self;
}

- (BOOL)shouldLogLevel:(ALNLogLevel)level {
  return level >= self.minimumLevel;
}

- (NSUInteger)droppedMessageCount {
  [_writeLock lock];
  NSUInteger value = _droppedMessageCount;
  [_writeLock unlock];
  return value;
}

// Write a single fully-formed line (newline appended here) to the configured
// sink, dropping it rather than blocking the calling thread if the sink stalls.
// Serialized through _writeLock so concurrent loggers cannot interleave the
// chunked writes of two lines.
- (void)emitLogLine:(NSString *)line {
  NSString *withNewline = [line stringByAppendingString:@"\n"];
  NSData *data = [withNewline dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return;
  }

  [_writeLock lock];
  int fd = self.outputFileDescriptor;
#if defined(_WIN32)
  // Windows has no pipe-backpressure failure mode in our deployments; preserve
  // the historical synchronous behavior.
  if (fd == 2) {
    fprintf(stderr, "%.*s", (int)[data length], (const char *)[data bytes]);
  } else {
    fwrite([data bytes], 1, [data length], stderr);
  }
  BOOL written = YES;
#else
  int timeoutMs = (self.writeTimeoutMilliseconds > INT_MAX)
                      ? INT_MAX
                      : (int)self.writeTimeoutMilliseconds;
  BOOL written = ALNLoggerEmitBytes(fd, (const char *)[data bytes], [data length], timeoutMs);
#endif
  if (!written) {
    _droppedMessageCount += 1;
  }
  [_writeLock unlock];
}

- (void)logLevel:(ALNLogLevel)level
         message:(NSString *)message
          fields:(NSDictionary *)fields {
  if (![self shouldLogLevel:level]) {
    return;
  }

  NSDictionary *merged = ALNMergedFields(message, level, fields);
  if ([self.format isEqualToString:@"json"]) {
    NSError *jsonError = nil;
    NSData *data = [ALNJSONSerialization dataWithJSONObject:merged
                                                    options:0
                                                      error:&jsonError];
    if (data != nil) {
      NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      if (line != nil) {
        [self emitLogLine:line];
        return;
      }
    }
  }

  NSMutableArray *pairs = [NSMutableArray array];
  NSArray *keys = [[merged allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    id value = merged[key];
    NSString *stringValue = (value == nil) ? @"" : [value description];
    [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                                                ALNEscapedTextLogComponent(key),
                                                ALNEscapedTextLogComponent(stringValue)]];
  }
  [self emitLogLine:[pairs componentsJoinedByString:@" "]];
}

- (void)debug:(NSString *)message fields:(NSDictionary *)fields {
  [self logLevel:ALNLogLevelDebug message:message fields:fields];
}

- (void)info:(NSString *)message fields:(NSDictionary *)fields {
  [self logLevel:ALNLogLevelInfo message:message fields:fields];
}

- (void)warn:(NSString *)message fields:(NSDictionary *)fields {
  [self logLevel:ALNLogLevelWarn message:message fields:fields];
}

- (void)error:(NSString *)message fields:(NSDictionary *)fields {
  [self logLevel:ALNLogLevelError message:message fields:fields];
}

@end
