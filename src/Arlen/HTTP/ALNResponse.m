#import "ALNResponse.h"

#import "ALNJSONSerialization.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>

NSString *const ALNResponseErrorDomain = @"Arlen.HTTP.Response.Error";

static NSLock *gALNResponseFaultInjectionLock = nil;
static NSMutableSet *gALNResponseFaultInjectionConsumed = nil;

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

static void ALNEnsureResponseFaultInjectionState(void) {
  if (gALNResponseFaultInjectionLock != nil && gALNResponseFaultInjectionConsumed != nil) {
    return;
  }
  @synchronized([NSProcessInfo processInfo]) {
    if (gALNResponseFaultInjectionLock == nil) {
      gALNResponseFaultInjectionLock = [[NSLock alloc] init];
    }
    if (gALNResponseFaultInjectionConsumed == nil) {
      gALNResponseFaultInjectionConsumed = [NSMutableSet set];
    }
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

static NSString *ALNStatusText(NSInteger statusCode) {
  switch (statusCode) {
  case 101:
    return @"Switching Protocols";
  case 200:
    return @"OK";
  case 201:
    return @"Created";
  case 204:
    return @"No Content";
  case 301:
    return @"Moved Permanently";
  case 302:
    return @"Found";
  case 304:
    return @"Not Modified";
  case 400:
    return @"Bad Request";
  case 403:
    return @"Forbidden";
  case 404:
    return @"Not Found";
  case 405:
    return @"Method Not Allowed";
  case 408:
    return @"Request Timeout";
  case 429:
    return @"Too Many Requests";
  case 413:
    return @"Payload Too Large";
  case 431:
    return @"Request Header Fields Too Large";
  case 503:
    return @"Service Unavailable";
  case 422:
    return @"Unprocessable Content";
  case 500:
    return @"Internal Server Error";
  default:
    return @"OK";
  }
}

@interface ALNResponse ()

@property(nonatomic, strong, readwrite) NSMutableDictionary *headers;
@property(nonatomic, strong, readwrite) NSMutableData *bodyData;
@property(nonatomic, strong) NSMutableArray *orderedHeaderKeys;
@property(nonatomic, strong) NSData *cachedHeaderData;
@property(nonatomic, assign) BOOL serializedHeadersDirty;

@end

@implementation ALNResponse

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusCode = 200;
    _headers = [NSMutableDictionary dictionary];
    _bodyData = [NSMutableData data];
    _orderedHeaderKeys = [NSMutableArray array];
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

- (void)rebuildOrderedHeaderKeysIfNeeded {
  if ([self.orderedHeaderKeys count] == [self.headers count]) {
    return;
  }
  [self.orderedHeaderKeys removeAllObjects];
  NSArray *sorted = [[self.headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  [self.orderedHeaderKeys addObjectsFromArray:sorted];
}

- (void)insertOrderedHeaderKeyIfNeeded:(NSString *)name {
  if ([name length] == 0) {
    return;
  }
  if ([self.orderedHeaderKeys containsObject:name]) {
    return;
  }
  NSUInteger insertion = ALNInsertionIndexForSortedHeaderKeys(self.orderedHeaderKeys, name);
  [self.orderedHeaderKeys insertObject:name atIndex:insertion];
}

- (BOOL)setHeaderInternal:(NSString *)name
                    value:(NSString *)value
               invalidate:(BOOL)invalidate {
  if ([name length] == 0) {
    return NO;
  }
  NSString *resolvedValue = value ?: @"";
  NSString *currentValue = [self.headers[name] isKindOfClass:[NSString class]] ? self.headers[name] : nil;
  if (currentValue != nil && [currentValue isEqualToString:resolvedValue]) {
    return NO;
  }
  if (currentValue == nil) {
    [self insertOrderedHeaderKeyIfNeeded:name];
  }
  self.headers[name] = resolvedValue;
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

- (void)setHeadersIfMissing:(NSDictionary<NSString *, NSString *> *)headers {
  if (![headers isKindOfClass:[NSDictionary class]] || [headers count] == 0) {
    return;
  }
  BOOL mutated = NO;
  for (id rawName in headers) {
    if (![rawName isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *name = (NSString *)rawName;
    if ([name length] == 0) {
      continue;
    }
    if ([self.headers[name] isKindOfClass:[NSString class]]) {
      continue;
    }
    id rawValue = headers[name];
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
  return self.headers[name];
}

- (void)appendData:(NSData *)data {
  if (data == nil) {
    return;
  }
  self.fileBodyPath = nil;
  self.fileBodyLength = 0;
  self.fileBodyDevice = 0;
  self.fileBodyInode = 0;
  self.fileBodyMTimeSeconds = 0;
  self.fileBodyMTimeNanoseconds = 0;
  [self.bodyData appendData:data];
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
  self.fileBodyPath = nil;
  self.fileBodyLength = 0;
  self.fileBodyDevice = 0;
  self.fileBodyInode = 0;
  self.fileBodyMTimeSeconds = 0;
  self.fileBodyMTimeNanoseconds = 0;
  [self.bodyData setLength:0];
  [self invalidateSerializedHeaders];
  [self appendText:text ?: @""];
  if ([self headerForName:@"Content-Type"] == nil) {
    [self setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  }
}

- (void)setDataBody:(NSData *)data contentType:(NSString *)contentType {
  self.fileBodyPath = nil;
  self.fileBodyLength = 0;
  self.fileBodyDevice = 0;
  self.fileBodyInode = 0;
  self.fileBodyMTimeSeconds = 0;
  self.fileBodyMTimeNanoseconds = 0;
  [self.bodyData setLength:0];
  [self invalidateSerializedHeaders];
  if (data != nil && [data length] > 0) {
    [self.bodyData appendData:data];
  }
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
  self.fileBodyPath = nil;
  self.fileBodyLength = 0;
  self.fileBodyDevice = 0;
  self.fileBodyInode = 0;
  self.fileBodyMTimeSeconds = 0;
  self.fileBodyMTimeNanoseconds = 0;
  [self.bodyData setLength:0];
  [self invalidateSerializedHeaders];
  if ([json length] > 0) {
    [self.bodyData appendData:json];
  }
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

  if (![self.headers[@"Content-Length"] isKindOfClass:[NSString class]]) {
    unsigned long long bodyLength = [self.bodyData length];
    if ([self.fileBodyPath length] > 0) {
      bodyLength = self.fileBodyLength;
    }
    (void)[self setHeaderInternal:@"Content-Length"
                            value:[NSString stringWithFormat:@"%llu", bodyLength]
                       invalidate:NO];
  }

  if (![self.headers[@"Content-Type"] isKindOfClass:[NSString class]]) {
    (void)[self setHeaderInternal:@"Content-Type"
                            value:@"text/plain; charset=utf-8"
                       invalidate:NO];
  }

  [self rebuildOrderedHeaderKeysIfNeeded];
  NSUInteger estimatedCapacity = 64 + ([self.orderedHeaderKeys count] * 32);
  NSMutableString *head = [NSMutableString stringWithCapacity:estimatedCapacity];
  [head appendString:@"HTTP/1.1 "];
  [head appendFormat:@"%ld", (long)self.statusCode];
  [head appendString:@" "];
  [head appendString:ALNStatusText(self.statusCode)];
  [head appendString:@"\r\n"];
  for (NSString *key in self.orderedHeaderKeys) {
    NSString *value = self.headers[key];
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    [head appendString:key];
    [head appendString:@": "];
    [head appendString:value];
    [head appendString:@"\r\n"];
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
  [result appendData:self.bodyData];
  return result;
}

@end
