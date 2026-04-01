#import "ALNLive.h"

#import "ALNRequest.h"
#import "ALNResponse.h"

#import <dispatch/dispatch.h>

static NSString *const ALNLiveErrorDomain = @"Arlen.Live.Error";

typedef NS_ENUM(NSInteger, ALNLiveErrorCode) {
  ALNLiveErrorCodeInvalidOperation = 1,
  ALNLiveErrorCodeSerializationFailed = 2,
  ALNLiveErrorCodePayloadTooLarge = 3,
  ALNLiveErrorCodeInvalidMeta = 4,
};

static const NSUInteger ALNLiveMaxOperationCount = 64;
static const NSUInteger ALNLiveMaxSelectorLength = 512;
static const NSUInteger ALNLiveMaxHTMLLength = 262144;
static const NSUInteger ALNLiveMaxLocationLength = 2048;
static const NSUInteger ALNLiveMaxEventNameLength = 128;
static const NSUInteger ALNLiveMaxKeyLength = 128;
static const NSUInteger ALNLiveMaxMetaEntries = 32;
static const NSUInteger ALNLiveMaxMetaJSONBytes = 16384;

static NSString *ALNLiveTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNLiveHeaderBoolValue(NSString *value, BOOL *parsed) {
  NSString *normalized = [[ALNLiveTrimmedString(value) lowercaseString] copy];
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    if (parsed != NULL) {
      *parsed = YES;
    }
    return YES;
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    if (parsed != NULL) {
      *parsed = NO;
    }
    return YES;
  }
  return NO;
}

static NSError *ALNLiveError(ALNLiveErrorCode code,
                             NSString *message,
                             NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] =
      [message isKindOfClass:[NSString class]] && [message length] > 0
          ? message
          : @"live response error";
  if ([details isKindOfClass:[NSDictionary class]] && [details count] > 0) {
    userInfo[@"details"] = details;
  }
  return [NSError errorWithDomain:ALNLiveErrorDomain code:code userInfo:userInfo];
}

static NSDictionary *ALNLiveOperation(NSString *operation,
                                      NSString *target,
                                      NSString *html,
                                      NSString *location,
                                      NSNumber *replace,
                                      NSString *eventName,
                                      NSDictionary *detail) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionary];
  if ([operation length] > 0) {
    entry[@"op"] = operation;
  }
  if ([target length] > 0) {
    entry[@"target"] = target;
  }
  if (html != nil) {
    entry[@"html"] = html;
  }
  if ([location length] > 0) {
    entry[@"location"] = location;
  }
  if (replace != nil) {
    entry[@"replace"] = replace;
  }
  if ([eventName length] > 0) {
    entry[@"event"] = eventName;
  }
  if ([detail isKindOfClass:[NSDictionary class]] && [detail count] > 0) {
    entry[@"detail"] = detail;
  }
  return [NSDictionary dictionaryWithDictionary:entry];
}

static BOOL ALNLivePayloadValueIsJSONSafe(id value) {
  if (value == nil || value == [NSNull null]) {
    return YES;
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
      [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
    return [NSJSONSerialization isValidJSONObject:@{ @"value" : value }];
  }
  return NO;
}

static NSUInteger ALNLiveJSONSizeForValue(id value) {
  if (value == nil || ![NSJSONSerialization isValidJSONObject:value]) {
    return 0;
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
  return [data length];
}

static BOOL ALNLiveStringFitsLimit(NSString *value,
                                   NSUInteger maxLength,
                                   ALNLiveErrorCode code,
                                   NSString *field,
                                   NSError **error) {
  if ([value length] <= maxLength) {
    return YES;
  }
  if (error != NULL) {
    *error = ALNLiveError(code,
                          [NSString stringWithFormat:@"Live %@ exceeds the allowed size", field ?: @"field"],
                          @{
                            @"field" : field ?: @"",
                            @"limit" : @(maxLength),
                          });
  }
  return NO;
}

static NSString *ALNLiveEscapedAttributeSelectorValue(NSString *value) {
  NSString *trimmed = ALNLiveTrimmedString(value);
  if ([trimmed length] == 0) {
    return @"";
  }
  NSMutableString *escaped = [NSMutableString stringWithString:trimmed];
  [escaped replaceOccurrencesOfString:@"\\"
                           withString:@"\\\\"
                              options:0
                                range:NSMakeRange(0, [escaped length])];
  [escaped replaceOccurrencesOfString:@"\""
                           withString:@"\\\""
                              options:0
                                range:NSMakeRange(0, [escaped length])];
  return [NSString stringWithString:escaped];
}

static NSDictionary *ALNLiveNormalizedMetaFromValue(id value, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (value == nil) {
    return nil;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodeInvalidMeta,
                            @"Live response meta must be a dictionary",
                            @{ @"meta_class" : NSStringFromClass([value class] ?: [NSObject class]) });
    }
    return nil;
  }

  NSDictionary *meta = (NSDictionary *)value;
  if ([meta count] > ALNLiveMaxMetaEntries) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodePayloadTooLarge,
                            @"Live response meta exceeds the allowed entry count",
                            @{
                              @"field" : @"meta",
                              @"limit" : @(ALNLiveMaxMetaEntries),
                            });
    }
    return nil;
  }

  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  for (id keyValue in meta) {
    if (![keyValue isKindOfClass:[NSString class]]) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidMeta,
                              @"Live response meta keys must be strings",
                              nil);
      }
      return nil;
    }

    NSString *key = ALNLiveTrimmedString(keyValue);
    if ([key length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidMeta,
                              @"Live response meta keys must be non-empty strings",
                              nil);
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(key, ALNLiveMaxEventNameLength, ALNLiveErrorCodeInvalidMeta, @"meta key", error)) {
      return nil;
    }

    id item = meta[keyValue];
    if (!ALNLivePayloadValueIsJSONSafe(item)) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidMeta,
                              @"Live response meta values must be JSON serializable",
                              @{ @"field" : key });
      }
      return nil;
    }
    normalized[key] = item ?: [NSNull null];
  }

  NSUInteger metaSize = ALNLiveJSONSizeForValue(normalized);
  if (metaSize > ALNLiveMaxMetaJSONBytes) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodePayloadTooLarge,
                            @"Live response meta exceeds the allowed payload size",
                            @{
                              @"field" : @"meta",
                              @"limit" : @(ALNLiveMaxMetaJSONBytes),
                            });
    }
    return nil;
  }

  return [NSDictionary dictionaryWithDictionary:normalized];
}

static NSDictionary *ALNLiveNormalizedOperationFromValue(id value, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                            @"Live operation must be a dictionary",
                            @{ @"operation_class" : NSStringFromClass([value class] ?: [NSObject class]) });
    }
    return nil;
  }

  NSDictionary *operation = (NSDictionary *)value;
  NSString *name = [[ALNLiveTrimmedString(operation[@"op"]) lowercaseString] copy];
  NSString *target = ALNLiveTrimmedString(operation[@"target"]);
  NSString *html = [operation[@"html"] isKindOfClass:[NSString class]] ? operation[@"html"] : nil;
  NSString *location = ALNLiveTrimmedString(operation[@"location"]);
  NSString *eventName = ALNLiveTrimmedString(operation[@"event"]);
  NSString *container = ALNLiveTrimmedString(operation[@"container"]);
  NSString *key = ALNLiveTrimmedString(operation[@"key"]);
  id replaceValue = operation[@"replace"];
  id prependValue = operation[@"prepend"];
  NSDictionary *detail = [operation[@"detail"] isKindOfClass:[NSDictionary class]]
                             ? operation[@"detail"]
                             : nil;

  BOOL replace = NO;
  BOOL replaceSpecified = NO;
  if ([replaceValue respondsToSelector:@selector(boolValue)]) {
    replace = [replaceValue boolValue];
    replaceSpecified = YES;
  }
  BOOL prepend = NO;
  BOOL prependSpecified = NO;
  if ([prependValue respondsToSelector:@selector(boolValue)]) {
    prepend = [prependValue boolValue];
    prependSpecified = YES;
  }

  if ([name isEqualToString:@"replace"] || [name isEqualToString:@"update"] ||
      [name isEqualToString:@"append"] || [name isEqualToString:@"prepend"]) {
    if ([target length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live HTML operations require a non-empty target selector",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(target,
                                ALNLiveMaxSelectorLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"target selector",
                                error)) {
      return nil;
    }
    if (![html isKindOfClass:[NSString class]]) {
      html = @"";
    }
    if ([html length] > ALNLiveMaxHTMLLength) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodePayloadTooLarge,
                              @"Live HTML operation exceeds the allowed size",
                              @{
                                @"field" : @"html",
                                @"limit" : @(ALNLiveMaxHTMLLength),
                                @"op" : name ?: @"",
                              });
      }
      return nil;
    }
    return ALNLiveOperation(name, target, html ?: @"", nil, nil, nil, nil);
  }

  if ([name isEqualToString:@"remove"]) {
    if ([target length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live remove operations require a non-empty target selector",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(target,
                                ALNLiveMaxSelectorLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"target selector",
                                error)) {
      return nil;
    }
    return ALNLiveOperation(name, target, nil, nil, nil, nil, nil);
  }

  if ([name isEqualToString:@"upsert"]) {
    if ([container length] == 0 || [key length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live keyed upsert operations require non-empty container and key values",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(container,
                                ALNLiveMaxSelectorLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"container selector",
                                error) ||
        !ALNLiveStringFitsLimit(key,
                                ALNLiveMaxKeyLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"key",
                                error)) {
      return nil;
    }
    if (![html isKindOfClass:[NSString class]]) {
      html = @"";
    }
    if ([html length] > ALNLiveMaxHTMLLength) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodePayloadTooLarge,
                              @"Live keyed upsert HTML exceeds the allowed size",
                              @{
                                @"field" : @"html",
                                @"limit" : @(ALNLiveMaxHTMLLength),
                                @"op" : name ?: @"",
                              });
      }
      return nil;
    }
    NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
    normalized[@"op"] = @"upsert";
    normalized[@"container"] = container;
    normalized[@"key"] = key;
    normalized[@"html"] = html ?: @"";
    NSString *normalizedTarget = [target length] > 0 ? target : [ALNLive keyedTargetSelectorForContainer:container key:key];
    if ([normalizedTarget length] > 0) {
      normalized[@"target"] = normalizedTarget;
    }
    if (prependSpecified) {
      normalized[@"prepend"] = @(prepend);
    }
    return [NSDictionary dictionaryWithDictionary:normalized];
  }

  if ([name isEqualToString:@"discard"]) {
    if ([container length] == 0 || [key length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live keyed discard operations require non-empty container and key values",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(container,
                                ALNLiveMaxSelectorLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"container selector",
                                error) ||
        !ALNLiveStringFitsLimit(key,
                                ALNLiveMaxKeyLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"key",
                                error)) {
      return nil;
    }
    NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
    normalized[@"op"] = @"discard";
    normalized[@"container"] = container;
    normalized[@"key"] = key;
    NSString *normalizedTarget = [target length] > 0 ? target : [ALNLive keyedTargetSelectorForContainer:container key:key];
    if ([normalizedTarget length] > 0) {
      normalized[@"target"] = normalizedTarget;
    }
    return [NSDictionary dictionaryWithDictionary:normalized];
  }

  if ([name isEqualToString:@"navigate"]) {
    if ([location length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live navigate operations require a non-empty location",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(location,
                                ALNLiveMaxLocationLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"location",
                                error)) {
      return nil;
    }
    return ALNLiveOperation(name,
                            nil,
                            nil,
                            location,
                            replaceSpecified ? @(replace) : @(NO),
                            nil,
                            nil);
  }

  if ([name isEqualToString:@"dispatch"]) {
    if ([eventName length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live dispatch operations require a non-empty event name",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (!ALNLiveStringFitsLimit(eventName,
                                ALNLiveMaxEventNameLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"event name",
                                error)) {
      return nil;
    }
    if ([target length] > 0 &&
        !ALNLiveStringFitsLimit(target,
                                ALNLiveMaxSelectorLength,
                                ALNLiveErrorCodePayloadTooLarge,
                                @"target selector",
                                error)) {
      return nil;
    }
    if (detail != nil && !ALNLivePayloadValueIsJSONSafe(detail)) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live dispatch detail must be JSON serializable",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    return ALNLiveOperation(name, target, nil, nil, nil, eventName, detail);
  }

  if (error != NULL) {
    *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                          @"Unsupported live operation",
                          @{ @"op" : name ?: @"" });
  }
  return nil;
}

static NSString *ALNLiveRequestHeaderValue(ALNRequest *request, NSString *name) {
  if (request == nil || ![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return @"";
  }
  return ALNLiveTrimmedString([request headerValueForName:name]);
}

@implementation ALNLive

+ (NSString *)contentType {
  return @"application/vnd.arlen.live+json; charset=utf-8";
}

+ (NSString *)acceptContentType {
  return @"application/vnd.arlen.live+json";
}

+ (NSString *)protocolVersion {
  return @"arlen-live-v1";
}

+ (NSDictionary *)replaceOperationForTarget:(NSString *)target
                                       html:(NSString *)html {
  return ALNLiveOperation(@"replace", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)updateOperationForTarget:(NSString *)target
                                      html:(NSString *)html {
  return ALNLiveOperation(@"update", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)appendOperationForTarget:(NSString *)target
                                      html:(NSString *)html {
  return ALNLiveOperation(@"append", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)prependOperationForTarget:(NSString *)target
                                       html:(NSString *)html {
  return ALNLiveOperation(@"prepend", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)removeOperationForTarget:(NSString *)target {
  return ALNLiveOperation(@"remove", target ?: @"", nil, nil, nil, nil, nil);
}

+ (NSString *)keyedTargetSelectorForContainer:(NSString *)container key:(NSString *)key {
  NSString *normalizedContainer = ALNLiveTrimmedString(container);
  NSString *escapedKey = ALNLiveEscapedAttributeSelectorValue(key);
  if ([escapedKey length] == 0) {
    return @"";
  }
  if ([normalizedContainer length] == 0) {
    return [NSString stringWithFormat:@"[data-arlen-live-key=\"%@\"]", escapedKey];
  }
  return [NSString stringWithFormat:@"%@ [data-arlen-live-key=\"%@\"]",
                                    normalizedContainer,
                                    escapedKey];
}

+ (NSDictionary *)upsertKeyedOperationForContainer:(NSString *)container
                                               key:(NSString *)key
                                              html:(NSString *)html
                                           prepend:(BOOL)prepend {
  NSMutableDictionary *operation = [NSMutableDictionary dictionary];
  operation[@"op"] = @"upsert";
  operation[@"container"] = ALNLiveTrimmedString(container);
  operation[@"key"] = ALNLiveTrimmedString(key);
  operation[@"html"] = html ?: @"";
  operation[@"prepend"] = @(prepend);
  NSString *target = [self keyedTargetSelectorForContainer:container key:key];
  if ([target length] > 0) {
    operation[@"target"] = target;
  }
  return [NSDictionary dictionaryWithDictionary:operation];
}

+ (NSDictionary *)removeKeyedOperationForContainer:(NSString *)container
                                               key:(NSString *)key {
  NSMutableDictionary *operation = [NSMutableDictionary dictionary];
  operation[@"op"] = @"discard";
  operation[@"container"] = ALNLiveTrimmedString(container);
  operation[@"key"] = ALNLiveTrimmedString(key);
  NSString *target = [self keyedTargetSelectorForContainer:container key:key];
  if ([target length] > 0) {
    operation[@"target"] = target;
  }
  return [NSDictionary dictionaryWithDictionary:operation];
}

+ (NSDictionary *)navigateOperationForLocation:(NSString *)location
                                       replace:(BOOL)replace {
  return ALNLiveOperation(@"navigate", nil, nil, location ?: @"", @(replace), nil, nil);
}

+ (NSDictionary *)dispatchOperationForEvent:(NSString *)eventName
                                      detail:(NSDictionary *)detail
                                      target:(NSString *)target {
  return ALNLiveOperation(@"dispatch", target ?: @"", nil, nil, nil, eventName ?: @"", detail);
}

+ (BOOL)requestIsLive:(ALNRequest *)request {
  if (request == nil) {
    return NO;
  }
  NSString *headerValue = [request headerValueForName:@"x-arlen-live"];
  BOOL parsedHeaderValue = NO;
  if (ALNLiveHeaderBoolValue(headerValue, &parsedHeaderValue)) {
    return parsedHeaderValue;
  }

  NSString *rawAcceptValue = [request headerValueForName:@"accept"];
  NSString *acceptValue =
      [([rawAcceptValue isKindOfClass:[NSString class]] ? rawAcceptValue : @"") lowercaseString];
  return [acceptValue containsString:[[self acceptContentType] lowercaseString]];
}

+ (NSDictionary *)requestMetadataForRequest:(ALNRequest *)request {
  if (request == nil) {
    return @{};
  }

  NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
  NSString *target = ALNLiveRequestHeaderValue(request, @"x-arlen-live-target");
  NSString *swap =
      [[ALNLiveRequestHeaderValue(request, @"x-arlen-live-swap") lowercaseString] copy];
  NSString *component = ALNLiveRequestHeaderValue(request, @"x-arlen-live-component");
  NSString *eventName = ALNLiveRequestHeaderValue(request, @"x-arlen-live-event");
  NSString *source =
      [[ALNLiveRequestHeaderValue(request, @"x-arlen-live-source") lowercaseString] copy];
  NSString *container = ALNLiveRequestHeaderValue(request, @"x-arlen-live-container");
  NSString *key = ALNLiveRequestHeaderValue(request, @"x-arlen-live-key");
  NSString *poll = ALNLiveRequestHeaderValue(request, @"x-arlen-live-poll");
  NSString *defer = ALNLiveRequestHeaderValue(request, @"x-arlen-live-defer");
  BOOL lazy = NO;
  BOOL lazySpecified =
      ALNLiveHeaderBoolValue([request headerValueForName:@"x-arlen-live-lazy"], &lazy);

  if ([target length] > 0) {
    metadata[@"target"] = target;
  }
  if ([swap length] > 0) {
    metadata[@"swap"] = swap;
  }
  if ([component length] > 0) {
    metadata[@"component"] = component;
  }
  if ([eventName length] > 0) {
    metadata[@"event"] = eventName;
  }
  if ([source length] > 0) {
    metadata[@"source"] = source;
  }
  if ([container length] > 0) {
    metadata[@"container"] = container;
  }
  if ([key length] > 0) {
    metadata[@"key"] = key;
  }
  if ([poll length] > 0) {
    metadata[@"poll"] = poll;
  }
  if ([defer length] > 0) {
    metadata[@"defer"] = defer;
  }
  if (lazySpecified) {
    metadata[@"lazy"] = @(lazy);
  }
  return [NSDictionary dictionaryWithDictionary:metadata];
}

+ (NSDictionary *)validatedPayloadWithOperations:(NSArray *)operations
                                             meta:(NSDictionary *)meta
                                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  if (operations != nil && ![operations isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                            @"Live operations must be provided as an array",
                            nil);
    }
    return nil;
  }

  if ([operations count] > ALNLiveMaxOperationCount) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodePayloadTooLarge,
                            @"Live response exceeds the allowed operation count",
                            @{
                              @"field" : @"operations",
                              @"limit" : @(ALNLiveMaxOperationCount),
                            });
    }
    return nil;
  }

  NSMutableArray *normalizedOperations = [NSMutableArray array];
  for (id value in operations ?: @[]) {
    NSError *normalizeError = nil;
    NSDictionary *normalized = ALNLiveNormalizedOperationFromValue(value, &normalizeError);
    if (normalized == nil) {
      if (error != NULL) {
        *error = normalizeError;
      }
      return nil;
    }
    [normalizedOperations addObject:normalized];
  }

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"version"] = [self protocolVersion];
  payload[@"operations"] = [NSArray arrayWithArray:normalizedOperations];
  NSDictionary *normalizedMeta = ALNLiveNormalizedMetaFromValue(meta, error);
  if (normalizedMeta == nil && meta != nil) {
    return nil;
  }
  if ([normalizedMeta count] > 0) {
    payload[@"meta"] = normalizedMeta;
  }
  return [NSDictionary dictionaryWithDictionary:payload];
}

+ (BOOL)renderResponse:(ALNResponse *)response
            operations:(NSArray *)operations
                  meta:(NSDictionary *)meta
                 error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (response == nil) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodeSerializationFailed,
                            @"Live response requires a response object",
                            nil);
    }
    return NO;
  }

  NSDictionary *payload = [self validatedPayloadWithOperations:operations meta:meta error:error];
  if (payload == nil) {
    return NO;
  }

  if (response.statusCode == 0) {
    response.statusCode = 200;
  }
  BOOL ok = [response setJSONBody:payload options:0 error:error];
  if (!ok) {
    if (error != NULL && *error == nil) {
      *error = ALNLiveError(ALNLiveErrorCodeSerializationFailed,
                            @"Live response serialization failed",
                            nil);
    }
    return NO;
  }
  [response setHeader:@"Content-Type" value:[self contentType]];
  [response setHeader:@"X-Arlen-Live-Protocol" value:[self protocolVersion]];
  [response setHeader:@"Cache-Control" value:@"no-store"];
  [response setHeader:@"Vary" value:@"Accept, X-Arlen-Live"];
  response.committed = YES;
  return YES;
}

+ (NSString *)runtimeJavaScript {
  static NSString *script = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    script = [@[
      @"(function () {",
      @"  'use strict';",
      @"  if (window.ArlenLive && window.ArlenLive.__version === 'arlen-live-v1') {",
      @"    return;",
      @"  }",
      @"",
      @"  var LIVE_CONTENT_TYPE = 'application/vnd.arlen.live+json';",
      @"  var LIVE_ACCEPT = LIVE_CONTENT_TYPE + ', application/json;q=0.9, text/html;q=0.8';",
      @"  var streamSockets = new Map();",
      @"  var streamState = new Map();",
      @"  var regionState = new WeakMap();",
      @"  var lazyObserver = null;",
      @"",
      @"  function closestLiveLink(node) {",
      @"    return node && node.closest ? node.closest('a[data-arlen-live]') : null;",
      @"  }",
      @"",
      @"  function closestLiveForm(node) {",
      @"    return node && node.closest ? node.closest('form[data-arlen-live]') : null;",
      @"  }",
      @"",
      @"  function attributeValue(node, name) {",
      @"    if (!node || !node.getAttribute) {",
      @"      return '';",
      @"    }",
      @"    var value = node.getAttribute(name);",
      @"    if (typeof value !== 'string') {",
      @"      return '';",
      @"    }",
      @"    return value.trim();",
      @"  }",
      @"",
      @"  function hasAttribute(node, name) {",
      @"    return !!(node && node.hasAttribute && node.hasAttribute(name));",
      @"  }",
      @"",
      @"  function parseDuration(value) {",
      @"    if (typeof value !== 'string') {",
      @"      return 0;",
      @"    }",
      @"    var trimmed = value.trim().toLowerCase();",
      @"    if (!trimmed) {",
      @"      return 0;",
      @"    }",
      @"    var multiplier = 1;",
      @"    if (trimmed.endsWith('ms')) {",
      @"      trimmed = trimmed.slice(0, -2);",
      @"    } else if (trimmed.endsWith('s')) {",
      @"      trimmed = trimmed.slice(0, -1);",
      @"      multiplier = 1000;",
      @"    } else if (trimmed.endsWith('m')) {",
      @"      trimmed = trimmed.slice(0, -1);",
      @"      multiplier = 60000;",
      @"    }",
      @"    var numeric = Number(trimmed);",
      @"    if (!Number.isFinite(numeric) || numeric <= 0) {",
      @"      return 0;",
      @"    }",
      @"    return Math.round(numeric * multiplier);",
      @"  }",
      @"",
      @"  function headerReaderFromResponse(response) {",
      @"    return {",
      @"      get: function (name) {",
      @"        if (!response || !response.headers || !response.headers.get) {",
      @"          return '';",
      @"        }",
      @"        return response.headers.get(name) || '';",
      @"      }",
      @"    };",
      @"  }",
      @"",
      @"  function collectLiveRequestMetadata(primary, fallback, source) {",
      @"    var metadata = {};",
      @"    var target = attributeValue(primary, 'data-arlen-live-target') || attributeValue(fallback, 'data-arlen-live-target');",
      @"    var swap = attributeValue(primary, 'data-arlen-live-swap') || attributeValue(fallback, 'data-arlen-live-swap');",
      @"    var component = attributeValue(primary, 'data-arlen-live-component') || attributeValue(fallback, 'data-arlen-live-component');",
      @"    var eventName = attributeValue(primary, 'data-arlen-live-event') || attributeValue(fallback, 'data-arlen-live-event');",
      @"    var container = attributeValue(primary, 'data-arlen-live-container') || attributeValue(fallback, 'data-arlen-live-container');",
      @"    var key = attributeValue(primary, 'data-arlen-live-key') || attributeValue(fallback, 'data-arlen-live-key');",
      @"    var poll = attributeValue(primary, 'data-arlen-live-poll') || attributeValue(fallback, 'data-arlen-live-poll');",
      @"    var deferValue = attributeValue(primary, 'data-arlen-live-defer') || attributeValue(fallback, 'data-arlen-live-defer');",
      @"    var lazy = hasAttribute(primary, 'data-arlen-live-lazy') || hasAttribute(fallback, 'data-arlen-live-lazy');",
      @"    var owner = primary || fallback;",
      @"    if (!target && owner && owner.id && attributeValue(owner, 'data-arlen-live-src')) {",
      @"      target = '#' + owner.id;",
      @"    }",
      @"    if (!swap && source === 'region') {",
      @"      swap = 'update';",
      @"    }",
      @"    if (target) {",
      @"      metadata.target = target;",
      @"    }",
      @"    if (swap) {",
      @"      metadata.swap = swap;",
      @"    }",
      @"    if (component) {",
      @"      metadata.component = component;",
      @"    }",
      @"    if (eventName) {",
      @"      metadata.event = eventName;",
      @"    }",
      @"    if (source) {",
      @"      metadata.source = source;",
      @"    }",
      @"    if (container) {",
      @"      metadata.container = container;",
      @"    }",
      @"    if (key) {",
      @"      metadata.key = key;",
      @"    }",
      @"    if (poll) {",
      @"      metadata.poll = poll;",
      @"    }",
      @"    if (deferValue) {",
      @"      metadata.defer = deferValue;",
      @"    }",
      @"    if (lazy) {",
      @"      metadata.lazy = true;",
      @"    }",
      @"    return metadata;",
      @"  }",
      @"",
      @"  function applyLiveHeaders(headers, metadata) {",
      @"    if (!headers || !metadata) {",
      @"      return;",
      @"    }",
      @"    if (metadata.target) {",
      @"      headers['X-Arlen-Live-Target'] = metadata.target;",
      @"    }",
      @"    if (metadata.swap) {",
      @"      headers['X-Arlen-Live-Swap'] = metadata.swap;",
      @"    }",
      @"    if (metadata.component) {",
      @"      headers['X-Arlen-Live-Component'] = metadata.component;",
      @"    }",
      @"    if (metadata.event) {",
      @"      headers['X-Arlen-Live-Event'] = metadata.event;",
      @"    }",
      @"    if (metadata.source) {",
      @"      headers['X-Arlen-Live-Source'] = metadata.source;",
      @"    }",
      @"    if (metadata.container) {",
      @"      headers['X-Arlen-Live-Container'] = metadata.container;",
      @"    }",
      @"    if (metadata.key) {",
      @"      headers['X-Arlen-Live-Key'] = metadata.key;",
      @"    }",
      @"    if (metadata.poll) {",
      @"      headers['X-Arlen-Live-Poll'] = metadata.poll;",
      @"    }",
      @"    if (metadata.defer) {",
      @"      headers['X-Arlen-Live-Defer'] = metadata.defer;",
      @"    }",
      @"    if (metadata.lazy) {",
      @"      headers['X-Arlen-Live-Lazy'] = 'true';",
      @"    }",
      @"  }",
      @"",
      @"  function applyLiveXHRHeaders(xhr, metadata) {",
      @"    if (!xhr) {",
      @"      return;",
      @"    }",
      @"    var headers = {};",
      @"    applyLiveHeaders(headers, metadata);",
      @"    Object.keys(headers).forEach(function (name) {",
      @"      xhr.setRequestHeader(name, headers[name]);",
      @"    });",
      @"  }",
      @"",
      @"  function resolveTarget(selector) {",
      @"    if (!selector || typeof selector !== 'string') {",
      @"      return null;",
      @"    }",
      @"    try {",
      @"      return document.querySelector(selector);",
      @"    } catch (error) {",
      @"      console.warn('ArlenLive invalid selector', selector, error);",
      @"      return null;",
      @"    }",
      @"  }",
      @"",
      @"  function dispatchDocumentEvent(name, detail, targetSelector) {",
      @"    if (!name || typeof name !== 'string') {",
      @"      return;",
      @"    }",
      @"    var target = resolveTarget(targetSelector) || document;",
      @"    target.dispatchEvent(new CustomEvent(name, { detail: detail || {} }));",
      @"  }",
      @"",
      @"  function regionStateFor(element) {",
      @"    var state = regionState.get(element);",
      @"    if (!state) {",
      @"      state = { pending: false, hydrated: false, pollTimer: 0, pollInterval: 0, lazyBound: false, deferTimer: 0 };",
      @"      regionState.set(element, state);",
      @"    }",
      @"    return state;",
      @"  }",
      @"",
      @"  function setLoadingState(node, loading) {",
      @"    if (!node || !node.setAttribute) {",
      @"      return;",
      @"    }",
      @"    node.setAttribute('data-arlen-live-loading', loading ? 'true' : 'false');",
      @"  }",
      @"",
      @"  function findKeyedChild(container, key) {",
      @"    if (!container || !key) {",
      @"      return null;",
      @"    }",
      @"    var candidates = container.querySelectorAll('[data-arlen-live-key]');",
      @"    for (var index = 0; index < candidates.length; index += 1) {",
      @"      if (attributeValue(candidates[index], 'data-arlen-live-key') === key) {",
      @"        return candidates[index];",
      @"      }",
      @"    }",
      @"    return null;",
      @"  }",
      @"",
      @"  function syncKeyedEmptyState(container) {",
      @"    if (!container || !container.querySelectorAll) {",
      @"      return;",
      @"    }",
      @"    var placeholders = container.querySelectorAll('[data-arlen-live-empty]');",
      @"    if (!placeholders.length) {",
      @"      return;",
      @"    }",
      @"    var keyedCount = container.querySelectorAll('[data-arlen-live-key]').length;",
      @"    Array.prototype.forEach.call(placeholders, function (placeholder) {",
      @"      placeholder.hidden = keyedCount > 0;",
      @"    });",
      @"  }",
      @"",
      @"  function applyHTMLSwap(target, action, html) {",
      @"    if (!target) {",
      @"      return;",
      @"    }",
      @"    switch ((action || 'update').toLowerCase()) {",
      @"      case 'replace':",
      @"        target.outerHTML = html || '';",
      @"        break;",
      @"      case 'append':",
      @"        target.insertAdjacentHTML('beforeend', html || '');",
      @"        break;",
      @"      case 'prepend':",
      @"        target.insertAdjacentHTML('afterbegin', html || '');",
      @"        break;",
      @"      default:",
      @"        target.innerHTML = html || '';",
      @"        break;",
      @"    }",
      @"  }",
      @"",
      @"  function applyOperation(operation) {",
      @"    if (!operation || typeof operation !== 'object') {",
      @"      return;",
      @"    }",
      @"    if (operation.op === 'upsert' || operation.op === 'discard') {",
      @"      var container = resolveTarget(operation.container || operation.target);",
      @"      if (!container) {",
      @"        return;",
      @"      }",
      @"      if (operation.op === 'upsert') {",
      @"        var existing = findKeyedChild(container, operation.key || '');",
      @"        if (existing) {",
      @"          existing.outerHTML = operation.html || '';",
      @"        } else if (operation.prepend) {",
      @"          container.insertAdjacentHTML('afterbegin', operation.html || '');",
      @"        } else {",
      @"          container.insertAdjacentHTML('beforeend', operation.html || '');",
      @"        }",
      @"      } else {",
      @"        var keyedTarget = findKeyedChild(container, operation.key || '');",
      @"        if (keyedTarget) {",
      @"          keyedTarget.remove();",
      @"        }",
      @"      }",
      @"      syncKeyedEmptyState(container);",
      @"      return;",
      @"    }",
      @"    var target = resolveTarget(operation.target);",
      @"    switch (operation.op) {",
      @"      case 'replace':",
      @"      case 'update':",
      @"      case 'append':",
      @"      case 'prepend':",
      @"        applyHTMLSwap(target, operation.op, operation.html || '');",
      @"        break;",
      @"      case 'remove':",
      @"        if (target) {",
      @"          target.remove();",
      @"        }",
      @"        break;",
      @"      case 'navigate':",
      @"        if (operation.location) {",
      @"          if (operation.replace) {",
      @"            window.location.replace(operation.location);",
      @"          } else {",
      @"            window.location.assign(operation.location);",
      @"          }",
      @"        }",
      @"        break;",
      @"      case 'dispatch':",
      @"        dispatchDocumentEvent(operation.event, operation.detail || {}, operation.target || '');",
      @"        break;",
      @"      default:",
      @"        console.warn('ArlenLive unknown operation', operation);",
      @"    }",
      @"  }",
      @"",
      @"  function applyPayload(payload) {",
      @"    if (!payload || typeof payload !== 'object') {",
      @"      return;",
      @"    }",
      @"    var operations = Array.isArray(payload.operations) ? payload.operations : [];",
      @"    operations.forEach(applyOperation);",
      @"    scanStreams();",
      @"    scanLiveRegions();",
      @"    dispatchDocumentEvent('arlen:live:applied', payload, '');",
      @"  }",
      @"",
      @"  function parsePayloadText(text) {",
      @"    if (typeof text !== 'string' || text.length === 0) {",
      @"      return null;",
      @"    }",
      @"    try {",
      @"      var parsed = JSON.parse(text);",
      @"      if (Array.isArray(parsed)) {",
      @"        return { version: 'arlen-live-v1', operations: parsed };",
      @"      }",
      @"      if (parsed && parsed.op) {",
      @"        return { version: 'arlen-live-v1', operations: [parsed] };",
      @"      }",
      @"      return parsed;",
      @"    } catch (error) {",
      @"      console.warn('ArlenLive failed to parse payload', error);",
      @"      return null;",
      @"    }",
      @"  }",
      @"",
      @"  function retryAfterMillis(headers) {",
      @"    var retryHeader = '';",
      @"    if (headers && headers.get) {",
      @"      retryHeader = headers.get('Retry-After') || headers.get('X-Arlen-Live-Retry-After') || '';",
      @"    }",
      @"    return parseDuration(retryHeader) || (retryHeader ? Math.max(0, Number(retryHeader) * 1000) : 0);",
      @"  }",
      @"",
      @"  function handleLiveTextResponse(result, fallbackURL, options) {",
      @"    options = options || {};",
      @"    if (!result) {",
      @"      return null;",
      @"    }",
      @"    var status = Number(result.status || 0);",
      @"    var contentType = String(result.contentType || '').toLowerCase();",
      @"    var responseURL = result.url || fallbackURL || window.location.href;",
      @"    if (status === 401 || status === 403) {",
      @"      dispatchDocumentEvent('arlen:live:auth-expired', { status: status, url: responseURL }, options.targetSelector || '');",
      @"      window.location.assign(responseURL);",
      @"      return null;",
      @"    }",
      @"    if (status === 429 || status === 503) {",
      @"      dispatchDocumentEvent('arlen:live:backpressure', { status: status, url: responseURL, retryAfter: retryAfterMillis(result.headers) }, options.targetSelector || '');",
      @"      return null;",
      @"    }",
      @"    if (status === 204) {",
      @"      return null;",
      @"    }",
      @"    if (contentType.indexOf(LIVE_CONTENT_TYPE) !== -1 || (result.headers && result.headers.get && result.headers.get('X-Arlen-Live-Protocol'))) {",
      @"      var payload = parsePayloadText(result.text || '');",
      @"      if (payload) {",
      @"        applyPayload(payload);",
      @"      }",
      @"      return payload;",
      @"    }",
      @"    if (result.redirected && responseURL) {",
      @"      window.location.assign(responseURL);",
      @"      return null;",
      @"    }",
      @"    if (contentType.indexOf('text/html') !== -1 && options.htmlTarget) {",
      @"      applyHTMLSwap(options.htmlTarget, options.htmlAction || 'update', result.text || '');",
      @"      scanStreams();",
      @"      scanLiveRegions();",
      @"      return null;",
      @"    }",
      @"    if (contentType.indexOf('text/html') !== -1) {",
      @"      window.location.assign(responseURL);",
      @"      return null;",
      @"    }",
      @"    return result;",
      @"  }",
      @"",
      @"  async function handleLiveResponse(response, fallbackURL, options) {",
      @"    if (!response) {",
      @"      return null;",
      @"    }",
      @"    var text = response.status === 204 ? '' : await response.text();",
      @"    return handleLiveTextResponse({",
      @"      status: response.status,",
      @"      contentType: response.headers.get('Content-Type') || '',",
      @"      headers: headerReaderFromResponse(response),",
      @"      redirected: response.redirected,",
      @"      url: response.url || fallbackURL || window.location.href,",
      @"      text: text",
      @"    }, fallbackURL, options);",
      @"  }",
      @"",
      @"  function setFormBusy(form, busy) {",
      @"    if (!form) {",
      @"      return;",
      @"    }",
      @"    form.setAttribute('data-arlen-live-busy', busy ? 'true' : 'false');",
      @"    Array.prototype.forEach.call(",
      @"      form.querySelectorAll('button, input[type=submit], input[type=button]'),",
      @"      function (control) {",
      @"        if (busy) {",
      @"          if (control.disabled) {",
      @"            control.setAttribute('data-arlen-live-disabled-before', 'true');",
      @"          } else {",
      @"            control.setAttribute('data-arlen-live-disabled-before', 'false');",
      @"            control.disabled = true;",
      @"          }",
      @"        } else if (control.getAttribute('data-arlen-live-disabled-before') === 'false') {",
      @"          control.disabled = false;",
      @"          control.removeAttribute('data-arlen-live-disabled-before');",
      @"        }",
      @"      }",
      @"    );",
      @"  }",
      @"",
      @"  function progressTargetForForm(form) {",
      @"    if (!form) {",
      @"      return null;",
      @"    }",
      @"    var selector = attributeValue(form, 'data-arlen-live-progress-target') || attributeValue(form, 'data-arlen-live-upload-progress');",
      @"    if (selector === 'self') {",
      @"      return form;",
      @"    }",
      @"    if (selector) {",
      @"      return resolveTarget(selector) || (form.querySelector ? form.querySelector(selector) : null);",
      @"    }",
      @"    return form.querySelector ? form.querySelector('[data-arlen-live-progress], progress') : null;",
      @"  }",
      @"",
      @"  function updateProgressTarget(target, loaded, total) {",
      @"    if (!target) {",
      @"      return;",
      @"    }",
      @"    var percent = total > 0 ? Math.max(0, Math.min(100, Math.round((loaded / total) * 100))) : 0;",
      @"    target.setAttribute('data-arlen-live-upload-loaded', String(Math.max(0, loaded || 0)));",
      @"    target.setAttribute('data-arlen-live-upload-total', String(Math.max(0, total || 0)));",
      @"    target.setAttribute('data-arlen-live-upload-percent', String(percent));",
      @"    if (target.tagName === 'PROGRESS') {",
      @"      target.max = total > 0 ? total : 100;",
      @"      target.value = total > 0 ? loaded : percent;",
      @"    } else if (!target.children.length) {",
      @"      target.textContent = percent + '%';",
      @"    }",
      @"  }",
      @"",
      @"  function emitUploadProgress(form, loaded, total) {",
      @"    var target = progressTargetForForm(form);",
      @"    updateProgressTarget(target, loaded, total);",
      @"    dispatchDocumentEvent('arlen:live:upload-progress', { loaded: loaded || 0, total: total || 0, form: form }, attributeValue(form, 'data-arlen-live-target'));",
      @"  }",
      @"",
      @"  function shouldUseXHR(form) {",
      @"    return !!(form && form.querySelector && (attributeValue(form, 'data-arlen-live-upload-progress') || attributeValue(form, 'data-arlen-live-progress-target') || form.querySelector('input[type=file]')));",
      @"  }",
      @"",
      @"  function submitViaXHR(form, method, fetchURL, metadata, formData) {",
      @"    return new Promise(function (resolve, reject) {",
      @"      var xhr = new XMLHttpRequest();",
      @"      xhr.open(method, fetchURL, true);",
      @"      xhr.withCredentials = true;",
      @"      xhr.setRequestHeader('Accept', LIVE_ACCEPT);",
      @"      xhr.setRequestHeader('X-Arlen-Live', 'true');",
      @"      applyLiveXHRHeaders(xhr, metadata);",
      @"      xhr.upload.addEventListener('progress', function (event) {",
      @"        emitUploadProgress(form, event.loaded || 0, event.lengthComputable ? event.total : 0);",
      @"      });",
      @"      xhr.addEventListener('error', reject);",
      @"      xhr.addEventListener('abort', reject);",
      @"      xhr.addEventListener('load', function () {",
      @"        emitUploadProgress(form, 1, 1);",
      @"        resolve(handleLiveTextResponse({",
      @"          status: xhr.status,",
      @"          contentType: xhr.getResponseHeader('Content-Type') || '',",
      @"          headers: { get: function (name) { return xhr.getResponseHeader(name) || ''; } },",
      @"          redirected: false,",
      @"          url: xhr.responseURL || fetchURL || window.location.href,",
      @"          text: xhr.responseText || ''",
      @"        }, fetchURL, { targetSelector: metadata.target || '', htmlTarget: resolveTarget(metadata.target || ''), htmlAction: metadata.swap || 'update' }));",
      @"      });",
      @"      emitUploadProgress(form, 0, 0);",
      @"      xhr.send(formData);",
      @"    });",
      @"  }",
      @"",
      @"  async function submitLiveForm(form, submitter) {",
      @"    var method = (form.getAttribute('method') || 'GET').toUpperCase();",
      @"    var action = form.getAttribute('action') || window.location.href;",
      @"    var metadata = collectLiveRequestMetadata(submitter, form, 'form');",
      @"    var headers = {",
      @"      'Accept': LIVE_ACCEPT,",
      @"      'X-Arlen-Live': 'true'",
      @"    };",
      @"    applyLiveHeaders(headers, metadata);",
      @"    var fetchURL = action;",
      @"    var options = {",
      @"      method: method,",
      @"      credentials: 'same-origin',",
      @"      headers: headers",
      @"    };",
      @"    var formData = new FormData(form);",
      @"    if (submitter && submitter.name && !formData.has(submitter.name)) {",
      @"      formData.append(submitter.name, submitter.value || '');",
      @"    }",
      @"    if (method === 'GET') {",
      @"      var url = new URL(action, window.location.href);",
      @"      var params = new URLSearchParams(formData);",
      @"      params.forEach(function (value, key) {",
      @"        url.searchParams.set(key, value);",
      @"      });",
      @"      fetchURL = url.toString();",
      @"    } else {",
      @"      options.body = formData;",
      @"    }",
      @"    setFormBusy(form, true);",
      @"    dispatchDocumentEvent('arlen:live:request-start', { url: fetchURL, method: method, metadata: metadata }, metadata.target || '');",
      @"    try {",
      @"      if (method !== 'GET' && shouldUseXHR(form)) {",
      @"        return await submitViaXHR(form, method, fetchURL, metadata, formData);",
      @"      }",
      @"      var response = await fetch(fetchURL, options);",
      @"      return await handleLiveResponse(response, fetchURL, { targetSelector: metadata.target || '' });",
      @"    } finally {",
      @"      setFormBusy(form, false);",
      @"      dispatchDocumentEvent('arlen:live:request-end', { url: fetchURL, method: method, metadata: metadata }, metadata.target || '');",
      @"    }",
      @"  }",
      @"",
      @"  async function followLiveLink(link) {",
      @"    var href = link.getAttribute('href');",
      @"    if (!href || href.charAt(0) === '#') {",
      @"      return null;",
      @"    }",
      @"    var url = new URL(href, window.location.href);",
      @"    var metadata = collectLiveRequestMetadata(link, null, 'link');",
      @"    var headers = {",
      @"      'Accept': LIVE_ACCEPT,",
      @"      'X-Arlen-Live': 'true'",
      @"    };",
      @"    applyLiveHeaders(headers, metadata);",
      @"    var response = await fetch(url.toString(), {",
      @"      method: 'GET',",
      @"      credentials: 'same-origin',",
      @"      headers: headers",
      @"    });",
      @"    return handleLiveResponse(response, url.toString(), { targetSelector: metadata.target || '' });",
      @"  }",
      @"",
      @"  async function fetchLiveRegion(element, reason) {",
      @"    if (!element || !document.contains(element)) {",
      @"      return null;",
      @"    }",
      @"    var state = regionStateFor(element);",
      @"    if (state.pending) {",
      @"      return null;",
      @"    }",
      @"    var src = attributeValue(element, 'data-arlen-live-src');",
      @"    if (!src) {",
      @"      return null;",
      @"    }",
      @"    state.pending = true;",
      @"    var metadata = collectLiveRequestMetadata(element, null, 'region');",
      @"    var headers = {",
      @"      'Accept': LIVE_ACCEPT,",
      @"      'X-Arlen-Live': 'true'",
      @"    };",
      @"    applyLiveHeaders(headers, metadata);",
      @"    var target = resolveTarget(metadata.target) || element;",
      @"    var url = new URL(src, window.location.href).toString();",
      @"    setLoadingState(element, true);",
      @"    dispatchDocumentEvent('arlen:live:region-start', { url: url, metadata: metadata, reason: reason || 'load' }, metadata.target || '');",
      @"    try {",
      @"      var response = await fetch(url, {",
      @"        method: 'GET',",
      @"        credentials: 'same-origin',",
      @"        headers: headers",
      @"      });",
      @"      var result = await handleLiveResponse(response, url, {",
      @"        targetSelector: metadata.target || '',",
      @"        htmlTarget: target,",
      @"        htmlAction: metadata.swap || 'update'",
      @"      });",
      @"      state.hydrated = true;",
      @"      if (state.pollInterval > 0 && !state.pollTimer) {",
      @"        state.pollTimer = window.setInterval(function () {",
      @"          if (!document.contains(element)) {",
      @"            window.clearInterval(state.pollTimer);",
      @"            state.pollTimer = 0;",
      @"            return;",
      @"          }",
      @"          fetchLiveRegion(element, 'poll').catch(function (error) {",
      @"            console.warn('ArlenLive region poll failed', error);",
      @"          });",
      @"        }, state.pollInterval);",
      @"      }",
      @"      return result;",
      @"    } finally {",
      @"      state.pending = false;",
      @"      setLoadingState(element, false);",
      @"      element.setAttribute('data-arlen-live-hydrated', 'true');",
      @"      dispatchDocumentEvent('arlen:live:region-end', { url: url, metadata: metadata, reason: reason || 'load' }, metadata.target || '');",
      @"    }",
      @"  }",
      @"",
      @"  function activateRegion(element) {",
      @"    if (!element || !document.contains(element)) {",
      @"      return;",
      @"    }",
      @"    var state = regionStateFor(element);",
      @"    var pollInterval = parseDuration(attributeValue(element, 'data-arlen-live-poll'));",
      @"    if (pollInterval > 0) {",
      @"      state.pollInterval = pollInterval;",
      @"    }",
      @"    if (state.hydrated || state.pending || state.deferTimer) {",
      @"      if (!state.hydrated && hasAttribute(element, 'data-arlen-live-lazy') && lazyObserver && !state.lazyBound) {",
      @"        lazyObserver.observe(element);",
      @"        state.lazyBound = true;",
      @"      }",
      @"      return;",
      @"    }",
      @"    if (hasAttribute(element, 'data-arlen-live-lazy')) {",
      @"      if (lazyObserver && !state.lazyBound) {",
      @"        lazyObserver.observe(element);",
      @"        state.lazyBound = true;",
      @"      } else if (!lazyObserver) {",
      @"        fetchLiveRegion(element, 'lazy').catch(function (error) {",
      @"          console.warn('ArlenLive lazy region failed', error);",
      @"        });",
      @"      }",
      @"      return;",
      @"    }",
      @"    var deferValue = parseDuration(attributeValue(element, 'data-arlen-live-defer'));",
      @"    if (deferValue > 0) {",
      @"      state.deferTimer = window.setTimeout(function () {",
      @"        state.deferTimer = 0;",
      @"        fetchLiveRegion(element, 'defer').catch(function (error) {",
      @"          console.warn('ArlenLive deferred region failed', error);",
      @"        });",
      @"      }, deferValue);",
      @"      return;",
      @"    }",
      @"    fetchLiveRegion(element, 'load').catch(function (error) {",
      @"      console.warn('ArlenLive region request failed', error);",
      @"    });",
      @"  }",
      @"",
      @"  function scanLiveRegions() {",
      @"    document.querySelectorAll('[data-arlen-live-src]').forEach(function (element) {",
      @"      activateRegion(element);",
      @"    });",
      @"  }",
      @"",
      @"  function normalizeStreamURL(rawURL) {",
      @"    var url = new URL(rawURL, window.location.href);",
      @"    if (url.protocol === 'http:') {",
      @"      url.protocol = 'ws:';",
      @"    } else if (url.protocol === 'https:') {",
      @"      url.protocol = 'wss:';",
      @"    }",
      @"    return url.toString();",
      @"  }",
      @"",
      @"  function streamElementsExist(rawURL) {",
      @"    return Array.prototype.some.call(document.querySelectorAll('[data-arlen-live-stream]'), function (element) {",
      @"      return attributeValue(element, 'data-arlen-live-stream') === rawURL;",
      @"    });",
      @"  }",
      @"",
      @"  function setStreamElementsState(rawURL, state) {",
      @"    Array.prototype.forEach.call(document.querySelectorAll('[data-arlen-live-stream]'), function (element) {",
      @"      if (attributeValue(element, 'data-arlen-live-stream') === rawURL) {",
      @"        element.setAttribute('data-arlen-live-stream-state', state);",
      @"      }",
      @"    });",
      @"  }",
      @"",
      @"  function ensureStream(rawURL) {",
      @"    if (!rawURL || typeof rawURL !== 'string') {",
      @"      return null;",
      @"    }",
      @"    var url = normalizeStreamURL(rawURL);",
      @"    var state = streamState.get(url) || { attempts: 0, reconnectTimer: 0, rawURL: rawURL };",
      @"    streamState.set(url, state);",
      @"    if (state.socket && (state.socket.readyState === WebSocket.OPEN || state.socket.readyState === WebSocket.CONNECTING)) {",
      @"      return state.socket;",
      @"    }",
      @"    if (!streamElementsExist(rawURL)) {",
      @"      return null;",
      @"    }",
      @"    var socket = new WebSocket(url);",
      @"    state.socket = socket;",
      @"    streamSockets.set(url, socket);",
      @"    setStreamElementsState(rawURL, 'connecting');",
      @"    socket.addEventListener('open', function () {",
      @"      state.attempts = 0;",
      @"      setStreamElementsState(rawURL, 'open');",
      @"      dispatchDocumentEvent('arlen:live:stream-open', { url: rawURL }, '');",
      @"    });",
      @"    socket.addEventListener('message', function (event) {",
      @"      var payload = parsePayloadText(event.data);",
      @"      if (payload) {",
      @"        applyPayload(payload);",
      @"      }",
      @"    });",
      @"    socket.addEventListener('error', function () {",
      @"      setStreamElementsState(rawURL, 'error');",
      @"      dispatchDocumentEvent('arlen:live:stream-error', { url: rawURL }, '');",
      @"    });",
      @"    socket.addEventListener('close', function (event) {",
      @"      streamSockets.delete(url);",
      @"      state.socket = null;",
      @"      setStreamElementsState(rawURL, 'closed');",
      @"      if (!streamElementsExist(rawURL)) {",
      @"        return;",
      @"      }",
      @"      state.attempts += 1;",
      @"      var delay = Math.min(30000, Math.pow(2, Math.max(0, state.attempts - 1)) * 1000);",
      @"      dispatchDocumentEvent('arlen:live:stream-closed', { url: rawURL, code: event.code, reason: event.reason || '', retryIn: delay }, '');",
      @"      state.reconnectTimer = window.setTimeout(function () {",
      @"        state.reconnectTimer = 0;",
      @"        ensureStream(rawURL);",
      @"      }, delay);",
      @"    });",
      @"    return socket;",
      @"  }",
      @"",
      @"  function scanStreams() {",
      @"    document.querySelectorAll('[data-arlen-live-stream]').forEach(function (element) {",
      @"      var streamURL = element.getAttribute('data-arlen-live-stream');",
      @"      if (streamURL) {",
      @"        ensureStream(streamURL);",
      @"      }",
      @"    });",
      @"  }",
      @"",
      @"  function start() {",
      @"    if ('IntersectionObserver' in window && !lazyObserver) {",
      @"      lazyObserver = new IntersectionObserver(function (entries) {",
      @"        entries.forEach(function (entry) {",
      @"          if (entry.isIntersecting || entry.intersectionRatio > 0) {",
      @"            lazyObserver.unobserve(entry.target);",
      @"            fetchLiveRegion(entry.target, 'lazy').catch(function (error) {",
      @"              console.warn('ArlenLive lazy region failed', error);",
      @"            });",
      @"          }",
      @"        });",
      @"      }, { rootMargin: '100px 0px' });",
      @"    }",
      @"    scanStreams();",
      @"    scanLiveRegions();",
      @"  }",
      @"",
      @"  document.addEventListener('submit', function (event) {",
      @"    var form = closestLiveForm(event.target);",
      @"    if (!form) {",
      @"      return;",
      @"    }",
      @"    event.preventDefault();",
      @"    submitLiveForm(form, event.submitter || null).catch(function (error) {",
      @"      console.error('ArlenLive form request failed', error);",
      @"      window.location.assign(form.getAttribute('action') || window.location.href);",
      @"    });",
      @"  });",
      @"",
      @"  document.addEventListener('click', function (event) {",
      @"    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {",
      @"      return;",
      @"    }",
      @"    var link = closestLiveLink(event.target);",
      @"    if (!link || link.target === '_blank' || link.hasAttribute('download')) {",
      @"      return;",
      @"    }",
      @"    event.preventDefault();",
      @"    followLiveLink(link).catch(function (error) {",
      @"      console.error('ArlenLive link request failed', error);",
      @"      window.location.assign(link.href);",
      @"    });",
      @"  });",
      @"",
      @"  if (document.readyState === 'loading') {",
      @"    document.addEventListener('DOMContentLoaded', start, { once: true });",
      @"  } else {",
      @"    start();",
      @"  }",
      @"",
      @"  window.ArlenLive = {",
      @"    __version: 'arlen-live-v1',",
      @"    applyPayload: applyPayload,",
      @"    ensureStream: ensureStream,",
      @"    fetchRegion: function (selector) {",
      @"      return fetchLiveRegion(resolveTarget(selector), 'manual');",
      @"    },",
      @"    requestIsLive: function () { return true; },",
      @"    start: start",
      @"  };",
      @"})();"
    ] componentsJoinedByString:@"\n"];
  });
  return script;
}

@end
