#import "ALNRequest.h"

NSString *const ALNRequestErrorDomain = @"Arlen.HTTP.Request.Error";

static NSString *ALNURLDecode(NSString *value) {
  NSString *plusNormalized = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
  NSString *decoded = [plusNormalized stringByRemovingPercentEncoding];
  return decoded ?: plusNormalized;
}

static NSDictionary *ALNParseQueryString(NSString *query) {
  if ([query length] == 0) {
    return @{};
  }

  NSMutableDictionary *params = [NSMutableDictionary dictionary];
  NSArray *pairs = [query componentsSeparatedByString:@"&"];
  for (NSString *pair in pairs) {
    if ([pair length] == 0) {
      continue;
    }
    NSRange equals = [pair rangeOfString:@"="];
    if (equals.location == NSNotFound) {
      params[ALNURLDecode(pair)] = @"";
      continue;
    }
    NSString *key = [pair substringToIndex:equals.location];
    NSString *value = [pair substringFromIndex:equals.location + 1];
    params[ALNURLDecode(key)] = ALNURLDecode(value);
  }
  return params;
}

static NSDictionary *ALNParseCookies(NSString *cookieHeader) {
  if ([cookieHeader length] == 0) {
    return @{};
  }

  NSMutableDictionary *cookies = [NSMutableDictionary dictionary];
  NSArray *parts = [cookieHeader componentsSeparatedByString:@";"];
  for (NSString *part in parts) {
    NSString *trimmed =
        [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) {
      continue;
    }
    NSRange equals = [trimmed rangeOfString:@"="];
    if (equals.location == NSNotFound || equals.location == 0) {
      continue;
    }
    NSString *name = [trimmed substringToIndex:equals.location];
    NSString *value = [trimmed substringFromIndex:equals.location + 1];
    cookies[name] = value ?: @"";
  }
  return cookies;
}

@interface ALNRequest ()

@property(nonatomic, copy, readwrite) NSString *method;
@property(nonatomic, copy, readwrite) NSString *path;
@property(nonatomic, copy, readwrite) NSString *queryString;
@property(nonatomic, copy, readwrite) NSDictionary *headers;
@property(nonatomic, strong, readwrite) NSData *body;
@property(nonatomic, copy, readwrite) NSDictionary *queryParams;
@property(nonatomic, copy, readwrite) NSDictionary *cookies;

@end

@implementation ALNRequest

- (instancetype)initWithMethod:(NSString *)method
                          path:(NSString *)path
                   queryString:(NSString *)queryString
                       headers:(NSDictionary *)headers
                          body:(NSData *)body {
  self = [super init];
  if (self) {
    _method = [[method uppercaseString] copy];
    _path = [path copy];
    _queryString = [queryString copy] ?: @"";
    _headers = [NSDictionary dictionaryWithDictionary:headers ?: @{}];
    _body = body ?: [NSData data];
    _queryParams = ALNParseQueryString(_queryString);
    _cookies = ALNParseCookies(_headers[@"cookie"]);
    _routeParams = @{};
    _remoteAddress = @"";
    _effectiveRemoteAddress = @"";
    _scheme = @"http";
    _parseDurationMilliseconds = 0.0;
    _responseWriteDurationMilliseconds = 0.0;
  }
  return self;
}

+ (ALNRequest *)requestFromRawData:(NSData *)data error:(NSError **)error {
  NSData *separatorData = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSRange separator = [data rangeOfData:separatorData
                                options:0
                                  range:NSMakeRange(0, [data length])];
  NSData *headData = nil;
  NSData *body = nil;
  if (separator.location == NSNotFound) {
    headData = data;
    body = [NSData data];
  } else {
    headData = [data subdataWithRange:NSMakeRange(0, separator.location)];
    NSUInteger bodyOffset = separator.location + separator.length;
    if (bodyOffset < [data length]) {
      body = [data subdataWithRange:NSMakeRange(bodyOffset, [data length] - bodyOffset)];
    } else {
      body = [NSData data];
    }
  }

  NSString *head = [[NSString alloc] initWithData:headData encoding:NSUTF8StringEncoding];
  if (head == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNRequestErrorDomain
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Request header is not valid UTF-8"
                               }];
    }
    return nil;
  }

  NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
  if ([lines count] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNRequestErrorDomain
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Missing request line"
                               }];
    }
    return nil;
  }

  NSString *requestLine = lines[0];
  NSArray *parts = [requestLine componentsSeparatedByString:@" "];
  if ([parts count] < 2) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNRequestErrorDomain
                                   code:3
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Invalid request line"
                               }];
    }
    return nil;
  }

  NSString *method = parts[0];
  NSString *uri = parts[1];
  NSString *path = uri;
  NSString *query = @"";
  NSRange q = [uri rangeOfString:@"?"];
  if (q.location != NSNotFound) {
    path = [uri substringToIndex:q.location];
    query = [uri substringFromIndex:q.location + 1];
  }
  if ([path length] == 0) {
    path = @"/";
  }

  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  for (NSUInteger idx = 1; idx < [lines count]; idx++) {
    NSString *line = lines[idx];
    if ([line length] == 0) {
      continue;
    }
    NSRange colon = [line rangeOfString:@":"];
    if (colon.location == NSNotFound) {
      continue;
    }
    NSString *name =
        [[line substringToIndex:colon.location] lowercaseString];
    NSString *value = [[line substringFromIndex:colon.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    headers[name] = value;
  }

  return [[ALNRequest alloc] initWithMethod:method
                                      path:path
                               queryString:query
                                   headers:headers
                                      body:body];
}

@end
