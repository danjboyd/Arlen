#import "ALNResponse.h"

#import "ALNJSONSerialization.h"
#import <dispatch/dispatch.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

NSString *const ALNResponseErrorDomain = @"Arlen.HTTP.Response.Error";

static NSLock *gALNResponseFaultInjectionLock = nil;
static NSMutableSet *gALNResponseFaultInjectionConsumed = nil;
static NSLock *gALNResponseFaultInjectionStateLock = nil;

static BOOL ALNResponseEnvFlagEnabled(const char *name) {
  if (name == NULL || name[0] == '\0') {
    return NO;
  }
  const char *raw = getenv(name);
  if (raw == NULL || raw[0] == '\0') {
    return NO;
  }
  if (strcmp(raw, "0") == 0) {
    return NO;
  }
  if (strcasecmp(raw, "false") == 0 || strcasecmp(raw, "off") == 0 ||
      strcasecmp(raw, "no") == 0) {
    return NO;
  }
  return YES;
}

static NSLock *ALNResponseFaultInjectionStateLock(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    gALNResponseFaultInjectionStateLock = [[NSLock alloc] init];
  });
  return gALNResponseFaultInjectionStateLock;
}

static void ALNEnsureResponseFaultInjectionState(void) {
  if (gALNResponseFaultInjectionLock != nil && gALNResponseFaultInjectionConsumed != nil) {
    return;
  }
  NSLock *stateLock = ALNResponseFaultInjectionStateLock();
  [stateLock lock];
  @try {
    if (gALNResponseFaultInjectionLock == nil) {
      gALNResponseFaultInjectionLock = [[NSLock alloc] init];
    }
    if (gALNResponseFaultInjectionConsumed == nil) {
      gALNResponseFaultInjectionConsumed = [NSMutableSet set];
    }
  } @finally {
    [stateLock unlock];
  }
}

static BOOL ALNResponseConsumeFaultOnce(const char *name) {
  if (!ALNResponseEnvFlagEnabled(name)) {
    return NO;
  }
  ALNEnsureResponseFaultInjectionState();
  NSString *key = [NSString stringWithUTF8String:name];
  if ([key length] == 0) {
    return NO;
  }
  BOOL shouldInject = NO;
  [gALNResponseFaultInjectionLock lock];
  if (![gALNResponseFaultInjectionConsumed containsObject:key]) {
    [gALNResponseFaultInjectionConsumed addObject:key];
    shouldInject = YES;
  }
  [gALNResponseFaultInjectionLock unlock];
  return shouldInject;
}

static NSUInteger ALNInsertionIndexForSortedHeaderKeys(NSArray *keys, NSString *candidate) {
  NSUInteger low = 0;
  NSUInteger high = [keys count];
  while (low < high) {
    NSUInteger mid = low + ((high - low) / 2);
    NSString *existing = [keys[mid] isKindOfClass:[NSString class]] ? keys[mid] : @"";
    NSComparisonResult comparison = [existing compare:(candidate ?: @"")];
    if (comparison == NSOrderedAscending) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

static NSString *ALNNormalizedHeaderKey(NSString *name) {
  if (![name isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed =
      [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }
  return [trimmed lowercaseString];
}

static BOOL ALNHeaderNameIsValid(NSString *name) {
  if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return NO;
  }
  for (NSUInteger index = 0; index < [name length]; index++) {
    unichar c = [name characterAtIndex:index];
    if (c > 127) {
      return NO;
    }
    BOOL isAlphaNum = (BOOL)(isalnum(c) != 0);
    BOOL isTokenSymbol = (c == '!' || c == '#' || c == '$' || c == '%' || c == '&' || c == '\'' ||
                          c == '*' || c == '+' || c == '-' || c == '.' || c == '^' || c == '_' ||
                          c == '`' || c == '|' || c == '~');
    if (!isAlphaNum && !isTokenSymbol) {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNHeaderValueContainsForbiddenBytes(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return YES;
  }
  NSUInteger length = [value length];
  for (NSUInteger idx = 0; idx < length; idx++) {
    unichar c = [value characterAtIndex:idx];
    if (c == '\r' || c == '\n' || c == '\0') {
      return YES;
    }
  }
  return NO;
}

// An explicit allowlist prevents append from introducing ambiguous framing or
// changing singleton fields. Expand only with a documented repeated-field contract.
static BOOL ALNHeaderSupportsRepeatedValues(NSString *key) {
  return [key isEqualToString:@"set-cookie"] ||
         [key isEqualToString:@"www-authenticate"] ||
         [key isEqualToString:@"proxy-authenticate"] ||
         [key isEqualToString:@"link"] ||
         [key isEqualToString:@"warning"] ||
         [key isEqualToString:@"vary"] ||
         [key isEqualToString:@"cache-control"];
}

/// Reason phrases are advisory -- a conformant client takes its meaning from the
/// status code -- but they are what lands in access logs, proxy logs and
/// `curl -i`, so a wrong one costs debugging time. Kept in numeric order: the
/// gaps are the point, and an unordered table is how 401 went missing.
static NSString *ALNStatusText(NSInteger statusCode) {
  switch (statusCode) {
  case 100:
    return @"Continue";
  case 101:
    return @"Switching Protocols";
  case 200:
    return @"OK";
  case 201:
    return @"Created";
  case 202:
    return @"Accepted";
  case 204:
    return @"No Content";
  case 206:
    return @"Partial Content";
  case 301:
    return @"Moved Permanently";
  case 302:
    return @"Found";
  case 303:
    return @"See Other";
  case 304:
    return @"Not Modified";
  case 307:
    return @"Temporary Redirect";
  case 308:
    return @"Permanent Redirect";
  case 400:
    return @"Bad Request";
  case 401:
    return @"Unauthorized";
  case 403:
    return @"Forbidden";
  case 404:
    return @"Not Found";
  case 405:
    return @"Method Not Allowed";
  case 406:
    return @"Not Acceptable";
  case 408:
    return @"Request Timeout";
  case 409:
    return @"Conflict";
  case 410:
    return @"Gone";
  case 411:
    return @"Length Required";
  case 412:
    return @"Precondition Failed";
  case 413:
    return @"Payload Too Large";
  case 414:
    return @"URI Too Long";
  case 415:
    return @"Unsupported Media Type";
  case 416:
    return @"Range Not Satisfiable";
  case 422:
    return @"Unprocessable Content";
  case 428:
    return @"Precondition Required";
  case 429:
    return @"Too Many Requests";
  case 431:
    return @"Request Header Fields Too Large";
  case 451:
    return @"Unavailable For Legal Reasons";
  case 500:
    return @"Internal Server Error";
  case 501:
    return @"Not Implemented";
  case 502:
    return @"Bad Gateway";
  case 503:
    return @"Service Unavailable";
  case 504:
    return @"Gateway Timeout";
  case 505:
    return @"HTTP Version Not Supported";
  default:
    // RFC 9112 section 4.1 permits an empty reason phrase. Saying nothing about
    // an unknown code is honest; the previous "OK" described every one of them,
    // including every error, as success.
    return @"";
  }
}

@interface ALNResponse ()

@property(nonatomic, strong, readwrite) NSMutableDictionary *headers;
@property(nonatomic, strong, readwrite) NSMutableData *bodyData;
@property(nonatomic, strong) NSData *bodyDataReference;
@property(nonatomic, strong) NSMutableArray *orderedHeaderKeys;
@property(nonatomic, strong) NSMutableDictionary *headerNamesByNormalizedKey;
@property(nonatomic, strong) NSData *cachedHeaderData;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *additionalHeaderValues;
@property(nonatomic, assign) BOOL serializedHeadersDirty;

@end

static NSCache *ALNSharedSerializedHeaderCache(void) {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    [cache setCountLimit:512];
  });
  return cache;
}

static void ALNAppendUTF8String(NSMutableData *data, NSString *string) {
  if (data == nil || ![string isKindOfClass:[NSString class]] || [string length] == 0) {
    return;
  }
  const char *utf8 = [string UTF8String];
  if (utf8 == NULL || utf8[0] == '\0') {
    return;
  }
  [data appendBytes:utf8 length:strlen(utf8)];
}

static BOOL ALNResponseCanUseSharedHeaderSerialization(ALNResponse *response,
                                                       NSString **connectionNameOut,
                                                       NSString **connectionValueOut,
                                                       NSString **contentLengthNameOut,
                                                       NSString **contentLengthValueOut,
                                                       NSString **contentTypeNameOut,
                                                       NSString **contentTypeValueOut,
                                                       NSString **serverNameOut,
                                                       NSString **serverValueOut) {
  if (response == nil || [response.additionalHeaderValues count] > 0) {
    return NO;
  }

  NSUInteger count = [response.headers count];
  if (count != 3 && count != 4) {
    return NO;
  }

  NSString *contentLengthValue =
      [response.headers[@"content-length"] isKindOfClass:[NSString class]]
          ? response.headers[@"content-length"]
          : nil;
  NSString *contentTypeValue =
      [response.headers[@"content-type"] isKindOfClass:[NSString class]]
          ? response.headers[@"content-type"]
          : nil;
  NSString *serverValue = [response.headers[@"server"] isKindOfClass:[NSString class]]
                              ? response.headers[@"server"]
                              : nil;
  NSString *connectionValue =
      [response.headers[@"connection"] isKindOfClass:[NSString class]]
          ? response.headers[@"connection"]
          : nil;
  if ([contentLengthValue length] == 0 || [contentTypeValue length] == 0 ||
      [serverValue length] == 0) {
    return NO;
  }
  if ((count == 4 && [connectionValue length] == 0) ||
      (count == 3 && [connectionValue length] > 0)) {
    return NO;
  }

  NSString *contentLengthName =
      [response.headerNamesByNormalizedKey[@"content-length"] isKindOfClass:[NSString class]]
          ? response.headerNamesByNormalizedKey[@"content-length"]
          : @"Content-Length";
  NSString *contentTypeName =
      [response.headerNamesByNormalizedKey[@"content-type"] isKindOfClass:[NSString class]]
          ? response.headerNamesByNormalizedKey[@"content-type"]
          : @"Content-Type";
  NSString *serverName =
      [response.headerNamesByNormalizedKey[@"server"] isKindOfClass:[NSString class]]
          ? response.headerNamesByNormalizedKey[@"server"]
          : @"Server";
  NSString *connectionName =
      [response.headerNamesByNormalizedKey[@"connection"] isKindOfClass:[NSString class]]
          ? response.headerNamesByNormalizedKey[@"connection"]
          : @"Connection";

  NSMutableSet *expectedKeys = [NSMutableSet setWithObjects:@"content-length",
                                                          @"content-type",
                                                          @"server",
                                                          nil];
  if ([connectionValue length] > 0) {
    [expectedKeys addObject:@"connection"];
  }
  for (NSString *normalizedKey in response.headers) {
    if (![expectedKeys containsObject:normalizedKey]) {
      return NO;
    }
  }

  if (connectionNameOut != NULL) {
    *connectionNameOut = connectionName;
  }
  if (connectionValueOut != NULL) {
    *connectionValueOut = connectionValue;
  }
  if (contentLengthNameOut != NULL) {
    *contentLengthNameOut = contentLengthName;
  }
  if (contentLengthValueOut != NULL) {
    *contentLengthValueOut = contentLengthValue;
  }
  if (contentTypeNameOut != NULL) {
    *contentTypeNameOut = contentTypeName;
  }
  if (contentTypeValueOut != NULL) {
    *contentTypeValueOut = contentTypeValue;
  }
  if (serverNameOut != NULL) {
    *serverNameOut = serverName;
  }
  if (serverValueOut != NULL) {
    *serverValueOut = serverValue;
  }
  return YES;
}

static NSData *ALNSharedSerializedHeaderDataForResponse(ALNResponse *response) {
  NSString *connectionName = nil;
  NSString *connectionValue = nil;
  NSString *contentLengthName = nil;
  NSString *contentLengthValue = nil;
  NSString *contentTypeName = nil;
  NSString *contentTypeValue = nil;
  NSString *serverName = nil;
  NSString *serverValue = nil;

  if (!ALNResponseCanUseSharedHeaderSerialization(response,
                                                  &connectionName,
                                                  &connectionValue,
                                                  &contentLengthName,
                                                  &contentLengthValue,
                                                  &contentTypeName,
                                                  &contentTypeValue,
                                                  &serverName,
                                                  &serverValue)) {
    return nil;
  }

  NSString *cacheKey = [NSString
      stringWithFormat:@"%ld|%@|%@|%@|%@|%@|%@|%@|%@",
                       (long)response.statusCode,
                       connectionName ?: @"",
                       connectionValue ?: @"",
                       contentLengthName ?: @"",
                       contentLengthValue ?: @"",
                       contentTypeName ?: @"",
                       contentTypeValue ?: @"",
                       serverName ?: @"",
                       serverValue ?: @""];
  NSCache *cache = ALNSharedSerializedHeaderCache();
  NSData *cached = [cache objectForKey:cacheKey];
  if (cached != nil) {
    return cached;
  }

  NSMutableData *data = [NSMutableData dataWithCapacity:128];
  [data appendBytes:"HTTP/1.1 " length:9];
  ALNAppendUTF8String(data, [NSString stringWithFormat:@"%ld", (long)response.statusCode]);
  [data appendBytes:" " length:1];
  ALNAppendUTF8String(data, ALNStatusText(response.statusCode));
  [data appendBytes:"\r\n" length:2];
  if ([connectionValue length] > 0) {
    ALNAppendUTF8String(data, connectionName);
    [data appendBytes:": " length:2];
    ALNAppendUTF8String(data, connectionValue);
    [data appendBytes:"\r\n" length:2];
  }
  ALNAppendUTF8String(data, contentLengthName);
  [data appendBytes:": " length:2];
  ALNAppendUTF8String(data, contentLengthValue);
  [data appendBytes:"\r\n" length:2];
  ALNAppendUTF8String(data, contentTypeName);
  [data appendBytes:": " length:2];
  ALNAppendUTF8String(data, contentTypeValue);
  [data appendBytes:"\r\n" length:2];
  ALNAppendUTF8String(data, serverName);
  [data appendBytes:": " length:2];
  ALNAppendUTF8String(data, serverValue);
  [data appendBytes:"\r\n\r\n" length:4];

  NSData *serialized = [data copy];
  if (serialized != nil) {
    [cache setObject:serialized forKey:cacheKey];
  }
  return serialized;
}

@implementation ALNResponse

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusCode = 200;
    _headers = [NSMutableDictionary dictionary];
    _bodyData = nil;
    _bodyDataReference = nil;
    _orderedHeaderKeys = [NSMutableArray array];
    _headerNamesByNormalizedKey = [NSMutableDictionary dictionary];
    _committed = NO;
    _fileBodyPath = nil;
    _fileBodyLength = 0;
    _fileBodyDevice = 0;
    _fileBodyInode = 0;
    _fileBodyMTimeSeconds = 0;
    _fileBodyMTimeNanoseconds = 0;
    _cachedHeaderData = nil;
    _serializedHeadersDirty = YES;
    [self setHeader:@"Server" value:@"Arlen"];
  }
  return self;
}

- (void)invalidateSerializedHeaders {
  self.serializedHeadersDirty = YES;
  self.cachedHeaderData = nil;
}

- (void)resetFileBodyState {
  self.fileBodyPath = nil;
  self.fileBodyLength = 0;
  self.fileBodyDevice = 0;
  self.fileBodyInode = 0;
  self.fileBodyMTimeSeconds = 0;
  self.fileBodyMTimeNanoseconds = 0;
}

- (void)materializeMutableBodyDataIfNeeded {
  if (_bodyData != nil) {
    return;
  }
  if (self.bodyDataReference != nil) {
    _bodyData = [NSMutableData dataWithData:self.bodyDataReference];
    self.bodyDataReference = nil;
    return;
  }
  _bodyData = [NSMutableData data];
}

- (NSMutableData *)bodyData {
  [self materializeMutableBodyDataIfNeeded];
  return _bodyData;
}

- (void)clearBody {
  [self resetFileBodyState];
  self.bodyDataReference = nil;
  if (_bodyData != nil) {
    [_bodyData setLength:0];
  }
  [self invalidateSerializedHeaders];
}

- (NSUInteger)bodyLength {
  if (self.bodyDataReference != nil) {
    return [self.bodyDataReference length];
  }
  return [_bodyData length];
}

- (NSData *)bodyDataForTransmission {
  if (self.bodyDataReference != nil) {
    return self.bodyDataReference;
  }
  return _bodyData ?: [NSData data];
}

- (void)rebuildOrderedHeaderKeysIfNeeded {
  if ([self.orderedHeaderKeys count] == [self.headers count]) {
    return;
  }
  [self.orderedHeaderKeys removeAllObjects];
  NSArray *sorted = [[self.headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  [self.orderedHeaderKeys addObjectsFromArray:sorted];
}

- (void)insertOrderedHeaderKeyIfNeeded:(NSString *)normalizedKey {
  if ([normalizedKey length] == 0) {
    return;
  }
  if ([self.orderedHeaderKeys containsObject:normalizedKey]) {
    return;
  }
  NSUInteger insertion =
      ALNInsertionIndexForSortedHeaderKeys(self.orderedHeaderKeys, normalizedKey);
  [self.orderedHeaderKeys insertObject:normalizedKey atIndex:insertion];
}

- (BOOL)setHeaderInternal:(NSString *)name
                    value:(NSString *)value
               invalidate:(BOOL)invalidate {
  NSString *normalizedKey = ALNNormalizedHeaderKey(name);
  if (ALNHeaderValueContainsForbiddenBytes(name) ||
      [normalizedKey length] == 0 || !ALNHeaderNameIsValid(normalizedKey)) {
    return NO;
  }
  NSString *resolvedValue = value ?: @"";
  if (ALNHeaderValueContainsForbiddenBytes(resolvedValue)) {
    return NO;
  }
  NSString *displayName = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([displayName length] == 0) {
    return NO;
  }
  NSString *currentValue = [self.headers[normalizedKey] isKindOfClass:[NSString class]]
                               ? self.headers[normalizedKey]
                               : nil;
  BOOL repeated = [self.additionalHeaderValues[normalizedKey] count] > 0;
  if (currentValue != nil && [currentValue isEqualToString:resolvedValue] && !repeated &&
      [self.headerNamesByNormalizedKey[normalizedKey] isEqualToString:displayName]) {
    return NO;
  }
  if (currentValue == nil) {
    [self insertOrderedHeaderKeyIfNeeded:normalizedKey];
  }
  [self.additionalHeaderValues removeObjectForKey:normalizedKey];
  self.headers[normalizedKey] = [resolvedValue copy];
  self.headerNamesByNormalizedKey[normalizedKey] = displayName;
  if (invalidate) {
    [self invalidateSerializedHeaders];
  }
  return YES;
}

- (void)setStatusCode:(NSInteger)statusCode {
  if (_statusCode == statusCode) {
    return;
  }
  _statusCode = statusCode;
  [self invalidateSerializedHeaders];
}

- (void)setFileBodyPath:(NSString *)fileBodyPath {
  if ((_fileBodyPath == nil && fileBodyPath == nil) ||
      [_fileBodyPath isEqualToString:fileBodyPath]) {
    return;
  }
  _fileBodyPath = [fileBodyPath copy];
  if ([_fileBodyPath length] == 0) {
    _fileBodyLength = 0;
    _fileBodyDevice = 0;
    _fileBodyInode = 0;
    _fileBodyMTimeSeconds = 0;
    _fileBodyMTimeNanoseconds = 0;
  } else {
    self.bodyDataReference = nil;
    if (_bodyData != nil) {
      [_bodyData setLength:0];
    }
  }
  [self invalidateSerializedHeaders];
}

- (void)setFileBodyLength:(unsigned long long)fileBodyLength {
  if (_fileBodyLength == fileBodyLength) {
    return;
  }
  _fileBodyLength = fileBodyLength;
  [self invalidateSerializedHeaders];
}

- (void)setFileBodyDevice:(unsigned long long)fileBodyDevice {
  _fileBodyDevice = fileBodyDevice;
}

- (void)setFileBodyInode:(unsigned long long)fileBodyInode {
  _fileBodyInode = fileBodyInode;
}

- (void)setFileBodyMTimeSeconds:(long long)fileBodyMTimeSeconds {
  _fileBodyMTimeSeconds = fileBodyMTimeSeconds;
}

- (void)setFileBodyMTimeNanoseconds:(long)fileBodyMTimeNanoseconds {
  _fileBodyMTimeNanoseconds = fileBodyMTimeNanoseconds;
}

- (void)setHeader:(NSString *)name value:(NSString *)value {
  (void)[self setHeaderInternal:name value:value invalidate:YES];
}

- (BOOL)appendHeader:(NSString *)name value:(NSString *)value {
  NSString *key = ALNNormalizedHeaderKey(name);
  if (ALNHeaderValueContainsForbiddenBytes(name) || !ALNHeaderNameIsValid(key) ||
      !ALNHeaderSupportsRepeatedValues(key) || ALNHeaderValueContainsForbiddenBytes(value)) {
    return NO;
  }
  if ([self headerForName:key] == nil) {
    return [self setHeaderInternal:name value:value invalidate:YES];
  }
  if (self.additionalHeaderValues == nil) {
    self.additionalHeaderValues = [NSMutableDictionary dictionary];
  }
  NSArray *existing = self.additionalHeaderValues[key] ?: @[];
  self.additionalHeaderValues[key] = [existing arrayByAddingObject:[value copy]];
  [self invalidateSerializedHeaders];
  return YES;
}

- (NSArray<NSString *> *)headerValuesForName:(NSString *)name {
  NSString *key = ALNNormalizedHeaderKey(name);
  NSString *first = [self headerForName:name];
  if (first == nil) {
    return @[];
  }
  NSArray *additional = self.additionalHeaderValues[key] ?: @[];
  return [@[ first ] arrayByAddingObjectsFromArray:additional];
}

- (void)removeHeaderForName:(NSString *)name {
  NSString *key = ALNNormalizedHeaderKey(name);
  if (key == nil || self.headers[key] == nil) {
    return;
  }
  [self.headers removeObjectForKey:key];
  [self.additionalHeaderValues removeObjectForKey:key];
  [self.headerNamesByNormalizedKey removeObjectForKey:key];
  [self.orderedHeaderKeys removeObject:key];
  [self invalidateSerializedHeaders];
}

- (void)setHeadersIfMissing:(NSDictionary<NSString *, NSString *> *)headers {
  if (![headers isKindOfClass:[NSDictionary class]] || [headers count] == 0) {
    return;
  }
  BOOL mutated = NO;
  for (id rawName in headers) {
    if (![rawName isKindOfClass:[NSString class]] || ALNHeaderValueContainsForbiddenBytes(rawName)) {
      continue;
    }
    NSString *name = [(NSString *)rawName
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalizedKey = ALNNormalizedHeaderKey(name);
    if ([normalizedKey length] == 0) {
      continue;
    }
    if ([self.headers[normalizedKey] isKindOfClass:[NSString class]]) {
      continue;
    }
    id rawValue = headers[rawName];
    NSString *value = [rawValue isKindOfClass:[NSString class]] ? rawValue : @"";
    if ([self setHeaderInternal:name value:value invalidate:NO]) {
      mutated = YES;
    }
  }
  if (mutated) {
    [self invalidateSerializedHeaders];
  }
}

- (NSString *)headerForName:(NSString *)name {
  NSString *normalizedKey = ALNNormalizedHeaderKey(name);
  if ([normalizedKey length] == 0) {
    return nil;
  }
  id value = self.headers[normalizedKey];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (void)appendData:(NSData *)data {
  if (data == nil) {
    return;
  }
  [self resetFileBodyState];
  [self materializeMutableBodyDataIfNeeded];
  [_bodyData appendData:data];
  [self invalidateSerializedHeaders];
  self.committed = YES;
}

- (void)appendText:(NSString *)text {
  if (text == nil) {
    return;
  }
  NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (data != nil) {
    [self appendData:data];
  }
}

- (void)setTextBody:(NSString *)text {
  [self resetFileBodyState];
  self.bodyDataReference = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  _bodyData = nil;
  [self invalidateSerializedHeaders];
  self.committed = YES;
  if ([self headerForName:@"Content-Type"] == nil) {
    [self setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  }
}

- (void)setDataBody:(NSData *)data contentType:(NSString *)contentType {
  [self resetFileBodyState];
  if ([data isKindOfClass:[NSMutableData class]]) {
    self.bodyDataReference = [data copy];
  } else {
    self.bodyDataReference = data ?: [NSData data];
  }
  _bodyData = nil;
  [self invalidateSerializedHeaders];
  NSString *resolvedType =
      ([contentType isKindOfClass:[NSString class]] && [contentType length] > 0)
          ? contentType
          : @"application/octet-stream";
  [self setHeader:@"Content-Type" value:resolvedType];
  self.committed = YES;
}

- (BOOL)setJSONBody:(id)object
            options:(NSJSONWritingOptions)options
              error:(NSError **)error {
  NSData *json = [ALNJSONSerialization dataWithJSONObject:object options:options error:error];
  if (json == nil) {
    return NO;
  }
  [self resetFileBodyState];
  self.bodyDataReference = json;
  _bodyData = nil;
  [self invalidateSerializedHeaders];
  self.committed = YES;
  [self setHeader:@"Content-Type" value:@"application/json; charset=utf-8"];
  return YES;
}

- (NSData *)serializedHeaderData {
  if (!self.serializedHeadersDirty && self.cachedHeaderData != nil) {
    return self.cachedHeaderData;
  }

  if (ALNResponseConsumeFaultOnce("ARLEN_FAULT_ALLOC_RESPONSE_SERIALIZE_ONCE")) {
    return nil;
  }

  if ([self headerForName:@"Content-Length"] == nil) {
    unsigned long long bodyLength = [self bodyLength];
    if ([self.fileBodyPath length] > 0) {
      bodyLength = self.fileBodyLength;
    }
    (void)[self setHeaderInternal:@"Content-Length"
                            value:[NSString stringWithFormat:@"%llu", bodyLength]
                       invalidate:NO];
  }

  if ([self headerForName:@"Content-Type"] == nil) {
    (void)[self setHeaderInternal:@"Content-Type"
                            value:@"text/plain; charset=utf-8"
                       invalidate:NO];
  }

  NSData *sharedSerialized = ALNSharedSerializedHeaderDataForResponse(self);
  if (sharedSerialized != nil) {
    self.cachedHeaderData = sharedSerialized;
    self.serializedHeadersDirty = NO;
    return sharedSerialized;
  }

  [self rebuildOrderedHeaderKeysIfNeeded];
  NSUInteger estimatedCapacity = 64 + ([self.orderedHeaderKeys count] * 32);
  NSMutableString *head = [NSMutableString stringWithCapacity:estimatedCapacity];
  [head appendString:@"HTTP/1.1 "];
  [head appendFormat:@"%ld", (long)self.statusCode];
  [head appendString:@" "];
  [head appendString:ALNStatusText(self.statusCode)];
  [head appendString:@"\r\n"];
  for (NSString *normalizedKey in self.orderedHeaderKeys) {
    NSString *value = self.headers[normalizedKey];
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *displayName = [self.headerNamesByNormalizedKey[normalizedKey] isKindOfClass:[NSString class]]
                                ? self.headerNamesByNormalizedKey[normalizedKey]
                                : normalizedKey;
    [head appendString:displayName];
    [head appendString:@": "];
    [head appendString:value];
    [head appendString:@"\r\n"];
    for (NSString *additional in self.additionalHeaderValues[normalizedKey]) {
      [head appendString:displayName];
      [head appendString:@": "];
      [head appendString:additional];
      [head appendString:@"\r\n"];
    }
  }
  [head appendString:@"\r\n"];
  NSData *serialized = [head dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  self.cachedHeaderData = serialized;
  self.serializedHeadersDirty = NO;
  return serialized;
}

- (NSData *)serializedData {
  NSMutableData *result = [NSMutableData data];
  [result appendData:[self serializedHeaderData]];
  [result appendData:[self bodyDataForTransmission]];
  return result;
}

@end
