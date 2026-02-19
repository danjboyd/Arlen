#import "ALNApplication.h"

#import "ALNConfig.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNCSRFMiddleware.h"
#import "ALNRateLimitMiddleware.h"
#import "ALNRouter.h"
#import "ALNSecurityHeadersMiddleware.h"
#import "ALNSessionMiddleware.h"
#import "ALNLogger.h"
#import "ALNPerf.h"

NSString *const ALNApplicationErrorDomain = @"Arlen.Application.Error";

@interface ALNApplication ()

@property(nonatomic, strong, readwrite) ALNRouter *router;
@property(nonatomic, copy, readwrite) NSDictionary *config;
@property(nonatomic, copy, readwrite) NSString *environment;
@property(nonatomic, strong, readwrite) ALNLogger *logger;
@property(nonatomic, strong) NSMutableArray *mutableMiddlewares;

@end

@implementation ALNApplication

- (instancetype)initWithEnvironment:(NSString *)environment
                         configRoot:(NSString *)configRoot
                              error:(NSError **)error {
  NSError *configError = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:configRoot
                                        environment:environment
                                              error:&configError];
  if (config == nil) {
    if (error != NULL) {
      *error = configError;
    }
    return nil;
  }
  return [self initWithConfig:config];
}

- (instancetype)initWithConfig:(NSDictionary *)config {
  self = [super init];
  if (self) {
    _config = [config copy] ?: @{};
    _environment = [_config[@"environment"] copy] ?: @"development";
    _router = [[ALNRouter alloc] init];
    _logger = [[ALNLogger alloc] initWithFormat:_config[@"logFormat"] ?: @"text"];
    _mutableMiddlewares = [NSMutableArray array];
    if ([_environment isEqualToString:@"development"]) {
      _logger.minimumLevel = ALNLogLevelDebug;
    }
    [self registerBuiltInMiddlewares];
  }
  return self;
}

- (void)registerRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(NSString *)name
            controllerClass:(Class)controllerClass
                     action:(NSString *)actionName {
  [self registerRouteMethod:method
                       path:path
                       name:name
                    formats:nil
            controllerClass:controllerClass
                guardAction:nil
                     action:actionName];
}

- (void)registerRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(NSString *)name
                    formats:(NSArray *)formats
            controllerClass:(Class)controllerClass
                guardAction:(NSString *)guardAction
                     action:(NSString *)actionName {
  [self.router addRouteMethod:method
                         path:path
                         name:name
                      formats:formats
              controllerClass:controllerClass
                  guardAction:guardAction
                       action:actionName];
}

- (void)beginRouteGroupWithPrefix:(NSString *)prefix
                      guardAction:(NSString *)guardAction
                          formats:(NSArray *)formats {
  [self.router beginRouteGroupWithPrefix:prefix
                             guardAction:guardAction
                                 formats:formats];
}

- (void)endRouteGroup {
  [self.router endRouteGroup];
}

- (NSArray *)routeTable {
  return [self.router routeTable];
}

- (NSArray *)middlewares {
  return [NSArray arrayWithArray:self.mutableMiddlewares];
}

- (void)addMiddleware:(id<ALNMiddleware>)middleware {
  if (middleware == nil) {
    return;
  }
  [self.mutableMiddlewares addObject:middleware];
}

static BOOL ALNResponseHasBody(ALNResponse *response) {
  return [response.bodyData length] > 0;
}

static NSDictionary *ALNDictionaryConfigValue(NSDictionary *config, NSString *key) {
  id value = config[key];
  if ([value isKindOfClass:[NSDictionary class]]) {
    return value;
  }
  return @{};
}

static BOOL ALNBoolConfigValue(id value, BOOL defaultValue) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return defaultValue;
}

static NSUInteger ALNUIntConfigValue(id value, NSUInteger defaultValue, NSUInteger minimum) {
  if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
    NSUInteger parsed = [value unsignedIntegerValue];
    if (parsed >= minimum) {
      return parsed;
    }
  }
  return defaultValue;
}

static NSString *ALNStringConfigValue(id value, NSString *defaultValue) {
  if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
    return value;
  }
  return defaultValue;
}

static NSString *ALNGenerateRequestID(void) {
  return [[NSUUID UUID] UUIDString];
}

static BOOL ALNPathLooksLikeAPI(NSString *path) {
  if (![path isKindOfClass:[NSString class]]) {
    return NO;
  }
  return [path hasPrefix:@"/api/"] || [path isEqualToString:@"/api"];
}

static NSString *ALNExtractPathFormat(NSString *path, NSString **strippedPath) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    if (strippedPath != NULL) {
      *strippedPath = @"/";
    }
    return nil;
  }

  NSString *normalized = path;
  NSRange queryRange = [normalized rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    normalized = [normalized substringToIndex:queryRange.location];
  }
  if ([normalized length] == 0) {
    normalized = @"/";
  }

  NSString *trimmed = normalized;
  while ([trimmed length] > 1 && [trimmed hasSuffix:@"/"]) {
    trimmed = [trimmed substringToIndex:[trimmed length] - 1];
  }

  NSRange lastSlash = [trimmed rangeOfString:@"/" options:NSBackwardsSearch];
  NSRange lastDot = [trimmed rangeOfString:@"." options:NSBackwardsSearch];
  BOOL hasExtension = (lastDot.location != NSNotFound &&
                       (lastSlash.location == NSNotFound || lastDot.location > lastSlash.location));
  if (!hasExtension) {
    if (strippedPath != NULL) {
      *strippedPath = trimmed;
    }
    return nil;
  }

  NSString *extension = [[trimmed substringFromIndex:lastDot.location + 1] lowercaseString];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([extension length] == 0 ||
      [[extension stringByTrimmingCharactersInSet:allowed] length] > 0) {
    if (strippedPath != NULL) {
      *strippedPath = trimmed;
    }
    return nil;
  }

  if (strippedPath != NULL) {
    NSString *withoutExt = [trimmed substringToIndex:lastDot.location];
    *strippedPath = ([withoutExt length] > 0) ? withoutExt : @"/";
  }
  return extension;
}

static NSString *ALNRequestPreferredFormat(ALNRequest *request, BOOL apiOnly, NSString **strippedPath) {
  NSString *path = request.path ?: @"/";
  NSString *pathFormat = ALNExtractPathFormat(path, strippedPath);
  if ([pathFormat length] > 0) {
    return pathFormat;
  }

  NSString *accept = [request.headers[@"accept"] isKindOfClass:[NSString class]]
                         ? [request.headers[@"accept"] lowercaseString]
                         : @"";
  if ([accept containsString:@"application/json"] || [accept containsString:@"text/json"]) {
    return @"json";
  }
  if ([accept containsString:@"text/html"] || [accept containsString:@"application/xhtml+xml"]) {
    return @"html";
  }

  NSString *resolvedPath = (strippedPath != NULL && [*strippedPath length] > 0)
                               ? *strippedPath
                               : (request.path ?: @"/");
  if (apiOnly || ALNPathLooksLikeAPI(resolvedPath)) {
    return @"json";
  }

  return @"html";
}

static BOOL ALNRequestPrefersJSON(ALNRequest *request, BOOL apiOnly) {
  NSString *format = ALNRequestPreferredFormat(request, apiOnly, NULL);
  return [format isEqualToString:@"json"];
}

static NSString *ALNEscapeHTML(NSString *value) {
  NSString *safe = value ?: @"";
  safe = [safe stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  safe = [safe stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  safe = [safe stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  safe = [safe stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  return [safe stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
}

static NSString *ALNBuiltInHealthBodyForPath(NSString *path) {
  if ([path isEqualToString:@"/healthz"]) {
    return @"ok\n";
  }
  if ([path isEqualToString:@"/readyz"]) {
    return @"ready\n";
  }
  if ([path isEqualToString:@"/livez"]) {
    return @"live\n";
  }
  return nil;
}

static NSDictionary *ALNErrorDetailsFromNSError(NSError *error) {
  if (error == nil) {
    return @{};
  }

  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[@"domain"] = error.domain ?: @"";
  details[@"code"] = @([error code]);
  details[@"description"] = error.localizedDescription ?: @"";

  id file = error.userInfo[@"ALNEOCErrorPath"] ?: error.userInfo[@"path"];
  id line = error.userInfo[@"ALNEOCErrorLine"] ?: error.userInfo[@"line"];
  id column = error.userInfo[@"ALNEOCErrorColumn"] ?: error.userInfo[@"column"];
  if ([file isKindOfClass:[NSString class]]) {
    details[@"file"] = file;
  }
  if ([line respondsToSelector:@selector(integerValue)]) {
    details[@"line"] = @([line integerValue]);
  }
  if ([column respondsToSelector:@selector(integerValue)]) {
    details[@"column"] = @([column integerValue]);
  }
  return details;
}

static NSDictionary *ALNErrorDetailsFromException(NSException *exception) {
  if (exception == nil) {
    return @{};
  }

  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[@"name"] = exception.name ?: @"";
  details[@"reason"] = exception.reason ?: @"";
  NSArray *stack = exception.callStackSymbols ?: @[];
  if ([stack count] > 0) {
    details[@"stack"] = stack;
  }
  return details;
}

static NSString *ALNDevelopmentErrorPageHTML(NSString *requestID,
                                             NSString *errorCode,
                                             NSString *message,
                                             NSDictionary *details) {
  NSMutableString *html = [NSMutableString string];
  [html appendString:@"<!doctype html><html><head><meta charset='utf-8'>"];
  [html appendString:@"<title>Arlen Development Exception</title>"];
  [html appendString:@"<style>body{font-family:Menlo,Consolas,monospace;background:#111;color:#eee;padding:24px;}h1{margin-top:0;}pre{background:#1b1b1b;border:1px solid #333;padding:12px;overflow:auto;}code{background:#1b1b1b;padding:2px 4px;}table{border-collapse:collapse;width:100%;}td{border:1px solid #333;padding:6px;vertical-align:top;} .muted{color:#aaa;}</style>"];
  [html appendString:@"</head><body>"];
  [html appendString:@"<h1>Arlen Development Exception</h1>"];
  [html appendFormat:@"<p><strong>Request ID:</strong> <code>%@</code></p>", ALNEscapeHTML(requestID)];
  [html appendFormat:@"<p><strong>Error Code:</strong> <code>%@</code></p>", ALNEscapeHTML(errorCode)];
  [html appendFormat:@"<p><strong>Message:</strong> %@</p>", ALNEscapeHTML(message)];

  if ([details count] > 0) {
    [html appendString:@"<h2>Details</h2><table>"];
    NSArray *keys = [[details allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
      id value = details[key];
      NSString *rendered = nil;
      if ([value isKindOfClass:[NSArray class]]) {
        rendered = [[(NSArray *)value componentsJoinedByString:@"\n"] copy];
      } else {
        rendered = [value description] ?: @"";
      }
      [html appendFormat:@"<tr><td><strong>%@</strong></td><td><pre>%@</pre></td></tr>",
                         ALNEscapeHTML(key), ALNEscapeHTML(rendered)];
    }
    [html appendString:@"</table>"];
  } else {
    [html appendString:@"<p class='muted'>No additional details were captured.</p>"];
  }

  [html appendString:@"</body></html>"];
  return html;
}

static NSDictionary *ALNStructuredErrorPayload(NSInteger statusCode,
                                               NSString *errorCode,
                                               NSString *message,
                                               NSString *requestID,
                                               NSDictionary *details) {
  NSMutableDictionary *errorObject = [NSMutableDictionary dictionary];
  errorObject[@"code"] = errorCode ?: @"internal_error";
  errorObject[@"message"] = message ?: @"Internal Server Error";
  errorObject[@"status"] = @(statusCode);
  errorObject[@"correlation_id"] = requestID ?: @"";
  errorObject[@"request_id"] = requestID ?: @"";

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"error"] = errorObject;
  if ([details count] > 0) {
    payload[@"details"] = details;
  }
  return payload;
}

static void ALNSetStructuredErrorResponse(ALNResponse *response,
                                          NSInteger statusCode,
                                          NSDictionary *payload) {
  NSError *jsonError = nil;
  BOOL ok = [response setJSONBody:payload options:0 error:&jsonError];
  if (!ok) {
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [response setTextBody:@"internal server error\n"];
  }
  response.statusCode = statusCode;
  response.committed = YES;
}

static void ALNApplyInternalErrorResponse(ALNApplication *application,
                                          ALNRequest *request,
                                          ALNResponse *response,
                                          NSString *requestID,
                                          NSInteger statusCode,
                                          NSString *errorCode,
                                          NSString *publicMessage,
                                          NSString *developerMessage,
                                          NSDictionary *details) {
  BOOL production = [application.environment isEqualToString:@"production"];
  BOOL apiOnly = ALNBoolConfigValue(application.config[@"apiOnly"], NO);
  BOOL prefersJSON = ALNRequestPrefersJSON(request, apiOnly);

  if (production || prefersJSON) {
    NSDictionary *payload = ALNStructuredErrorPayload(statusCode,
                                                      errorCode,
                                                      publicMessage,
                                                      requestID,
                                                      production ? @{} : (details ?: @{}));
    ALNSetStructuredErrorResponse(response, statusCode, payload);
    return;
  }

  NSString *html = ALNDevelopmentErrorPageHTML(requestID,
                                               errorCode ?: @"internal_error",
                                               developerMessage ?: publicMessage,
                                               details ?: @{});
  response.statusCode = statusCode;
  [response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
  [response setTextBody:html ?: @"internal server error\n"];
  response.committed = YES;
}

static void ALNFinalizeResponse(ALNResponse *response,
                                ALNPerfTrace *trace,
                                ALNRequest *request,
                                NSString *requestID,
                                BOOL performanceLogging) {
  if (performanceLogging && [trace isEnabled]) {
    [trace setStage:@"parse" durationMilliseconds:request.parseDurationMilliseconds >= 0.0
                                           ? request.parseDurationMilliseconds
                                           : 0.0];

    NSNumber *writeStage = [trace durationMillisecondsForStage:@"response_write"];
    if (writeStage == nil) {
      double writeMs = request.responseWriteDurationMilliseconds;
      if (writeMs < 0.0) {
        writeMs = 0.0;
      }
      [trace setStage:@"response_write" durationMilliseconds:writeMs];
    }

    [trace endStage:@"total"];
    NSNumber *total = [trace durationMillisecondsForStage:@"total"] ?: @(0);
    NSNumber *parse = [trace durationMillisecondsForStage:@"parse"] ?: @(0);
    NSNumber *responseWrite = [trace durationMillisecondsForStage:@"response_write"] ?: @(0);

    [response setHeader:@"X-Arlen-Total-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [total doubleValue]]];
    [response setHeader:@"X-Mojo-Total-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [total doubleValue]]];
    [response setHeader:@"X-Arlen-Parse-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [parse doubleValue]]];
    [response setHeader:@"X-Arlen-Response-Write-Ms"
                  value:[NSString stringWithFormat:@"%.3f", [responseWrite doubleValue]]];
  }

  if ([requestID length] > 0) {
    [response setHeader:@"X-Request-Id" value:requestID];
  }
}

- (void)registerBuiltInMiddlewares {
  NSDictionary *securityHeaders = ALNDictionaryConfigValue(self.config, @"securityHeaders");
  BOOL securityHeadersEnabled = ALNBoolConfigValue(securityHeaders[@"enabled"], YES);
  if (securityHeadersEnabled) {
    NSString *csp =
        ALNStringConfigValue(securityHeaders[@"contentSecurityPolicy"], @"default-src 'self'");
    [self addMiddleware:[[ALNSecurityHeadersMiddleware alloc] initWithContentSecurityPolicy:csp]];
  }

  NSDictionary *rateLimit = ALNDictionaryConfigValue(self.config, @"rateLimit");
  BOOL rateLimitEnabled = ALNBoolConfigValue(rateLimit[@"enabled"], NO);
  if (rateLimitEnabled) {
    NSUInteger requests = ALNUIntConfigValue(rateLimit[@"requests"], 120, 1);
    NSUInteger windowSeconds = ALNUIntConfigValue(rateLimit[@"windowSeconds"], 60, 1);
    [self addMiddleware:[[ALNRateLimitMiddleware alloc] initWithMaxRequests:requests
                                                               windowSeconds:windowSeconds]];
  }

  NSDictionary *session = ALNDictionaryConfigValue(self.config, @"session");
  BOOL sessionEnabled = ALNBoolConfigValue(session[@"enabled"], NO);
  if (sessionEnabled) {
    NSString *secret = ALNStringConfigValue(session[@"secret"], nil);
    if ([secret length] == 0) {
      [self.logger warn:@"session middleware disabled"
                 fields:@{
                   @"reason" : @"missing session.secret",
                 }];
    } else {
      NSString *cookieName = ALNStringConfigValue(session[@"cookieName"], @"arlen_session");
      NSUInteger maxAge = ALNUIntConfigValue(session[@"maxAgeSeconds"], 1209600, 1);
      BOOL secureDefault = [self.environment isEqualToString:@"production"];
      BOOL secure = ALNBoolConfigValue(session[@"secure"], secureDefault);
      NSString *sameSite = ALNStringConfigValue(session[@"sameSite"], @"Lax");
      [self addMiddleware:[[ALNSessionMiddleware alloc] initWithSecret:secret
                                                             cookieName:cookieName
                                                          maxAgeSeconds:maxAge
                                                                 secure:secure
                                                               sameSite:sameSite]];
    }
  }

  NSDictionary *csrf = ALNDictionaryConfigValue(self.config, @"csrf");
  BOOL csrfEnabled = ALNBoolConfigValue(csrf[@"enabled"], sessionEnabled);
  if (csrfEnabled) {
    if (!sessionEnabled) {
      [self.logger warn:@"csrf middleware disabled"
                 fields:@{
                   @"reason" : @"csrf requires session middleware",
                 }];
    } else {
      NSString *headerName = ALNStringConfigValue(csrf[@"headerName"], @"x-csrf-token");
      NSString *queryParam = ALNStringConfigValue(csrf[@"queryParamName"], @"csrf_token");
      [self addMiddleware:[[ALNCSRFMiddleware alloc] initWithHeaderName:headerName
                                                         queryParamName:queryParam]];
    }
  }
}

- (ALNResponse *)dispatchRequest:(ALNRequest *)request {
  ALNResponse *response = [[ALNResponse alloc] init];
  NSString *requestID = ALNGenerateRequestID();
  [response setHeader:@"X-Request-Id" value:requestID];

  BOOL performanceLogging = ALNBoolConfigValue(self.config[@"performanceLogging"], YES);
  BOOL apiOnly = ALNBoolConfigValue(self.config[@"apiOnly"], NO);
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:performanceLogging];
  [trace startStage:@"total"];

  NSString *routePath = nil;
  NSString *requestFormat = ALNRequestPreferredFormat(request, apiOnly, &routePath);
  if ([routePath length] == 0) {
    routePath = request.path ?: @"/";
  }

  [trace startStage:@"route"];
  ALNRouteMatch *match =
      [self.router matchMethod:request.method ?: @"GET"
                          path:routePath
                        format:requestFormat];
  [trace endStage:@"route"];

  if (match == nil) {
    NSString *healthBody = nil;
    BOOL healthMethod = [request.method isEqualToString:@"GET"] ||
                        [request.method isEqualToString:@"HEAD"];
    if (healthMethod) {
      healthBody = ALNBuiltInHealthBodyForPath(routePath);
    }

    if ([healthBody length] > 0) {
      response.statusCode = 200;
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      if (![request.method isEqualToString:@"HEAD"]) {
        [response setTextBody:healthBody];
      }
      response.committed = YES;
    } else if (apiOnly || ALNRequestPrefersJSON(request, apiOnly)) {
      NSDictionary *payload = ALNStructuredErrorPayload(404,
                                                        @"not_found",
                                                        @"Not Found",
                                                        requestID,
                                                        @{});
      ALNSetStructuredErrorResponse(response, 404, payload);
    } else {
      response.statusCode = 404;
      [response setTextBody:@"not found\n"];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
    }
    ALNFinalizeResponse(response, trace, request, requestID, performanceLogging);

    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    fields[@"method"] = request.method ?: @"";
    fields[@"path"] = request.path ?: @"";
    fields[@"status"] = @(response.statusCode);
    fields[@"request_id"] = requestID ?: @"";
    if (performanceLogging) {
      fields[@"timings"] = [trace dictionaryRepresentation];
    }
    [self.logger info:@"request" fields:fields];
    return response;
  }

  NSMutableDictionary *stash = [NSMutableDictionary dictionary];
  stash[@"request_id"] = requestID ?: @"";
  stash[ALNContextRequestFormatStashKey] = requestFormat ?: @"";
  NSDictionary *eoc = ALNDictionaryConfigValue(self.config, @"eoc");
  stash[ALNContextEOCStrictLocalsStashKey] =
      @(ALNBoolConfigValue(eoc[@"strictLocals"], NO));
  stash[ALNContextEOCStrictStringifyStashKey] =
      @(ALNBoolConfigValue(eoc[@"strictStringify"], NO));
  request.routeParams = match.params ?: @{};
  ALNContext *context = [[ALNContext alloc] initWithRequest:request
                                                   response:response
                                                     params:request.routeParams
                                                      stash:stash
                                                     logger:self.logger
                                                  perfTrace:trace
                                                  routeName:match.route.name ?: @""
                                             controllerName:NSStringFromClass(match.route.controllerClass)
                                                 actionName:match.route.actionName ?: @""];

  id returnValue = nil;
  BOOL shouldDispatchController = YES;
  NSMutableArray *executedMiddlewares = [NSMutableArray array];
  if ([self.mutableMiddlewares count] > 0) {
    [trace startStage:@"middleware"];
    for (id<ALNMiddleware> middleware in self.mutableMiddlewares) {
      NSError *middlewareError = nil;
      BOOL shouldContinue = [middleware processContext:context error:&middlewareError];
      [executedMiddlewares addObject:middleware];
      if (!shouldContinue) {
        shouldDispatchController = NO;
        if (!response.committed) {
          if (middlewareError != nil) {
            NSDictionary *details = ALNErrorDetailsFromNSError(middlewareError);
            ALNApplyInternalErrorResponse(self,
                                          request,
                                          response,
                                          requestID,
                                          500,
                                          @"middleware_failure",
                                          @"Internal Server Error",
                                          middlewareError.localizedDescription ?: @"middleware failure",
                                          details);
          } else {
            response.statusCode = 400;
            [response setTextBody:@"request halted by middleware\n"];
            [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
            response.committed = YES;
          }
        }
        if (middlewareError != nil) {
          [self.logger error:@"middleware failure"
                      fields:@{
                        @"request_id" : requestID ?: @"",
                        @"controller" : context.controllerName ?: @"",
                        @"action" : context.actionName ?: @"",
                        @"error" : middlewareError.localizedDescription ?: @""
                      }];
        }
        break;
      }
    }
    [trace endStage:@"middleware"];
  }

  if (shouldDispatchController) {
    [trace startStage:@"controller"];
    @try {
      id controller = [[match.route.controllerClass alloc] init];
      if ([controller isKindOfClass:[ALNController class]]) {
        ((ALNController *)controller).context = context;
      }
      BOOL guardPassed = YES;
      if (match.route.guardSelector != NULL) {
        NSMethodSignature *guardSignature =
            [controller methodSignatureForSelector:match.route.guardSelector];
        if (guardSignature == nil || [guardSignature numberOfArguments] != 3) {
          NSDictionary *details = @{
            @"controller" : context.controllerName ?: @"",
            @"guard" : match.route.guardActionName ?: @"",
            @"reason" : @"Guard must accept exactly one ALNContext * parameter"
          };
          ALNApplyInternalErrorResponse(self,
                                        request,
                                        response,
                                        requestID,
                                        500,
                                        @"invalid_guard_signature",
                                        @"Internal Server Error",
                                        @"Invalid route guard signature",
                                        details);
          guardPassed = NO;
        } else {
          NSInvocation *guardInvocation =
              [NSInvocation invocationWithMethodSignature:guardSignature];
          [guardInvocation setTarget:controller];
          [guardInvocation setSelector:match.route.guardSelector];
          ALNContext *arg = context;
          [guardInvocation setArgument:&arg atIndex:2];
          [guardInvocation invoke];

          const char *guardReturnType = [guardSignature methodReturnType];
          if (strcmp(guardReturnType, @encode(void)) == 0) {
            guardPassed = !response.committed;
          } else if (strcmp(guardReturnType, @encode(BOOL)) == 0 ||
                     strcmp(guardReturnType, @encode(bool)) == 0 ||
                     strcmp(guardReturnType, "c") == 0) {
            BOOL value = NO;
            [guardInvocation getReturnValue:&value];
            guardPassed = value;
          } else {
            __unsafe_unretained id guardResult = nil;
            [guardInvocation getReturnValue:&guardResult];
            if ([guardResult respondsToSelector:@selector(boolValue)]) {
              guardPassed = [guardResult boolValue];
            } else {
              guardPassed = (guardResult != nil);
            }
          }
        }
      }

      if (!guardPassed && !response.committed) {
        if (apiOnly || ALNRequestPrefersJSON(request, apiOnly)) {
          NSDictionary *payload = ALNStructuredErrorPayload(403,
                                                            @"forbidden",
                                                            @"Forbidden",
                                                            requestID,
                                                            @{});
          ALNSetStructuredErrorResponse(response, 403, payload);
        } else {
          response.statusCode = 403;
          [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
          [response setTextBody:@"forbidden\n"];
          response.committed = YES;
        }
      }

      if (guardPassed && !response.committed) {
        NSMethodSignature *signature =
            [controller methodSignatureForSelector:match.route.actionSelector];
        if (signature == nil || [signature numberOfArguments] != 3) {
          NSDictionary *details = @{
            @"controller" : context.controllerName ?: @"",
            @"action" : context.actionName ?: @"",
            @"reason" : @"Action must accept exactly one ALNContext * parameter"
          };
          ALNApplyInternalErrorResponse(self,
                                        request,
                                        response,
                                        requestID,
                                        500,
                                        @"invalid_action_signature",
                                        @"Internal Server Error",
                                        @"Invalid controller action signature",
                                        details);
        } else {
          NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
          [invocation setTarget:controller];
          [invocation setSelector:match.route.actionSelector];
          ALNContext *arg = context;
          [invocation setArgument:&arg atIndex:2];
          [invocation invoke];

          const char *returnType = [signature methodReturnType];
          if (strcmp(returnType, @encode(void)) != 0) {
            __unsafe_unretained id temp = nil;
            [invocation getReturnValue:&temp];
            returnValue = temp;
          }
        }
      }
    } @catch (NSException *exception) {
      NSDictionary *details = ALNErrorDetailsFromException(exception);
      ALNApplyInternalErrorResponse(self,
                                    request,
                                    response,
                                    requestID,
                                    500,
                                    @"controller_exception",
                                    @"Internal Server Error",
                                    exception.reason ?: @"controller exception",
                                    details);
      [self.logger error:@"controller exception"
                  fields:@{
                    @"request_id" : requestID ?: @"",
                    @"controller" : context.controllerName ?: @"",
                    @"action" : context.actionName ?: @"",
                    @"exception" : exception.description ?: @""
                  }];
    }
    [trace endStage:@"controller"];
  }

  if (!response.committed) {
    if ([returnValue isKindOfClass:[NSDictionary class]] ||
        [returnValue isKindOfClass:[NSArray class]]) {
      Class controllerClass = match.route.controllerClass;
      NSJSONWritingOptions options = 0;
      if ([controllerClass respondsToSelector:@selector(jsonWritingOptions)]) {
        options = (NSJSONWritingOptions)[controllerClass jsonWritingOptions];
      }

      NSError *jsonError = nil;
      BOOL ok = [response setJSONBody:returnValue options:options error:&jsonError];
      if (!ok) {
        NSDictionary *details = ALNErrorDetailsFromNSError(jsonError);
        ALNApplyInternalErrorResponse(self,
                                      request,
                                      response,
                                      requestID,
                                      500,
                                      @"json_serialization_failed",
                                      @"Internal Server Error",
                                      jsonError.localizedDescription ?: @"json serialization failed",
                                      details);
        [self.logger error:@"implicit json serialization failed"
                    fields:@{
                      @"request_id" : requestID ?: @"",
                      @"controller" : context.controllerName ?: @"",
                      @"action" : context.actionName ?: @"",
                      @"error" : jsonError.localizedDescription ?: @""
                    }];
      } else {
        if (response.statusCode == 0) {
          response.statusCode = 200;
        }
        response.committed = YES;
      }
    } else if ([returnValue isKindOfClass:[NSString class]]) {
      [response setTextBody:returnValue];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
    } else if (returnValue != nil) {
      [response setTextBody:[returnValue description]];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
    } else if (!ALNResponseHasBody(response)) {
      response.statusCode = 204;
      response.committed = YES;
    }
  }

  for (NSInteger idx = (NSInteger)[executedMiddlewares count] - 1; idx >= 0; idx--) {
    id<ALNMiddleware> middleware = executedMiddlewares[(NSUInteger)idx];
    if (![middleware respondsToSelector:@selector(didProcessContext:)]) {
      continue;
    }
    @try {
      [middleware didProcessContext:context];
    } @catch (NSException *exception) {
      if (!response.committed) {
        NSDictionary *details = ALNErrorDetailsFromException(exception);
        ALNApplyInternalErrorResponse(self,
                                      request,
                                      response,
                                      requestID,
                                      500,
                                      @"middleware_finalize_failure",
                                      @"Internal Server Error",
                                      exception.reason ?: @"middleware finalize failure",
                                      details);
      }
      [self.logger error:@"middleware finalize failure"
                  fields:@{
                    @"request_id" : requestID ?: @"",
                    @"controller" : context.controllerName ?: @"",
                    @"action" : context.actionName ?: @"",
                    @"exception" : exception.description ?: @""
                  }];
    }
  }

  ALNFinalizeResponse(response, trace, request, requestID, performanceLogging);

  NSMutableDictionary *logFields = [NSMutableDictionary dictionary];
  logFields[@"method"] = request.method ?: @"";
  logFields[@"path"] = request.path ?: @"";
  logFields[@"status"] = @(response.statusCode);
  logFields[@"request_id"] = requestID ?: @"";
  logFields[@"controller"] = context.controllerName ?: @"";
  logFields[@"action"] = context.actionName ?: @"";
  if (performanceLogging) {
    logFields[@"timings"] = [trace dictionaryRepresentation];
  }
  [self.logger info:@"request" fields:logFields];

  return response;
}

@end
