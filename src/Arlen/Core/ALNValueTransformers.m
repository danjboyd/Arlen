#import "ALNValueTransformers.h"

NSString *const ALNValueTransformerErrorDomain = @"Arlen.ValueTransformer.Error";
NSString *const ALNValueTransformerNameKey = @"transformer";

@protocol ALNErrorReportingValueTransformer <NSObject>
- (id _Nullable)aln_transformedValue:(id _Nullable)value
                               error:(NSError **_Nullable)error;
@end

typedef NS_ENUM(NSInteger, ALNBuiltInTransformerKind) {
  ALNBuiltInTransformerKindTrim = 1,
  ALNBuiltInTransformerKindLowercase = 2,
  ALNBuiltInTransformerKindUppercase = 3,
  ALNBuiltInTransformerKindInteger = 4,
  ALNBuiltInTransformerKindNumber = 5,
  ALNBuiltInTransformerKindBoolean = 6,
  ALNBuiltInTransformerKindISO8601Date = 7,
};

@interface ALNBuiltInValueTransformer : NSValueTransformer <ALNErrorReportingValueTransformer>

@property(nonatomic, assign) ALNBuiltInTransformerKind kind;
@property(nonatomic, copy) NSString *name;

- (instancetype)initWithName:(NSString *)name kind:(ALNBuiltInTransformerKind)kind;

@end

static NSMutableSet *ALNRegisteredTransformerNames(void) {
  static NSMutableSet *names = nil;
  if (names == nil) {
    names = [[NSMutableSet alloc] init];
  }
  return names;
}

static NSString *ALNNormalizedTransformerName(NSString *name) {
  if (![name isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [name stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }
  return [trimmed lowercaseString];
}

static NSError *ALNTransformerError(ALNValueTransformerErrorCode code,
                                    NSString *name,
                                    NSString *description) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = description ?: @"Value transform failed";
  if ([name length] > 0) {
    userInfo[ALNValueTransformerNameKey] = name;
  }
  return [NSError errorWithDomain:ALNValueTransformerErrorDomain
                             code:code
                         userInfo:userInfo];
}

static NSString *ALNStringFromValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return nil;
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(description)]) {
    return [value description];
  }
  return nil;
}

static BOOL ALNParseInteger(NSString *value, NSInteger *outValue) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  NSInteger parsed = 0;
  if (![scanner scanInteger:&parsed]) {
    return NO;
  }
  if (![scanner isAtEnd]) {
    return NO;
  }
  if (outValue != NULL) {
    *outValue = parsed;
  }
  return YES;
}

static BOOL ALNParseDouble(NSString *value, double *outValue) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  double parsed = 0.0;
  if (![scanner scanDouble:&parsed]) {
    return NO;
  }
  if (![scanner isAtEnd]) {
    return NO;
  }
  if (outValue != NULL) {
    *outValue = parsed;
  }
  return YES;
}

static NSNumber *ALNParseBoolean(id value) {
  if ([value isKindOfClass:[NSNumber class]]) {
    return @([value boolValue]);
  }
  NSString *raw = ALNStringFromValue(value);
  if ([raw length] == 0) {
    return nil;
  }
  NSString *normalized = [[raw lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    return @(YES);
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    return @(NO);
  }
  return nil;
}

static NSDate *ALNParseISO8601Date(id value) {
  if ([value isKindOfClass:[NSDate class]]) {
    return value;
  }
  NSString *raw = ALNStringFromValue(value);
  if ([raw length] == 0) {
    return nil;
  }

  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  NSLocale *locale =
      [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.locale = locale;
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

  NSArray *formats = @[
    @"yyyy-MM-dd'T'HH:mm:ssXXXXX",
    @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
    @"yyyy-MM-dd'T'HH:mm:ss'Z'",
    @"yyyy-MM-dd",
  ];
  for (NSString *format in formats) {
    formatter.dateFormat = format;
    NSDate *parsed = [formatter dateFromString:raw];
    if (parsed != nil) {
      return parsed;
    }
  }
  return nil;
}

@implementation ALNBuiltInValueTransformer

+ (BOOL)allowsReverseTransformation {
  return NO;
}

+ (Class)transformedValueClass {
  return [NSObject class];
}

- (instancetype)initWithName:(NSString *)name kind:(ALNBuiltInTransformerKind)kind {
  self = [super init];
  if (self) {
    _name = [name copy] ?: @"";
    _kind = kind;
  }
  return self;
}

- (id)transformedValue:(id)value {
  return [self aln_transformedValue:value error:NULL];
}

- (id)aln_transformedValue:(id)value error:(NSError **)error {
  switch (self.kind) {
  case ALNBuiltInTransformerKindTrim: {
    NSString *raw = ALNStringFromValue(value);
    if (raw == nil) {
      return nil;
    }
    return [raw stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  case ALNBuiltInTransformerKindLowercase: {
    NSString *raw = ALNStringFromValue(value);
    if (raw == nil) {
      return nil;
    }
    return [raw lowercaseString];
  }
  case ALNBuiltInTransformerKindUppercase: {
    NSString *raw = ALNStringFromValue(value);
    if (raw == nil) {
      return nil;
    }
    return [raw uppercaseString];
  }
  case ALNBuiltInTransformerKindInteger: {
    if ([value isKindOfClass:[NSNumber class]]) {
      return @([value integerValue]);
    }
    NSString *raw = ALNStringFromValue(value);
    NSInteger parsed = 0;
    if (!ALNParseInteger(raw, &parsed)) {
      if (error != NULL) {
        *error = ALNTransformerError(ALNValueTransformerErrorTransformFailed,
                                     self.name,
                                     [NSString
                                         stringWithFormat:@"Transformer '%@' expected an integer-compatible value",
                                                          self.name ?: @""]);
      }
      return nil;
    }
    return @(parsed);
  }
  case ALNBuiltInTransformerKindNumber: {
    if ([value isKindOfClass:[NSNumber class]]) {
      return @([value doubleValue]);
    }
    NSString *raw = ALNStringFromValue(value);
    double parsed = 0.0;
    if (!ALNParseDouble(raw, &parsed)) {
      if (error != NULL) {
        *error = ALNTransformerError(ALNValueTransformerErrorTransformFailed,
                                     self.name,
                                     [NSString
                                         stringWithFormat:@"Transformer '%@' expected a numeric value",
                                                          self.name ?: @""]);
      }
      return nil;
    }
    return @(parsed);
  }
  case ALNBuiltInTransformerKindBoolean: {
    NSNumber *parsed = ALNParseBoolean(value);
    if (parsed == nil) {
      if (error != NULL) {
        *error = ALNTransformerError(ALNValueTransformerErrorTransformFailed,
                                     self.name,
                                     [NSString
                                         stringWithFormat:@"Transformer '%@' expected a boolean-compatible value",
                                                          self.name ?: @""]);
      }
      return nil;
    }
    return parsed;
  }
  case ALNBuiltInTransformerKindISO8601Date: {
    NSDate *parsed = ALNParseISO8601Date(value);
    if (parsed == nil) {
      if (error != NULL) {
        *error = ALNTransformerError(ALNValueTransformerErrorTransformFailed,
                                     self.name,
                                     [NSString
                                         stringWithFormat:@"Transformer '%@' expected an ISO8601 date value",
                                                          self.name ?: @""]);
      }
      return nil;
    }
    return parsed;
  }
  default:
    if (error != NULL) {
      *error = ALNTransformerError(ALNValueTransformerErrorInvalidArgument,
                                   self.name,
                                   @"Unknown built-in transformer");
    }
    return nil;
  }
}

@end

BOOL ALNRegisterValueTransformer(NSString *name, NSValueTransformer *transformer) {
  NSString *normalized = ALNNormalizedTransformerName(name);
  if ([normalized length] == 0 || transformer == nil) {
    return NO;
  }

  @synchronized([NSValueTransformer class]) {
    [NSValueTransformer setValueTransformer:transformer forName:normalized];
    [ALNRegisteredTransformerNames() addObject:normalized];
  }
  return YES;
}

NSValueTransformer *ALNValueTransformerNamed(NSString *name) {
  NSString *normalized = ALNNormalizedTransformerName(name);
  if ([normalized length] == 0) {
    return nil;
  }
  ALNRegisterDefaultValueTransformers();
  return [NSValueTransformer valueTransformerForName:normalized];
}

NSArray<NSString *> *ALNRegisteredValueTransformerNames(void) {
  ALNRegisterDefaultValueTransformers();
  @synchronized([NSValueTransformer class]) {
    NSArray *names = [[ALNRegisteredTransformerNames() allObjects]
        sortedArrayUsingSelector:@selector(compare:)];
    return names ?: @[];
  }
}

id ALNApplyValueTransformerNamed(NSString *name, id value, NSError **error) {
  NSString *normalized = ALNNormalizedTransformerName(name);
  if ([normalized length] == 0) {
    if (error != NULL) {
      *error = ALNTransformerError(ALNValueTransformerErrorInvalidArgument,
                                   nil,
                                   @"Transformer name must not be empty");
    }
    return nil;
  }

  NSValueTransformer *transformer = ALNValueTransformerNamed(normalized);
  if (transformer == nil) {
    if (error != NULL) {
      *error = ALNTransformerError(
          ALNValueTransformerErrorUnknownTransformer,
          normalized,
          [NSString stringWithFormat:@"Unknown value transformer '%@'", normalized]);
    }
    return nil;
  }

  if ([transformer respondsToSelector:@selector(aln_transformedValue:error:)]) {
    return [(id<ALNErrorReportingValueTransformer>)transformer
        aln_transformedValue:value
                       error:error];
  }
  return [transformer transformedValue:value];
}

void ALNRegisterDefaultValueTransformers(void) {
  static BOOL registered = NO;
  @synchronized([NSValueTransformer class]) {
    if (registered) {
      return;
    }
    registered = YES;
  }

  ALNRegisterValueTransformer(
      @"trim",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"trim"
                                                 kind:ALNBuiltInTransformerKindTrim]);
  ALNRegisterValueTransformer(
      @"lowercase",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"lowercase"
                                                 kind:ALNBuiltInTransformerKindLowercase]);
  ALNRegisterValueTransformer(
      @"uppercase",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"uppercase"
                                                 kind:ALNBuiltInTransformerKindUppercase]);
  ALNRegisterValueTransformer(
      @"to_integer",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"to_integer"
                                                 kind:ALNBuiltInTransformerKindInteger]);
  ALNRegisterValueTransformer(
      @"to_number",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"to_number"
                                                 kind:ALNBuiltInTransformerKindNumber]);
  ALNRegisterValueTransformer(
      @"to_boolean",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"to_boolean"
                                                 kind:ALNBuiltInTransformerKindBoolean]);
  ALNRegisterValueTransformer(
      @"iso8601_date",
      [[ALNBuiltInValueTransformer alloc] initWithName:@"iso8601_date"
                                                 kind:ALNBuiltInTransformerKindISO8601Date]);
}
