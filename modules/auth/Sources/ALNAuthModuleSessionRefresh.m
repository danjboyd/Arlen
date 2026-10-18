#import "ALNAuthModule.h"

#import "ALNApplication.h"
#import "ALNAuthModuleOIDC.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNPg.h"

// Per-request session resolution for the auth module. Sessions are signed
// cookies, so the roles written at sign-in would otherwise stay in force until
// the cookie expires. Every request with a session identity is re-resolved
// against its source of truth instead: one indexed `auth_users` lookup for
// module sign-ins, or the application resolver for configured OIDC providers.
// Nothing is cached between requests.

static NSString *const ALNAuthModuleSessionStampSessionKey = @"aln.auth_module.session_stamp";

// Providers whose sessions the module itself establishes for `auth_users` rows.
// Sessions carrying a stamp record are treated the same way whatever their
// provider; this list also covers sessions issued before stamps existed.
static NSArray<NSString *> *ARModuleSessionProviders(void) {
  return @[ @"local", @"email_link", @"stub" ];
}

static NSString *ARTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// Trimmed and de-duplicated, as ALNAuthSession stores descriptor roles.
static NSArray *ARNormalizedRoles(id value, BOOL lowercase) {
  NSMutableArray *roles = [NSMutableArray array];
  for (id entry in ([value isKindOfClass:[NSArray class]] ? value : @[])) {
    NSString *role = lowercase ? [ARTrimmedString(entry) lowercaseString] : ARTrimmedString(entry);
    if ([role length] > 0 && ![roles containsObject:role]) {
      [roles addObject:role];
    }
  }
  return [NSArray arrayWithArray:roles];
}

static NSArray *ARRolesFromJSONString(id value) {
  NSData *data = [ARTrimmedString(value) dataUsingEncoding:NSUTF8StringEncoding];
  id object = ([data length] > 0) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  // Matches how the module reads roles_json everywhere else.
  return ARNormalizedRoles(object, YES);
}

static NSError *ARError(ALNAuthModuleErrorCode code, NSString *message, NSError *underlying) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"auth session refresh failed";
  if (underlying != nil) {
    userInfo[NSUnderlyingErrorKey] = underlying;
  }
  return [NSError errorWithDomain:ALNAuthModuleErrorDomain code:code userInfo:userInfo];
}

// 42P01 undefined_table, 42703 undefined_column: the auth migrations have not
// been applied to this database yet.
static NSError *ARTranslatedQueryError(NSError *error, NSString *environmentName) {
  NSString *sqlState = [error.domain isEqualToString:ALNPgErrorDomain]
                           ? ARTrimmedString(error.userInfo[ALNPgErrorSQLStateKey])
                           : @"";
  if (![sqlState isEqualToString:@"42P01"] && ![sqlState isEqualToString:@"42703"]) {
    return error ?: ARError(ALNAuthModuleErrorDatabaseUnavailable, @"auth session lookup failed", nil);
  }
  NSString *environment = [ARTrimmedString(environmentName) length] > 0 ? ARTrimmedString(environmentName)
                                                                        : @"development";
  NSString *message =
      [NSString stringWithFormat:@"Auth module tables are missing or out of date. Run ./bin/arlen module migrate --env %@.",
                                 environment];
  return ARError(ALNAuthModuleErrorInvalidConfiguration, message, error);
}

@interface ALNAuthModuleRuntime (ALNAuthModuleSessionRefreshPrivate)
- (nullable ALNPg *)database;
- (nullable NSString *)environmentName;
- (nullable NSDictionary<NSString *, ALNAuthModuleOIDC *> *)oidcProviders;
@end

@interface ALNAuthModuleSessionMiddleware : NSObject <ALNMiddleware>
@end

@implementation ALNAuthModuleSessionMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  return [[ALNAuthModuleRuntime sharedRuntime] refreshAuthenticatedSessionForContext:context error:error];
}

@end

// A plain function keeps this file linked (and its category loaded) wherever the
// module is linked from a static archive.
void ALNAuthModuleInstallSessionRefresh(ALNApplication *application) {
  for (id middleware in [application middlewares] ?: @[]) {
    if ([middleware isKindOfClass:[ALNAuthModuleSessionMiddleware class]]) {
      return;
    }
  }
  [application addMiddleware:[[ALNAuthModuleSessionMiddleware alloc] init]];
}

@implementation ALNAuthModuleRuntime (ALNAuthModuleSessionRefresh)

- (BOOL)providerSessionEstablishedForDescriptor:(NSDictionary *)sessionDescriptor
                                        context:(ALNContext *)context
                                          error:(NSError **)error {
  (void)sessionDescriptor;
  return [self recordSessionStampForContext:context error:error];
}

- (BOOL)recordSessionStampForContext:(ALNContext *)context error:(NSError **)error {
  NSString *subject = ARTrimmedString([ALNAuthSession subjectFromContext:context]);
  if (context == nil || [subject length] == 0 || [self database] == nil) {
    return YES;
  }
  NSError *queryError = nil;
  NSArray *rows = [[self database] executeQuery:@"SELECT session_stamp::text AS session_stamp "
                                                 "FROM auth_users WHERE subject = $1 LIMIT 1"
                                     parameters:@[ subject ]
                                          error:&queryError];
  if (rows == nil) {
    if (error != NULL) {
      *error = ARTranslatedQueryError(queryError, [self environmentName]);
    }
    return NO;
  }
  NSDictionary *row = [rows firstObject];
  if (row == nil) {
    // Not an auth_users subject (for example a session policy hook mapped the
    // sign-in elsewhere); there is no stamp to record.
    return YES;
  }
  context.session[ALNAuthModuleSessionStampSessionKey] = @{
    @"subject" : subject,
    @"stamp" : ARTrimmedString(row[@"session_stamp"]),
  };
  [context markSessionDirty];
  return YES;
}

- (BOOL)bumpSessionStampForSubject:(NSString *)subject error:(NSError **)error {
  NSString *normalizedSubject = ARTrimmedString(subject);
  if ([normalizedSubject length] == 0) {
    if (error != NULL) {
      *error = ARError(ALNAuthModuleErrorValidationFailed, @"subject is required", nil);
    }
    return NO;
  }
  if ([self database] == nil) {
    if (error != NULL) {
      *error = ARError(ALNAuthModuleErrorDatabaseUnavailable, @"auth database is not configured", nil);
    }
    return NO;
  }
  NSError *queryError = nil;
  NSArray *rows = [[self database] executeQuery:@"UPDATE auth_users SET session_stamp = session_stamp + 1, "
                                                 "updated_at = NOW() WHERE subject = $1 RETURNING id::text AS id"
                                     parameters:@[ normalizedSubject ]
                                          error:&queryError];
  if (rows == nil) {
    if (error != NULL) {
      *error = ARTranslatedQueryError(queryError, [self environmentName]);
    }
    return NO;
  }
  if ([rows count] == 0) {
    if (error != NULL) {
      *error = ARError(ALNAuthModuleErrorNotFound, @"user not found", nil);
    }
    return NO;
  }
  return YES;
}

- (void)signOutSessionForContext:(ALNContext *)context {
  [ALNAuthSession clearAuthenticatedSessionForContext:context];
  if (context.session[ALNAuthModuleSessionStampSessionKey] != nil) {
    [context.session removeObjectForKey:ALNAuthModuleSessionStampSessionKey];
    [context markSessionDirty];
  }
  [context.stash removeObjectForKey:ALNContextAuthRolesStashKey];
}

- (BOOL)refreshAuthenticatedSessionForContext:(ALNContext *)context error:(NSError **)error {
  if (context == nil) {
    return YES;
  }
  // An identity some earlier middleware applied from bearer claims is not a
  // session identity; ALNAuth owns those.
  if (context.stash[ALNContextAuthClaimsStashKey] != nil || context.stash[ALNContextAuthSubjectStashKey] != nil) {
    return YES;
  }
  NSString *subject = ARTrimmedString([ALNAuthSession subjectFromContext:context]);
  if ([subject length] == 0) {
    return YES;
  }
  NSString *provider = ARTrimmedString([ALNAuthSession providerFromContext:context]);

  ALNAuthModuleOIDC *oidcProvider = [self oidcProviders][provider];
  if (oidcProvider != nil) {
    return [self refreshProviderSessionForContext:context
                                          subject:subject
                                         provider:provider
                                         resolver:oidcProvider.resolver
                                            error:error];
  }

  NSDictionary *record = [context.session[ALNAuthModuleSessionStampSessionKey] isKindOfClass:[NSDictionary class]]
                             ? context.session[ALNAuthModuleSessionStampSessionKey]
                             : nil;
  BOOL recordMatchesSubject = [ARTrimmedString(record[@"subject"]) isEqualToString:subject];
  if (!recordMatchesSubject && ![ARModuleSessionProviders() containsObject:provider]) {
    // Established by application code for an identity the module does not own.
    return YES;
  }
  if ([self database] == nil) {
    return YES;
  }

  NSError *queryError = nil;
  NSArray *rows = [[self database]
      executeQuery:@"SELECT id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                    "COALESCE(roles_json, '[]') AS roles_json, "
                    "CASE WHEN email_verified_at IS NULL THEN '' ELSE email_verified_at::text END AS email_verified_at, "
                    "session_stamp::text AS session_stamp "
                    "FROM auth_users WHERE subject = $1 LIMIT 1"
        parameters:@[ subject ]
             error:&queryError];
  if (rows == nil) {
    if (error != NULL) {
      *error = ARTranslatedQueryError(queryError, [self environmentName]);
    }
    return NO;
  }
  NSDictionary *row = [rows firstObject];
  if (row == nil) {
    [self signOutSessionForContext:context];
    return YES;
  }
  // Sessions without a record (issued before stamps existed, or established
  // outside the module) belong to the initial generation.
  NSString *sessionStamp = recordMatchesSubject ? ARTrimmedString(record[@"stamp"]) : @"0";
  if (![sessionStamp isEqualToString:ARTrimmedString(row[@"session_stamp"])]) {
    [self signOutSessionForContext:context];
    return YES;
  }

  NSArray *storedRoles = ARRolesFromJSONString(row[@"roles_json"]);
  NSString *verifiedAt = ARTrimmedString(row[@"email_verified_at"]);
  NSDictionary *user = @{
    @"id" : ARTrimmedString(row[@"id"]),
    @"subject" : subject,
    @"email" : [ARTrimmedString(row[@"email"]) lowercaseString],
    @"display_name" : ARTrimmedString(row[@"display_name"]),
    @"roles" : storedRoles,
    @"email_verified" : @([verifiedAt length] > 0),
    @"email_verified_at" : verifiedAt,
  };
  // The session policy hook decides session roles at sign-in; apply it to the
  // current record so hook-derived roles keep working.
  NSDictionary *defaultDescriptor = @{
    @"subject" : subject,
    @"provider" : provider,
    @"methods" : [ALNAuthSession authenticationMethodsFromContext:context] ?: @[],
    @"roles" : storedRoles,
    @"scopes" : [ALNAuthSession scopesFromContext:context] ?: @[],
    @"assuranceLevel" : @([ALNAuthSession assuranceLevelFromContext:context]),
  };
  NSDictionary *descriptor = [self sessionDescriptorForUser:user defaultDescriptor:defaultDescriptor];
  NSArray *roles = [descriptor[@"roles"] isKindOfClass:[NSArray class]] ? ARNormalizedRoles(descriptor[@"roles"], NO)
                                                                         : storedRoles;
  context.stash[ALNContextAuthRolesStashKey] = roles;
  return YES;
}

- (BOOL)refreshProviderSessionForContext:(ALNContext *)context
                                 subject:(NSString *)subject
                                provider:(NSString *)provider
                                resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                   error:(NSError **)error {
  if (![resolver respondsToSelector:@selector(refreshSessionDescriptorForSubject:provider:error:)]) {
    // The resolver does not offer refresh; the roles stored at sign-in stay in force.
    return YES;
  }
  NSError *resolverError = nil;
  NSDictionary *descriptor = [resolver refreshSessionDescriptorForSubject:subject
                                                                 provider:provider
                                                                    error:&resolverError];
  if (![descriptor isKindOfClass:[NSDictionary class]]) {
    if (resolverError != nil) {
      if (error != NULL) {
        *error = resolverError;
      }
      return NO;
    }
    [self signOutSessionForContext:context];
    return YES;
  }
  NSString *resolvedSubject = ARTrimmedString(descriptor[@"subject"]);
  if ([resolvedSubject length] > 0 && ![resolvedSubject isEqualToString:subject]) {
    [self signOutSessionForContext:context];
    return YES;
  }
  context.stash[ALNContextAuthRolesStashKey] = ARNormalizedRoles(descriptor[@"roles"], NO);
  return YES;
}

@end
