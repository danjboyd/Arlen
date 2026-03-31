#import "ALNDataverseClient.h"

#import <ctype.h>
#import <string.h>

#import "ALNDataverseQuery.h"
#import "ALNJSONSerialization.h"

NSString *const ALNDataverseErrorDomain = @"Arlen.Data.Dataverse.Error";
NSString *const ALNDataverseErrorDiagnosticsKey = @"diagnostics";
NSString *const ALNDataverseErrorHTTPStatusKey = @"http_status";
NSString *const ALNDataverseErrorRequestURLKey = @"request_url";
NSString *const ALNDataverseErrorRequestMethodKey = @"request_method";
NSString *const ALNDataverseErrorRequestHeadersKey = @"request_headers";
NSString *const ALNDataverseErrorResponseHeadersKey = @"response_headers";
NSString *const ALNDataverseErrorResponseBodyKey = @"response_body";
NSString *const ALNDataverseErrorRetryAfterKey = @"retry_after_seconds";
NSString *const ALNDataverseErrorCorrelationIDKey = @"correlation_id";
NSString *const ALNDataverseErrorTargetNameKey = @"target_name";

static NSTimeInterval const ALNDataverseDefaultTimeoutInterval = 60.0;
static NSUInteger const ALNDataverseDefaultMaxRetries = 2;
static NSUInteger const ALNDataverseDefaultPageSize = 500;

static NSString *ALNDataverseTrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static NSUInteger ALNDataverseUnsignedIntegerValue(id value, NSUInteger fallback) {
  if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
    NSUInteger parsed = [value unsignedIntegerValue];
    return parsed > 0 ? parsed : fallback;
  }
  return fallback;
}

static NSTimeInterval ALNDataverseTimeIntervalValue(id value, NSTimeInterval fallback) {
  if ([value respondsToSelector:@selector(doubleValue)]) {
    NSTimeInterval parsed = [value doubleValue];
    return parsed > 0 ? parsed : fallback;
  }
  return fallback;
}

static BOOL ALNDataverseIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [value characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

static BOOL ALNDataverseLooksLikeGUID(NSString *value) {
  NSString *trimmed = ALNDataverseTrimmedString(value);
  if ([trimmed length] != 36) {
    return NO;
  }
  for (NSUInteger idx = 0; idx < [trimmed length]; idx++) {
    unichar character = [trimmed characterAtIndex:idx];
    if (idx == 8 || idx == 13 || idx == 18 || idx == 23) {
      if (character != '-') {
        return NO;
      }
      continue;
    }
    if (!isxdigit((int)character)) {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNDataverseNumberLooksBoolean(NSNumber *number) {
  if (number == nil) {
    return NO;
  }
  const char *type = [number objCType];
  if (type == NULL) {
    return NO;
  }
  return (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "B") == 0);
}

static NSString *ALNDataverseEscapeODataStringLiteral(NSString *value) {
  return [ALNDataverseTrimmedString(value) stringByReplacingOccurrencesOfString:@"'"
                                                                     withString:@"''"];
}

static NSString *ALNDataverseCorrelationIDFromHeaders(NSDictionary<NSString *, NSString *> *headers) {
  NSArray<NSString *> *candidateKeys = @[
    @"x-ms-request-id",
    @"x-ms-correlation-request-id",
    @"request-id",
    @"activityid",
    @"x-ms-service-request-id",
  ];
  for (NSString *key in candidateKeys) {
    for (NSString *headerKey in [headers allKeys]) {
      if (![[ALNDataverseTrimmedString(headerKey) lowercaseString] isEqualToString:key]) {
        continue;
      }
      NSString *value = ALNDataverseTrimmedString(headers[headerKey]);
      if ([value length] > 0) {
        return value;
      }
    }
  }
  return nil;
}

static NSString *ALNDataverseTemporaryPath(NSString *prefix) {
  NSString *directory = NSTemporaryDirectory();
  NSString *name = [NSString stringWithFormat:@"%@-%@",
                                              ([prefix length] > 0 ? prefix : @"dataverse"),
                                              [[[NSUUID UUID] UUIDString] lowercaseString]];
  return [directory stringByAppendingPathComponent:name];
}

static NSData *ALNDataverseJSONStringData(id object, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (object == nil || object == [NSNull null]) {
    return nil;
  }
  NSJSONWritingOptions options = 0;
#ifdef NSJSONWritingSortedKeys
  options |= NSJSONWritingSortedKeys;
#endif
  return [ALNJSONSerialization dataWithJSONObject:object options:options error:error];
}

static NSString *ALNDataverseFormEncodedString(NSDictionary<NSString *, NSString *> *fields) {
  if (![fields isKindOfClass:[NSDictionary class]] || [fields count] == 0) {
    return @"";
  }
  NSMutableArray<NSString *> *pairs = [NSMutableArray array];
  NSArray<NSString *> *keys = [[fields allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableCharacterSet *mutableAllowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [mutableAllowed removeCharactersInString:@"&=+?"];
  for (NSString *key in keys) {
    NSString *value = ALNDataverseTrimmedString(fields[key]);
    NSString *encodedKey =
        [ALNDataverseTrimmedString(key) stringByAddingPercentEncodingWithAllowedCharacters:mutableAllowed] ?: @"";
    NSString *encodedValue =
        [value stringByAddingPercentEncodingWithAllowedCharacters:mutableAllowed] ?: @"";
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
  }
  return [pairs componentsJoinedByString:@"&"];
}

static NSDictionary<NSString *, NSString *> *ALNDataverseLowercaseHeaderMap(
    NSDictionary<NSString *, NSString *> *headers) {
  NSMutableDictionary<NSString *, NSString *> *lowercase = [NSMutableDictionary dictionary];
  NSArray<NSString *> *keys = [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSString *normalizedKey = [[ALNDataverseTrimmedString(key) lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *value = ALNDataverseTrimmedString(headers[key]);
    if ([normalizedKey length] > 0 && [value length] > 0) {
      lowercase[normalizedKey] = value;
    }
  }
  return [lowercase copy];
}

static NSDictionary<NSString *, NSString *> *ALNDataverseParseHeaders(NSString *headerText) {
  NSString *raw = [headerText isKindOfClass:[NSString class]] ? headerText : @"";
  if ([raw length] == 0) {
    return @{};
  }

  NSArray<NSString *> *lines = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSMutableArray<NSArray<NSString *> *> *blocks = [NSMutableArray array];
  NSMutableArray<NSString *> *current = [NSMutableArray array];
  for (NSString *line in lines) {
    NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedLine length] == 0) {
      if ([current count] > 0) {
        [blocks addObject:[NSArray arrayWithArray:current]];
        [current removeAllObjects];
      }
      continue;
    }
    [current addObject:trimmedLine];
  }
  if ([current count] > 0) {
    [blocks addObject:[NSArray arrayWithArray:current]];
  }

  NSArray<NSString *> *selected = nil;
  for (NSArray<NSString *> *candidate in blocks) {
    if ([candidate count] == 0) {
      continue;
    }
    NSString *first = candidate[0];
    if ([first hasPrefix:@"HTTP/"]) {
      selected = candidate;
    }
  }
  if (selected == nil) {
    return @{};
  }

  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
  for (NSUInteger idx = 1; idx < [selected count]; idx++) {
    NSString *line = selected[idx];
    NSRange separator = [line rangeOfString:@":"];
    if (separator.location == NSNotFound) {
      continue;
    }
    NSString *key = [[[line substringToIndex:separator.location] lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *value = [[line substringFromIndex:(separator.location + 1)]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key length] > 0 && [value length] > 0) {
      headers[key] = value;
    }
  }
  return [headers copy];
}

static NSString *ALNDataverseQueryStringFromParameters(NSDictionary<NSString *, NSString *> *parameters) {
  NSDictionary<NSString *, NSString *> *query = [parameters isKindOfClass:[NSDictionary class]] ? parameters : nil;
  if ([query count] == 0) {
    return @"";
  }
  NSArray<NSString *> *keys = [[query allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:[keys count]];
  NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [allowed removeCharactersInString:@"&=+"];
  for (NSString *key in keys) {
    NSString *value = query[key];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
      continue;
    }
    NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    NSString *encodedValue = [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
  }
  return [pairs componentsJoinedByString:@"&"];
}

static NSString *ALNDataverseAbsoluteURLString(NSString *serviceRootURLString,
                                               NSString *path,
                                               NSDictionary<NSString *, NSString *> *query) {
  NSString *rawPath = ALNDataverseTrimmedString(path);
  NSString *base = [ALNDataverseTrimmedString(serviceRootURLString)
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([rawPath hasPrefix:@"http://"] || [rawPath hasPrefix:@"https://"]) {
    if ([query count] == 0) {
      return rawPath;
    }
    NSString *separator = [rawPath containsString:@"?"] ? @"&" : @"?";
    return [rawPath stringByAppendingFormat:@"%@%@", separator, ALNDataverseQueryStringFromParameters(query)];
  }

  NSString *trimmedBase = [base hasSuffix:@"/"] ? [base substringToIndex:([base length] - 1)] : base;
  NSString *trimmedPath = rawPath;
  if ([trimmedPath hasPrefix:@"/"]) {
    trimmedPath = [trimmedPath substringFromIndex:1];
  }
  NSString *URLString = [NSString stringWithFormat:@"%@/%@", trimmedBase, trimmedPath];
  if ([query count] > 0) {
    URLString = [URLString stringByAppendingFormat:@"?%@", ALNDataverseQueryStringFromParameters(query)];
  }
  return URLString;
}

static NSInteger ALNDataverseHTTPStatusFromCurlOutput(NSString *output) {
  NSString *trimmed = [ALNDataverseTrimmedString(output)
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [trimmed integerValue];
}

static NSInteger ALNDataverseRetryAfterSeconds(NSDictionary<NSString *, NSString *> *headers) {
  NSString *value = ALNDataverseTrimmedString(headers[@"retry-after"]);
  if ([value length] == 0) {
    value = ALNDataverseTrimmedString(headers[@"Retry-After"]);
  }
  if ([value length] == 0) {
    value = ALNDataverseTrimmedString(headers[@"Retry-after"]);
  }
  NSInteger seconds = [value integerValue];
  if (seconds > 0) {
    return seconds;
  }

  if ([value length] == 0) {
    return 0;
  }
  static NSArray<NSDateFormatter *> *formatters = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSDateFormatter *rfc1123 = [[NSDateFormatter alloc] init];
    rfc1123.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    rfc1123.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    rfc1123.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss 'GMT'";

    NSDateFormatter *rfc850 = [[NSDateFormatter alloc] init];
    rfc850.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    rfc850.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    rfc850.dateFormat = @"EEEE, dd-MMM-yy HH:mm:ss 'GMT'";

    NSDateFormatter *asctime = [[NSDateFormatter alloc] init];
    asctime.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    asctime.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    asctime.dateFormat = @"EEE MMM d HH:mm:ss yyyy";

    formatters = @[ rfc1123, rfc850, asctime ];
  });

  NSDate *retryDate = nil;
  for (NSDateFormatter *formatter in formatters) {
    retryDate = [formatter dateFromString:value];
    if (retryDate != nil) {
      break;
    }
  }
  if (retryDate == nil) {
    return 0;
  }
  NSTimeInterval interval = ceil([retryDate timeIntervalSinceNow]);
  return (interval > 0) ? (NSInteger)interval : 0;
}

static NSDictionary<NSString *, NSString *> *ALNDataverseRedactedRequestHeaders(
    NSDictionary<NSString *, NSString *> *headers) {
  NSMutableDictionary<NSString *, NSString *> *sanitized = [NSMutableDictionary dictionary];
  NSArray<NSString *> *keys = [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSString *normalizedKey = [ALNDataverseTrimmedString(key) lowercaseString];
    NSString *value = ALNDataverseTrimmedString(headers[key]);
    if ([normalizedKey length] == 0 || [value length] == 0) {
      continue;
    }
    if ([normalizedKey isEqualToString:@"authorization"]) {
      sanitized[key] = @"Bearer [redacted]";
    } else {
      sanitized[key] = value;
    }
  }
  return [sanitized copy];
}

static NSDictionary<NSString *, id> *ALNDataverseResponseSummary(ALNDataverseResponse *response) {
  NSMutableDictionary<NSString *, id> *summary = [NSMutableDictionary dictionary];
  NSString *entityID = [response headerValueForName:@"odata-entityid"];
  NSString *location = [response headerValueForName:@"location"];
  NSString *etag = [response headerValueForName:@"etag"];
  if ([entityID length] > 0) {
    summary[@"odata_entity_id"] = entityID;
  }
  if ([location length] > 0) {
    summary[@"location"] = location;
  }
  if ([etag length] > 0) {
    summary[@"etag"] = etag;
  }
  return [summary copy];
}

static NSString *ALNDataversePreferHeader(NSUInteger pageSize,
                                          BOOL includeFormattedValues,
                                          BOOL returnRepresentation,
                                          NSString *existingValue) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSString *trimmedExisting = ALNDataverseTrimmedString(existingValue);
  if ([trimmedExisting length] > 0) {
    for (NSString *component in [trimmedExisting componentsSeparatedByString:@","]) {
      NSString *trimmedComponent =
          [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([trimmedComponent length] > 0) {
        [parts addObject:trimmedComponent];
      }
    }
  }
  if (pageSize > 0) {
    NSString *pageValue = [NSString stringWithFormat:@"odata.maxpagesize=%lu", (unsigned long)pageSize];
    if (![parts containsObject:pageValue]) {
      [parts addObject:pageValue];
    }
  }
  if (includeFormattedValues) {
    NSString *annotationValue = @"odata.include-annotations=\"OData.Community.Display.V1.FormattedValue\"";
    if (![parts containsObject:annotationValue]) {
      [parts addObject:annotationValue];
    }
  }
  if (returnRepresentation && ![parts containsObject:@"return=representation"]) {
    [parts addObject:@"return=representation"];
  }
  return [parts componentsJoinedByString:@", "];
}

static id ALNDataverseSerializedObject(id object, NSError **error);

static NSDictionary<NSString *, id> *ALNDataverseSerializedDictionary(NSDictionary<NSString *, id> *dictionary,
                                                                      NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSMutableDictionary<NSString *, id> *serialized = [NSMutableDictionary dictionary];
  NSArray<NSString *> *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSString *normalizedKey = ALNDataverseTrimmedString(key);
    if ([normalizedKey length] == 0) {
      continue;
    }
    id value = dictionary[key];
    if ([value isKindOfClass:[ALNDataverseLookupBinding class]]) {
      NSString *bindKey = [NSString stringWithFormat:@"%@@odata.bind", normalizedKey];
      NSString *bindPath = [(ALNDataverseLookupBinding *)value bindPath];
      if (![bindPath hasPrefix:@"/"]) {
        bindPath = [@"/" stringByAppendingString:bindPath];
      }
      serialized[bindKey] = bindPath;
      continue;
    }

    NSError *childError = nil;
    id serializedValue = ALNDataverseSerializedObject(value, &childError);
    if (serializedValue == nil && childError != nil) {
      if (error != NULL) {
        *error = childError;
      }
      return nil;
    }
    serialized[normalizedKey] = serializedValue ?: [NSNull null];
  }
  return [serialized copy];
}

static id ALNDataverseSerializedArray(NSArray *items, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSMutableArray *serialized = [NSMutableArray arrayWithCapacity:[items count]];
  for (id value in items) {
    NSError *childError = nil;
    id serializedValue = ALNDataverseSerializedObject(value, &childError);
    if (serializedValue == nil && childError != nil) {
      if (error != NULL) {
        *error = childError;
      }
      return nil;
    }
    [serialized addObject:serializedValue ?: [NSNull null]];
  }
  return [NSArray arrayWithArray:serialized];
}

static id ALNDataverseSerializedObject(id object, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (object == nil || object == [NSNull null]) {
    return [NSNull null];
  }
  if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]]) {
    return object;
  }
  if ([object isKindOfClass:[ALNDataverseChoiceValue class]]) {
    return [(ALNDataverseChoiceValue *)object numericValue];
  }
  if ([object isKindOfClass:[NSDictionary class]]) {
    return ALNDataverseSerializedDictionary((NSDictionary *)object, error);
  }
  if ([object isKindOfClass:[NSArray class]]) {
    return ALNDataverseSerializedArray((NSArray *)object, error);
  }
  if ([object isKindOfClass:[NSDate class]]) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
      formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
      formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });
    return [formatter stringFromDate:(NSDate *)object] ?: @"";
  }
  if ([object isKindOfClass:[NSUUID class]]) {
    return [(NSUUID *)object UUIDString];
  }
  if ([object respondsToSelector:@selector(stringValue)]) {
    return [object stringValue] ?: @"";
  }
  if (error != NULL) {
    *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                   @"Dataverse payload contains an unsupported value type",
                                   @{ @"value" : [object description] ?: @"" });
  }
  return nil;
}

static NSString *ALNDataverseODataLiteral(id value, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (value == nil || value == [NSNull null]) {
    return @"null";
  }
  if ([value isKindOfClass:[NSString class]]) {
    NSString *text = (NSString *)value;
    if (ALNDataverseLooksLikeGUID(text)) {
      return text;
    }
    return [NSString stringWithFormat:@"'%@'", ALNDataverseEscapeODataStringLiteral(text)];
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    if (ALNDataverseNumberLooksBoolean((NSNumber *)value)) {
      return [(NSNumber *)value boolValue] ? @"true" : @"false";
    }
    return [(NSNumber *)value stringValue];
  }
  if ([value isKindOfClass:[NSUUID class]]) {
    return [(NSUUID *)value UUIDString];
  }
  if ([value isKindOfClass:[NSDate class]]) {
    return ALNDataverseSerializedObject(value, error);
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [NSString stringWithFormat:@"'%@'",
                                      ALNDataverseEscapeODataStringLiteral([value stringValue] ?: @"")];
  }
  if (error != NULL) {
    *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                   @"Dataverse key predicate contains an unsupported literal value",
                                   @{ @"value" : [value description] ?: @"" });
  }
  return nil;
}

static NSString *ALNDataverseBatchHTTPPath(NSString *serviceRootURLString, NSString *relativePath) {
  NSString *path = ALNDataverseTrimmedString(relativePath);
  if ([path hasPrefix:@"http://"] || [path hasPrefix:@"https://"]) {
    NSURLComponents *components = [NSURLComponents componentsWithString:path];
    NSString *result = components.path ?: path;
    if ([components.query length] > 0) {
      result = [result stringByAppendingFormat:@"?%@", components.query];
    }
    return result;
  }
  if ([path hasPrefix:@"/api/"]) {
    return path;
  }
  NSURLComponents *components = [NSURLComponents componentsWithString:serviceRootURLString];
  NSString *servicePath = components.path ?: @"";
  if ([servicePath hasSuffix:@"/"]) {
    servicePath = [servicePath substringToIndex:([servicePath length] - 1)];
  }
  if (![path hasPrefix:@"/"]) {
    path = [@"/" stringByAppendingString:path];
  }
  return [servicePath stringByAppendingString:path];
}

static NSArray<ALNDataverseBatchResponse *> *ALNDataverseParseBatchResponses(ALNDataverseResponse *response,
                                                                             NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *contentType = [response headerValueForName:@"content-type"] ?: @"";
  NSRange boundaryRange = [[contentType lowercaseString] rangeOfString:@"boundary="];
  if (boundaryRange.location == NSNotFound) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                     @"Dataverse batch response is missing a multipart boundary",
                                     @{
                                       ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"",
                                     });
    }
    return nil;
  }
  NSString *boundary = [contentType substringFromIndex:(boundaryRange.location + boundaryRange.length)];
  boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([boundary hasPrefix:@"\""] && [boundary hasSuffix:@"\""] && [boundary length] > 1) {
    boundary = [boundary substringWithRange:NSMakeRange(1, [boundary length] - 2)];
  }
  NSString *delimiter = [NSString stringWithFormat:@"--%@", boundary];
  NSArray<NSString *> *parts = [response.bodyText componentsSeparatedByString:delimiter];
  NSMutableArray<ALNDataverseBatchResponse *> *parsed = [NSMutableArray array];
  for (NSString *rawPart in parts) {
    NSString *part = [rawPart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([part length] == 0 || [part isEqualToString:@"--"]) {
      continue;
    }
    NSRange statusRange = [part rangeOfString:@"HTTP/1.1 "];
    if (statusRange.location == NSNotFound) {
      continue;
    }
    NSString *httpSection = [part substringFromIndex:statusRange.location];
    NSArray<NSString *> *lines = [httpSection componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if ([lines count] == 0) {
      continue;
    }
    NSString *statusLine = [lines[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *statusParts = [statusLine componentsSeparatedByString:@" "];
    NSInteger statusCode = ([statusParts count] >= 2) ? [statusParts[1] integerValue] : 0;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *bodyLines = [NSMutableArray array];
    BOOL inBody = NO;
    for (NSUInteger idx = 1; idx < [lines count]; idx++) {
      NSString *line = [lines[idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (!inBody) {
        if ([line length] == 0) {
          inBody = YES;
          continue;
        }
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location != NSNotFound) {
          NSString *key = [[[line substringToIndex:separator.location] lowercaseString]
              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          NSString *value = [[line substringFromIndex:(separator.location + 1)]
              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if ([key length] > 0 && [value length] > 0) {
            headers[key] = value;
          }
        }
      } else {
        [bodyLines addObject:line ?: @""];
      }
    }
    NSString *bodyText = [bodyLines componentsJoinedByString:@"\n"];
    id bodyObject = nil;
    if ([bodyText length] > 0) {
      NSError *jsonError = nil;
      NSData *bodyData = [bodyText dataUsingEncoding:NSUTF8StringEncoding];
      bodyObject = [ALNJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
      if (jsonError != nil) {
        bodyObject = nil;
      }
    }
    NSString *contentID = headers[@"content-id"];
    ALNDataverseBatchResponse *batchResponse =
        [[ALNDataverseBatchResponse alloc] initWithStatusCode:statusCode
                                                      headers:headers
                                                   bodyObject:bodyObject
                                                     bodyText:bodyText
                                                    contentID:contentID];
    [parsed addObject:batchResponse];
  }
  return [NSArray arrayWithArray:parsed];
}

NSError *ALNDataverseMakeError(ALNDataverseErrorCode code,
                               NSString *message,
                               NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"Dataverse error";
  return [NSError errorWithDomain:ALNDataverseErrorDomain code:code userInfo:details];
}

@interface ALNDataverseTarget ()
@property(nonatomic, copy, readwrite) NSString *serviceRootURLString;
@property(nonatomic, copy, readwrite) NSString *environmentURLString;
@property(nonatomic, copy, readwrite) NSString *tenantID;
@property(nonatomic, copy, readwrite) NSString *clientID;
@property(nonatomic, copy, readwrite) NSString *clientSecret;
@property(nonatomic, copy, readwrite) NSString *targetName;
@property(nonatomic, assign, readwrite) NSTimeInterval timeoutInterval;
@property(nonatomic, assign, readwrite) NSUInteger maxRetries;
@property(nonatomic, assign, readwrite) NSUInteger pageSize;
@end

@interface ALNDataverseResponse ()
@property(nonatomic, assign, readwrite) NSInteger statusCode;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, copy, readwrite) NSData *bodyData;
@property(nonatomic, copy, readwrite) NSString *bodyText;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *lowercaseHeaders;
@end

@interface ALNDataverseClientCredentialsTokenProvider ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *tokenCache;
@end

@interface ALNDataverseRecord ()
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *formattedValues;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *annotations;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *rawDictionary;
@property(nonatomic, copy, readwrite) NSString *etag;
@end

@interface ALNDataverseEntityPage ()
@property(nonatomic, copy, readwrite) NSArray<ALNDataverseRecord *> *records;
@property(nonatomic, copy, readwrite) NSString *nextLinkURLString;
@property(nonatomic, copy, readwrite) NSString *deltaLinkURLString;
@property(nonatomic, strong, readwrite) NSNumber *totalCount;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *rawPayload;
@end

@interface ALNDataverseClient ()
@property(nonatomic, strong, readwrite) ALNDataverseTarget *target;
@property(nonatomic, strong, readwrite) id<ALNDataverseTransport> transport;
@property(nonatomic, strong, readwrite) id<ALNDataverseTokenProvider> tokenProvider;
- (nullable ALNDataverseResponse *)executeAuthorizedRequestWithMethod:(NSString *)method
                                                            URLString:(NSString *)URLString
                                                              headers:(NSDictionary<NSString *, NSString *> *)headers
                                                             bodyData:(nullable NSData *)bodyData
                                                                error:(NSError **)error;
@end

@implementation ALNDataverseTarget

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException
              format:@"Use -initWithServiceRootURLString:tenantID:clientID:clientSecret:targetName:timeoutInterval:maxRetries:pageSize:error:"];
  return nil;
}

+ (NSString *)normalizedEnvironmentURLStringFromServiceRootURLString:(NSString *)serviceRootURLString {
  NSString *serviceRoot = ALNDataverseTrimmedString(serviceRootURLString);
  if ([serviceRoot length] == 0) {
    return nil;
  }
  NSString *trimmed = [serviceRoot hasSuffix:@"/"] ? [serviceRoot substringToIndex:([serviceRoot length] - 1)] : serviceRoot;
  NSString *lowercase = [trimmed lowercaseString];
  NSRange marker = [lowercase rangeOfString:@"/api/data/"];
  if (marker.location != NSNotFound) {
    return [trimmed substringToIndex:marker.location];
  }
  if ([lowercase hasSuffix:@"/api"]) {
    return [trimmed substringToIndex:([trimmed length] - 4)];
  }
  return trimmed;
}

+ (NSArray<NSString *> *)configuredTargetNamesFromConfig:(NSDictionary *)config {
  NSMutableOrderedSet<NSString *> *targets = [NSMutableOrderedSet orderedSet];
  NSDictionary *root = [config[@"dataverse"] isKindOfClass:[NSDictionary class]] ? config[@"dataverse"] : nil;
  NSDictionary *topTargets =
      [config[@"dataverseTargets"] isKindOfClass:[NSDictionary class]] ? config[@"dataverseTargets"] : nil;
  NSDictionary *nestedTargets =
      [root[@"targets"] isKindOfClass:[NSDictionary class]] ? root[@"targets"] : nil;

  for (NSString *key in [topTargets allKeys] ?: @[]) {
    NSString *normalized = [[ALNDataverseTrimmedString(key) lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized length] > 0) {
      [targets addObject:normalized];
    }
  }
  for (NSString *key in [nestedTargets allKeys] ?: @[]) {
    NSString *normalized = [[ALNDataverseTrimmedString(key) lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized length] > 0) {
      [targets addObject:normalized];
    }
  }
  return [[targets array] sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSDictionary<NSString *, id> *)configurationNamed:(NSString *)targetName
                                          fromConfig:(NSDictionary *)config {
  NSDictionary *root = [config[@"dataverse"] isKindOfClass:[NSDictionary class]] ? config[@"dataverse"] : nil;
  NSString *normalizedTarget = [[ALNDataverseTrimmedString(targetName) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalizedTarget length] == 0) {
    normalizedTarget = @"default";
  }
  if ([normalizedTarget isEqualToString:@"default"]) {
    return root;
  }

  NSDictionary *topTargets =
      [config[@"dataverseTargets"] isKindOfClass:[NSDictionary class]] ? config[@"dataverseTargets"] : nil;
  NSDictionary *nestedTargets =
      [root[@"targets"] isKindOfClass:[NSDictionary class]] ? root[@"targets"] : nil;
  NSDictionary *targetConfig =
      [topTargets[normalizedTarget] isKindOfClass:[NSDictionary class]] ? topTargets[normalizedTarget]
      : ([nestedTargets[normalizedTarget] isKindOfClass:[NSDictionary class]] ? nestedTargets[normalizedTarget] : nil);
  if (targetConfig == nil) {
    return nil;
  }

  NSMutableDictionary *merged = [NSMutableDictionary dictionary];
  for (NSString *key in root) {
    if ([key isEqualToString:@"targets"]) {
      continue;
    }
    merged[key] = root[key];
  }
  for (NSString *key in targetConfig) {
    merged[key] = targetConfig[key];
  }
  return [merged copy];
}

+ (instancetype)targetNamed:(NSString *)targetName fromConfig:(NSDictionary *)config error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSDictionary<NSString *, id> *resolved = [self configurationNamed:targetName fromConfig:config];
  if (![resolved isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidConfiguration,
                                     @"Dataverse configuration is missing or invalid",
                                     nil);
    }
    return nil;
  }
  NSString *serviceRoot = resolved[@"serviceRootURL"];
  if ([serviceRoot length] == 0) {
    serviceRoot = resolved[@"serviceRoot"];
  }
  if ([serviceRoot length] == 0) {
    serviceRoot = resolved[@"baseURL"];
  }
  if ([serviceRoot length] == 0) {
    serviceRoot = resolved[@"url"];
  }
  NSString *tenantID = resolved[@"tenantID"];
  if ([tenantID length] == 0) {
    tenantID = resolved[@"tenantId"];
  }
  NSString *clientID = resolved[@"clientID"];
  if ([clientID length] == 0) {
    clientID = resolved[@"clientId"];
  }
  NSString *clientSecret = resolved[@"clientSecret"];
  NSTimeInterval timeout = ALNDataverseTimeIntervalValue(resolved[@"timeout"], ALNDataverseDefaultTimeoutInterval);
  NSUInteger maxRetries = ALNDataverseUnsignedIntegerValue(resolved[@"maxRetries"], ALNDataverseDefaultMaxRetries);
  NSUInteger pageSize = ALNDataverseUnsignedIntegerValue(resolved[@"pageSize"], ALNDataverseDefaultPageSize);
  return [[self alloc] initWithServiceRootURLString:serviceRoot
                                           tenantID:tenantID
                                           clientID:clientID
                                       clientSecret:clientSecret
                                         targetName:targetName
                                    timeoutInterval:timeout
                                         maxRetries:maxRetries
                                           pageSize:pageSize
                                              error:error];
}

- (instancetype)initWithServiceRootURLString:(NSString *)serviceRootURLString
                                    tenantID:(NSString *)tenantID
                                    clientID:(NSString *)clientID
                                clientSecret:(NSString *)clientSecret
                                   targetName:(NSString *)targetName
                              timeoutInterval:(NSTimeInterval)timeoutInterval
                                   maxRetries:(NSUInteger)maxRetries
                                     pageSize:(NSUInteger)pageSize
                                        error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *serviceRoot = ALNDataverseTrimmedString(serviceRootURLString);
  NSString *normalizedTenant = ALNDataverseTrimmedString(tenantID);
  NSString *normalizedClientID = ALNDataverseTrimmedString(clientID);
  NSString *normalizedSecret = ALNDataverseTrimmedString(clientSecret);
  NSString *normalizedTargetName = [[ALNDataverseTrimmedString(targetName) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalizedTargetName length] == 0) {
    normalizedTargetName = @"default";
  }
  NSString *environmentURL = [[self class] normalizedEnvironmentURLStringFromServiceRootURLString:serviceRoot];
  if ([serviceRoot length] == 0 || [environmentURL length] == 0 || [normalizedTenant length] == 0 ||
      [normalizedClientID length] == 0 || [normalizedSecret length] == 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidConfiguration,
                                     @"Dataverse target requires service root URL, tenant ID, client ID, and client secret",
                                     nil);
    }
    return nil;
  }
  if (!([serviceRoot hasPrefix:@"https://"] || [serviceRoot hasPrefix:@"http://"])) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidConfiguration,
                                     @"Dataverse service root URL must include an http or https scheme",
                                     @{ @"service_root_url" : serviceRoot ?: @"" });
    }
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _serviceRootURLString = [serviceRoot copy];
  _environmentURLString = [environmentURL copy];
  _tenantID = [normalizedTenant copy];
  _clientID = [normalizedClientID copy];
  _clientSecret = [normalizedSecret copy];
  _targetName = [normalizedTargetName copy];
  _timeoutInterval = timeoutInterval > 0 ? timeoutInterval : ALNDataverseDefaultTimeoutInterval;
  _maxRetries = maxRetries;
  _pageSize = pageSize > 0 ? pageSize : ALNDataverseDefaultPageSize;
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  NSError *error = nil;
  ALNDataverseTarget *copy = [[[self class] allocWithZone:zone]
      initWithServiceRootURLString:self.serviceRootURLString
                          tenantID:self.tenantID
                          clientID:self.clientID
                      clientSecret:self.clientSecret
                         targetName:self.targetName
                    timeoutInterval:self.timeoutInterval
                         maxRetries:self.maxRetries
                           pageSize:self.pageSize
                              error:&error];
  NSCAssert(copy != nil && error == nil, @"Dataverse target copy must succeed");
  return copy;
}

@end

@implementation ALNDataverseLookupBinding

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithBindPath:"];
  return nil;
}

+ (instancetype)bindingWithBindPath:(NSString *)bindPath {
  return [[self alloc] initWithBindPath:bindPath];
}

+ (instancetype)bindingWithEntitySetName:(NSString *)entitySetName recordID:(NSString *)recordID error:(NSError **)error {
  NSString *path = [ALNDataverseClient recordPathForEntitySet:entitySetName recordID:recordID error:error];
  if ([path length] == 0) {
    return nil;
  }
  return [[self alloc] initWithBindPath:path];
}

- (instancetype)initWithBindPath:(NSString *)bindPath {
  NSString *path = ALNDataverseTrimmedString(bindPath);
  if ([path length] == 0) {
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _bindPath = [path copy];
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] initWithBindPath:self.bindPath];
}

@end

@implementation ALNDataverseChoiceValue

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithIntegerValue:"];
  return nil;
}

+ (instancetype)valueWithIntegerValue:(NSNumber *)integerValue {
  return [[self alloc] initWithIntegerValue:integerValue];
}

- (instancetype)initWithIntegerValue:(NSNumber *)integerValue {
  NSString *stringValue = ALNDataverseTrimmedString(integerValue);
  if ([stringValue length] == 0) {
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _numericValue = [integerValue copy];
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] initWithIntegerValue:self.numericValue];
}

@end

@implementation ALNDataverseRequest

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithMethod:URLString:headers:bodyData:"];
  return nil;
}

- (instancetype)initWithMethod:(NSString *)method
                     URLString:(NSString *)URLString
                       headers:(NSDictionary<NSString *, NSString *> *)headers
                      bodyData:(NSData *)bodyData {
  NSString *normalizedMethod = [[ALNDataverseTrimmedString(method) uppercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *normalizedURL = ALNDataverseTrimmedString(URLString);
  if ([normalizedMethod length] == 0 || [normalizedURL length] == 0) {
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _method = [normalizedMethod copy];
  _URLString = [normalizedURL copy];
  _headers = [headers isKindOfClass:[NSDictionary class]] ? [headers copy] : @{};
  _bodyData = [bodyData copy];
  return self;
}

@end

@implementation ALNDataverseResponse

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithStatusCode:headers:bodyData:"];
  return nil;
}

- (instancetype)initWithStatusCode:(NSInteger)statusCode
                           headers:(NSDictionary<NSString *, NSString *> *)headers
                          bodyData:(NSData *)bodyData {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _statusCode = statusCode;
  _headers = [headers isKindOfClass:[NSDictionary class]] ? [headers copy] : @{};
  _lowercaseHeaders = ALNDataverseLowercaseHeaderMap(_headers);
  _bodyData = [bodyData copy] ?: [NSData data];
  _bodyText = [[NSString alloc] initWithData:_bodyData encoding:NSUTF8StringEncoding] ?: @"";
  return self;
}

- (NSString *)headerValueForName:(NSString *)name {
  return self.lowercaseHeaders[[[ALNDataverseTrimmedString(name) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}

- (id)JSONObject:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if ([self.bodyData length] == 0) {
    return nil;
  }
  return [ALNJSONSerialization JSONObjectWithData:self.bodyData options:0 error:error];
}

@end

@implementation ALNDataverseCurlTransport

- (instancetype)init {
  return [self initWithTimeoutInterval:ALNDataverseDefaultTimeoutInterval];
}

- (instancetype)initWithTimeoutInterval:(NSTimeInterval)timeoutInterval {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _timeoutInterval = timeoutInterval > 0 ? timeoutInterval : ALNDataverseDefaultTimeoutInterval;
  return self;
}

- (ALNDataverseResponse *)executeRequest:(ALNDataverseRequest *)request error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (request == nil) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse transport request is required",
                                     nil);
    }
    return nil;
  }

  NSString *headerPath = ALNDataverseTemporaryPath(@"dataverse-headers");
  NSString *bodyPath = ALNDataverseTemporaryPath(@"dataverse-body");
  NSString *requestBodyPath = nil;
  if ([request.bodyData length] > 0) {
    requestBodyPath = ALNDataverseTemporaryPath(@"dataverse-request");
    BOOL wrote = [request.bodyData writeToFile:requestBodyPath atomically:YES];
    if (!wrote) {
      if (error != NULL) {
        *error = ALNDataverseMakeError(ALNDataverseErrorTransportFailed,
                                       @"Dataverse transport could not stage the request body",
                                       @{ ALNDataverseErrorRequestURLKey : request.URLString ?: @"" });
      }
      return nil;
    }
  }

  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  [arguments addObjectsFromArray:@[
    @"curl",
    @"--silent",
    @"--show-error",
    @"--no-progress-meter",
    @"--globoff",
    @"--request",
    request.method ?: @"GET",
    @"--dump-header",
    headerPath,
    @"--output",
    bodyPath,
    @"--write-out",
    @"%{http_code}",
    @"--max-time",
    [NSString stringWithFormat:@"%.0f", self.timeoutInterval],
    @"--connect-timeout",
    [NSString stringWithFormat:@"%.0f", MIN(self.timeoutInterval, 30.0)],
  ]];
  NSArray<NSString *> *headerKeys = [[request.headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in headerKeys) {
    NSString *value = request.headers[key];
    if ([ALNDataverseTrimmedString(key) length] == 0 || [ALNDataverseTrimmedString(value) length] == 0) {
      continue;
    }
    [arguments addObject:@"--header"];
    [arguments addObject:[NSString stringWithFormat:@"%@: %@", key, value]];
  }
  if ([request.bodyData length] > 0 && [requestBodyPath length] > 0) {
    [arguments addObject:@"--data-binary"];
    [arguments addObject:[NSString stringWithFormat:@"@%@", requestBodyPath]];
  }
  [arguments addObject:request.URLString ?: @""];

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/env";
  task.arguments = arguments;
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;

  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorTransportFailed,
                                     @"Dataverse transport could not launch curl",
                                     @{
                                       ALNDataverseErrorRequestURLKey : request.URLString ?: @"",
                                       @"exception" : exception.reason ?: @"",
                                     });
    }
    [[NSFileManager defaultManager] removeItemAtPath:headerPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:bodyPath error:nil];
    if ([requestBodyPath length] > 0) {
      [[NSFileManager defaultManager] removeItemAtPath:requestBodyPath error:nil];
    }
    return nil;
  }

  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
  NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";

  NSData *payload = [NSData dataWithContentsOfFile:bodyPath] ?: [NSData data];
  NSString *headerText = [[NSString alloc] initWithContentsOfFile:headerPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil] ?: @"";
  [[NSFileManager defaultManager] removeItemAtPath:headerPath error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:bodyPath error:nil];
  if ([requestBodyPath length] > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:requestBodyPath error:nil];
  }

  if (task.terminationStatus != 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorTransportFailed,
                                     @"Dataverse transport curl request failed",
                                     @{
                                       ALNDataverseErrorRequestURLKey : request.URLString ?: @"",
                                       @"curl_exit_code" : @(task.terminationStatus),
                                       @"curl_stderr" : stderrText ?: @"",
                                     });
    }
    return nil;
  }

  NSInteger statusCode = ALNDataverseHTTPStatusFromCurlOutput(stdoutText);
  NSDictionary<NSString *, NSString *> *headers = ALNDataverseParseHeaders(headerText);
  return [[ALNDataverseResponse alloc] initWithStatusCode:statusCode headers:headers bodyData:payload];
}

@end

@implementation ALNDataverseClientCredentialsTokenProvider

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _tokenCache = [NSMutableDictionary dictionary];
  return self;
}

- (NSString *)accessTokenForTarget:(ALNDataverseTarget *)target
                         transport:(id<ALNDataverseTransport>)transport
                             error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%@",
                                                  target.environmentURLString ?: @"",
                                                  target.tenantID ?: @"",
                                                  target.clientID ?: @""];
  NSDictionary<NSString *, id> *cached = self.tokenCache[cacheKey];
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSNumber *expiresAt = [cached[@"expires_at"] isKindOfClass:[NSNumber class]] ? cached[@"expires_at"] : nil;
  NSString *cachedToken = [cached[@"access_token"] isKindOfClass:[NSString class]] ? cached[@"access_token"] : nil;
  if ([cachedToken length] > 0 && expiresAt != nil && [expiresAt doubleValue] > (now + 60.0)) {
    return cachedToken;
  }

  NSString *scope = [NSString stringWithFormat:@"%@/.default", target.environmentURLString ?: @""];
  NSString *bodyString = ALNDataverseFormEncodedString(@{
    @"client_id" : target.clientID ?: @"",
    @"client_secret" : target.clientSecret ?: @"",
    @"grant_type" : @"client_credentials",
    @"scope" : scope ?: @"",
  });
  NSData *bodyData = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
  NSString *tokenURLString =
      [NSString stringWithFormat:@"https://login.microsoftonline.com/%@/oauth2/v2.0/token",
                                 target.tenantID ?: @""];
  ALNDataverseRequest *request = [[ALNDataverseRequest alloc]
      initWithMethod:@"POST"
           URLString:tokenURLString
             headers:@{
               @"Accept" : @"application/json",
               @"Content-Type" : @"application/x-www-form-urlencoded",
             }
            bodyData:bodyData];
  NSError *transportError = nil;
  ALNDataverseResponse *response = [transport executeRequest:request error:&transportError];
  if (response == nil) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorAuthenticationFailed,
                                     @"Dataverse token request failed",
                                     @{
                                       NSUnderlyingErrorKey : transportError ?: [NSNull null],
                                       ALNDataverseErrorRequestURLKey : tokenURLString ?: @"",
                                     });
    }
    return nil;
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorAuthenticationFailed,
                                     @"Dataverse token request returned a non-success status",
                                     @{
                                       ALNDataverseErrorHTTPStatusKey : @(response.statusCode),
                                       ALNDataverseErrorRequestURLKey : tokenURLString ?: @"",
                                       ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"",
                                       ALNDataverseErrorResponseHeadersKey : response.headers ?: @{},
                                     });
    }
    return nil;
  }

  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  NSString *accessToken = [payload[@"access_token"] isKindOfClass:[NSString class]] ? payload[@"access_token"] : nil;
  NSTimeInterval expiresIn = [payload[@"expires_in"] respondsToSelector:@selector(doubleValue)]
                                 ? [payload[@"expires_in"] doubleValue]
                                 : 3600.0;
  if ([accessToken length] == 0 || jsonError != nil) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorAuthenticationFailed,
                                     @"Dataverse token response payload was invalid",
                                     @{
                                       ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"",
                                     });
    }
    return nil;
  }

  self.tokenCache[cacheKey] = @{
    @"access_token" : accessToken,
    @"expires_at" : @([[NSDate date] timeIntervalSince1970] + expiresIn),
  };
  return accessToken;
}

@end

@implementation ALNDataverseRecord

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithDictionary:error:"];
  return nil;
}

+ (instancetype)recordWithDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError **)error {
  return [[self alloc] initWithDictionary:dictionary error:error];
}

- (instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![dictionary isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                     @"Dataverse record payload must be a dictionary",
                                     nil);
    }
    return nil;
  }

  self = [super init];
  if (self == nil) {
    return nil;
  }

  NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, id> *formattedValues = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, id> *annotations = [NSMutableDictionary dictionary];
  NSArray<NSString *> *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    id value = dictionary[key];
    if ([key isEqualToString:@"@odata.etag"]) {
      _etag = [ALNDataverseTrimmedString(value) copy];
      continue;
    }
    NSRange annotationSeparator = [key rangeOfString:@"@"];
    if (annotationSeparator.location == NSNotFound || annotationSeparator.location == 0) {
      values[key] = value ?: [NSNull null];
      continue;
    }
    NSString *baseKey = [key substringToIndex:annotationSeparator.location];
    NSString *annotation = [key substringFromIndex:(annotationSeparator.location + 1)];
    if ([annotation isEqualToString:@"OData.Community.Display.V1.FormattedValue"]) {
      formattedValues[baseKey] = value ?: [NSNull null];
    } else {
      annotations[key] = value ?: [NSNull null];
    }
  }

  _values = [values copy];
  _formattedValues = [formattedValues copy];
  _annotations = [annotations copy];
  _rawDictionary = [dictionary copy];
  return self;
}

@end

@implementation ALNDataverseEntityPage

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithPayload:error:"];
  return nil;
}

+ (instancetype)pageWithPayload:(NSDictionary<NSString *, id> *)payload error:(NSError **)error {
  return [[self alloc] initWithPayload:payload error:error];
}

- (instancetype)initWithPayload:(NSDictionary<NSString *, id> *)payload error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSArray *items = [payload[@"value"] isKindOfClass:[NSArray class]] ? payload[@"value"] : nil;
  if (![payload isKindOfClass:[NSDictionary class]] || items == nil) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                     @"Dataverse page payload must contain a value array",
                                     nil);
    }
    return nil;
  }

  self = [super init];
  if (self == nil) {
    return nil;
  }

  NSMutableArray<ALNDataverseRecord *> *records = [NSMutableArray arrayWithCapacity:[items count]];
  for (id item in items) {
    NSError *recordError = nil;
    ALNDataverseRecord *record = [ALNDataverseRecord recordWithDictionary:item error:&recordError];
    if (record == nil) {
      if (error != NULL) {
        *error = recordError;
      }
      return nil;
    }
    [records addObject:record];
  }

  _records = [records copy];
  _nextLinkURLString = [[payload[@"@odata.nextLink"] isKindOfClass:[NSString class]] ? payload[@"@odata.nextLink"] : nil copy];
  _deltaLinkURLString = [[payload[@"@odata.deltaLink"] isKindOfClass:[NSString class]] ? payload[@"@odata.deltaLink"] : nil copy];
  _totalCount =
      [payload[@"@odata.count"] respondsToSelector:@selector(integerValue)] ? payload[@"@odata.count"] : nil;
  _rawPayload = [payload copy];
  return self;
}

@end

@implementation ALNDataverseBatchRequest

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithMethod:relativePath:headers:bodyObject:contentID:"];
  return nil;
}

+ (instancetype)requestWithMethod:(NSString *)method
                     relativePath:(NSString *)relativePath
                          headers:(NSDictionary<NSString *, NSString *> *)headers
                       bodyObject:(id)bodyObject
                        contentID:(NSString *)contentID {
  return [[self alloc] initWithMethod:method
                         relativePath:relativePath
                              headers:headers
                           bodyObject:bodyObject
                            contentID:contentID];
}

- (instancetype)initWithMethod:(NSString *)method
                  relativePath:(NSString *)relativePath
                       headers:(NSDictionary<NSString *, NSString *> *)headers
                    bodyObject:(id)bodyObject
                     contentID:(NSString *)contentID {
  NSString *normalizedMethod = [[ALNDataverseTrimmedString(method) uppercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *normalizedPath = ALNDataverseTrimmedString(relativePath);
  if ([normalizedMethod length] == 0 || [normalizedPath length] == 0) {
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _method = [normalizedMethod copy];
  _relativePath = [normalizedPath copy];
  _headers = [headers isKindOfClass:[NSDictionary class]] ? [headers copy] : @{};
  _bodyObject = bodyObject;
  _contentID = [ALNDataverseTrimmedString(contentID) copy];
  return self;
}

@end

@implementation ALNDataverseBatchResponse

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithStatusCode:headers:bodyObject:bodyText:contentID:"];
  return nil;
}

- (instancetype)initWithStatusCode:(NSInteger)statusCode
                           headers:(NSDictionary<NSString *, NSString *> *)headers
                        bodyObject:(id)bodyObject
                          bodyText:(NSString *)bodyText
                         contentID:(NSString *)contentID {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _statusCode = statusCode;
  _headers = [headers isKindOfClass:[NSDictionary class]] ? [headers copy] : @{};
  _bodyObject = bodyObject;
  _bodyText = [bodyText copy] ?: @"";
  _contentID = [ALNDataverseTrimmedString(contentID) copy];
  return self;
}

@end

@implementation ALNDataverseClient

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithTarget:error:"];
  return nil;
}

+ (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"adapter_name" : @"dataverse",
    @"transport" : @"http",
    @"runtime_default_active" : @NO,
    @"sql_queries" : @NO,
    @"transactions" : @NO,
    @"paging" : @YES,
    @"formatted_values" : @YES,
    @"alternate_keys" : @YES,
    @"lookup_bindings" : @YES,
    @"batch" : @YES,
    @"actions" : @YES,
    @"functions" : @YES,
    @"metadata" : @YES,
    @"typed_codegen" : @YES,
    @"retry_after" : @YES,
  };
}

+ (NSString *)recordPathForEntitySet:(NSString *)entitySetName recordID:(NSString *)recordID error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *entitySet = ALNDataverseTrimmedString(entitySetName);
  NSString *identifier = ALNDataverseTrimmedString(recordID);
  if (!ALNDataverseIdentifierIsSafe(entitySet) || [identifier length] == 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse entity set and record identifier are required",
                                     nil);
    }
    return nil;
  }
  if ([identifier hasPrefix:@"("] && [identifier hasSuffix:@")"]) {
    return [NSString stringWithFormat:@"%@%@", entitySet, identifier];
  }
  if ([identifier containsString:@"="]) {
    return [NSString stringWithFormat:@"%@(%@)", entitySet, identifier];
  }
  return [NSString stringWithFormat:@"%@(%@)", entitySet, identifier];
}

+ (NSString *)recordPathForEntitySet:(NSString *)entitySetName
                   alternateKeyValues:(NSDictionary<NSString *, id> *)alternateKeyValues
                                error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *entitySet = ALNDataverseTrimmedString(entitySetName);
  if (!ALNDataverseIdentifierIsSafe(entitySet) || ![alternateKeyValues isKindOfClass:[NSDictionary class]] ||
      [alternateKeyValues count] == 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse alternate-key upsert requires a safe entity set name and key values",
                                     nil);
    }
    return nil;
  }

  NSArray<NSString *> *keys = [[alternateKeyValues allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[keys count]];
  for (NSString *key in keys) {
    if (!ALNDataverseIdentifierIsSafe(key)) {
      if (error != NULL) {
        *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                       @"Dataverse alternate-key name must be a safe identifier",
                                       @{ @"key" : key ?: @"" });
      }
      return nil;
    }
    NSError *literalError = nil;
    NSString *literal = ALNDataverseODataLiteral(alternateKeyValues[key], &literalError);
    if ([literal length] == 0 || literalError != nil) {
      if (error != NULL) {
        *error = literalError;
      }
      return nil;
    }
    [parts addObject:[NSString stringWithFormat:@"%@=%@", key, literal]];
  }
  return [NSString stringWithFormat:@"%@(%@)", entitySet, [parts componentsJoinedByString:@","]];
}

- (instancetype)initWithTarget:(ALNDataverseTarget *)target error:(NSError **)error {
  return [self initWithTarget:target transport:nil tokenProvider:nil error:error];
}

- (instancetype)initWithTarget:(ALNDataverseTarget *)target
                     transport:(id<ALNDataverseTransport>)transport
                 tokenProvider:(id<ALNDataverseTokenProvider>)tokenProvider
                         error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (target == nil) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidConfiguration,
                                     @"Dataverse client requires a target",
                                     nil);
    }
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _target = target;
  _transport = transport ?: [[ALNDataverseCurlTransport alloc] initWithTimeoutInterval:target.timeoutInterval];
  _tokenProvider = tokenProvider ?: [[ALNDataverseClientCredentialsTokenProvider alloc] init];
  return self;
}

- (NSDictionary<NSString *, id> *)ping:(NSError **)error {
  ALNDataverseResponse *response = [self performRequestWithMethod:@"GET"
                                                            path:@"WhoAmI()"
                                                           query:nil
                                                         headers:nil
                                                      bodyObject:nil
                                          includeFormattedValues:NO
                                            returnRepresentation:NO
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  id object = [response JSONObject:error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

- (ALNDataverseResponse *)performRequestWithMethod:(NSString *)method
                                              path:(NSString *)path
                                             query:(NSDictionary<NSString *, NSString *> *)query
                                           headers:(NSDictionary<NSString *, NSString *> *)headers
                                        bodyObject:(id)bodyObject
                            includeFormattedValues:(BOOL)includeFormattedValues
                              returnRepresentation:(BOOL)returnRepresentation
                                  consistencyCount:(BOOL)consistencyCount
                                             error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *normalizedMethod = [[ALNDataverseTrimmedString(method) uppercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *normalizedPath = ALNDataverseTrimmedString(path);
  if ([normalizedMethod length] == 0 || [normalizedPath length] == 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse request requires a method and path",
                                     nil);
    }
    return nil;
  }

  NSError *serializationError = nil;
  id serializedObject = ALNDataverseSerializedObject(bodyObject, &serializationError);
  if (bodyObject != nil && serializationError != nil) {
    if (error != NULL) {
      *error = serializationError;
    }
    return nil;
  }
  NSData *bodyData = (bodyObject != nil) ? ALNDataverseJSONStringData(serializedObject, &serializationError) : nil;
  if (bodyObject != nil && bodyData == nil && serializationError != nil) {
    if (error != NULL) {
      *error = serializationError;
    }
    return nil;
  }

  NSMutableDictionary<NSString *, NSString *> *requestHeaders = [NSMutableDictionary dictionary];
  requestHeaders[@"Accept"] = @"application/json";
  requestHeaders[@"OData-Version"] = @"4.0";
  requestHeaders[@"OData-MaxVersion"] = @"4.0";
  if ([bodyData length] > 0) {
    requestHeaders[@"Content-Type"] = @"application/json; charset=utf-8";
  }
  if (consistencyCount) {
    requestHeaders[@"ConsistencyLevel"] = @"eventual";
  }
  for (NSString *key in headers ?: @{}) {
    NSString *value = headers[key];
    if ([ALNDataverseTrimmedString(key) length] > 0 && [ALNDataverseTrimmedString(value) length] > 0) {
      requestHeaders[key] = value;
    }
  }
  NSString *preferValue = ALNDataversePreferHeader(self.target.pageSize,
                                                   includeFormattedValues,
                                                   returnRepresentation,
                                                   requestHeaders[@"Prefer"]);
  if ([preferValue length] > 0) {
    requestHeaders[@"Prefer"] = preferValue;
  }

  NSString *URLString = ALNDataverseAbsoluteURLString(self.target.serviceRootURLString, normalizedPath, query);
  return [self executeAuthorizedRequestWithMethod:normalizedMethod
                                        URLString:URLString
                                          headers:requestHeaders
                                         bodyData:bodyData
                                            error:error];
}

- (ALNDataverseResponse *)executeAuthorizedRequestWithMethod:(NSString *)method
                                                   URLString:(NSString *)URLString
                                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                                    bodyData:(NSData *)bodyData
                                                       error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  NSString *normalizedMethod = [[ALNDataverseTrimmedString(method) uppercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *normalizedURL = ALNDataverseTrimmedString(URLString);
  if ([normalizedMethod length] == 0 || [normalizedURL length] == 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse authorized request requires a method and URL",
                                     nil);
    }
    return nil;
  }

  NSError *tokenError = nil;
  NSString *accessToken = [self.tokenProvider accessTokenForTarget:self.target
                                                         transport:self.transport
                                                             error:&tokenError];
  if ([accessToken length] == 0) {
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    if ([self.target.targetName length] > 0) {
      details[ALNDataverseErrorTargetNameKey] = self.target.targetName;
    }
    details[ALNDataverseErrorRequestMethodKey] = normalizedMethod;
    details[ALNDataverseErrorRequestURLKey] = normalizedURL;
    if (error != NULL) {
      *error = tokenError ?: ALNDataverseMakeError(ALNDataverseErrorAuthenticationFailed,
                                                   @"Dataverse authentication failed",
                                                   details);
    }
    return nil;
  }

  NSMutableDictionary<NSString *, NSString *> *requestHeaders =
      [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
  requestHeaders[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", accessToken];
  NSDictionary<NSString *, NSString *> *redactedHeaders = ALNDataverseRedactedRequestHeaders(requestHeaders);
  NSUInteger maxAttempts = MAX((NSUInteger)1, (self.target.maxRetries + 1));
  NSError *lastError = nil;

  for (NSUInteger attempt = 0; attempt < maxAttempts; attempt++) {
    ALNDataverseRequest *request = [[ALNDataverseRequest alloc] initWithMethod:normalizedMethod
                                                                     URLString:normalizedURL
                                                                       headers:requestHeaders
                                                                      bodyData:bodyData];
    NSError *transportError = nil;
    ALNDataverseResponse *response = [self.transport executeRequest:request error:&transportError];
    if (response == nil) {
      NSMutableDictionary *details = [NSMutableDictionary dictionary];
      details[ALNDataverseErrorRequestMethodKey] = normalizedMethod;
      details[ALNDataverseErrorRequestURLKey] = normalizedURL;
      details[ALNDataverseErrorRequestHeadersKey] = redactedHeaders ?: @{};
      if ([self.target.targetName length] > 0) {
        details[ALNDataverseErrorTargetNameKey] = self.target.targetName;
      }
      NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
      diagnostics[@"attempt"] = @(attempt + 1);
      diagnostics[@"max_attempts"] = @(maxAttempts);
      diagnostics[@"method"] = normalizedMethod;
      diagnostics[@"target_name"] = self.target.targetName ?: @"";
      diagnostics[@"body_bytes"] = @([bodyData length]);
      if ([transportError.localizedDescription length] > 0) {
        diagnostics[@"transport_error"] = transportError.localizedDescription;
      }
      details[ALNDataverseErrorDiagnosticsKey] = diagnostics;
      lastError = transportError ?: ALNDataverseMakeError(ALNDataverseErrorTransportFailed,
                                                          @"Dataverse transport failed",
                                                          details);
      if ((attempt + 1) < maxAttempts) {
        [NSThread sleepForTimeInterval:(NSTimeInterval)(attempt + 1)];
        continue;
      }
      if (error != NULL) {
        *error = lastError;
      }
      return nil;
    }

    NSInteger statusCode = response.statusCode;
    NSInteger retryAfterSeconds = ALNDataverseRetryAfterSeconds(response.headers);
    BOOL retryableStatus = (statusCode == 429 || statusCode == 503 || statusCode == 504);
    if (retryableStatus && (attempt + 1) < maxAttempts) {
      NSTimeInterval delay = retryAfterSeconds > 0 ? retryAfterSeconds : (attempt + 1);
      [NSThread sleepForTimeInterval:delay];
      continue;
    }

    if (statusCode >= 200 && statusCode < 300) {
      return response;
    }

    NSString *correlationID = ALNDataverseCorrelationIDFromHeaders(response.headers);
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    details[ALNDataverseErrorHTTPStatusKey] = @(statusCode);
    details[ALNDataverseErrorRequestMethodKey] = normalizedMethod;
    details[ALNDataverseErrorRequestURLKey] = normalizedURL;
    details[ALNDataverseErrorRequestHeadersKey] = redactedHeaders ?: @{};
    details[ALNDataverseErrorResponseHeadersKey] = response.headers ?: @{};
    details[ALNDataverseErrorResponseBodyKey] = response.bodyText ?: @"";
    if ([self.target.targetName length] > 0) {
      details[ALNDataverseErrorTargetNameKey] = self.target.targetName;
    }
    if (retryAfterSeconds > 0) {
      details[ALNDataverseErrorRetryAfterKey] = @(retryAfterSeconds);
    }
    if ([correlationID length] > 0) {
      details[ALNDataverseErrorCorrelationIDKey] = correlationID;
    }
    NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
    diagnostics[@"attempt"] = @(attempt + 1);
    diagnostics[@"max_attempts"] = @(maxAttempts);
    diagnostics[@"method"] = normalizedMethod ?: @"GET";
    diagnostics[@"status_code"] = @(statusCode);
    diagnostics[@"target_name"] = self.target.targetName ?: @"";
    diagnostics[@"body_bytes"] = @([bodyData length]);
    if (retryAfterSeconds > 0) {
      diagnostics[@"retry_after_seconds"] = @(retryAfterSeconds);
    }
    details[ALNDataverseErrorDiagnosticsKey] = diagnostics;
    lastError = ALNDataverseMakeError((statusCode == 429 ? ALNDataverseErrorThrottled : ALNDataverseErrorRequestFailed),
                                      @"Dataverse request returned a non-success status",
                                      details);
    break;
  }

  if (error != NULL) {
    NSMutableDictionary *fallback = [NSMutableDictionary dictionary];
    fallback[ALNDataverseErrorRequestMethodKey] = normalizedMethod;
    fallback[ALNDataverseErrorRequestURLKey] = normalizedURL;
    fallback[ALNDataverseErrorRequestHeadersKey] = redactedHeaders ?: @{};
    if ([self.target.targetName length] > 0) {
      fallback[ALNDataverseErrorTargetNameKey] = self.target.targetName;
    }
    *error = lastError ?: ALNDataverseMakeError(ALNDataverseErrorRequestFailed,
                                                @"Dataverse request failed",
                                                fallback);
  }
  return nil;
}

- (ALNDataverseEntityPage *)fetchPageForQuery:(ALNDataverseQuery *)query error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (query == nil) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse query object is required",
                                     nil);
    }
    return nil;
  }
  NSError *queryError = nil;
  NSDictionary<NSString *, NSString *> *parameters = [query queryParameters:&queryError];
  if (parameters == nil && queryError != nil) {
    if (error != NULL) {
      *error = queryError;
    }
    return nil;
  }
  ALNDataverseResponse *response = [self performRequestWithMethod:@"GET"
                                                            path:query.entitySetName
                                                           query:parameters
                                                         headers:nil
                                                      bodyObject:nil
                                          includeFormattedValues:query.includeFormattedValues
                                            returnRepresentation:NO
                                                consistencyCount:query.includeCount
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  if (payload == nil) {
    if (error != NULL) {
      *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                  @"Dataverse query response payload must be a dictionary",
                                                  @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
    }
    return nil;
  }
  return [ALNDataverseEntityPage pageWithPayload:payload error:error];
}

- (ALNDataverseEntityPage *)fetchNextPageWithURLString:(NSString *)URLString error:(NSError **)error {
  ALNDataverseResponse *response = [self performRequestWithMethod:@"GET"
                                                            path:URLString
                                                           query:nil
                                                         headers:nil
                                                      bodyObject:nil
                                          includeFormattedValues:NO
                                            returnRepresentation:NO
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  if (payload == nil) {
    if (error != NULL) {
      *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                  @"Dataverse nextLink response payload must be a dictionary",
                                                  @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
    }
    return nil;
  }
  return [ALNDataverseEntityPage pageWithPayload:payload error:error];
}

- (ALNDataverseRecord *)retrieveRecordInEntitySet:(NSString *)entitySetName
                                         recordID:(NSString *)recordID
                                     selectFields:(NSArray<NSString *> *)selectFields
                                           expand:(NSDictionary<NSString *, id> *)expand
                           includeFormattedValues:(BOOL)includeFormattedValues
                                            error:(NSError **)error {
  NSError *pathError = nil;
  NSString *path = [[self class] recordPathForEntitySet:entitySetName recordID:recordID error:&pathError];
  if ([path length] == 0) {
    if (error != NULL) {
      *error = pathError;
    }
    return nil;
  }
  NSError *queryError = nil;
  NSDictionary<NSString *, NSString *> *query =
      [ALNDataverseQuery queryParametersWithSelectFields:selectFields
                                                   where:nil
                                                 orderBy:nil
                                                     top:nil
                                                    skip:nil
                                               countFlag:NO
                                                  expand:expand
                                                   error:&queryError];
  if (query == nil && queryError != nil) {
    if (error != NULL) {
      *error = queryError;
    }
    return nil;
  }
  ALNDataverseResponse *response = [self performRequestWithMethod:@"GET"
                                                            path:path
                                                           query:query
                                                         headers:nil
                                                      bodyObject:nil
                                          includeFormattedValues:includeFormattedValues
                                            returnRepresentation:NO
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  if (payload == nil) {
    if (error != NULL) {
      *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                  @"Dataverse record response payload must be a dictionary",
                                                  @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
    }
    return nil;
  }
  return [ALNDataverseRecord recordWithDictionary:payload error:error];
}

- (NSDictionary<NSString *, id> *)createRecordInEntitySet:(NSString *)entitySetName
                                                   values:(NSDictionary<NSString *, id> *)values
                                      returnRepresentation:(BOOL)returnRepresentation
                                                    error:(NSError **)error {
  ALNDataverseResponse *response = [self performRequestWithMethod:@"POST"
                                                            path:entitySetName
                                                           query:nil
                                                         headers:nil
                                                      bodyObject:values
                                          includeFormattedValues:returnRepresentation
                                            returnRepresentation:returnRepresentation
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  if ([response.bodyData length] == 0) {
    return ALNDataverseResponseSummary(response);
  }
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  if (payload != nil) {
    return payload;
  }
  if (error != NULL) {
    *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                @"Dataverse create response payload must be a dictionary",
                                                @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
  }
  return nil;
}

- (NSDictionary<NSString *, id> *)updateRecordInEntitySet:(NSString *)entitySetName
                                                 recordID:(NSString *)recordID
                                                   values:(NSDictionary<NSString *, id> *)values
                                                  ifMatch:(NSString *)ifMatch
                                      returnRepresentation:(BOOL)returnRepresentation
                                                    error:(NSError **)error {
  NSError *pathError = nil;
  NSString *path = [[self class] recordPathForEntitySet:entitySetName recordID:recordID error:&pathError];
  if ([path length] == 0) {
    if (error != NULL) {
      *error = pathError;
    }
    return nil;
  }
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
  if ([ALNDataverseTrimmedString(ifMatch) length] > 0) {
    headers[@"If-Match"] = ifMatch;
  }
  ALNDataverseResponse *response = [self performRequestWithMethod:@"PATCH"
                                                            path:path
                                                           query:nil
                                                         headers:headers
                                                      bodyObject:values
                                          includeFormattedValues:returnRepresentation
                                            returnRepresentation:returnRepresentation
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  if ([response.bodyData length] == 0) {
    return ALNDataverseResponseSummary(response);
  }
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  if (payload != nil) {
    return payload;
  }
  if (error != NULL) {
    *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                @"Dataverse update response payload must be a dictionary",
                                                @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
  }
  return nil;
}

- (NSDictionary<NSString *, id> *)upsertRecordInEntitySet:(NSString *)entitySetName
                                       alternateKeyValues:(NSDictionary<NSString *, id> *)alternateKeyValues
                                                   values:(NSDictionary<NSString *, id> *)values
                                                createOnly:(BOOL)createOnly
                                                updateOnly:(BOOL)updateOnly
                                       returnRepresentation:(BOOL)returnRepresentation
                                                    error:(NSError **)error {
  NSError *pathError = nil;
  NSString *path = [[self class] recordPathForEntitySet:entitySetName
                                      alternateKeyValues:alternateKeyValues
                                                   error:&pathError];
  if ([path length] == 0) {
    if (error != NULL) {
      *error = pathError;
    }
    return nil;
  }
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
  if (createOnly) {
    headers[@"If-None-Match"] = @"*";
  }
  if (updateOnly) {
    headers[@"If-Match"] = @"*";
  }
  ALNDataverseResponse *response = [self performRequestWithMethod:@"PATCH"
                                                            path:path
                                                           query:nil
                                                         headers:headers
                                                      bodyObject:values
                                          includeFormattedValues:returnRepresentation
                                            returnRepresentation:returnRepresentation
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  if ([response.bodyData length] == 0) {
    return ALNDataverseResponseSummary(response);
  }
  NSError *jsonError = nil;
  NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                              ? [response JSONObject:&jsonError]
                                              : nil;
  if (payload != nil) {
    return payload;
  }
  if (error != NULL) {
    *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                @"Dataverse upsert response payload must be a dictionary",
                                                @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
  }
  return nil;
}

- (BOOL)deleteRecordInEntitySet:(NSString *)entitySetName
                       recordID:(NSString *)recordID
                        ifMatch:(NSString *)ifMatch
                          error:(NSError **)error {
  NSError *pathError = nil;
  NSString *path = [[self class] recordPathForEntitySet:entitySetName recordID:recordID error:&pathError];
  if ([path length] == 0) {
    if (error != NULL) {
      *error = pathError;
    }
    return NO;
  }
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
  if ([ALNDataverseTrimmedString(ifMatch) length] > 0) {
    headers[@"If-Match"] = ifMatch;
  }
  ALNDataverseResponse *response = [self performRequestWithMethod:@"DELETE"
                                                            path:path
                                                           query:nil
                                                         headers:headers
                                                      bodyObject:nil
                                          includeFormattedValues:NO
                                            returnRepresentation:NO
                                                consistencyCount:NO
                                                           error:error];
  return (response != nil);
}

- (id)invokeActionNamed:(NSString *)actionName
               boundPath:(NSString *)boundPath
              parameters:(NSDictionary<NSString *, id> *)parameters
                   error:(NSError **)error {
  NSString *name = ALNDataverseTrimmedString(actionName);
  NSString *path = ([ALNDataverseTrimmedString(boundPath) length] > 0)
                       ? [NSString stringWithFormat:@"%@/%@", ALNDataverseTrimmedString(boundPath), name]
                       : name;
  ALNDataverseResponse *response = [self performRequestWithMethod:@"POST"
                                                            path:path
                                                           query:nil
                                                         headers:nil
                                                      bodyObject:parameters ?: @{}
                                          includeFormattedValues:NO
                                            returnRepresentation:NO
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  if ([response.bodyData length] == 0) {
    return ALNDataverseResponseSummary(response);
  }
  NSError *jsonError = nil;
  id payload = [response JSONObject:&jsonError];
  if (payload != nil) {
    return payload;
  }
  if (error != NULL) {
    *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                @"Dataverse action response payload was not valid JSON",
                                                @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
  }
  return nil;
}

- (id)invokeFunctionNamed:(NSString *)functionName
                 boundPath:(NSString *)boundPath
                parameters:(NSDictionary<NSString *, id> *)parameters
                     error:(NSError **)error {
  NSString *name = ALNDataverseTrimmedString(functionName);
  NSMutableArray<NSString *> *parameterParts = [NSMutableArray array];
  NSArray<NSString *> *keys = [[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSError *literalError = nil;
    NSString *literal = ALNDataverseODataLiteral(parameters[key], &literalError);
    if ([literal length] == 0 || literalError != nil) {
      if (error != NULL) {
        *error = literalError;
      }
      return nil;
    }
    [parameterParts addObject:[NSString stringWithFormat:@"%@=%@", key, literal]];
  }
  NSString *suffix = [NSString stringWithFormat:@"%@(%@)", name, [parameterParts componentsJoinedByString:@","]];
  NSString *path = ([ALNDataverseTrimmedString(boundPath) length] > 0)
                       ? [NSString stringWithFormat:@"%@/%@", ALNDataverseTrimmedString(boundPath), suffix]
                       : suffix;
  ALNDataverseResponse *response = [self performRequestWithMethod:@"GET"
                                                            path:path
                                                           query:nil
                                                         headers:nil
                                                      bodyObject:nil
                                          includeFormattedValues:NO
                                            returnRepresentation:NO
                                                consistencyCount:NO
                                                           error:error];
  if (response == nil) {
    return nil;
  }
  if ([response.bodyData length] == 0) {
    return ALNDataverseResponseSummary(response);
  }
  NSError *jsonError = nil;
  id payload = [response JSONObject:&jsonError];
  if (payload != nil) {
    return payload;
  }
  if (error != NULL) {
    *error = jsonError ?: ALNDataverseMakeError(ALNDataverseErrorInvalidResponse,
                                                @"Dataverse function response payload was not valid JSON",
                                                @{ ALNDataverseErrorResponseBodyKey : response.bodyText ?: @"" });
  }
  return nil;
}

- (NSArray<ALNDataverseBatchResponse *> *)executeBatchRequests:(NSArray<ALNDataverseBatchRequest *> *)requests
                                                         error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![requests isKindOfClass:[NSArray class]] || [requests count] == 0) {
    if (error != NULL) {
      *error = ALNDataverseMakeError(ALNDataverseErrorInvalidArgument,
                                     @"Dataverse batch requires at least one request",
                                     nil);
    }
    return nil;
  }

  NSString *boundary = [NSString stringWithFormat:@"batch_%@", [[[NSUUID UUID] UUIDString] lowercaseString]];
  NSMutableString *body = [NSMutableString string];
  for (ALNDataverseBatchRequest *request in requests) {
    [body appendFormat:@"--%@\r\n", boundary];
    [body appendString:@"Content-Type: application/http\r\n"];
    [body appendString:@"Content-Transfer-Encoding: binary\r\n"];
    if ([request.contentID length] > 0) {
      [body appendFormat:@"Content-ID: %@\r\n", request.contentID];
    }
    [body appendString:@"\r\n"];
    NSString *httpPath = ALNDataverseBatchHTTPPath(self.target.serviceRootURLString, request.relativePath);
    [body appendFormat:@"%@ %@ HTTP/1.1\r\n", request.method ?: @"GET", httpPath ?: @"/"];
    [body appendString:@"Accept: application/json\r\n"];
    NSArray<NSString *> *headerKeys = [[request.headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in headerKeys) {
      NSString *value = request.headers[key];
      if ([ALNDataverseTrimmedString(key) length] > 0 && [ALNDataverseTrimmedString(value) length] > 0) {
        [body appendFormat:@"%@: %@\r\n", key, value];
      }
    }
    if (request.bodyObject != nil) {
      NSError *serializationError = nil;
      id serializedObject = ALNDataverseSerializedObject(request.bodyObject, &serializationError);
      NSData *payload = ALNDataverseJSONStringData(serializedObject, &serializationError);
      if (payload == nil || serializationError != nil) {
        if (error != NULL) {
          *error = serializationError;
        }
        return nil;
      }
      NSString *payloadText = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding] ?: @"{}";
      [body appendString:@"Content-Type: application/json; charset=utf-8\r\n"];
      [body appendString:@"\r\n"];
      [body appendString:payloadText];
      [body appendString:@"\r\n"];
    } else {
      [body appendString:@"\r\n"];
    }
  }
  [body appendFormat:@"--%@--\r\n", boundary];

  NSDictionary<NSString *, NSString *> *headers = @{
    @"Content-Type" : [NSString stringWithFormat:@"multipart/mixed; boundary=%@", boundary],
  };
  NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
  NSString *batchURL = ALNDataverseAbsoluteURLString(self.target.serviceRootURLString, @"$batch", nil);
  NSMutableDictionary<NSString *, NSString *> *requestHeaders = [NSMutableDictionary dictionaryWithDictionary:headers];
  requestHeaders[@"Accept"] = @"application/json";
  requestHeaders[@"OData-Version"] = @"4.0";
  requestHeaders[@"OData-MaxVersion"] = @"4.0";
  ALNDataverseResponse *response = [self executeAuthorizedRequestWithMethod:@"POST"
                                                                  URLString:batchURL
                                                                    headers:requestHeaders
                                                                   bodyData:bodyData
                                                                      error:error];
  if (response == nil) {
    return nil;
  }
  return ALNDataverseParseBatchResponses(response, error);
}

@end
