#import "ALNJSONSerialization.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#if ARLEN_ENABLE_YYJSON
#include "third_party/yyjson/yyjson.h"
#endif

static NSString *const ALNJSONSerializationErrorDomain = @"Arlen.JSON.Serialization.Error";

enum {
  ALNJSONSerializationErrorInvalidArgument = 1,
  ALNJSONSerializationErrorParseFailed = 2,
  ALNJSONSerializationErrorUnsupportedType = 3,
  ALNJSONSerializationErrorEncodingFailed = 4,
  ALNJSONSerializationErrorWriteFailed = 5,
  ALNJSONSerializationErrorDepthExceeded = 6,
};

static NSUInteger const ALNJSONMaxDepth = 512;

static ALNJSONBackend gALNJSONBackend =
#if ARLEN_ENABLE_YYJSON
    ALNJSONBackendYYJSON;
#else
    ALNJSONBackendFoundation;
#endif
static BOOL gALNJSONBackendInitialized = NO;

static void ALNSetError(NSError **error, NSInteger code, NSString *message) {
  if (error == NULL) {
    return;
  }
  NSDictionary *userInfo = @{NSLocalizedDescriptionKey : message ?: @"Unknown JSON error"};
  *error = [NSError errorWithDomain:ALNJSONSerializationErrorDomain
                               code:code
                           userInfo:userInfo];
}

static BOOL ALNNSNumberLooksBoolean(NSNumber *number) {
  if (number == nil) {
    return NO;
  }
  const char *type = [number objCType];
  if (type == NULL) {
    return NO;
  }
  return (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "B") == 0);
}

static BOOL ALNValidateJSONObjectRecursive(id obj, NSUInteger depth);

#if ARLEN_ENABLE_YYJSON
static id ALNFoundationFromYYValue(yyjson_val *value,
                                   NSJSONReadingOptions options,
                                   NSUInteger depth,
                                   NSError **error) {
  if (value == NULL) {
    ALNSetError(error,
                ALNJSONSerializationErrorParseFailed,
                @"yyjson returned a NULL JSON value");
    return nil;
  }
  if (depth > ALNJSONMaxDepth) {
    ALNSetError(error,
                ALNJSONSerializationErrorDepthExceeded,
                @"JSON nesting depth exceeds safety limit");
    return nil;
  }

  if (yyjson_is_null(value)) {
    return [NSNull null];
  }
  if (yyjson_is_bool(value)) {
    return yyjson_get_bool(value) ? (id)@YES : (id)@NO;
  }
  if (yyjson_is_uint(value)) {
    return [NSNumber numberWithUnsignedLongLong:yyjson_get_uint(value)];
  }
  if (yyjson_is_sint(value)) {
    return [NSNumber numberWithLongLong:yyjson_get_sint(value)];
  }
  if (yyjson_is_real(value)) {
    return [NSNumber numberWithDouble:yyjson_get_real(value)];
  }
  if (yyjson_is_str(value)) {
    const char *bytes = yyjson_get_str(value);
    size_t length = yyjson_get_len(value);
    NSString *str = [[NSString alloc] initWithBytes:bytes
                                             length:length
                                           encoding:NSUTF8StringEncoding];
    if (str == nil) {
      ALNSetError(error,
                  ALNJSONSerializationErrorParseFailed,
                  @"Failed to decode JSON string as UTF-8");
      return nil;
    }
    if ((options & NSJSONReadingMutableLeaves) != 0) {
      return [str mutableCopy];
    }
    return str;
  }
  if (yyjson_is_arr(value)) {
    NSUInteger capacity = (NSUInteger)yyjson_arr_size(value);
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:capacity];
    size_t idx = 0;
    size_t max = 0;
    yyjson_val *child = NULL;
    yyjson_arr_foreach(value, idx, max, child) {
      id childObject = ALNFoundationFromYYValue(child, options, depth + 1, error);
      if (childObject == nil) {
        return nil;
      }
      [array addObject:childObject];
    }

    if ((options & NSJSONReadingMutableContainers) != 0) {
      return array;
    }

    return [array copy];
  }
  if (yyjson_is_obj(value)) {
    NSUInteger capacity = (NSUInteger)yyjson_obj_size(value);
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:capacity];
    size_t idx = 0;
    size_t max = 0;
    yyjson_val *key = NULL;
    yyjson_val *child = NULL;
    yyjson_obj_foreach(value, idx, max, key, child) {
      NSString *keyString = [[NSString alloc] initWithBytes:yyjson_get_str(key)
                                                     length:yyjson_get_len(key)
                                                   encoding:NSUTF8StringEncoding];
      if (keyString == nil) {
        ALNSetError(error,
                    ALNJSONSerializationErrorParseFailed,
                    @"Failed to decode object key as UTF-8");
        return nil;
      }
      id childObject = ALNFoundationFromYYValue(child, options, depth + 1, error);
      if (childObject == nil) {
        return nil;
      }
      dict[keyString] = childObject;
    }

    if ((options & NSJSONReadingMutableContainers) != 0) {
      return dict;
    }

    return [dict copy];
  }

  ALNSetError(error,
              ALNJSONSerializationErrorParseFailed,
              @"Encountered unsupported yyjson node type");
  return nil;
}

static yyjson_mut_val *ALNYYValueFromFoundation(yyjson_mut_doc *doc,
                                                id obj,
                                                NSJSONWritingOptions options,
                                                NSUInteger depth,
                                                NSError **error) {
  if (doc == NULL || obj == nil) {
    ALNSetError(error,
                ALNJSONSerializationErrorInvalidArgument,
                @"Cannot encode nil JSON value");
    return NULL;
  }
  if (depth > ALNJSONMaxDepth) {
    ALNSetError(error,
                ALNJSONSerializationErrorDepthExceeded,
                @"JSON nesting depth exceeds safety limit");
    return NULL;
  }

  if (obj == [NSNull null]) {
    return yyjson_mut_null(doc);
  }

  if ([obj isKindOfClass:[NSString class]]) {
    NSData *utf8 = [(NSString *)obj dataUsingEncoding:NSUTF8StringEncoding];
    if (utf8 == nil) {
      ALNSetError(error,
                  ALNJSONSerializationErrorEncodingFailed,
                  @"Failed to encode NSString as UTF-8");
      return NULL;
    }
    return yyjson_mut_strncpy(doc, (const char *)[utf8 bytes], (size_t)[utf8 length]);
  }

  if ([obj isKindOfClass:[NSNumber class]]) {
    NSNumber *number = (NSNumber *)obj;
    const char *type = [number objCType];
    if (ALNNSNumberLooksBoolean(number)) {
      return yyjson_mut_bool(doc, [number boolValue]);
    }

    if (type != NULL) {
      switch (type[0]) {
      case 'c':
      case 's':
      case 'i':
      case 'l':
      case 'q':
        return yyjson_mut_sint(doc, [number longLongValue]);
      case 'C':
      case 'S':
      case 'I':
      case 'L':
      case 'Q':
        return yyjson_mut_uint(doc, [number unsignedLongLongValue]);
      case 'f':
      case 'd':
        return yyjson_mut_real(doc, [number doubleValue]);
      default:
        break;
      }
    }
    return yyjson_mut_real(doc, [number doubleValue]);
  }

  if ([obj isKindOfClass:[NSArray class]]) {
    yyjson_mut_val *array = yyjson_mut_arr(doc);
    if (array == NULL) {
      ALNSetError(error,
                  ALNJSONSerializationErrorWriteFailed,
                  @"Failed to create yyjson array");
      return NULL;
    }
    for (id child in (NSArray *)obj) {
      yyjson_mut_val *childValue =
          ALNYYValueFromFoundation(doc, child, options, depth + 1, error);
      if (childValue == NULL) {
        return NULL;
      }
      if (!yyjson_mut_arr_add_val(array, childValue)) {
        ALNSetError(error,
                    ALNJSONSerializationErrorWriteFailed,
                    @"Failed appending value to yyjson array");
        return NULL;
      }
    }
    return array;
  }

  if ([obj isKindOfClass:[NSDictionary class]]) {
    yyjson_mut_val *dict = yyjson_mut_obj(doc);
    if (dict == NULL) {
      ALNSetError(error,
                  ALNJSONSerializationErrorWriteFailed,
                  @"Failed to create yyjson object");
      return NULL;
    }

    NSDictionary *dictionary = (NSDictionary *)obj;
    NSArray *keys = [dictionary allKeys];
#ifdef NSJSONWritingSortedKeys
    if ((options & NSJSONWritingSortedKeys) != 0) {
      keys = [keys sortedArrayUsingSelector:@selector(compare:)];
    }
#endif

    for (id rawKey in keys) {
      if (![rawKey isKindOfClass:[NSString class]]) {
        ALNSetError(error,
                    ALNJSONSerializationErrorUnsupportedType,
                    @"JSON object keys must be NSString instances");
        return NULL;
      }

      id rawValue = dictionary[rawKey];
      yyjson_mut_val *yyValue =
          ALNYYValueFromFoundation(doc, rawValue, options, depth + 1, error);
      if (yyValue == NULL) {
        return NULL;
      }

      NSData *utf8Key = [(NSString *)rawKey dataUsingEncoding:NSUTF8StringEncoding];
      if (utf8Key == nil) {
        ALNSetError(error,
                    ALNJSONSerializationErrorEncodingFailed,
                    @"Failed to encode dictionary key as UTF-8");
        return NULL;
      }

      yyjson_mut_val *yyKey =
          yyjson_mut_strncpy(doc, (const char *)[utf8Key bytes], (size_t)[utf8Key length]);
      if (yyKey == NULL || !yyjson_mut_obj_add(dict, yyKey, yyValue)) {
        ALNSetError(error,
                    ALNJSONSerializationErrorWriteFailed,
                    @"Failed inserting key/value into yyjson object");
        return NULL;
      }
    }
    return dict;
  }

  ALNSetError(error,
              ALNJSONSerializationErrorUnsupportedType,
              [NSString stringWithFormat:@"Unsupported JSON type: %@", NSStringFromClass([obj class])]);
  return NULL;
}
#endif

static BOOL ALNValidateJSONObjectRecursive(id obj, NSUInteger depth) {
  if (obj == nil) {
    return NO;
  }
  if (depth > ALNJSONMaxDepth) {
    return NO;
  }
  if (obj == [NSNull null]) {
    return YES;
  }
  if ([obj isKindOfClass:[NSString class]]) {
    return YES;
  }
  if ([obj isKindOfClass:[NSNumber class]]) {
    NSNumber *number = (NSNumber *)obj;
    if (ALNNSNumberLooksBoolean(number)) {
      return YES;
    }
    return isfinite([number doubleValue]) != 0;
  }
  if ([obj isKindOfClass:[NSArray class]]) {
    for (id child in (NSArray *)obj) {
      if (!ALNValidateJSONObjectRecursive(child, depth + 1)) {
        return NO;
      }
    }
    return YES;
  }
  if ([obj isKindOfClass:[NSDictionary class]]) {
    for (id key in (NSDictionary *)obj) {
      if (![key isKindOfClass:[NSString class]]) {
        return NO;
      }
      id value = [(NSDictionary *)obj objectForKey:key];
      if (!ALNValidateJSONObjectRecursive(value, depth + 1)) {
        return NO;
      }
    }
    return YES;
  }
  return NO;
}

@implementation ALNJSONSerialization

+ (ALNJSONBackend)backendFromEnvironment {
  const char *rawValue = getenv("ARLEN_JSON_BACKEND");
  NSString *raw = (rawValue != NULL) ? [[NSString stringWithUTF8String:rawValue] lowercaseString] : @"";
  if ([raw length] == 0) {
#if ARLEN_ENABLE_YYJSON
    return ALNJSONBackendYYJSON;
#else
    return ALNJSONBackendFoundation;
#endif
  }
  if ([raw isEqualToString:@"foundation"] || [raw isEqualToString:@"nsjson"]) {
    return ALNJSONBackendFoundation;
  }
#if ARLEN_ENABLE_YYJSON
  if ([raw isEqualToString:@"yyjson"]) {
    return ALNJSONBackendYYJSON;
  }
  return ALNJSONBackendYYJSON;
#else
  return ALNJSONBackendFoundation;
#endif
}

+ (void)initializeBackendIfNeeded {
  @synchronized(self) {
    if (gALNJSONBackendInitialized) {
      return;
    }
    gALNJSONBackend = [self backendFromEnvironment];
    gALNJSONBackendInitialized = YES;
  }
}

+ (ALNJSONBackend)backend {
  [self initializeBackendIfNeeded];
  @synchronized(self) {
    return gALNJSONBackend;
  }
}

+ (NSString *)backendName {
  if ([self backend] == ALNJSONBackendFoundation || ![self isYYJSONAvailable]) {
    return @"foundation";
  }
  return @"yyjson";
}

+ (NSString *)yyjsonVersion {
#if ARLEN_ENABLE_YYJSON
  return @YYJSON_VERSION_STRING;
#else
  return @"disabled";
#endif
}

+ (BOOL)isYYJSONAvailable {
#if ARLEN_ENABLE_YYJSON
  return YES;
#else
  return NO;
#endif
}

+ (NSString *)foundationFallbackDeprecationDate {
  return @"2026-04-30";
}

+ (void)setBackendForTesting:(ALNJSONBackend)backend {
  ALNJSONBackend effectiveBackend = backend;
  if (effectiveBackend == ALNJSONBackendYYJSON && ![self isYYJSONAvailable]) {
    effectiveBackend = ALNJSONBackendFoundation;
  }
  @synchronized(self) {
    gALNJSONBackend = effectiveBackend;
    gALNJSONBackendInitialized = YES;
  }
}

+ (void)resetBackendForTesting {
  @synchronized(self) {
    gALNJSONBackendInitialized = NO;
#if ARLEN_ENABLE_YYJSON
    gALNJSONBackend = ALNJSONBackendYYJSON;
#else
    gALNJSONBackend = ALNJSONBackendFoundation;
#endif
  }
}

+ (id)JSONObjectWithData:(NSData *)data
                 options:(NSJSONReadingOptions)options
                   error:(NSError **)error {
  if (data == nil) {
    ALNSetError(error,
                ALNJSONSerializationErrorInvalidArgument,
                @"Input NSData cannot be nil");
    return nil;
  }

  if ([self backend] == ALNJSONBackendFoundation || ![self isYYJSONAvailable]) {
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:options error:error];
    if (parsed == nil) {
      return nil;
    }
    if ((options & NSJSONReadingAllowFragments) == 0 &&
        !([parsed isKindOfClass:[NSArray class]] || [parsed isKindOfClass:[NSDictionary class]])) {
      ALNSetError(error,
                  ALNJSONSerializationErrorParseFailed,
                  @"Top-level JSON value must be array or object unless fragments are allowed");
      return nil;
    }
    return parsed;
  }

#if ARLEN_ENABLE_YYJSON
  yyjson_read_err readErr;
  memset(&readErr, 0, sizeof(readErr));
  yyjson_doc *doc = yyjson_read_opts((char *)[data bytes],
                                     (size_t)[data length],
                                     YYJSON_READ_NOFLAG,
                                     NULL,
                                     &readErr);
  if (doc == NULL) {
    NSString *message =
        [NSString stringWithFormat:@"yyjson parse failed: %s at byte %lu",
                                   (readErr.msg ? readErr.msg : "unknown error"),
                                   (unsigned long)readErr.pos];
    ALNSetError(error, ALNJSONSerializationErrorParseFailed, message);
    return nil;
  }

  yyjson_val *root = yyjson_doc_get_root(doc);
  if ((options & NSJSONReadingAllowFragments) == 0 &&
      !(yyjson_is_arr(root) || yyjson_is_obj(root))) {
    yyjson_doc_free(doc);
    ALNSetError(error,
                ALNJSONSerializationErrorParseFailed,
                @"Top-level JSON value must be array or object unless fragments are allowed");
    return nil;
  }

  id parsed = ALNFoundationFromYYValue(root, options, 0, error);
  yyjson_doc_free(doc);
  return parsed;
#else
  return [NSJSONSerialization JSONObjectWithData:data options:options error:error];
#endif
}

+ (NSData *)dataWithJSONObject:(id)obj
                       options:(NSJSONWritingOptions)options
                         error:(NSError **)error {
  if (![self isValidJSONObject:obj]) {
    ALNSetError(error,
                ALNJSONSerializationErrorUnsupportedType,
                @"Invalid object graph for JSON encoding");
    return nil;
  }

  if ([self backend] == ALNJSONBackendFoundation || ![self isYYJSONAvailable]) {
    return [NSJSONSerialization dataWithJSONObject:obj options:options error:error];
  }

#if ARLEN_ENABLE_YYJSON
  yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
  if (doc == NULL) {
    ALNSetError(error,
                ALNJSONSerializationErrorWriteFailed,
                @"Failed allocating yyjson document");
    return nil;
  }

  yyjson_mut_val *root = ALNYYValueFromFoundation(doc, obj, options, 0, error);
  if (root == NULL) {
    yyjson_mut_doc_free(doc);
    return nil;
  }
  yyjson_mut_doc_set_root(doc, root);

  yyjson_write_flag flags = YYJSON_WRITE_NOFLAG;
  if ((options & NSJSONWritingPrettyPrinted) != 0) {
    flags |= YYJSON_WRITE_PRETTY_TWO_SPACES;
  }

  yyjson_write_err writeErr;
  memset(&writeErr, 0, sizeof(writeErr));
  size_t length = 0;
  char *raw = yyjson_mut_write_opts(doc, flags, NULL, &length, &writeErr);
  if (raw == NULL) {
    yyjson_mut_doc_free(doc);
    NSString *message =
        [NSString stringWithFormat:@"yyjson write failed: %s",
                                   (writeErr.msg ? writeErr.msg : "unknown error")];
    ALNSetError(error, ALNJSONSerializationErrorWriteFailed, message);
    return nil;
  }

  NSData *data = [NSData dataWithBytes:raw length:length];
  free(raw);
  yyjson_mut_doc_free(doc);
  return data;
#else
  return [NSJSONSerialization dataWithJSONObject:obj options:options error:error];
#endif
}

+ (BOOL)isValidJSONObject:(id)obj {
  if (obj == nil) {
    return NO;
  }
  BOOL rootIsContainer = [obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]];
  if (!rootIsContainer) {
    return NO;
  }
  return ALNValidateJSONObjectRecursive(obj, 0);
}

@end
