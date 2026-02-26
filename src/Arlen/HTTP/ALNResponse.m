#import "ALNResponse.h"

#import "ALNJSONSerialization.h"

NSString *const ALNResponseErrorDomain = @"Arlen.HTTP.Response.Error";

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
    _committed = NO;
    _fileBodyPath = nil;
    _fileBodyLength = 0;
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
  [self invalidateSerializedHeaders];
}

- (void)setFileBodyLength:(unsigned long long)fileBodyLength {
  if (_fileBodyLength == fileBodyLength) {
    return;
  }
  _fileBodyLength = fileBodyLength;
  [self invalidateSerializedHeaders];
}

- (void)setHeader:(NSString *)name value:(NSString *)value {
  if ([name length] == 0) {
    return;
  }
  self.headers[name] = value ?: @"";
  [self invalidateSerializedHeaders];
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
  [self.bodyData setLength:0];
  [self invalidateSerializedHeaders];
  [self appendText:text ?: @""];
  if ([self headerForName:@"Content-Type"] == nil) {
    [self setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  }
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
  [self.bodyData setLength:0];
  [self invalidateSerializedHeaders];
  [self appendData:json];
  [self setHeader:@"Content-Type" value:@"application/json; charset=utf-8"];
  return YES;
}

- (NSData *)serializedHeaderData {
  if (!self.serializedHeadersDirty && self.cachedHeaderData != nil) {
    return self.cachedHeaderData;
  }

  if ([self headerForName:@"Content-Length"] == nil) {
    unsigned long long bodyLength = [self.bodyData length];
    if ([self.fileBodyPath length] > 0) {
      bodyLength = self.fileBodyLength;
    }
    [self setHeader:@"Content-Length"
              value:[NSString stringWithFormat:@"%llu", bodyLength]];
  }

  if ([self headerForName:@"Content-Type"] == nil) {
    [self setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  }

  NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\n",
                                                             (long)self.statusCode,
                                                             ALNStatusText(self.statusCode)];
  NSArray *keys = [[self.headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    [head appendFormat:@"%@: %@\r\n", key, self.headers[key]];
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
