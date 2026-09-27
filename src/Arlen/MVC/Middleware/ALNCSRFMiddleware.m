#import "ALNCSRFMiddleware.h"

#import "ALNContext.h"
#import "ALNPlatform.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"

static NSString *ALNCSRFTokenFromRandomBytes(void) {
  uint32_t parts[2] = {0, 0};
  if (!ALNPlatformFillRandomBytes(parts, sizeof(parts))) {
    parts[0] = (uint32_t)[[NSProcessInfo processInfo] processIdentifier];
    parts[1] = (uint32_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
  }
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"%08x%08x%@", parts[0], parts[1], uuid];
}

static BOOL ALNIsSafeMethod(NSString *method) {
  NSString *upper = [method uppercaseString];
  return [upper isEqualToString:@"GET"] || [upper isEqualToString:@"HEAD"] ||
         [upper isEqualToString:@"OPTIONS"] || [upper isEqualToString:@"TRACE"];
}

static NSString *ALNCSRFTokenFromFormBody(ALNRequest *request, NSString *queryParamName) {
  if (request == nil || ![queryParamName isKindOfClass:[NSString class]] ||
      [queryParamName length] == 0) {
    return nil;
  }
  NSString *value = request.formParams[queryParamName];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL ALNCSRFTokensMatch(id provided, NSString *expected) {
  if (![provided isKindOfClass:[NSString class]] || [(NSString *)provided length] == 0 ||
      [expected length] == 0) {
    return NO;
  }
  return ALNConstantTimeDataEquals([(NSString *)provided dataUsingEncoding:NSUTF8StringEncoding],
                                   [expected dataUsingEncoding:NSUTF8StringEncoding]);
}

static void ALNCSRFRejectRequest(ALNContext *context) {
  ALNResponse *response = context.response;
  [response clearBody];
  response.statusCode = 403;
  if ([context wantsJSON]) {
    id stashedRequestID = context.stash[@"request_id"];
    NSString *requestID = [stashedRequestID isKindOfClass:[NSString class]]
                              ? stashedRequestID
                              : ([response headerForName:@"X-Request-Id"] ?: @"");
    NSDictionary *payload = @{
      @"error" : @{
        @"code" : @"csrf_invalid",
        @"message" : @"CSRF token missing or invalid",
        @"status" : @(403),
        @"request_id" : requestID,
        @"correlation_id" : requestID,
      }
    };
    if ([response setJSONBody:payload options:0 error:NULL]) {
      response.committed = YES;
      return;
    }
  }
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [response setTextBody:@"csrf verification failed\n"];
  response.committed = YES;
}

@interface ALNCSRFMiddleware ()

@property(nonatomic, copy) NSString *headerName;
@property(nonatomic, copy) NSString *queryParamName;
@property(nonatomic, assign) BOOL allowQueryParamFallback;
@property(nonatomic, copy) NSArray<NSString *> *exemptPathPrefixes;

@end

@implementation ALNCSRFMiddleware

- (instancetype)initWithHeaderName:(NSString *)headerName
                    queryParamName:(NSString *)queryParamName {
  return [self initWithHeaderName:headerName
                   queryParamName:queryParamName
        allowQueryParamFallback:NO];
}

- (instancetype)initWithHeaderName:(NSString *)headerName
                    queryParamName:(NSString *)queryParamName
         allowQueryParamFallback:(BOOL)allowQueryParamFallback {
  return [self initWithHeaderName:headerName
                   queryParamName:queryParamName
        allowQueryParamFallback:allowQueryParamFallback
               exemptPathPrefixes:nil];
}

- (instancetype)initWithHeaderName:(NSString *)headerName
                    queryParamName:(NSString *)queryParamName
         allowQueryParamFallback:(BOOL)allowQueryParamFallback
                exemptPathPrefixes:(NSArray<NSString *> *)exemptPathPrefixes {
  self = [super init];
  if (self) {
    NSString *resolvedHeader = [[headerName lowercaseString] copy];
    if ([resolvedHeader length] == 0) {
      resolvedHeader = @"x-csrf-token";
    }
    _headerName = resolvedHeader;

    _queryParamName = [queryParamName copy];
    if ([_queryParamName length] == 0) {
      _queryParamName = @"csrf_token";
    }
    _allowQueryParamFallback = allowQueryParamFallback;
    _exemptPathPrefixes = [[[self class] normalizedExemptPathPrefixes:exemptPathPrefixes problem:NULL] copy] ?: @[];
  }
  return self;
}

+ (NSArray<NSString *> *)normalizedExemptPathPrefixes:(id)value problem:(NSString **)problem {
  if (value == nil) {
    return @[];
  }
  if (![value isKindOfClass:[NSArray class]]) {
    if (problem != NULL) {
      *problem = @"csrf.exemptPathPrefixes must be an array of paths";
    }
    return nil;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:
                          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._-~"];
  NSMutableArray<NSString *> *prefixes = [NSMutableArray array];
  for (id entry in (NSArray *)value) {
    NSString *path = [entry isKindOfClass:[NSString class]]
                         ? [entry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                         : nil;
    while ([path length] > 1 && [path hasSuffix:@"/"]) {
      path = [path substringToIndex:[path length] - 1];
    }
    NSArray *segments = [path componentsSeparatedByString:@"/"];
    if (![path hasPrefix:@"/"] || [path isEqualToString:@"/"] || [path containsString:@"//"] ||
        [segments containsObject:@"."] || [segments containsObject:@".."] ||
        [path rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound) {
      if (problem != NULL) {
        *problem = @"csrf.exemptPathPrefixes entries must be literal non-root absolute paths";
      }
      return nil;
    }
    [prefixes addObject:path];
  }
  return prefixes;
}

- (BOOL)isExemptPath:(NSString *)path {
  for (NSString *prefix in self.exemptPathPrefixes) {
    if ([path isEqualToString:prefix] || [path hasPrefix:[prefix stringByAppendingString:@"/"]]) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  // Checked before touching the session so an exempt request never mints a
  // session (and its Set-Cookie) just to hold a token it will not use.
  if ([self.exemptPathPrefixes count] > 0 && ![context.stash[ALNContextSessionHadCookieStashKey] boolValue] &&
      [self isExemptPath:context.request.path ?: @""]) {
    return YES;
  }
  NSMutableDictionary *session = [context session];

  NSString *token = session[@"_csrf_token"];
  if (![token isKindOfClass:[NSString class]] || [token length] == 0) {
    token = ALNCSRFTokenFromRandomBytes();
    session[@"_csrf_token"] = token;
    [context markSessionDirty];
  }
  context.stash[ALNContextCSRFTokenStashKey] = token;

  if (ALNIsSafeMethod(context.request.method ?: @"GET")) {
    return YES;
  }

  NSString *provided = [context.request headerValueForName:self.headerName];
  if ([provided length] == 0) {
    provided = ALNCSRFTokenFromFormBody(context.request, self.queryParamName);
  }
  if ([provided length] == 0) {
    if (self.allowQueryParamFallback) {
      provided = context.request.queryParams[self.queryParamName];
    }
  }

  if (ALNCSRFTokensMatch(provided, token)) {
    return YES;
  }

  ALNCSRFRejectRequest(context);
  return NO;
}

@end
