#import "ALNAuthSession.h"

#import "ALNContext.h"
#import "ALNSecurityPrimitives.h"

NSString *const ALNAuthSessionErrorDomain = @"Arlen.AuthSession.Error";

static NSString *const ALNAuthSessionStateKey = @"_auth";
static NSString *const ALNAuthSessionSubjectKey = @"subject";
static NSString *const ALNAuthSessionProviderKey = @"provider";
static NSString *const ALNAuthSessionMethodsKey = @"amr";
static NSString *const ALNAuthSessionScopesKey = @"scope";
static NSString *const ALNAuthSessionRolesKey = @"roles";
static NSString *const ALNAuthSessionAssuranceLevelKey = @"aal";
static NSString *const ALNAuthSessionAuthenticatedAtKey = @"auth_time";
static NSString *const ALNAuthSessionMFASatisfiedAtKey = @"mfa_time";
static NSString *const ALNAuthSessionIdentifierKey = @"session_id";

static NSError *ALNAuthSessionError(ALNAuthSessionErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNAuthSessionErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"auth session failed",
                         }];
}

static NSString *ALNTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSArray *ALNNormalizedMethodsArray(id rawMethods) {
  NSMutableArray *normalized = [NSMutableArray array];
  NSArray *source = nil;
  if ([rawMethods isKindOfClass:[NSArray class]]) {
    source = rawMethods;
  } else if ([rawMethods isKindOfClass:[NSString class]]) {
    source = @[ rawMethods ];
  } else {
    source = @[];
  }
  for (id value in source) {
    NSString *method = ALNTrimmedString(value);
    if ([method length] == 0) {
      continue;
    }
    method = [method lowercaseString];
    if ([normalized containsObject:method]) {
      continue;
    }
    [normalized addObject:method];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray *ALNNormalizedStringClaimsArray(id rawValues) {
  NSMutableArray *normalized = [NSMutableArray array];
  NSArray *source = nil;
  if ([rawValues isKindOfClass:[NSArray class]]) {
    source = rawValues;
  } else if ([rawValues isKindOfClass:[NSString class]]) {
    source = @[ rawValues ];
  } else {
    source = @[];
  }
  for (id value in source) {
    NSString *entry = ALNTrimmedString(value);
    if ([entry length] == 0) {
      continue;
    }
    entry = [entry lowercaseString];
    if ([normalized containsObject:entry]) {
      continue;
    }
    [normalized addObject:entry];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSDate *ALNDateFromUnixValue(id value) {
  if (![value respondsToSelector:@selector(doubleValue)]) {
    return nil;
  }
  return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
}

static NSDictionary *ALNClaimsBackedAuthState(ALNContext *context) {
  if (context == nil) {
    return nil;
  }
  NSDictionary *claims = [context.stash[ALNContextAuthClaimsStashKey] isKindOfClass:[NSDictionary class]]
                             ? context.stash[ALNContextAuthClaimsStashKey]
                             : nil;
  NSString *subject = ALNTrimmedString(context.stash[ALNContextAuthSubjectStashKey]);
  if ([subject length] == 0) {
    subject = ALNTrimmedString(claims[@"sub"]);
  }
  if ([subject length] == 0) {
    return nil;
  }

  NSString *provider = ALNTrimmedString(claims[@"iss"]);
  NSArray *methods = ALNNormalizedMethodsArray(claims[@"amr"]);
  NSArray *scopes = ALNNormalizedStringClaimsArray(context.stash[ALNContextAuthScopesStashKey]);
  if ([scopes count] == 0) {
    scopes = ALNNormalizedStringClaimsArray(claims[@"scp"]);
  }
  if ([scopes count] == 0) {
    NSString *scopeString = ALNTrimmedString(claims[@"scope"]);
    if ([scopeString length] > 0) {
      scopes = ALNNormalizedStringClaimsArray([scopeString componentsSeparatedByCharactersInSet:
                                                             [NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    }
  }
  NSArray *roles = ALNNormalizedStringClaimsArray(context.stash[ALNContextAuthRolesStashKey]);
  if ([roles count] == 0) {
    roles = ALNNormalizedStringClaimsArray(claims[@"roles"]);
  }
  NSUInteger assuranceLevel = 1;
  id aal = claims[@"aal"];
  if ([aal respondsToSelector:@selector(integerValue)] && [aal integerValue] > 0) {
    assuranceLevel = (NSUInteger)[aal integerValue];
  }

  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  state[ALNAuthSessionSubjectKey] = subject;
  if ([provider length] > 0) {
    state[ALNAuthSessionProviderKey] = provider;
  }
  state[ALNAuthSessionMethodsKey] = methods;
  state[ALNAuthSessionScopesKey] = scopes ?: @[];
  state[ALNAuthSessionRolesKey] = roles ?: @[];
  state[ALNAuthSessionAssuranceLevelKey] = @(assuranceLevel);
  NSDate *authenticatedAt = ALNDateFromUnixValue(claims[@"auth_time"]);
  if (authenticatedAt == nil) {
    authenticatedAt = ALNDateFromUnixValue(claims[@"iat"]);
  }
  if (authenticatedAt != nil) {
    state[ALNAuthSessionAuthenticatedAtKey] = @([authenticatedAt timeIntervalSince1970]);
  }
  if (assuranceLevel >= 2 && authenticatedAt != nil) {
    state[ALNAuthSessionMFASatisfiedAtKey] = @([authenticatedAt timeIntervalSince1970]);
  }
  return state;
}

static NSDictionary *ALNSessionBackedAuthState(ALNContext *context) {
  if (context == nil) {
    return nil;
  }
  NSDictionary *session = [context session];
  NSDictionary *state = [session[ALNAuthSessionStateKey] isKindOfClass:[NSDictionary class]]
                            ? session[ALNAuthSessionStateKey]
                            : nil;
  NSString *subject = ALNTrimmedString(state[ALNAuthSessionSubjectKey]);
  return ([subject length] > 0) ? state : nil;
}

static NSDictionary *ALNResolvedAuthState(ALNContext *context) {
  NSDictionary *claimsState = ALNClaimsBackedAuthState(context);
  if (claimsState != nil) {
    return claimsState;
  }
  return ALNSessionBackedAuthState(context);
}

static NSString *ALNNewSessionIdentifier(void) {
  NSData *random = ALNSecureRandomData(16);
  return ALNLowercaseHexStringFromData(random);
}

@implementation ALNAuthSession

+ (NSString *)subjectFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNTrimmedString(state[ALNAuthSessionSubjectKey]);
}

+ (NSString *)providerFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNTrimmedString(state[ALNAuthSessionProviderKey]);
}

+ (NSArray *)authenticationMethodsFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNNormalizedMethodsArray(state[ALNAuthSessionMethodsKey]);
}

+ (NSArray *)scopesFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNNormalizedStringClaimsArray(state[ALNAuthSessionScopesKey]);
}

+ (NSArray *)rolesFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNNormalizedStringClaimsArray(state[ALNAuthSessionRolesKey]);
}

+ (NSUInteger)assuranceLevelFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  id value = state[ALNAuthSessionAssuranceLevelKey];
  if ([value respondsToSelector:@selector(integerValue)] && [value integerValue] > 0) {
    return (NSUInteger)[value integerValue];
  }
  return ([self subjectFromContext:context] != nil) ? 1 : 0;
}

+ (NSDate *)primaryAuthenticatedAtFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNDateFromUnixValue(state[ALNAuthSessionAuthenticatedAtKey]);
}

+ (NSDate *)mfaAuthenticatedAtFromContext:(ALNContext *)context {
  NSDictionary *state = ALNResolvedAuthState(context);
  return ALNDateFromUnixValue(state[ALNAuthSessionMFASatisfiedAtKey]);
}

+ (NSString *)sessionIdentifierFromContext:(ALNContext *)context {
  NSDictionary *state = ALNSessionBackedAuthState(context);
  return ALNTrimmedString(state[ALNAuthSessionIdentifierKey]);
}

+ (BOOL)isMFAAuthenticatedForContext:(ALNContext *)context {
  return [self assuranceLevelFromContext:context] >= 2;
}

+ (BOOL)context:(ALNContext *)context
    satisfiesMinimumAssuranceLevel:(NSUInteger)minimumAssuranceLevel
  maximumAuthenticationAgeSeconds:(NSUInteger)maximumAuthenticationAgeSeconds
                     referenceDate:(NSDate *)referenceDate {
  if (minimumAssuranceLevel == 0 && maximumAuthenticationAgeSeconds == 0) {
    return YES;
  }
  if ([[self subjectFromContext:context] length] == 0) {
    return NO;
  }
  NSUInteger currentLevel = [self assuranceLevelFromContext:context];
  if (currentLevel < minimumAssuranceLevel) {
    return NO;
  }
  if (maximumAuthenticationAgeSeconds == 0) {
    return YES;
  }

  NSDate *now = referenceDate ?: [NSDate date];
  NSDate *relevantDate = nil;
  if (minimumAssuranceLevel >= 2) {
    relevantDate = [self mfaAuthenticatedAtFromContext:context];
  }
  if (relevantDate == nil) {
    relevantDate = [self primaryAuthenticatedAtFromContext:context];
  }
  if (relevantDate == nil) {
    return NO;
  }

  NSTimeInterval age = [now timeIntervalSinceDate:relevantDate];
  return (age >= 0.0 && age <= (NSTimeInterval)maximumAuthenticationAgeSeconds);
}

+ (BOOL)establishAuthenticatedSessionForSubject:(NSString *)subject
                                       provider:(NSString *)provider
                                        methods:(NSArray *)methods
                                         scopes:(NSArray *)scopes
                                          roles:(NSArray *)roles
                                 assuranceLevel:(NSUInteger)assuranceLevel
                                authenticatedAt:(NSDate *)authenticatedAt
                                        context:(ALNContext *)context
                                          error:(NSError **)error {
  NSString *normalizedSubject = ALNTrimmedString(subject);
  if ([normalizedSubject length] == 0 || context == nil) {
    if (error != NULL) {
      *error = ALNAuthSessionError(ALNAuthSessionErrorInvalidArgument,
                                   @"Authenticated session requires a non-empty subject");
    }
    return NO;
  }

  NSUInteger normalizedLevel = (assuranceLevel > 0) ? assuranceLevel : 1;
  NSArray *normalizedMethods = ALNNormalizedMethodsArray(methods);
  if ([normalizedMethods count] == 0) {
    normalizedMethods = @[ @"pwd" ];
  }
  NSArray *normalizedScopes = ALNNormalizedStringClaimsArray(scopes);
  NSArray *normalizedRoles = ALNNormalizedStringClaimsArray(roles);
  NSDate *timestamp = authenticatedAt ?: [NSDate date];
  NSString *sessionID = ALNNewSessionIdentifier();
  if ([sessionID length] == 0) {
    if (error != NULL) {
      *error = ALNAuthSessionError(ALNAuthSessionErrorRandomGenerationFailed,
                                   @"Failed to create a new authenticated session identifier");
    }
    return NO;
  }

  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  state[ALNAuthSessionSubjectKey] = normalizedSubject;
  NSString *normalizedProvider = ALNTrimmedString(provider);
  if ([normalizedProvider length] > 0) {
    state[ALNAuthSessionProviderKey] = normalizedProvider;
  }
  state[ALNAuthSessionMethodsKey] = normalizedMethods;
  state[ALNAuthSessionScopesKey] = normalizedScopes ?: @[];
  state[ALNAuthSessionRolesKey] = normalizedRoles ?: @[];
  state[ALNAuthSessionAssuranceLevelKey] = @(normalizedLevel);
  state[ALNAuthSessionAuthenticatedAtKey] = @([timestamp timeIntervalSince1970]);
  if (normalizedLevel >= 2) {
    state[ALNAuthSessionMFASatisfiedAtKey] = @([timestamp timeIntervalSince1970]);
  }
  state[ALNAuthSessionIdentifierKey] = sessionID;

  NSMutableDictionary *session = [context session];
  session[ALNAuthSessionStateKey] = state;
  [context markSessionDirty];
  return YES;
}

+ (BOOL)establishAuthenticatedSessionForSubject:(NSString *)subject
                                       provider:(NSString *)provider
                                        methods:(NSArray *)methods
                                 assuranceLevel:(NSUInteger)assuranceLevel
                                authenticatedAt:(NSDate *)authenticatedAt
                                        context:(ALNContext *)context
                                          error:(NSError **)error {
  return [self establishAuthenticatedSessionForSubject:subject
                                              provider:provider
                                               methods:methods
                                                scopes:nil
                                                 roles:nil
                                        assuranceLevel:assuranceLevel
                                       authenticatedAt:authenticatedAt
                                               context:context
                                                 error:error];
}

+ (BOOL)elevateAuthenticatedSessionForMethod:(NSString *)method
                              assuranceLevel:(NSUInteger)assuranceLevel
                             authenticatedAt:(NSDate *)authenticatedAt
                                     context:(ALNContext *)context
                                       error:(NSError **)error {
  if (context == nil) {
    if (error != NULL) {
      *error = ALNAuthSessionError(ALNAuthSessionErrorInvalidArgument, @"Context is required");
    }
    return NO;
  }
  NSMutableDictionary *session = [context session];
  NSMutableDictionary *state =
      [session[ALNAuthSessionStateKey] isKindOfClass:[NSDictionary class]]
          ? [NSMutableDictionary dictionaryWithDictionary:session[ALNAuthSessionStateKey]]
          : nil;
  NSString *subject = ALNTrimmedString(state[ALNAuthSessionSubjectKey]);
  if ([subject length] == 0) {
    if (error != NULL) {
      *error = ALNAuthSessionError(ALNAuthSessionErrorMissingAuthenticatedSession,
                                   @"No authenticated session is available to elevate");
    }
    return NO;
  }

  NSString *normalizedMethod = [[ALNTrimmedString(method) lowercaseString] copy];
  if ([normalizedMethod length] == 0) {
    if (error != NULL) {
      *error = ALNAuthSessionError(ALNAuthSessionErrorInvalidArgument,
                                   @"Step-up requires a non-empty authentication method");
    }
    return NO;
  }

  NSMutableArray *methods =
      [NSMutableArray arrayWithArray:ALNNormalizedMethodsArray(state[ALNAuthSessionMethodsKey])];
  if (![methods containsObject:normalizedMethod]) {
    [methods addObject:normalizedMethod];
  }

  NSDate *timestamp = authenticatedAt ?: [NSDate date];
  NSUInteger currentLevel =
      [state[ALNAuthSessionAssuranceLevelKey] respondsToSelector:@selector(integerValue)]
          ? (NSUInteger)[state[ALNAuthSessionAssuranceLevelKey] integerValue]
          : 1;
  NSUInteger elevatedLevel = MAX(MAX(currentLevel, assuranceLevel), 2U);
  NSString *sessionID = ALNNewSessionIdentifier();
  if ([sessionID length] == 0) {
    if (error != NULL) {
      *error = ALNAuthSessionError(ALNAuthSessionErrorRandomGenerationFailed,
                                   @"Failed to rotate authenticated session identifier");
    }
    return NO;
  }

  state[ALNAuthSessionMethodsKey] = methods;
  state[ALNAuthSessionAssuranceLevelKey] = @(elevatedLevel);
  state[ALNAuthSessionMFASatisfiedAtKey] = @([timestamp timeIntervalSince1970]);
  state[ALNAuthSessionIdentifierKey] = sessionID;
  session[ALNAuthSessionStateKey] = state;
  [context markSessionDirty];
  return YES;
}

+ (void)clearAuthenticatedSessionForContext:(ALNContext *)context {
  if (context == nil) {
    return;
  }
  NSMutableDictionary *session = [context session];
  if (session[ALNAuthSessionStateKey] != nil) {
    [session removeObjectForKey:ALNAuthSessionStateKey];
    [context markSessionDirty];
  }
}

@end
