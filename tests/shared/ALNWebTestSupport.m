#import "ALNWebTestSupport.h"

#import "ALNRouter.h"

static NSString *const ALNWebTestSupportErrorDomain = @"Arlen.WebTestSupport.Error";

static NSError *ALNWebTestSupportMakeError(NSString *message, NSDictionary *userInfo) {
  return [NSError errorWithDomain:ALNWebTestSupportErrorDomain
                             code:1
                         userInfo:userInfo != nil
                                      ? userInfo
                                      : @{
                                          NSLocalizedDescriptionKey :
                                              message ?: @"web test support error",
                                        }];
}

static NSString *ALNWebTestSupportHeaderKey(NSDictionary *headers, NSString *name) {
  if (![headers isKindOfClass:[NSDictionary class]] || ![name isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *needle = [name lowercaseString];
  for (id key in headers) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    if ([[key lowercaseString] isEqualToString:needle]) {
      return key;
    }
  }
  return nil;
}

ALNRequest *ALNTestRequestWithMethod(NSString *method,
                                     NSString *path,
                                     NSString *queryString,
                                     NSDictionary *headers,
                                     NSData *body) {
  return [[ALNRequest alloc] initWithMethod:[method isKindOfClass:[NSString class]] ? method : @"GET"
                                      path:[path isKindOfClass:[NSString class]] ? path : @"/"
                               queryString:[queryString isKindOfClass:[NSString class]] ? queryString : @""
                                   headers:[headers isKindOfClass:[NSDictionary class]] ? headers : @{}
                                      body:[body isKindOfClass:[NSData class]] ? body : [NSData data]];
}

ALNRequest *ALNTestJSONRequestWithMethod(NSString *method,
                                         NSString *path,
                                         NSString *queryString,
                                         NSDictionary *headers,
                                         id object) {
  NSMutableDictionary *resolvedHeaders =
      [[headers isKindOfClass:[NSDictionary class]] ? headers : @{} mutableCopy];
  NSString *existingContentTypeKey =
      ALNWebTestSupportHeaderKey(resolvedHeaders, @"Content-Type");
  if ([existingContentTypeKey length] == 0) {
    resolvedHeaders[@"Content-Type"] = @"application/json";
  }
  NSData *body = [NSData data];
  if (object != nil) {
    body = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] ?: [NSData data];
  }
  return ALNTestRequestWithMethod(method, path, queryString, resolvedHeaders, body);
}

NSString *ALNTestStringFromResponse(ALNResponse *response) {
  NSData *data = [response isKindOfClass:[ALNResponse class]] ? response.bodyData : nil;
  NSString *value = [[NSString alloc] initWithData:data ?: [NSData data]
                                          encoding:NSUTF8StringEncoding];
  return value ?: @"";
}

id ALNTestJSONObjectFromResponse(ALNResponse *response, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSData *data = [response isKindOfClass:[ALNResponse class]] ? response.bodyData : nil;
  if (data == nil) {
    if (error != NULL) {
      *error = ALNWebTestSupportMakeError(
          @"response is missing body data",
          @{
            NSLocalizedDescriptionKey : @"response is missing body data",
          });
    }
    return nil;
  }

  NSError *jsonError = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (object == nil && error != NULL) {
    *error = jsonError;
  }
  return object;
}

NSDictionary *ALNTestJSONDictionaryFromResponse(ALNResponse *response, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  id object = ALNTestJSONObjectFromResponse(response, error);
  if (![object isKindOfClass:[NSDictionary class]]) {
    if (object != nil && error != NULL) {
      *error = ALNWebTestSupportMakeError(
          @"response JSON payload must be a dictionary",
          @{
            NSLocalizedDescriptionKey : @"response JSON payload must be a dictionary",
          });
    }
    return nil;
  }
  return object;
}

NSArray *ALNTestJSONArrayFromResponse(ALNResponse *response, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  id object = ALNTestJSONObjectFromResponse(response, error);
  if (![object isKindOfClass:[NSArray class]]) {
    if (object != nil && error != NULL) {
      *error = ALNWebTestSupportMakeError(
          @"response JSON payload must be an array",
          @{
            NSLocalizedDescriptionKey : @"response JSON payload must be an array",
          });
    }
    return nil;
  }
  return object;
}

NSString *ALNTestCookiePairFromSetCookie(NSString *setCookie) {
  NSString *value = [setCookie isKindOfClass:[NSString class]] ? setCookie : @"";
  NSArray *parts = [value componentsSeparatedByString:@";"];
  if ([parts count] == 0) {
    return @"";
  }
  NSString *pair = [parts[0] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [pair isKindOfClass:[NSString class]] ? pair : @"";
}

@interface ALNWebTestHarness ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mutableRecycledCookies;

@end

@implementation ALNWebTestHarness

- (instancetype)initWithApplication:(ALNApplication *)application {
  self = [super init];
  if (self != nil) {
    _application = application;
    _mutableRecycledCookies = [NSMutableDictionary dictionary];
  }
  return self;
}

+ (instancetype)harnessWithApplication:(ALNApplication *)application {
  return [[self alloc] initWithApplication:application];
}

+ (instancetype)harnessWithConfig:(NSDictionary *)config
                      routeMethod:(NSString *)method
                             path:(NSString *)path
                        routeName:(NSString *)routeName
                  controllerClass:(Class)controllerClass
                           action:(NSString *)action
                      middlewares:(NSArray *)middlewares {
  ALNApplication *application =
      [[ALNApplication alloc] initWithConfig:[config isKindOfClass:[NSDictionary class]] ? config : @{}];
  for (id middleware in [middlewares isKindOfClass:[NSArray class]] ? middlewares : @[]) {
    if ([middleware conformsToProtocol:@protocol(ALNMiddleware)]) {
      [application addMiddleware:middleware];
    }
  }
  [application registerRouteMethod:[method isKindOfClass:[NSString class]] ? method : @"GET"
                              path:[path isKindOfClass:[NSString class]] ? path : @"/"
                              name:[routeName isKindOfClass:[NSString class]] ? routeName : nil
                   controllerClass:controllerClass
                            action:[action isKindOfClass:[NSString class]] ? action : @"index"];
  return [self harnessWithApplication:application];
}

- (NSDictionary<NSString *, NSString *> *)recycledCookies {
  return [self.mutableRecycledCookies copy];
}

- (NSString *)recycledCookieHeaderValue {
  if ([self.mutableRecycledCookies count] == 0) {
    return @"";
  }
  NSMutableArray<NSString *> *pairs = [NSMutableArray array];
  for (NSString *name in [[self.mutableRecycledCookies allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *value = self.mutableRecycledCookies[name];
    if ([name length] == 0 || ![value isKindOfClass:[NSString class]]) {
      continue;
    }
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, value]];
  }
  return [pairs componentsJoinedByString:@"; "];
}

- (ALNResponse *)dispatchMethod:(NSString *)method path:(NSString *)path {
  return [self dispatchMethod:method path:path queryString:@"" headers:@{} body:nil];
}

- (ALNResponse *)dispatchMethod:(NSString *)method
                           path:(NSString *)path
                    queryString:(NSString *)queryString
                        headers:(NSDictionary *)headers
                           body:(NSData *)body {
  NSMutableDictionary *resolvedHeaders =
      [[headers isKindOfClass:[NSDictionary class]] ? headers : @{} mutableCopy];
  NSString *recycledCookieHeader = [self recycledCookieHeaderValue];
  if ([recycledCookieHeader length] > 0) {
    NSString *cookieKey = ALNWebTestSupportHeaderKey(resolvedHeaders, @"Cookie");
    if ([cookieKey length] == 0) {
      resolvedHeaders[@"Cookie"] = recycledCookieHeader;
    } else {
      NSString *existingValue =
          [resolvedHeaders[cookieKey] isKindOfClass:[NSString class]] ? resolvedHeaders[cookieKey] : @"";
      resolvedHeaders[cookieKey] =
          [existingValue length] > 0
              ? [NSString stringWithFormat:@"%@; %@", existingValue, recycledCookieHeader]
              : recycledCookieHeader;
    }
  }
  ALNRequest *request = ALNTestRequestWithMethod(method, path, queryString, resolvedHeaders, body);
  return [self dispatchRequest:request recycleCookies:NO];
}

- (ALNResponse *)dispatchJSONMethod:(NSString *)method
                               path:(NSString *)path
                        queryString:(NSString *)queryString
                            headers:(NSDictionary *)headers
                         JSONObject:(id)object {
  ALNRequest *request = ALNTestJSONRequestWithMethod(method, path, queryString, headers, object);
  return [self dispatchRequest:request recycleCookies:NO];
}

- (ALNResponse *)dispatchRequest:(ALNRequest *)request recycleCookies:(BOOL)recycleCookies {
  ALNResponse *response = [self.application dispatchRequest:request];
  if (recycleCookies) {
    [self recycleCookiesFromResponse:response];
  }
  return response;
}

- (void)recycleCookiesFromResponse:(ALNResponse *)response {
  NSString *pair = ALNTestCookiePairFromSetCookie([response headerForName:@"Set-Cookie"]);
  NSRange equalsRange = [pair rangeOfString:@"="];
  if ([pair length] == 0 || equalsRange.location == NSNotFound) {
    return;
  }
  NSString *name = [pair substringToIndex:equalsRange.location];
  NSString *value = [pair substringFromIndex:(equalsRange.location + 1)];
  if ([name length] == 0) {
    return;
  }
  self.mutableRecycledCookies[name] = value ?: @"";
}

- (void)resetRecycledState {
  [self.mutableRecycledCookies removeAllObjects];
}

- (ALNRoute *)routeNamed:(NSString *)name {
  return [self.application.router routeNamed:name];
}

- (NSArray *)routeTable {
  return [self.application routeTable];
}

- (NSArray *)middlewares {
  return [self.application middlewares];
}

- (NSArray *)modules {
  return [self.application modules];
}

@end
