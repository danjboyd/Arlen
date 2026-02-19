#import "ALNContext.h"

#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNLogger.h"
#import "ALNPerf.h"

NSString *const ALNContextSessionStashKey = @"aln.session";
NSString *const ALNContextSessionDirtyStashKey = @"aln.session.dirty";
NSString *const ALNContextSessionHadCookieStashKey = @"aln.session.had_cookie";
NSString *const ALNContextCSRFTokenStashKey = @"aln.csrf.token";
NSString *const ALNContextValidationErrorsStashKey = @"aln.validation.errors";

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

static BOOL ALNStringRepresentsInteger(NSString *value, NSInteger *parsed) {
  if ([value length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  NSInteger tmp = 0;
  if (![scanner scanInteger:&tmp]) {
    return NO;
  }
  if (![scanner isAtEnd]) {
    return NO;
  }
  if (parsed != NULL) {
    *parsed = tmp;
  }
  return YES;
}

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

- (NSDictionary *)allParams {
  NSMutableDictionary *combined =
      [NSMutableDictionary dictionaryWithDictionary:self.request.queryParams ?: @{}];
  [combined addEntriesFromDictionary:self.params ?: @{}];
  return [NSDictionary dictionaryWithDictionary:combined];
}

- (id)paramValueForName:(NSString *)name {
  if ([name length] == 0) {
    return nil;
  }
  NSDictionary *combined = [self allParams];
  return combined[name];
}

- (NSString *)stringParamForName:(NSString *)name {
  id value = [self paramValueForName:name];
  if (value == nil || value == [NSNull null]) {
    return nil;
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(description)]) {
    return [value description];
  }
  return nil;
}

- (BOOL)requireStringParam:(NSString *)name value:(NSString **)value {
  NSString *found = [self stringParamForName:name];
  if ([found length] == 0) {
    [self addValidationErrorForField:name
                                code:@"missing"
                             message:@"is required"];
    return NO;
  }
  if (value != NULL) {
    *value = found;
  }
  return YES;
}

- (BOOL)requireIntegerParam:(NSString *)name value:(NSInteger *)value {
  NSString *raw = [self stringParamForName:name];
  if ([raw length] == 0) {
    [self addValidationErrorForField:name
                                code:@"missing"
                             message:@"is required"];
    return NO;
  }
  NSInteger parsed = 0;
  if (!ALNStringRepresentsInteger(raw, &parsed)) {
    [self addValidationErrorForField:name
                                code:@"invalid_integer"
                             message:@"must be an integer"];
    return NO;
  }
  if (value != NULL) {
    *value = parsed;
  }
  return YES;
}

- (void)addValidationErrorForField:(NSString *)field
                              code:(NSString *)code
                           message:(NSString *)message {
  NSMutableArray *errors = nil;
  id current = self.stash[ALNContextValidationErrorsStashKey];
  if ([current isKindOfClass:[NSMutableArray class]]) {
    errors = current;
  } else if ([current isKindOfClass:[NSArray class]]) {
    errors = [NSMutableArray arrayWithArray:current];
  } else {
    errors = [NSMutableArray array];
  }

  [errors addObject:@{
    @"field" : field ?: @"",
    @"code" : code ?: @"invalid",
    @"message" : message ?: @"invalid value",
  }];
  self.stash[ALNContextValidationErrorsStashKey] = errors;
}

- (NSArray *)validationErrors {
  id current = self.stash[ALNContextValidationErrorsStashKey];
  if ([current isKindOfClass:[NSArray class]]) {
    return [NSArray arrayWithArray:current];
  }
  return @[];
}

@end
