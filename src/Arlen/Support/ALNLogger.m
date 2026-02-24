#import "ALNLogger.h"

#include <stdio.h>
#include <sys/time.h>
#include <time.h>

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
  struct timeval tv;
  if (gettimeofday(&tv, NULL) != 0) {
    return @"1970-01-01T00:00:00.000Z";
  }

  time_t seconds = tv.tv_sec;
  struct tm utc;
  if (gmtime_r(&seconds, &utc) == NULL) {
    return @"1970-01-01T00:00:00.000Z";
  }

  int milliseconds = (int)(tv.tv_usec / 1000);
  char buffer[32];
  int written = snprintf(buffer,
                         sizeof(buffer),
                         "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                         utc.tm_year + 1900,
                         utc.tm_mon + 1,
                         utc.tm_mday,
                         utc.tm_hour,
                         utc.tm_min,
                         utc.tm_sec,
                         milliseconds);
  if (written <= 0 || written >= (int)sizeof(buffer)) {
    return @"1970-01-01T00:00:00.000Z";
  }

  NSString *formatted = [NSString stringWithUTF8String:buffer];
  return [formatted length] > 0 ? formatted : @"1970-01-01T00:00:00.000Z";
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

@implementation ALNLogger

- (instancetype)initWithFormat:(NSString *)format {
  self = [super init];
  if (self) {
    NSString *normalized = [[format ?: @"text" lowercaseString] copy];
    if (![normalized isEqualToString:@"json"]) {
      normalized = @"text";
    }
    _format = normalized;
    _minimumLevel = ALNLogLevelInfo;
  }
  return self;
}

- (void)logLevel:(ALNLogLevel)level
         message:(NSString *)message
          fields:(NSDictionary *)fields {
  if (level < self.minimumLevel) {
    return;
  }

  NSDictionary *merged = ALNMergedFields(message, level, fields);
  if ([self.format isEqualToString:@"json"]) {
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:merged
                                                   options:0
                                                     error:&jsonError];
    if (data != nil) {
      NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      const char *utf8 = [line UTF8String];
      if (utf8 != NULL) {
        fprintf(stderr, "%s\n", utf8);
        return;
      }
    }
  }

  NSMutableArray *pairs = [NSMutableArray array];
  NSArray *keys = [[merged allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    id value = merged[key];
    NSString *stringValue = (value == nil) ? @"" : [value description];
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, stringValue]];
  }
  NSString *line = [pairs componentsJoinedByString:@" "];
  fprintf(stderr, "%s\n", [line UTF8String]);
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
