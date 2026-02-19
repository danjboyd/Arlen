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
  [self.router addRouteMethod:method
                         path:path
                         name:name
              controllerClass:controllerClass
                       action:actionName];
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

static void ALNFinalizeResponse(ALNResponse *response, ALNPerfTrace *trace, NSString *requestID) {
  [trace endStage:@"total"];
  NSNumber *total = [trace durationMillisecondsForStage:@"total"] ?: @(0);
  [response setHeader:@"X-Arlen-Total-Ms"
                value:[NSString stringWithFormat:@"%.3f", [total doubleValue]]];
  [response setHeader:@"X-Mojo-Total-Ms"
                value:[NSString stringWithFormat:@"%.3f", [total doubleValue]]];
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
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] init];
  [trace startStage:@"total"];
  [trace startStage:@"route"];
  ALNRouteMatch *match =
      [self.router matchMethod:request.method ?: @"GET" path:request.path ?: @"/"];
  [trace endStage:@"route"];

  if (match == nil) {
    response.statusCode = 404;
    [response setTextBody:@"not found\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    ALNFinalizeResponse(response, trace, requestID);
    [self.logger info:@"request"
               fields:@{
                 @"method" : request.method ?: @"",
                 @"path" : request.path ?: @"",
                 @"status" : @(response.statusCode),
                 @"request_id" : requestID ?: @"",
                 @"timings" : [trace dictionaryRepresentation]
               }];
    return response;
  }

  NSMutableDictionary *stash = [NSMutableDictionary dictionary];
  stash[@"request_id"] = requestID ?: @"";
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
            response.statusCode = 500;
            [response setTextBody:@"middleware failure\n"];
          } else {
            response.statusCode = 400;
            [response setTextBody:@"request halted by middleware\n"];
          }
          [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
          response.committed = YES;
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

      NSMethodSignature *signature =
          [controller methodSignatureForSelector:match.route.actionSelector];
      if (signature == nil || [signature numberOfArguments] != 3) {
        response.statusCode = 500;
        [response setTextBody:@"invalid controller action signature\n"];
        [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
        response.committed = YES;
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
    } @catch (NSException *exception) {
      response.statusCode = 500;
      [response setTextBody:@"internal server error\n"];
      [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
      response.committed = YES;
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
        response.statusCode = 500;
        [response setTextBody:@"json serialization failed\n"];
        [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
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
      }
      response.committed = YES;
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
        response.statusCode = 500;
        [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
        [response setTextBody:@"middleware finalize failure\n"];
        response.committed = YES;
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

  ALNFinalizeResponse(response, trace, requestID);

  NSMutableDictionary *logFields = [NSMutableDictionary dictionary];
  logFields[@"method"] = request.method ?: @"";
  logFields[@"path"] = request.path ?: @"";
  logFields[@"status"] = @(response.statusCode);
  logFields[@"request_id"] = requestID ?: @"";
  logFields[@"controller"] = context.controllerName ?: @"";
  logFields[@"action"] = context.actionName ?: @"";
  logFields[@"timings"] = [trace dictionaryRepresentation];
  [self.logger info:@"request" fields:logFields];

  return response;
}

@end
