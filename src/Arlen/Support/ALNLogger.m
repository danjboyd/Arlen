#import "ALNLogger.h"
#import "ALNJSONSerialization.h"
#import "ALNPlatform.h"

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

- (BOOL)shouldLogLevel:(ALNLogLevel)level {
  return level >= self.minimumLevel;
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
    [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                                                ALNEscapedTextLogComponent(key),
                                                ALNEscapedTextLogComponent(stringValue)]];
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
