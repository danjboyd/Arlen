#import "ALNContext.h"

#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNPageState.h"

NSString *const ALNContextSessionStashKey = @"aln.session";
NSString *const ALNContextSessionDirtyStashKey = @"aln.session.dirty";
NSString *const ALNContextSessionHadCookieStashKey = @"aln.session.had_cookie";
NSString *const ALNContextCSRFTokenStashKey = @"aln.csrf.token";
NSString *const ALNContextValidationErrorsStashKey = @"aln.validation.errors";
NSString *const ALNContextEOCStrictLocalsStashKey = @"aln.eoc.strict_locals";
NSString *const ALNContextEOCStrictStringifyStashKey = @"aln.eoc.strict_stringify";
NSString *const ALNContextRequestFormatStashKey = @"aln.request.format";
NSString *const ALNContextValidatedParamsStashKey = @"aln.contract.validated_params";
NSString *const ALNContextAuthClaimsStashKey = @"aln.auth.claims";
NSString *const ALNContextAuthScopesStashKey = @"aln.auth.scopes";
NSString *const ALNContextAuthRolesStashKey = @"aln.auth.roles";
NSString *const ALNContextAuthSubjectStashKey = @"aln.auth.subject";
NSString *const ALNContextPageStateEnabledStashKey = @"aln.compat.page_state_enabled";
NSString *const ALNContextJobsAdapterStashKey = @"aln.services.jobs";
NSString *const ALNContextCacheAdapterStashKey = @"aln.services.cache";
NSString *const ALNContextLocalizationAdapterStashKey = @"aln.services.i18n";
NSString *const ALNContextMailAdapterStashKey = @"aln.services.mail";
NSString *const ALNContextAttachmentAdapterStashKey = @"aln.services.attachment";
NSString *const ALNContextI18nDefaultLocaleStashKey = @"aln.services.i18n.default_locale";
NSString *const ALNContextI18nFallbackLocaleStashKey = @"aln.services.i18n.fallback_locale";

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

static BOOL ALNStringRepresentsBoolean(NSString *value, BOOL *parsed) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSString *normalized = [[value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    if (parsed != NULL) {
      *parsed = YES;
    }
    return YES;
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    if (parsed != NULL) {
      *parsed = NO;
    }
    return YES;
  }
  return NO;
}

static NSString *ALNStringFromValue(id value) {
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

static NSString *ALNNormalizeETag(NSString *etag) {
  if (![etag isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed =
      [etag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }
  BOOL weak = [trimmed hasPrefix:@"W/"];
  NSString *token = weak ? [trimmed substringFromIndex:2] : trimmed;
  token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (![token hasPrefix:@"\""]) {
    token = [NSString stringWithFormat:@"\"%@\"", token];
  } else if (![token hasSuffix:@"\""] && [token length] > 1) {
    token = [token stringByAppendingString:@"\""];
  }
  return weak ? [NSString stringWithFormat:@"W/%@", token] : token;
}

static NSString *ALNComparableETagToken(NSString *tag) {
  NSString *normalized = ALNNormalizeETag(tag);
  if ([normalized length] == 0) {
    return @"";
  }
  if ([normalized hasPrefix:@"W/"]) {
    normalized = [normalized substringFromIndex:2];
  }
  return normalized;
}

static BOOL ALNETagListMatches(NSString *ifNoneMatchHeader, NSString *etag) {
  if (![ifNoneMatchHeader isKindOfClass:[NSString class]] || [ifNoneMatchHeader length] == 0 ||
      [etag length] == 0) {
    return NO;
  }
  NSString *comparableETag = ALNComparableETagToken(etag);
  NSArray *parts = [ifNoneMatchHeader componentsSeparatedByString:@","];
  for (NSString *part in parts) {
    NSString *token =
        [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([token isEqualToString:@"*"]) {
      return YES;
    }
    if ([token isEqualToString:etag]) {
      return YES;
    }
    if ([[ALNComparableETagToken(token) lowercaseString]
            isEqualToString:[comparableETag lowercaseString]]) {
      return YES;
    }
  }
  return NO;
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
  id validated = self.stash[ALNContextValidatedParamsStashKey];
  if ([validated isKindOfClass:[NSDictionary class]]) {
    [combined addEntriesFromDictionary:validated];
  }
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
  return ALNStringFromValue(value);
}

- (NSString *)queryValueForName:(NSString *)name {
  if ([name length] == 0) {
    return nil;
  }
  return ALNStringFromValue(self.request.queryParams[name]);
}

- (NSString *)headerValueForName:(NSString *)name {
  if ([name length] == 0) {
    return nil;
  }
  NSString *normalized = [[name lowercaseString] copy];
  id value = self.request.headers[normalized];
  if (value == nil) {
    value = self.request.headers[name];
  }
  return ALNStringFromValue(value);
}

- (NSNumber *)queryIntegerForName:(NSString *)name {
  NSString *raw = [self queryValueForName:name];
  NSInteger parsed = 0;
  if (!ALNStringRepresentsInteger(raw, &parsed)) {
    return nil;
  }
  return @(parsed);
}

- (NSNumber *)queryBooleanForName:(NSString *)name {
  NSString *raw = [self queryValueForName:name];
  BOOL parsed = NO;
  if (!ALNStringRepresentsBoolean(raw, &parsed)) {
    return nil;
  }
  return @(parsed);
}

- (NSNumber *)headerIntegerForName:(NSString *)name {
  NSString *raw = [self headerValueForName:name];
  NSInteger parsed = 0;
  if (!ALNStringRepresentsInteger(raw, &parsed)) {
    return nil;
  }
  return @(parsed);
}

- (NSNumber *)headerBooleanForName:(NSString *)name {
  NSString *raw = [self headerValueForName:name];
  BOOL parsed = NO;
  if (!ALNStringRepresentsBoolean(raw, &parsed)) {
    return nil;
  }
  return @(parsed);
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

- (BOOL)applyETagAndReturnNotModifiedIfMatch:(NSString *)etag {
  NSString *normalized = ALNNormalizeETag(etag);
  if ([normalized length] == 0) {
    return NO;
  }

  [self.response setHeader:@"ETag" value:normalized];
  NSString *ifNoneMatch = [self headerValueForName:@"if-none-match"];
  if (!ALNETagListMatches(ifNoneMatch, normalized)) {
    return NO;
  }

  self.response.statusCode = 304;
  [self.response.bodyData setLength:0];
  self.response.committed = YES;
  return YES;
}

- (NSString *)requestFormat {
  id stashValue = self.stash[ALNContextRequestFormatStashKey];
  if ([stashValue isKindOfClass:[NSString class]] && [stashValue length] > 0) {
    return [stashValue lowercaseString];
  }

  NSString *accept = [self.request.headers[@"accept"] isKindOfClass:[NSString class]]
                         ? [self.request.headers[@"accept"] lowercaseString]
                         : @"";
  if ([accept containsString:@"application/json"] || [accept containsString:@"text/json"] ||
      [self.request.path hasPrefix:@"/api/"] || [self.request.path isEqualToString:@"/api"]) {
    return @"json";
  }
  return @"html";
}

- (BOOL)wantsJSON {
  return [[self requestFormat] isEqualToString:@"json"];
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

- (NSDictionary *)validatedParams {
  id value = self.stash[ALNContextValidatedParamsStashKey];
  if ([value isKindOfClass:[NSDictionary class]]) {
    return value;
  }
  return @{};
}

- (id)validatedValueForName:(NSString *)name {
  if ([name length] == 0) {
    return nil;
  }
  return [self validatedParams][name];
}

- (NSDictionary *)authClaims {
  id value = self.stash[ALNContextAuthClaimsStashKey];
  if ([value isKindOfClass:[NSDictionary class]]) {
    return value;
  }
  return nil;
}

- (NSArray *)authScopes {
  id value = self.stash[ALNContextAuthScopesStashKey];
  if ([value isKindOfClass:[NSArray class]]) {
    return value;
  }
  return @[];
}

- (NSArray *)authRoles {
  id value = self.stash[ALNContextAuthRolesStashKey];
  if ([value isKindOfClass:[NSArray class]]) {
    return value;
  }
  return @[];
}

- (NSString *)authSubject {
  id value = self.stash[ALNContextAuthSubjectStashKey];
  if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
    return value;
  }
  NSDictionary *claims = [self authClaims];
  id subject = claims[@"sub"];
  if ([subject isKindOfClass:[NSString class]] && [subject length] > 0) {
    return subject;
  }
  return nil;
}

- (id<ALNJobAdapter>)jobsAdapter {
  id value = self.stash[ALNContextJobsAdapterStashKey];
  if ([value conformsToProtocol:@protocol(ALNJobAdapter)]) {
    return value;
  }
  return nil;
}

- (id<ALNCacheAdapter>)cacheAdapter {
  id value = self.stash[ALNContextCacheAdapterStashKey];
  if ([value conformsToProtocol:@protocol(ALNCacheAdapter)]) {
    return value;
  }
  return nil;
}

- (id<ALNLocalizationAdapter>)localizationAdapter {
  id value = self.stash[ALNContextLocalizationAdapterStashKey];
  if ([value conformsToProtocol:@protocol(ALNLocalizationAdapter)]) {
    return value;
  }
  return nil;
}

- (id<ALNMailAdapter>)mailAdapter {
  id value = self.stash[ALNContextMailAdapterStashKey];
  if ([value conformsToProtocol:@protocol(ALNMailAdapter)]) {
    return value;
  }
  return nil;
}

- (id<ALNAttachmentAdapter>)attachmentAdapter {
  id value = self.stash[ALNContextAttachmentAdapterStashKey];
  if ([value conformsToProtocol:@protocol(ALNAttachmentAdapter)]) {
    return value;
  }
  return nil;
}

- (NSString *)localizedStringForKey:(NSString *)key
                             locale:(NSString *)locale
                     fallbackLocale:(NSString *)fallbackLocale
                       defaultValue:(NSString *)defaultValue
                          arguments:(NSDictionary *)arguments {
  id<ALNLocalizationAdapter> adapter = [self localizationAdapter];
  if (adapter == nil) {
    return defaultValue ?: @"";
  }

  NSString *resolvedLocale = ([locale isKindOfClass:[NSString class]] && [locale length] > 0)
                                 ? locale
                                 : self.stash[ALNContextI18nDefaultLocaleStashKey];
  NSString *resolvedFallback =
      ([fallbackLocale isKindOfClass:[NSString class]] && [fallbackLocale length] > 0)
          ? fallbackLocale
          : self.stash[ALNContextI18nFallbackLocaleStashKey];

  if (![resolvedLocale isKindOfClass:[NSString class]]) {
    resolvedLocale = @"en";
  }
  if (![resolvedFallback isKindOfClass:[NSString class]]) {
    resolvedFallback = resolvedLocale;
  }

  return [adapter localizedStringForKey:key ?: @""
                                 locale:resolvedLocale ?: @"en"
                         fallbackLocale:resolvedFallback ?: @"en"
                           defaultValue:defaultValue ?: @""
                              arguments:arguments ?: @{}];
}

- (ALNPageState *)pageStateForKey:(NSString *)pageKey {
  return [[ALNPageState alloc] initWithContext:self pageKey:pageKey];
}

@end
