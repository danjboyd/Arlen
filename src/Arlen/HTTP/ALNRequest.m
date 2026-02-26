#import "ALNRequest.h"

#if ARLEN_ENABLE_LLHTTP
#import "third_party/llhttp/llhttp.h"
#include <pthread.h>
#endif

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
#if ARLEN_ENABLE_LLHTTP
    return ALNHTTPParserBackendLLHTTP;
#else
    return ALNHTTPParserBackendLegacy;
#endif
  }

  NSString *value = [NSString stringWithUTF8String:raw];
  NSString *normalized = [[value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"legacy"] ||
      [normalized isEqualToString:@"manual"] ||
      [normalized isEqualToString:@"string"]) {
    return ALNHTTPParserBackendLegacy;
  }
#if ARLEN_ENABLE_LLHTTP
  return ALNHTTPParserBackendLLHTTP;
#else
  return ALNHTTPParserBackendLegacy;
#endif
}

#if ARLEN_ENABLE_LLHTTP
@interface ALNLLHTTPParseState : NSObject {
@public
const char *_urlStart;
size_t _urlLength;
NSMutableData *_urlData;

const char *_headerFieldStart;
size_t _headerFieldLength;
NSMutableData *_headerFieldData;

const char *_headerValueStart;
size_t _headerValueLength;
NSMutableData *_headerValueData;

const char *_bodyStart;
size_t _bodyLength;
NSMutableData *_bodyData;

NSMutableDictionary *_headers;
NSString *_errorMessage;
BOOL _messageComplete;
}

@end

@implementation ALNLLHTTPParseState

- (instancetype)init {
  self = [super init];
  if (self) {
    _urlStart = NULL;
    _urlLength = 0;
    _urlData = nil;
    _headerFieldStart = NULL;
    _headerFieldLength = 0;
    _headerFieldData = nil;
    _headerValueStart = NULL;
    _headerValueLength = 0;
    _headerValueData = nil;
    _bodyStart = NULL;
    _bodyLength = 0;
    _bodyData = nil;
    _headers = [NSMutableDictionary dictionary];
    _errorMessage = @"";
    _messageComplete = NO;
  }
  return self;
}

@end

static llhttp_settings_t gALNLLHTTPSettings;
static pthread_once_t gALNLLHTTPSettingsOnce = PTHREAD_ONCE_INIT;

static ALNLLHTTPParseState *ALNLLHTTPState(llhttp_t *parser) {
  if (parser == NULL || parser->data == NULL) {
    return nil;
  }
  return (__bridge ALNLLHTTPParseState *)parser->data;
}

static size_t ALNLLHTTPSpanLength(const char *start, size_t length, NSData *data) {
  (void)start;
  if (data != nil) {
    return [data length];
  }
  return length;
}

static void ALNLLHTTPResetSpan(const char **start,
                               size_t *length,
                               NSMutableData *__strong *buffer) {
  if (start != NULL) {
    *start = NULL;
  }
  if (length != NULL) {
    *length = 0;
  }
  if (buffer != NULL) {
    *buffer = nil;
  }
}

static int ALNLLHTTPAppendSpan(const char **start,
                               size_t *length,
                               NSMutableData *__strong *buffer,
                               const char *at,
                               size_t segmentLength) {
  if (start == NULL || length == NULL || buffer == NULL || at == NULL || segmentLength == 0) {
    return 0;
  }

  if (*buffer != nil) {
    [*buffer appendBytes:at length:segmentLength];
    return 0;
  }

  if (*start == NULL) {
    *start = at;
    *length = segmentLength;
    return 0;
  }

  if ((*start + *length) == at) {
    *length += segmentLength;
    return 0;
  }

  NSMutableData *combined = [[NSMutableData alloc] initWithCapacity:(*length + segmentLength)];
  [combined appendBytes:*start length:*length];
  [combined appendBytes:at length:segmentLength];
  *buffer = combined;
  *start = NULL;
  *length = 0;
  return 0;
}

static NSString *ALNLLHTTPStringFromSpan(const char *start, size_t length, NSData *data) {
  if (data != nil) {
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  }
  if (start == NULL || length == 0) {
    return @"";
  }
  return [[NSString alloc] initWithBytes:start length:length encoding:NSUTF8StringEncoding];
}

static NSData *ALNLLHTTPCopyDataFromSpan(const char *start, size_t length, NSData *data) {
  if (data != nil) {
    return [data copy];
  }
  if (start == NULL || length == 0) {
    return [NSData data];
  }
  return [NSData dataWithBytes:start length:length];
}

static int ALNLLHTTPSetError(llhttp_t *parser, NSString *message) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state != nil) {
    state->_errorMessage = [message copy] ?: @"invalid request";
    llhttp_set_error_reason(parser, [state->_errorMessage UTF8String]);
  } else {
    llhttp_set_error_reason(parser, "invalid request");
  }
  return HPE_USER;
}

static int ALNLLHTTPFinalizeHeader(llhttp_t *parser) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }

  size_t fieldLength =
      ALNLLHTTPSpanLength(state->_headerFieldStart, state->_headerFieldLength, state->_headerFieldData);
  size_t valueLength =
      ALNLLHTTPSpanLength(state->_headerValueStart, state->_headerValueLength, state->_headerValueData);
  if (fieldLength == 0) {
    if (valueLength == 0) {
      return 0;
    }
    return ALNLLHTTPSetError(parser, @"Invalid header field");
  }

  NSString *field =
      ALNLLHTTPStringFromSpan(state->_headerFieldStart, state->_headerFieldLength, state->_headerFieldData);
  NSString *value =
      ALNLLHTTPStringFromSpan(state->_headerValueStart, state->_headerValueLength, state->_headerValueData);
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

  state->_headers[name] = trimmedValue ?: @"";
  ALNLLHTTPResetSpan(&state->_headerFieldStart, &state->_headerFieldLength, &state->_headerFieldData);
  ALNLLHTTPResetSpan(&state->_headerValueStart, &state->_headerValueLength, &state->_headerValueData);
  return 0;
}

static int ALNLLHTTPOnURL(llhttp_t *parser, const char *at, size_t length) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }
  return ALNLLHTTPAppendSpan(&state->_urlStart, &state->_urlLength, &state->_urlData, at, length);
}

static int ALNLLHTTPOnHeaderField(llhttp_t *parser, const char *at, size_t length) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }
  return ALNLLHTTPAppendSpan(&state->_headerFieldStart,
                             &state->_headerFieldLength,
                             &state->_headerFieldData,
                             at,
                             length);
}

static int ALNLLHTTPOnHeaderValue(llhttp_t *parser, const char *at, size_t length) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }
  return ALNLLHTTPAppendSpan(&state->_headerValueStart,
                             &state->_headerValueLength,
                             &state->_headerValueData,
                             at,
                             length);
}

static int ALNLLHTTPOnHeaderValueComplete(llhttp_t *parser) {
  return ALNLLHTTPFinalizeHeader(parser);
}

static int ALNLLHTTPOnHeadersComplete(llhttp_t *parser) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }
  if (ALNLLHTTPSpanLength(state->_headerFieldStart, state->_headerFieldLength, state->_headerFieldData) > 0 ||
      ALNLLHTTPSpanLength(state->_headerValueStart, state->_headerValueLength, state->_headerValueData) > 0) {
    return ALNLLHTTPFinalizeHeader(parser);
  }
  return 0;
}

static int ALNLLHTTPOnBody(llhttp_t *parser, const char *at, size_t length) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state == nil) {
    return ALNLLHTTPSetError(parser, @"invalid parser state");
  }
  return ALNLLHTTPAppendSpan(&state->_bodyStart, &state->_bodyLength, &state->_bodyData, at, length);
}

static int ALNLLHTTPOnMessageComplete(llhttp_t *parser) {
  ALNLLHTTPParseState *state = ALNLLHTTPState(parser);
  if (state != nil) {
    state->_messageComplete = YES;
  }
  return 0;
}

static void ALNLLHTTPInitializeSharedSettings(void) {
  llhttp_settings_init(&gALNLLHTTPSettings);
  gALNLLHTTPSettings.on_url = ALNLLHTTPOnURL;
  gALNLLHTTPSettings.on_header_field = ALNLLHTTPOnHeaderField;
  gALNLLHTTPSettings.on_header_value = ALNLLHTTPOnHeaderValue;
  gALNLLHTTPSettings.on_header_value_complete = ALNLLHTTPOnHeaderValueComplete;
  gALNLLHTTPSettings.on_headers_complete = ALNLLHTTPOnHeadersComplete;
  gALNLLHTTPSettings.on_body = ALNLLHTTPOnBody;
  gALNLLHTTPSettings.on_message_complete = ALNLLHTTPOnMessageComplete;
}

static const llhttp_settings_t *ALNLLHTTPSharedSettings(void) {
  pthread_once(&gALNLLHTTPSettingsOnce, ALNLLHTTPInitializeSharedSettings);
  return &gALNLLHTTPSettings;
}

static BOOL ALNRequestLineNeedsHTTPVersionNormalization(NSData *data) {
  if (data == nil || [data length] == 0) {
    return NO;
  }

  NSData *lineSeparator = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSRange lineEnd = [data rangeOfData:lineSeparator options:0 range:NSMakeRange(0, [data length])];
  if (lineEnd.location == NSNotFound || lineEnd.location == 0) {
    return NO;
  }

  NSData *lineData = [data subdataWithRange:NSMakeRange(0, lineEnd.location)];
  NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
  if (line == nil) {
    return NO;
  }
  if ([line rangeOfString:@"HTTP/"].location != NSNotFound) {
    return NO;
  }

  NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSUInteger tokenCount = 0;
  for (NSString *part in parts) {
    if ([part length] > 0) {
      tokenCount += 1;
    }
  }
  return tokenCount == 2;
}

static NSData *ALNNormalizedRawDataForLLHTTP(NSData *data) {
  if (!ALNRequestLineNeedsHTTPVersionNormalization(data)) {
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
  if (line == nil) {
    return data;
  }

  NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
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
#endif

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

#if ARLEN_ENABLE_LLHTTP
static ALNRequest *ALNRequestFromRawDataLLHTTPOnce(NSData *data, NSError **error) {
  if (data == nil || [data length] == 0) {
    if (error != NULL) {
      *error = ALNRequestError(2, @"Missing request line");
    }
    return nil;
  }

  ALNLLHTTPParseState *state = [[ALNLLHTTPParseState alloc] init];

  llhttp_t parser;
  llhttp_init(&parser, HTTP_REQUEST, ALNLLHTTPSharedSettings());
  parser.data = (__bridge void *)state;

  const char *bytes = (const char *)[data bytes];
  size_t length = (size_t)[data length];
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
    NSString *message = state->_errorMessage;
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

  if (!state->_messageComplete) {
    if (error != NULL) {
      *error = ALNRequestError(3, @"Invalid request line");
    }
    return nil;
  }

  uint8_t parsedMethod = llhttp_get_method(&parser);
  const char *methodCString = llhttp_method_name((llhttp_method_t)parsedMethod);
  NSString *method = (methodCString != NULL) ? [NSString stringWithUTF8String:methodCString] : nil;
  NSString *uri = ALNLLHTTPStringFromSpan(state->_urlStart, state->_urlLength, state->_urlData);
  if (method == nil || uri == nil) {
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

  uint8_t major = llhttp_get_http_major(&parser);
  uint8_t minor = llhttp_get_http_minor(&parser);
  BOOL missingVersionRequestLine = NO;
  if (major == 0 && minor == 9) {
    // Preserve legacy compatibility for request lines that omit the HTTP version token.
    missingVersionRequestLine = ALNRequestLineNeedsHTTPVersionNormalization(data);
  }
  NSString *httpVersion = (missingVersionRequestLine
                               ? @"HTTP/1.1"
                               : ((major == 0 && minor == 0)
                                      ? @"HTTP/1.1"
                                      : [NSString stringWithFormat:@"HTTP/%u.%u", major, minor]));

  NSString *path = nil;
  NSString *query = nil;
  ALNSplitURI(uri, &path, &query);

  NSData *body = ALNLLHTTPCopyDataFromSpan(state->_bodyStart, state->_bodyLength, state->_bodyData);
  return [[ALNRequest alloc] initWithMethod:method
                                       path:path
                                queryString:query
                                httpVersion:httpVersion
                                    headers:state->_headers
                                       body:body];
}

static ALNRequest *ALNRequestFromRawDataLLHTTP(NSData *data, NSError **error) {
  NSError *parseError = nil;
  ALNRequest *request = ALNRequestFromRawDataLLHTTPOnce(data, &parseError);
  if (request != nil) {
    return request;
  }

  if (ALNRequestLineNeedsHTTPVersionNormalization(data)) {
    NSData *normalizedData = ALNNormalizedRawDataForLLHTTP(data);
    if (normalizedData != data) {
      NSError *normalizedError = nil;
      request = ALNRequestFromRawDataLLHTTPOnce(normalizedData, &normalizedError);
      if (request != nil) {
        return request;
      }
      if (normalizedError != nil) {
        parseError = normalizedError;
      }
    }
  }

  if (error != NULL) {
    *error = parseError ?: ALNRequestError(3, @"Invalid request line");
  }
  return nil;
}
#endif

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

- (NSDictionary *)queryParams {
  if (_queryParams != nil) {
    return _queryParams;
  }

  @synchronized(self) {
    if (_queryParams == nil) {
      _queryParams = [ALNParseQueryString(_queryString) copy];
    }
    return _queryParams;
  }
}

- (NSDictionary *)cookies {
  if (_cookies != nil) {
    return _cookies;
  }

  @synchronized(self) {
    if (_cookies == nil) {
      _cookies = [ALNParseCookies(_headers[@"cookie"]) copy];
    }
    return _cookies;
  }
}

+ (ALNHTTPParserBackend)resolvedParserBackend {
  return ALNResolvedParserBackendFromEnvironment();
}

+ (NSString *)parserBackendNameForBackend:(ALNHTTPParserBackend)backend {
  if (backend == ALNHTTPParserBackendLegacy) {
    return @"legacy";
  }
#if ARLEN_ENABLE_LLHTTP
  return @"llhttp";
#else
  return @"legacy";
#endif
}

+ (NSString *)resolvedParserBackendName {
  return [self parserBackendNameForBackend:[self resolvedParserBackend]];
}

+ (NSString *)llhttpVersion {
#if ARLEN_ENABLE_LLHTTP
  return [NSString stringWithFormat:@"%d.%d.%d",
                                    LLHTTP_VERSION_MAJOR,
                                    LLHTTP_VERSION_MINOR,
                                    LLHTTP_VERSION_PATCH];
#else
  return @"disabled";
#endif
}

+ (BOOL)isLLHTTPAvailable {
#if ARLEN_ENABLE_LLHTTP
  return YES;
#else
  return NO;
#endif
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
#if ARLEN_ENABLE_LLHTTP
  return ALNRequestFromRawDataLLHTTP(data ?: [NSData data], error);
#else
  return ALNRequestFromRawDataLegacy(data ?: [NSData data], error);
#endif
}

@end
