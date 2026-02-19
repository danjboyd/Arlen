#import "ALNContext.h"

#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNLogger.h"
#import "ALNPerf.h"

NSString *const ALNContextSessionStashKey = @"aln.session";
NSString *const ALNContextSessionDirtyStashKey = @"aln.session.dirty";
NSString *const ALNContextSessionHadCookieStashKey = @"aln.session.had_cookie";
NSString *const ALNContextCSRFTokenStashKey = @"aln.csrf.token";

@interface ALNContext ()

@property(nonatomic, strong, readwrite) ALNRequest *request;
@property(nonatomic, strong, readwrite) ALNResponse *response;
@property(nonatomic, copy, readwrite) NSDictionary *params;
@property(nonatomic, strong, readwrite) NSMutableDictionary *stash;
@property(nonatomic, strong, readwrite) ALNLogger *logger;
@property(nonatomic, strong, readwrite) ALNPerfTrace *perfTrace;
@property(nonatomic, copy, readwrite) NSString *routeName;
@property(nonatomic, copy, readwrite) NSString *controllerName;
@property(nonatomic, copy, readwrite) NSString *actionName;

@end

@implementation ALNContext

- (instancetype)initWithRequest:(ALNRequest *)request
                       response:(ALNResponse *)response
                         params:(NSDictionary *)params
                          stash:(NSMutableDictionary *)stash
                         logger:(ALNLogger *)logger
                      perfTrace:(ALNPerfTrace *)perfTrace
                      routeName:(NSString *)routeName
                 controllerName:(NSString *)controllerName
                     actionName:(NSString *)actionName {
  self = [super init];
  if (self) {
    _request = request;
    _response = response;
    _params = [params copy] ?: @{};
    _stash = stash ?: [NSMutableDictionary dictionary];
    _logger = logger;
    _perfTrace = perfTrace;
    _routeName = [routeName copy] ?: @"";
    _controllerName = [controllerName copy] ?: @"";
    _actionName = [actionName copy] ?: @"";
  }
  return self;
}

- (NSMutableDictionary *)session {
  id current = self.stash[ALNContextSessionStashKey];
  if ([current isKindOfClass:[NSMutableDictionary class]]) {
    return current;
  }
  if ([current isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *mutable = [NSMutableDictionary dictionaryWithDictionary:current];
    self.stash[ALNContextSessionStashKey] = mutable;
    return mutable;
  }
  NSMutableDictionary *empty = [NSMutableDictionary dictionary];
  self.stash[ALNContextSessionStashKey] = empty;
  return empty;
}

- (void)markSessionDirty {
  self.stash[ALNContextSessionDirtyStashKey] = @(YES);
}

- (NSString *)csrfToken {
  id stashToken = self.stash[ALNContextCSRFTokenStashKey];
  if ([stashToken isKindOfClass:[NSString class]] && [stashToken length] > 0) {
    return stashToken;
  }

  id sessionToken = [self session][@"_csrf_token"];
  if ([sessionToken isKindOfClass:[NSString class]] && [sessionToken length] > 0) {
    self.stash[ALNContextCSRFTokenStashKey] = sessionToken;
    return sessionToken;
  }
  return nil;
}

@end
