#import "ALNORMValueConverter.h"

#import <dispatch/dispatch.h>

#import "../Data/ALNDatabaseAdapter.h"
#import "ALNORMErrors.h"

static NSDateFormatter *ALNORMISO8601DateFormatter(void) {
  static NSDateFormatter *formatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssXXXXX";
  });
  return formatter;
}

static id ALNORMValueConverterFail(NSString *message,
                                   id value,
                                   NSError **error) {
  if (error != NULL) {
    *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                             message,
                             @{
                               @"value_class" : (value != nil) ? NSStringFromClass([value class]) : @"",
                             });
  }
  return nil;
}

@implementation ALNORMValueConverter

- (instancetype)init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

+ (instancetype)converterWithDecodeBlock:(ALNORMValueConversionBlock)decodeBlock
                              encodeBlock:(ALNORMValueConversionBlock)encodeBlock {
  return [[self alloc] initWithDecodeBlock:decodeBlock encodeBlock:encodeBlock];
}

+ (instancetype)passthroughConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           (void)error;
           return value;
         }
                            encodeBlock:^id(id value, NSError **error) {
                              (void)error;
                              return value;
                            }];
}

+ (instancetype)stringConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           (void)error;
           if (value == nil || value == [NSNull null]) {
             return nil;
           }
           return [value isKindOfClass:[NSString class]] ? value : [value description];
         }
                            encodeBlock:^id(id value, NSError **error) {
                              (void)error;
                              if (value == nil || value == [NSNull null]) {
                                return nil;
                              }
                              return [value isKindOfClass:[NSString class]] ? value : [value description];
                            }];
}

+ (instancetype)numberConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           if (value == nil || value == [NSNull null]) {
             return nil;
           }
           if ([value isKindOfClass:[NSNumber class]]) {
             return value;
           }
           if ([value isKindOfClass:[NSString class]]) {
             NSString *stringValue = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
             if ([stringValue length] == 0) {
               return nil;
             }
             NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
             NSNumber *number = [formatter numberFromString:stringValue];
             if (number != nil) {
               return number;
             }
           }
           return ALNORMValueConverterFail(@"value could not be coerced to NSNumber", value, error);
         }
                            encodeBlock:^id(id value, NSError **error) {
                              if (value == nil || value == [NSNull null]) {
                                return nil;
                              }
                              if ([value isKindOfClass:[NSNumber class]]) {
                                return value;
                              }
                              return ALNORMValueConverterFail(@"value could not be encoded as NSNumber", value, error);
                            }];
}

+ (instancetype)integerConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           id decoded = [[self numberConverter] decodeValue:value error:error];
           return decoded != nil ? @([decoded integerValue]) : nil;
         }
                            encodeBlock:^id(id value, NSError **error) {
                              id encoded = [[self numberConverter] encodeValue:value error:error];
                              return encoded != nil ? @([encoded integerValue]) : nil;
                            }];
}

+ (instancetype)ISO8601DateTimeConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           if (value == nil || value == [NSNull null]) {
             return nil;
           }
           if ([value isKindOfClass:[NSDate class]]) {
             return value;
           }
           if ([value isKindOfClass:[NSString class]]) {
             NSDate *date = [ALNORMISO8601DateFormatter() dateFromString:value];
             if (date != nil) {
               return date;
             }
           }
           return ALNORMValueConverterFail(@"value could not be coerced to NSDate", value, error);
         }
                            encodeBlock:^id(id value, NSError **error) {
                              if (value == nil || value == [NSNull null]) {
                                return nil;
                              }
                              if ([value isKindOfClass:[NSDate class]]) {
                                return value;
                              }
                              return ALNORMValueConverterFail(@"value could not be encoded as NSDate", value, error);
                            }];
}

+ (instancetype)JSONConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           if (value == nil || value == [NSNull null]) {
             return nil;
           }
           if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
             return value;
           }
           if ([value isKindOfClass:[NSString class]]) {
             NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
             if (data == nil) {
               return ALNORMValueConverterFail(@"JSON string could not be encoded as UTF-8", value, error);
             }
             NSError *jsonError = nil;
             id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
             if (object != nil) {
               return object;
             }
             if (error != NULL) {
               *error = jsonError;
             }
             return nil;
           }
           return ALNORMValueConverterFail(@"value could not be coerced to JSON-compatible Foundation object", value, error);
         }
                            encodeBlock:^id(id value, NSError **error) {
                              if (value == nil || value == [NSNull null]) {
                                return nil;
                              }
                              if ([value isKindOfClass:[ALNDatabaseJSONValue class]]) {
                                return value;
                              }
                              if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                                return ALNDatabaseJSONParameter(value);
                              }
                              return ALNORMValueConverterFail(@"value could not be encoded as JSON parameter", value, error);
                            }];
}

+ (instancetype)arrayConverter {
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           if (value == nil || value == [NSNull null]) {
             return nil;
           }
           if ([value isKindOfClass:[NSArray class]]) {
             return value;
           }
           return ALNORMValueConverterFail(@"value could not be coerced to NSArray", value, error);
         }
                            encodeBlock:^id(id value, NSError **error) {
                              if (value == nil || value == [NSNull null]) {
                                return nil;
                              }
                              if ([value isKindOfClass:[ALNDatabaseArrayValue class]]) {
                                return value;
                              }
                              if ([value isKindOfClass:[NSArray class]]) {
                                return ALNDatabaseArrayParameter(value);
                              }
                              return ALNORMValueConverterFail(@"value could not be encoded as SQL array parameter", value, error);
                            }];
}

+ (instancetype)enumConverterWithAllowedValues:(NSArray<NSString *> *)allowedValues {
  NSSet *allowed = [NSSet setWithArray:allowedValues ?: @[]];
  return [self converterWithDecodeBlock:^id(id value, NSError **error) {
           if (value == nil || value == [NSNull null]) {
             return nil;
           }
           NSString *stringValue = [value isKindOfClass:[NSString class]] ? value : [value description];
           if ([allowed containsObject:stringValue]) {
             return stringValue;
           }
           return ALNORMValueConverterFail(@"value is not part of the allowed enum set", value, error);
         }
                            encodeBlock:^id(id value, NSError **error) {
                              if (value == nil || value == [NSNull null]) {
                                return nil;
                              }
                              NSString *stringValue = [value isKindOfClass:[NSString class]] ? value : [value description];
                              if ([allowed containsObject:stringValue]) {
                                return stringValue;
                              }
                              return ALNORMValueConverterFail(@"value is not part of the allowed enum set", value, error);
                            }];
}

- (instancetype)initWithDecodeBlock:(ALNORMValueConversionBlock)decodeBlock
                         encodeBlock:(ALNORMValueConversionBlock)encodeBlock {
  self = [super init];
  if (self != nil) {
    if (decodeBlock != nil) {
      _decodeBlock = [decodeBlock copy];
    } else {
      _decodeBlock = ^id(id value, NSError **error) {
        (void)error;
        return value;
      };
    }
    if (encodeBlock != nil) {
      _encodeBlock = [encodeBlock copy];
    } else {
      _encodeBlock = ^id(id value, NSError **error) {
        (void)error;
        return value;
      };
    }
  }
  return self;
}

- (id)decodeValue:(id)value error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  return self.decodeBlock != nil ? self.decodeBlock(value, error) : value;
}

- (id)encodeValue:(id)value error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  return self.encodeBlock != nil ? self.encodeBlock(value, error) : value;
}

@end
