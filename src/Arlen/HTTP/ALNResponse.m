#import "ALNResponse.h"

NSString *const ALNResponseErrorDomain = @"Arlen.HTTP.Response.Error";

static NSString *ALNStatusText(NSInteger statusCode) {
  switch (statusCode) {
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
  case 500:
    return @"Internal Server Error";
  default:
    return @"OK";
  }
}

@interface ALNResponse ()

@property(nonatomic, strong, readwrite) NSMutableDictionary *headers;
@property(nonatomic, strong, readwrite) NSMutableData *bodyData;

@end

@implementation ALNResponse

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusCode = 200;
    _headers = [NSMutableDictionary dictionary];
    _bodyData = [NSMutableData data];
    _committed = NO;
    [self setHeader:@"Connection" value:@"close"];
    [self setHeader:@"Server" value:@"Arlen"];
  }
  return self;
}

- (void)setHeader:(NSString *)name value:(NSString *)value {
  if ([name length] == 0) {
    return;
  }
  self.headers[name] = value ?: @"";
}

- (NSString *)headerForName:(NSString *)name {
  return self.headers[name];
}

- (void)appendData:(NSData *)data {
  if (data == nil) {
    return;
  }
  [self.bodyData appendData:data];
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
  [self.bodyData setLength:0];
  [self appendText:text ?: @""];
  if ([self headerForName:@"Content-Type"] == nil) {
    [self setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  }
}

- (BOOL)setJSONBody:(id)object
            options:(NSJSONWritingOptions)options
              error:(NSError **)error {
  NSData *json = [NSJSONSerialization dataWithJSONObject:object options:options error:error];
  if (json == nil) {
    return NO;
  }
  [self.bodyData setLength:0];
  [self appendData:json];
  [self setHeader:@"Content-Type" value:@"application/json; charset=utf-8"];
  return YES;
}

- (NSData *)serializedData {
  if ([self headerForName:@"Content-Length"] == nil) {
    [self setHeader:@"Content-Length"
              value:[NSString stringWithFormat:@"%lu",
                                             (unsigned long)[self.bodyData length]]];
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

  NSMutableData *result = [NSMutableData data];
  [result appendData:[head dataUsingEncoding:NSUTF8StringEncoding]];
  [result appendData:self.bodyData];
  return result;
}

@end
