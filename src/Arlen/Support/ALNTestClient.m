#import "ALNTestClient.h"

#import "ALNApplication.h"
#import "ALNAuthSession.h"
#import "ALNConfig.h"
#import "ALNContext.h"
#import "ALNPerf.h"
#import "ALNRequest.h"
#import "ALNSessionMiddleware.h"

static NSString *const ALNTestClientErrorDomain = @"Arlen.TestClient.Error";
static ALNAppMainFunction gALNTestClientAppMain = NULL;

void ALNTestClientSetAppMain(ALNAppMainFunction appMain) {
  gALNTestClientAppMain = appMain;
}

static NSError *ALNTestClientError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:ALNTestClientErrorDomain
                             code:code
                         userInfo:@{ NSLocalizedDescriptionKey : message ?: @"test client error" }];
}

static NSDictionary *ALNTestClientDeepMerge(NSDictionary *base, NSDictionary *overrides) {
  NSMutableDictionary *merged = [base mutableCopy] ?: [NSMutableDictionary dictionary];
  for (id key in overrides) {
    id value = overrides[key];
    if ([value isKindOfClass:[NSDictionary class]] && [merged[key] isKindOfClass:[NSDictionary class]]) {
      merged[key] = ALNTestClientDeepMerge(merged[key], value);
    } else {
      merged[key] = value;
    }
  }
  return merged;
}

static NSString *ALNTestClientPercentEncode(NSString *value) {
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:
                          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
  return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *ALNTestClientFormEncode(NSDictionary<NSString *, NSString *> *values) {
  NSMutableArray *pairs = [NSMutableArray array];
  for (NSString *key in [[values allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *value = [values[key] isKindOfClass:[NSString class]] ? values[key] : [values[key] description];
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", ALNTestClientPercentEncode(key),
                                                ALNTestClientPercentEncode(value ?: @"")]];
  }
  return [pairs componentsJoinedByString:@"&"];
}

static BOOL ALNTestClientIsSafeMethod(NSString *method) {
  NSString *upper = [method uppercaseString];
  return [upper isEqualToString:@"GET"] || [upper isEqualToString:@"HEAD"] ||
         [upper isEqualToString:@"OPTIONS"] || [upper isEqualToString:@"TRACE"];
}

@interface ALNTestClient ()
@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *jar;
@end

@implementation ALNTestClient

+ (void)setAppMain:(ALNAppMainFunction)appMain {
  ALNTestClientSetAppMain(appMain);
}

+ (instancetype)clientWithEnvironment:(NSString *)environment
                      configOverrides:(NSDictionary *)configOverrides
                                error:(NSError **)error {
  return [self clientWithAppRoot:nil
                     environment:environment
                 configOverrides:configOverrides
                  registerRoutes:NULL
                           error:error];
}

+ (instancetype)clientWithAppRoot:(NSString *)appRoot
                      environment:(NSString *)environment
                  configOverrides:(NSDictionary *)configOverrides
                   registerRoutes:(ALNRouteRegistrationCallback)registerRoutes
                            error:(NSError **)error {
  NSString *root = appRoot;
  if ([root length] == 0) {
    const char *envRoot = getenv("ARLEN_APP_ROOT");
    root = (envRoot != NULL && envRoot[0] != '\0') ? [NSString stringWithUTF8String:envRoot]
                                                   : [[NSFileManager defaultManager] currentDirectoryPath];
  }
  root = [root stringByStandardizingPath];
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:([environment length] > 0 ? environment : @"test")
                                               error:error];
  if (config == nil) {
    return nil;
  }
  if ([configOverrides count] > 0) {
    config = ALNTestClientDeepMerge(config, configOverrides);
  }
  ALNRouteRegistrationCallback routes = registerRoutes;
  if (routes == NULL && gALNTestClientAppMain != NULL) {
    routes = ALNCaptureRouteRegistration(gALNTestClientAppMain);
  }
  ALNApplication *application = [[ALNApplication alloc] initWithConfig:config];
  if (routes != NULL) {
    routes(application);
  }
  return [[self alloc] initWithApplication:application error:error];
}

- (instancetype)initWithApplication:(ALNApplication *)application error:(NSError **)error {
  self = [super init];
  if (self != nil) {
    _application = application;
    _jar = [NSMutableDictionary dictionary];
    _automaticCSRF = YES;
    if (!application.isStarted && ![application startWithError:error]) {
      return nil;
    }
  }
  return self;
}

- (NSDictionary<NSString *, NSString *> *)cookies {
  return [self.jar copy];
}

- (void)clearCookies {
  [self.jar removeAllObjects];
}

#pragma mark - Requests

- (ALNResponse *)get:(NSString *)path {
  return [self get:path query:nil headers:nil];
}

- (ALNResponse *)get:(NSString *)path
               query:(NSDictionary<NSString *, NSString *> *)query
             headers:(NSDictionary<NSString *, NSString *> *)headers {
  return [self requestWithMethod:@"GET"
                            path:path
                           query:([query count] > 0 ? ALNTestClientFormEncode(query) : nil)
                         headers:headers
                            body:nil];
}

- (ALNResponse *)post:(NSString *)path form:(NSDictionary<NSString *, NSString *> *)form {
  NSData *body = [ALNTestClientFormEncode(form ?: @{}) dataUsingEncoding:NSUTF8StringEncoding];
  return [self requestWithMethod:@"POST"
                            path:path
                           query:nil
                         headers:@{ @"content-type" : @"application/x-www-form-urlencoded" }
                            body:body];
}

- (ALNResponse *)post:(NSString *)path JSON:(id)object {
  NSData *body = (object != nil) ? [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] : nil;
  return [self requestWithMethod:@"POST"
                            path:path
                           query:nil
                         headers:@{ @"content-type" : @"application/json", @"accept" : @"application/json" }
                            body:body ?: [NSData data]];
}

- (ALNResponse *)post:(NSString *)path
      multipartFields:(NSDictionary<NSString *, NSString *> *)fields
                files:(NSArray<NSDictionary *> *)files {
  NSString *boundary = [@"ArlenTestBoundary" stringByAppendingString:[[NSUUID UUID] UUIDString]];
  NSMutableData *body = [NSMutableData data];
  void (^append)(NSString *) = ^(NSString *text) {
    [body appendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
  };
  for (NSString *name in [[fields allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    append([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
                                      boundary, name, fields[name]]);
  }
  for (NSDictionary *file in files ?: @[]) {
    append([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
                                      "Content-Type: %@\r\n\r\n",
                                      boundary, file[@"name"] ?: @"file", file[@"filename"] ?: @"upload.bin",
                                      file[@"contentType"] ?: @"application/octet-stream"]);
    NSData *data = [file[@"data"] isKindOfClass:[NSData class]] ? file[@"data"] : [NSData data];
    [body appendData:data];
    append(@"\r\n");
  }
  append([NSString stringWithFormat:@"--%@--\r\n", boundary]);
  NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
  return [self requestWithMethod:@"POST" path:path query:nil headers:@{ @"content-type" : contentType } body:body];
}

- (ALNResponse *)requestWithMethod:(NSString *)method
                              path:(NSString *)path
                             query:(NSString *)query
                           headers:(NSDictionary<NSString *, NSString *> *)headers
                              body:(NSData *)body {
  NSMutableDictionary *requestHeaders = [NSMutableDictionary dictionary];
  for (NSString *name in headers ?: @{}) {
    requestHeaders[[name lowercaseString]] = headers[name];
  }
  if (self.automaticCSRF && !ALNTestClientIsSafeMethod(method)) {
    NSString *headerName = [self csrfHeaderName];
    if (headerName != nil && requestHeaders[headerName] == nil) {
      NSString *token = [self csrfToken];
      if (token != nil) {
        requestHeaders[headerName] = token;
      }
    }
  }
  if ([self.jar count] > 0 && requestHeaders[@"cookie"] == nil) {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *name in [[self.jar allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, self.jar[name]]];
    }
    requestHeaders[@"cookie"] = [pairs componentsJoinedByString:@"; "];
  }
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:[method uppercaseString]
                                                      path:path
                                               queryString:query ?: @""
                                                   headers:requestHeaders
                                                      body:body ?: [NSData data]];
  request.remoteAddress = @"127.0.0.1";
  request.effectiveRemoteAddress = @"127.0.0.1";
  ALNResponse *response = [self.application dispatchRequest:request];
  [self storeCookiesFromResponse:response];
  return response;
}

- (void)storeCookiesFromResponse:(ALNResponse *)response {
  for (NSString *setCookie in [response headerValuesForName:@"Set-Cookie"]) {
    NSArray *parts = [setCookie componentsSeparatedByString:@";"];
    NSString *pair = [[parts firstObject] stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceCharacterSet]];
    NSRange equals = [pair rangeOfString:@"="];
    if (equals.location == NSNotFound || equals.location == 0) {
      continue;
    }
    NSString *name = [pair substringToIndex:equals.location];
    BOOL expired = NO;
    for (NSString *attribute in parts) {
      NSString *trimmed = [[attribute stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
          lowercaseString];
      if ([trimmed isEqualToString:@"max-age=0"] || [trimmed hasPrefix:@"max-age=-"]) {
        expired = YES;
      }
    }
    if (expired) {
      [self.jar removeObjectForKey:name];
    } else {
      self.jar[name] = [pair substringFromIndex:equals.location + 1];
    }
  }
}

#pragma mark - Session

- (ALNSessionMiddleware *)sessionMiddleware {
  for (id middleware in self.application.middlewares) {
    if ([middleware isKindOfClass:[ALNSessionMiddleware class]]) {
      return middleware;
    }
  }
  return nil;
}

- (NSString *)csrfHeaderName {
  NSDictionary *csrf = [self.application.config[@"csrf"] isKindOfClass:[NSDictionary class]]
                           ? self.application.config[@"csrf"]
                           : @{};
  NSDictionary *session = [self.application.config[@"session"] isKindOfClass:[NSDictionary class]]
                              ? self.application.config[@"session"]
                              : @{};
  BOOL enabled = csrf[@"enabled"] != nil ? [csrf[@"enabled"] boolValue] : [session[@"enabled"] boolValue];
  if (!enabled || [self sessionMiddleware] == nil) {
    return nil;
  }
  NSString *name = [csrf[@"headerName"] isKindOfClass:[NSString class]] ? csrf[@"headerName"] : @"";
  return [name length] > 0 ? [name lowercaseString] : @"x-csrf-token";
}

- (NSDictionary *)session {
  ALNSessionMiddleware *middleware = [self sessionMiddleware];
  NSString *value = self.jar[middleware.cookieName ?: @""];
  return (middleware != nil && [value length] > 0) ? [middleware sessionDictionaryFromCookieValue:value] : nil;
}

- (BOOL)updateSession:(void (^)(NSMutableDictionary *session))update error:(NSError **)error {
  ALNSessionMiddleware *middleware = [self sessionMiddleware];
  if (middleware == nil) {
    if (error != NULL) {
      *error = ALNTestClientError(1, @"sessions are not enabled for this application");
    }
    return NO;
  }
  NSMutableDictionary *session = [[self session] mutableCopy] ?: [NSMutableDictionary dictionary];
  if (update != nil) {
    update(session);
  }
  NSString *value = [middleware encodeSessionDictionary:session];
  if ([value length] == 0) {
    if (error != NULL) {
      *error = ALNTestClientError(2, @"could not encode the session cookie");
    }
    return NO;
  }
  self.jar[middleware.cookieName] = value;
  return YES;
}

- (NSString *)csrfToken {
  NSString *token = [self session][@"_csrf_token"];
  if ([token isKindOfClass:[NSString class]] && [token length] > 0) {
    return token;
  }
  NSString *fresh = [[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]
      lowercaseString];
  BOOL stored = [self updateSession:^(NSMutableDictionary *session) {
    session[@"_csrf_token"] = fresh;
  }
                              error:NULL];
  return stored ? fresh : nil;
}

- (BOOL)signInAsSubject:(NSString *)subject
                  roles:(NSArray<NSString *> *)roles
                 scopes:(NSArray<NSString *> *)scopes
                  error:(NSError **)error {
  __block BOOL established = NO;
  __block NSError *authError = nil;
  BOOL stored = [self updateSession:^(NSMutableDictionary *session) {
    NSMutableDictionary *stash = [NSMutableDictionary dictionaryWithObject:session forKey:ALNContextSessionStashKey];
    ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"POST"
                                                        path:@"/"
                                                 queryString:@""
                                                     headers:@{}
                                                        body:[NSData data]];
    ALNContext *context = [[ALNContext alloc] initWithRequest:request
                                                     response:[[ALNResponse alloc] init]
                                                       params:@{}
                                                        stash:stash
                                                       logger:self.application.logger
                                                    perfTrace:[[ALNPerfTrace alloc] initWithEnabled:NO]
                                                    routeName:@""
                                               controllerName:@""
                                                   actionName:@""];
    established = [ALNAuthSession establishAuthenticatedSessionForSubject:subject
                                                                 provider:@"test"
                                                                  methods:@[ @"test" ]
                                                                   scopes:scopes ?: @[]
                                                                    roles:roles ?: @[]
                                                           assuranceLevel:1
                                                          authenticatedAt:[NSDate date]
                                                                  context:context
                                                                    error:&authError];
    // The context may replace the stashed dictionary (for example on session
    // rotation), so copy its final contents back into the jar's session.
    NSDictionary *updated = [[context session] copy];
    [session removeAllObjects];
    [session addEntriesFromDictionary:updated ?: @{}];
  }
                              error:error];
  if (stored && !established && error != NULL) {
    *error = authError ?: ALNTestClientError(3, @"could not establish the authenticated session");
  }
  return stored && established;
}

@end

@implementation ALNResponse (ALNTestClient)

- (NSString *)bodyText {
  NSData *data = [self bodyDataForTransmission];
  return [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
}

- (id)JSONObject {
  NSData *data = [self bodyDataForTransmission];
  if ([data length] == 0) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

@end
