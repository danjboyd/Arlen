#import "ALNRequest.h"

#import "third_party/llhttp/llhttp.h"

NSString *const ALNRequestErrorDomain = @"Arlen.HTTP.Request.Error";

static NSError *ALNRequestError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:ALNRequestErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"Request parse error"
                         }];
}

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

static void ALNSplitURI(NSString *uri, NSString **pathOut, NSString **queryOut) {
  NSString *path = [uri isKindOfClass:[NSString class]] ? uri : @"";
  NSString *query = @"";
  NSRange question = [path rangeOfString:@"?"];
  if (question.location != NSNotFound) {
    query = [path substringFromIndex:question.location + 1];
    path = [path substringToIndex:question.location];
  }
  if ([path length] == 0) {
    path = @"/";
  }

  if (pathOut != NULL) {
    *pathOut = path;
  }
  if (queryOut != NULL) {
    *queryOut = query;
  }
}

static ALNHTTPParserBackend ALNResolvedParserBackendFromEnvironment(void) {
  const char *raw = getenv("ARLEN_HTTP_PARSER_BACKEND");
  if (raw == NULL || raw[0] == '\0') {
    return ALNHTTPParserBackendLLHTTP;
  }

  NSString *value = [NSString stringWithUTF8String:raw];
  NSString *normalized = [[value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"legacy"] ||
      [normalized isEqualToString:@"manual"] ||
      [normalized isEqualToString:@"string"]) {
    return ALNHTTPParserBackendLegacy;
  }
  return ALNHTTPParserBackendLLHTTP;
}

@interface ALNLLHTTPParseState : NSObject

@property(nonatomic, strong) NSMutableData *methodData;
@property(nonatomic, strong) NSMutableData *urlData;
@property(nonatomic, strong) NSMutableData *versionData;
@property(nonatomic, strong) NSMutableData *headerFieldData;
@property(nonatomic, strong) NSMutableData *headerValueData;
@property(nonatomic, strong) NSMutableData *bodyData;
@property(nonatomic, strong) NSMutableDictionary *headers;
@property(nonatomic, copy) NSString *errorMessage;
@property(nonatomic, assign) BOOL messageComplete;

@end

@implementation ALNLLHTTPParseState

- (instancetype)init {
  self = [super init];
  if (self) {
    _methodData = [NSMutableData data];
    _urlData = [NSMutableData data];
    _versionData = [NSMutableData data];
    _headerFieldData = [NSMutableData data];
    _headerValueData = [NSMutableData data];
    _bodyData = [NSMutableData data];
    _headers = [NSMutableDictionary dictionary];
    _errorMessage = @"";
    _messageComplete = NO;
  }
  return self;
}

@end

static ALNLLHTTPParseState *ALNLLHTTPState(llhttp_t *parser) {
  if (parser == NULL || parser->data == NULL) {
    return nil;
  }
  return (__bridge ALNLLHTTPParseState *)parser->data;
}

static int ALNLLHTTPSetError(llhttp_t *parser, NSString *message) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  state.errorMessage = [message copy] ?: @"invalid request";
  llhttp_set_error_reason(parser, [state.errorMessage UTF8String]);
  return HPE_USER;
}

static int ALNLLHTTPAppendData(NSMutableData *target, const char *at, size_t length) {
  if (target == nil || at == NULL || length == 0) {
    return 0;
  }
  [target appendBytes:at length:length];
  return 0;
}

static int ALNLLHTTPFinalizeHeader(llhttp_t *parser) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }

  if ([state.headerFieldData length] == 0) {
    if ([state.headerValueData length] == 0) {
      return 0;
    }
    return ALNLLHTTPSetError(parser, @"Invalid header field");
  }

  NSString *field = [[NSString alloc] initWithData:state.headerFieldData
                                          encoding:NSUTF8StringEncoding];
  NSString *value = [[NSString alloc] initWithData:state.headerValueData
                                          encoding:NSUTF8StringEncoding];
  if (field == nil || value == nil) {
    return ALNLLHTTPSetError(parser, @"Request header is not valid UTF-8");
  }

  NSString *name = [[[field lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
  NSString *trimmedValue =
      [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] copy];
  if ([name length] == 0) {
    return ALNLLHTTPSetError(parser, @"Invalid header field");
  }

  state.headers[name] = trimmedValue ?: @"";
  [state.headerFieldData setLength:0];
  [state.headerValueData setLength:0];
  return 0;
}

static int ALNLLHTTPOnMethod(llhttp_t *parser, const char *at, size_t length) {
  return ALNLLHTTPAppendData(ALNLLHTTPState(parser).methodData, at, length);
}

static int ALNLLHTTPOnURL(llhttp_t *parser, const char *at, size_t length) {
  return ALNLLHTTPAppendData(ALNLLHTTPState(parser).urlData, at, length);
}

static int ALNLLHTTPOnVersion(llhttp_t *parser, const char *at, size_t length) {
  return ALNLLHTTPAppendData(ALNLLHTTPState(parser).versionData, at, length);
}

static int ALNLLHTTPOnHeaderField(llhttp_t *parser, const char *at, size_t length) {
  return ALNLLHTTPAppendData(ALNLLHTTPState(parser).headerFieldData, at, length);
}

static int ALNLLHTTPOnHeaderValue(llhttp_t *parser, const char *at, size_t length) {
  return ALNLLHTTPAppendData(ALNLLHTTPState(parser).headerValueData, at, length);
}

static int ALNLLHTTPOnHeaderValueComplete(llhttp_t *parser) {
  return ALNLLHTTPFinalizeHeader(parser);
}

static int ALNLLHTTPOnHeadersComplete(llhttp_t *parser) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }
  if ([state.headerFieldData length] > 0 || [state.headerValueData length] > 0) {
    return ALNLLHTTPFinalizeHeader(parser);
  }
  return 0;
}

static int ALNLLHTTPOnBody(llhttp_t *parser, const char *at, size_t length) {
  return ALNLLHTTPAppendData(ALNLLHTTPState(parser).bodyData, at, length);
}

static int ALNLLHTTPOnMessageComplete(llhttp_t *parser) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state != nil) {
    state.messageComplete = YES;
  }
  return 0;
}

static NSData *ALNNormalizedRawDataForLLHTTP(NSData *data) {
  if (data == nil || [data length] == 0) {
    return data;
  }

  NSData *lineSeparator = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSRange lineEnd = [data rangeOfData:lineSeparator
                              options:0
                                range:NSMakeRange(0, [data length])];
  if (lineEnd.location == NSNotFound || lineEnd.location == 0) {
    return data;
  }

  NSData *lineData = [data subdataWithRange:NSMakeRange(0, lineEnd.location)];
  NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
  if (line == nil || [line rangeOfString:@"HTTP/"].location != NSNotFound) {
    return data;
  }

  NSArray *parts = [line componentsSeparatedByString:@" "];
  NSMutableArray *tokens = [NSMutableArray array];
  for (NSString *part in parts) {
    if ([part length] > 0) {
      [tokens addObject:part];
    }
  }
  if ([tokens count] != 2) {
    return data;
  }

  NSString *normalizedLine = [NSString stringWithFormat:@"%@ %@ HTTP/1.1", tokens[0], tokens[1]];
  NSMutableData *normalized = [NSMutableData data];
  [normalized appendData:[normalizedLine dataUsingEncoding:NSUTF8StringEncoding]];
  [normalized appendData:lineSeparator];

  NSUInteger remainderOffset = lineEnd.location + lineEnd.length;
  if (remainderOffset < [data length]) {
    [normalized appendData:[data subdataWithRange:NSMakeRange(remainderOffset,
                                                              [data length] - remainderOffset)]];
  }
  return normalized;
}

static ALNRequest *ALNRequestFromRawDataLegacy(NSData *data, NSError **error) {
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
      *error = ALNRequestError(1, @"Request header is not valid UTF-8");
    }
    return nil;
  }

  NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
  if ([lines count] == 0) {
    if (error != NULL) {
      *error = ALNRequestError(2, @"Missing request line");
    }
    return nil;
  }

  NSString *requestLine = lines[0];
  NSArray *parts = [requestLine componentsSeparatedByString:@" "];
  if ([parts count] < 2) {
    if (error != NULL) {
      *error = ALNRequestError(3, @"Invalid request line");
    }
    return nil;
  }

  NSString *method = parts[0];
  NSString *uri = parts[1];
  NSString *httpVersion = ([parts count] >= 3) ? parts[2] : @"HTTP/1.1";
  if (![httpVersion isKindOfClass:[NSString class]] || [httpVersion length] == 0) {
    httpVersion = @"HTTP/1.1";
  }

  NSString *path = nil;
  NSString *query = nil;
  ALNSplitURI(uri, &path, &query);

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
    NSString *name = [[line substringToIndex:colon.location] lowercaseString];
    NSString *value = [[line substringFromIndex:colon.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    headers[name] = value;
  }

  return [[ALNRequest alloc] initWithMethod:method
                                       path:path
                                queryString:query
                                httpVersion:httpVersion
                                    headers:headers
                                       body:body];
}

static ALNRequest *ALNRequestFromRawDataLLHTTP(NSData *data, NSError **error) {
  if (data == nil || [data length] == 0) {
    if (error != NULL) {
      *error = ALNRequestError(2, @"Missing request line");
    }
    return nil;
  }

  NSData *normalizedData = ALNNormalizedRawDataForLLHTTP(data);
  ALNLLHTTPParseState *state = [[ALNLLHTTPParseState alloc] init];

  llhttp_settings_t settings;
  llhttp_settings_init(&settings);
  settings.on_method = ALNLLHTTPOnMethod;
  settings.on_url = ALNLLHTTPOnURL;
  settings.on_version = ALNLLHTTPOnVersion;
  settings.on_header_field = ALNLLHTTPOnHeaderField;
  settings.on_header_value = ALNLLHTTPOnHeaderValue;
  settings.on_header_value_complete = ALNLLHTTPOnHeaderValueComplete;
  settings.on_headers_complete = ALNLLHTTPOnHeadersComplete;
  settings.on_body = ALNLLHTTPOnBody;
  settings.on_message_complete = ALNLLHTTPOnMessageComplete;

  llhttp_t parser;
  llhttp_init(&parser, HTTP_REQUEST, &settings);
  parser.data = (__bridge void *)state;

  const char *bytes = (const char *)[normalizedData bytes];
  size_t length = (size_t)[normalizedData length];
  llhttp_errno_t parseError = llhttp_execute(&parser, bytes, length);
  BOOL pausedForUpgrade = (parseError == HPE_PAUSED_UPGRADE);
  if (pausedForUpgrade) {
    llhttp_resume_after_upgrade(&parser);
    parseError = HPE_OK;
  }
  if (parseError == HPE_OK && !pausedForUpgrade) {
    parseError = llhttp_finish(&parser);
  }

  if (parseError != HPE_OK) {
    NSInteger code = 3;
    NSString *message = state.errorMessage;
    if ([message length] == 0) {
      const char *reason = llhttp_get_error_reason(&parser);
      if (reason != NULL && reason[0] != '\0') {
        message = [NSString stringWithUTF8String:reason] ?: @"Invalid request line";
      } else {
        const char *name = llhttp_errno_name(parseError);
        message = [NSString stringWithFormat:@"HTTP parse error (%s)", name != NULL ? name : "unknown"];
      }
    }
    if ([message containsString:@"UTF-8"]) {
      code = 1;
    }
    if (error != NULL) {
      *error = ALNRequestError(code, message);
    }
    return nil;
  }

  if (!state.messageComplete) {
    if (error != NULL) {
      *error = ALNRequestError(3, @"Invalid request line");
    }
    return nil;
  }

  NSString *method = [[NSString alloc] initWithData:state.methodData encoding:NSUTF8StringEncoding];
  NSString *uri = [[NSString alloc] initWithData:state.urlData encoding:NSUTF8StringEncoding];
  NSString *version = [[NSString alloc] initWithData:state.versionData encoding:NSUTF8StringEncoding];

  if (method == nil || uri == nil || (version == nil && [state.versionData length] > 0)) {
    if (error != NULL) {
      *error = ALNRequestError(1, @"Request header is not valid UTF-8");
    }
    return nil;
  }
  if ([method length] == 0 || [uri length] == 0) {
    if (error != NULL) {
      *error = ALNRequestError(3, @"Invalid request line");
    }
    return nil;
  }

  NSString *httpVersion = ([version length] > 0)
                              ? [NSString stringWithFormat:@"HTTP/%@", version]
                              : @"HTTP/1.1";

  NSString *path = nil;
  NSString *query = nil;
  ALNSplitURI(uri, &path, &query);

  return [[ALNRequest alloc] initWithMethod:method
                                       path:path
                                queryString:query
                                httpVersion:httpVersion
                                    headers:state.headers
                                       body:state.bodyData];
}

@interface ALNRequest ()

@property(nonatomic, copy, readwrite) NSString *method;
@property(nonatomic, copy, readwrite) NSString *path;
@property(nonatomic, copy, readwrite) NSString *queryString;
@property(nonatomic, copy, readwrite) NSString *httpVersion;
@property(nonatomic, copy, readwrite) NSDictionary *headers;
@property(nonatomic, strong, readwrite) NSData *body;
@property(nonatomic, copy, readwrite) NSDictionary *queryParams;
@property(nonatomic, copy, readwrite) NSDictionary *cookies;

@end

@implementation ALNRequest

- (instancetype)initWithMethod:(NSString *)method
                          path:(NSString *)path
                   queryString:(NSString *)queryString
                   httpVersion:(NSString *)httpVersion
                       headers:(NSDictionary *)headers
                          body:(NSData *)body {
  self = [super init];
  if (self) {
    _method = [[method uppercaseString] copy];
    _path = [path copy];
    _queryString = [queryString copy] ?: @"";
    _httpVersion = [httpVersion copy] ?: @"HTTP/1.1";
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

- (instancetype)initWithMethod:(NSString *)method
                          path:(NSString *)path
                   queryString:(NSString *)queryString
                       headers:(NSDictionary *)headers
                          body:(NSData *)body {
  return [self initWithMethod:method
                         path:path
                  queryString:queryString
                  httpVersion:@"HTTP/1.1"
                      headers:headers
                         body:body];
}

+ (ALNHTTPParserBackend)resolvedParserBackend {
  return ALNResolvedParserBackendFromEnvironment();
}

+ (NSString *)parserBackendNameForBackend:(ALNHTTPParserBackend)backend {
  if (backend == ALNHTTPParserBackendLegacy) {
    return @"legacy";
  }
  return @"llhttp";
}

+ (NSString *)resolvedParserBackendName {
  return [self parserBackendNameForBackend:[self resolvedParserBackend]];
}

+ (NSString *)llhttpVersion {
  return [NSString stringWithFormat:@"%d.%d.%d",
                                    LLHTTP_VERSION_MAJOR,
                                    LLHTTP_VERSION_MINOR,
                                    LLHTTP_VERSION_PATCH];
}

+ (ALNRequest *)requestFromRawData:(NSData *)data error:(NSError **)error {
  return [self requestFromRawData:data backend:[self resolvedParserBackend] error:error];
}

+ (ALNRequest *)requestFromRawData:(NSData *)data
                           backend:(ALNHTTPParserBackend)backend
                             error:(NSError **)error {
  if (backend == ALNHTTPParserBackendLegacy) {
    return ALNRequestFromRawDataLegacy(data ?: [NSData data], error);
  }
  return ALNRequestFromRawDataLLHTTP(data ?: [NSData data], error);
}

@end
