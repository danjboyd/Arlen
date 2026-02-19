#import "ALNLogger.h"

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
  static NSDateFormatter *formatter = nil;
  if (formatter == nil) {
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  }
  return [formatter stringFromDate:[NSDate date]];
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
      fprintf(stderr, "%s\n", [[NSString alloc] initWithData:data
                                                    encoding:NSUTF8StringEncoding]
                                 .UTF8String);
      return;
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
