#import "ALNAuthModule.h"

#import "ALNApplication.h"
#import "ALNAuthModuleOIDC.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNLogger.h"
#import "ALNPg.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"

#import <dispatch/dispatch.h>
#import <objc/runtime.h>

// Per-request session resolution for the auth module. Sessions are signed
// cookies, so the roles written at sign-in would otherwise stay in force until
// the cookie expires. Every request with a session identity is re-resolved
// against its source of truth instead: one indexed `auth_users` lookup for
// module sign-ins, or the application resolver for configured OIDC providers.
// The same lookup refuses sessions that were signed out (`auth_revoked_sessions`)
// and sessions older than `authModule.session.absoluteLifetimeSeconds`.
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

static BOOL ARPgErrorMentions(NSError *error, NSString *sqlState, NSString *token) {
  if (![error.domain isEqualToString:ALNPgErrorDomain] ||
      ![ARTrimmedString(error.userInfo[ALNPgErrorSQLStateKey]) isEqualToString:sqlState]) {
    return NO;
  }
  if ([[error localizedDescription] containsString:token]) {
    return YES;
  }
  for (id value in [error.userInfo allValues]) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value containsString:token]) {
      return YES;
    }
  }
  return NO;
}

// True only when the error is PostgreSQL undefined_column for
// auth_users.session_stamp: the database predates 002_auth_session_stamp.sql.
// Roles and user existence can still be read live; only the stamp is skipped.
static BOOL ARErrorIsMissingSessionStampColumn(NSError *error) {
  return ARPgErrorMentions(error, @"42703", @"session_stamp");
}

// True only when the error is PostgreSQL undefined_table for
// auth_revoked_sessions: the database predates 003_auth_revoked_sessions.sql.
static BOOL ARErrorIsMissingRevokedSessionsTable(NSError *error) {
  return ARPgErrorMentions(error, @"42P01", @"auth_revoked_sessions");
}

static void ARWarnOnce(NSString *key, ALNLogger *logger, NSString *message, NSString *migration) {
  static NSMutableSet *warned = nil;
  static NSLock *lock = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [[NSLock alloc] init];
    warned = [NSMutableSet set];
  });
  [lock lock];
  BOOL alreadyWarned = [warned containsObject:key];
  [warned addObject:key];
  [lock unlock];
  if (alreadyWarned) {
    return;
  }
  if (logger != nil) {
    [logger warn:message fields:@{ @"module" : @"auth", @"migration" : migration ?: @"" }];
  } else {
    NSLog(@"auth module: %@", message);
  }
}

static NSString *AREnvironment(NSString *environmentName) {
  return [ARTrimmedString(environmentName) length] > 0 ? ARTrimmedString(environmentName) : @"development";
}

static void ARWarnMissingSessionStampColumn(ALNLogger *logger, NSString *environmentName) {
  NSString *message = [NSString stringWithFormat:
      @"auth_users.session_stamp is missing; roles are still read from the database on each request, "
       "but sessions cannot be ended by stamp. Run ./bin/arlen module migrate --env %@.", AREnvironment(environmentName)];
  ARWarnOnce(@"session_stamp", logger, message, @"002_auth_session_stamp.sql");
}

static void ARWarnMissingRevokedSessionsTable(ALNLogger *logger, NSString *environmentName) {
  NSString *message = [NSString stringWithFormat:
      @"auth_revoked_sessions is missing; signing out clears the session cookie, but other copies of a "
       "signed-out session cookie are not refused. Run ./bin/arlen module migrate --env %@.",
      AREnvironment(environmentName)];
  ARWarnOnce(@"revoked_sessions", logger, message, @"003_auth_revoked_sessions.sql");
}

static NSString *ARNewSessionRecordIdentifier(void) {
  NSData *random = ALNSecureRandomData(16);
  return ([random length] == 16) ? (ALNLowercaseHexStringFromData(random) ?: @"") : @"";
}

static NSDictionary *ARSessionRecord(ALNContext *context) {
  id record = context.session[ALNAuthModuleSessionStampSessionKey];
  return [record isKindOfClass:[NSDictionary class]] ? record : nil;
}

// The identifiers a sign-out is recorded under: the module's record identifier,
// which stays the same for the life of a sign-in, and the framework session
// identifier (which changes on step-up, and is all that sessions without a
// record carry).
static NSArray<NSString *> *ARSessionRevocationIdentifiers(ALNContext *context, NSString *subject) {
  NSMutableArray *identifiers = [NSMutableArray array];
  NSDictionary *record = ARSessionRecord(context);
  if ([ARTrimmedString(record[@"subject"]) isEqualToString:subject]) {
    NSString *recordIdentifier = ARTrimmedString(record[@"sid"]);
    if ([recordIdentifier length] > 0) {
      [identifiers addObject:recordIdentifier];
    }
  }
  NSString *sessionIdentifier = ARTrimmedString([ALNAuthSession sessionIdentifierFromContext:context]);
  if ([sessionIdentifier length] > 0 && ![identifiers containsObject:sessionIdentifier]) {
    [identifiers addObject:sessionIdentifier];
  }
  return identifiers;
}

// Which optional auth schema objects exist, probed once per database adapter
// so a database that predates a migration does not see a failing query on
// every request. A later query error that shows an object has gone clears its
// flag; applying a migration takes effect when the application restarts.
@interface ARAuthSchemaFeatures : NSObject
@property(atomic, assign) BOOL sessionStamp;
@property(atomic, assign) BOOL revokedSessions;
@end

@implementation ARAuthSchemaFeatures
@end

static char ARAuthSchemaFeaturesKey;

static NSString *const ARRevokedSessionPredicate =
    @"EXISTS (SELECT 1 FROM auth_revoked_sessions r WHERE r.session_id IN ($2, $3) AND r.expires_at > NOW())";

@interface ALNAuthModuleRuntime (ALNAuthModuleSessionRefreshPrivate)
- (nullable ALNPg *)database;
- (nullable NSString *)environmentName;
- (nullable NSDictionary<NSString *, ALNAuthModuleOIDC *> *)oidcProviders;
- (NSUInteger)sessionCookieMaxAgeSeconds;
@end

@interface ALNAuthModuleSessionMiddleware : NSObject <ALNMiddleware>
@end

@implementation ALNAuthModuleSessionMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  NSError *refreshError = nil;
  if ([[ALNAuthModuleRuntime sharedRuntime] refreshAuthenticatedSessionForContext:context error:&refreshError]) {
    return YES;
  }
  if ([refreshError.domain isEqualToString:ALNPgErrorDomain] ||
      ([refreshError.domain isEqualToString:ALNAuthModuleErrorDomain] &&
       refreshError.code == ALNAuthModuleErrorDatabaseUnavailable)) {
    context.response.statusCode = 503;
    [context.response setHeader:@"Retry-After" value:@"2"];
    [context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [context.response setTextBody:@"The sign-in service is temporarily unavailable. Try again shortly.\n"];
    context.response.committed = YES;
    return NO;
  }
  if (error != NULL) {
    *error = refreshError;
  }
  return NO;
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

// nil with `error` when the probe itself fails. While `auth_users` is missing
// (migrations not run yet) nothing is cached, so the lookup that follows
// reports the missing tables and the next request probes again.
- (ARAuthSchemaFeatures *)authSchemaFeaturesWithLogger:(ALNLogger *)logger error:(NSError **)error {
  ALNPg *database = [self database];
  if (database == nil) {
    return nil;
  }
  static NSLock *probeLock = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    probeLock = [[NSLock alloc] init];
  });
  [probeLock lock];
  ARAuthSchemaFeatures *features = objc_getAssociatedObject(database, &ARAuthSchemaFeaturesKey);
  if (features != nil) {
    [probeLock unlock];
    return features;
  }
  NSError *queryError = nil;
  NSArray *rows = [database
      executeQuery:@"SELECT CASE WHEN to_regclass('auth_users') IS NULL THEN 'f' ELSE 't' END AS users, "
                    "CASE WHEN EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('auth_users') "
                    "AND attname = 'session_stamp' AND attnum > 0 AND NOT attisdropped) THEN 't' ELSE 'f' END AS stamp, "
                    "CASE WHEN to_regclass('auth_revoked_sessions') IS NULL THEN 'f' ELSE 't' END AS revoked"
        parameters:@[]
             error:&queryError];
  if (rows == nil) {
    [probeLock unlock];
    if (error != NULL) {
      *error = ARTranslatedQueryError(queryError, [self environmentName]);
    }
    return nil;
  }
  NSDictionary *row = [rows firstObject];
  features = [[ARAuthSchemaFeatures alloc] init];
  features.sessionStamp = [ARTrimmedString(row[@"stamp"]) isEqualToString:@"t"];
  features.revokedSessions = [ARTrimmedString(row[@"revoked"]) isEqualToString:@"t"];
  BOOL usersTableExists = [ARTrimmedString(row[@"users"]) isEqualToString:@"t"];
  if (usersTableExists) {
    objc_setAssociatedObject(database, &ARAuthSchemaFeaturesKey, features, OBJC_ASSOCIATION_RETAIN);
  }
  [probeLock unlock];
  if (!usersTableExists) {
    return features;
  }
  if (!features.sessionStamp) {
    ARWarnMissingSessionStampColumn(logger, [self environmentName]);
  }
  if (!features.revokedSessions) {
    ARWarnMissingRevokedSessionsTable(logger, [self environmentName]);
  }
  return features;
}

- (BOOL)providerSessionEstablishedForDescriptor:(NSDictionary *)sessionDescriptor
                                        context:(ALNContext *)context
                                          error:(NSError **)error {
  (void)sessionDescriptor;
  return [self recordSessionStampForContext:context error:error];
}

- (BOOL)recordSessionStampForContext:(ALNContext *)context error:(NSError **)error {
  return [self recordSessionStampForContext:context preservingIdentifier:NO error:error];
}

- (BOOL)recordCurrentSessionStampForContext:(ALNContext *)context error:(NSError **)error {
  return [self recordSessionStampForContext:context preservingIdentifier:YES error:error];
}

- (BOOL)recordSessionStampForContext:(ALNContext *)context
                preservingIdentifier:(BOOL)preserveIdentifier
                               error:(NSError **)error {
  NSString *subject = ARTrimmedString([ALNAuthSession subjectFromContext:context]);
  if (context == nil || [subject length] == 0 || [self database] == nil) {
    return YES;
  }
  ARAuthSchemaFeatures *features = [self authSchemaFeaturesWithLogger:context.logger error:error];
  if (features == nil) {
    return NO;
  }
  if (!features.sessionStamp) {
    return YES;
  }
  NSError *queryError = nil;
  NSArray *rows = [[self database] executeQuery:@"SELECT session_stamp::text AS session_stamp "
                                                 "FROM auth_users WHERE subject = $1 LIMIT 1"
                                     parameters:@[ subject ]
                                          error:&queryError];
  if (rows == nil && ARErrorIsMissingSessionStampColumn(queryError)) {
    features.sessionStamp = NO;
    ARWarnMissingSessionStampColumn(context.logger, [self environmentName]);
    return YES;
  }
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
  NSDictionary *existing = ARSessionRecord(context);
  NSString *recordIdentifier = @"";
  if (preserveIdentifier && [ARTrimmedString(existing[@"subject"]) isEqualToString:subject]) {
    recordIdentifier = ARTrimmedString(existing[@"sid"]);
  }
  if ([recordIdentifier length] == 0) {
    recordIdentifier = ARNewSessionRecordIdentifier();
  }
  context.session[ALNAuthModuleSessionStampSessionKey] = @{
    @"subject" : subject,
    @"stamp" : ARTrimmedString(row[@"session_stamp"]),
    @"sid" : recordIdentifier ?: @"",
  };
  [context markSessionDirty];
  return YES;
}

- (BOOL)bumpSessionStampForUserID:(NSString *)userID
                       connection:(ALNPgConnection *)connection
                            error:(NSError **)error {
  ARAuthSchemaFeatures *features = [self authSchemaFeaturesWithLogger:nil error:error];
  if (features == nil) {
    return NO;
  }
  if (!features.sessionStamp) {
    return YES;
  }
  NSArray *noParameters = @[];
  if ([connection executeCommand:@"SAVEPOINT aln_auth_session_stamp" parameters:noParameters error:error] < 0) {
    return NO;
  }
  NSError *updateError = nil;
  NSInteger updated = [connection executeCommand:@"UPDATE auth_users SET session_stamp = session_stamp + 1, "
                                                  "updated_at = NOW() WHERE id = $1"
                                      parameters:@[ ARTrimmedString(userID) ]
                                           error:&updateError];
  if (updated < 0) {
    if (!ARErrorIsMissingSessionStampColumn(updateError)) {
      if (error != NULL) {
        *error = updateError;
      }
      return NO;
    }
    // The column has gone: keep the surrounding change, skip the stamp.
    features.sessionStamp = NO;
    ARWarnMissingSessionStampColumn(nil, [self environmentName]);
    return [connection executeCommand:@"ROLLBACK TO SAVEPOINT aln_auth_session_stamp"
                           parameters:noParameters
                                error:error] >= 0;
  }
  return [connection executeCommand:@"RELEASE SAVEPOINT aln_auth_session_stamp" parameters:noParameters error:error] >= 0;
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
  ARAuthSchemaFeatures *features = [self authSchemaFeaturesWithLogger:nil error:error];
  if (features == nil) {
    return NO;
  }
  if (!features.sessionStamp) {
    // Nothing to bump yet; current roles are still enforced on every request.
    return YES;
  }
  NSError *queryError = nil;
  NSArray *rows = [[self database] executeQuery:@"UPDATE auth_users SET session_stamp = session_stamp + 1, "
                                                 "updated_at = NOW() WHERE subject = $1 RETURNING id::text AS id"
                                     parameters:@[ normalizedSubject ]
                                          error:&queryError];
  if (rows == nil && ARErrorIsMissingSessionStampColumn(queryError)) {
    features.sessionStamp = NO;
    ARWarnMissingSessionStampColumn(nil, [self environmentName]);
    return YES;
  }
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

- (BOOL)revokeCurrentSessionForContext:(ALNContext *)context error:(NSError **)error {
  if (context == nil) {
    return YES;
  }
  NSString *subject = ARTrimmedString([ALNAuthSession subjectFromContext:context]);
  // Sessions from configured OIDC providers are checked by the application
  // resolver rather than against auth_users, so there is nothing to record.
  BOOL providerSession = ([self oidcProviders][ARTrimmedString([ALNAuthSession providerFromContext:context])] != nil);
  NSArray<NSString *> *identifiers =
      ([subject length] > 0 && !providerSession) ? ARSessionRevocationIdentifiers(context, subject) : @[];
  NSDate *authenticatedAt = [ALNAuthSession primaryAuthenticatedAtFromContext:context];
  [self signOutSessionForContext:context];
  if ([identifiers count] == 0 || [self database] == nil) {
    return YES;
  }
  ARAuthSchemaFeatures *features = [self authSchemaFeaturesWithLogger:context.logger error:error];
  if (features == nil) {
    return NO;
  }
  if (!features.revokedSessions) {
    return YES;
  }

  // Any other copy of this session cookie expires within the cookie max age
  // (and is refused after the absolute lifetime), so the record need not
  // outlive either.
  NSTimeInterval keepSeconds = (NSTimeInterval)MAX([self sessionCookieMaxAgeSeconds], (NSUInteger)60U);
  if (authenticatedAt != nil && self.absoluteSessionLifetimeSeconds > 0) {
    NSTimeInterval remaining =
        [authenticatedAt timeIntervalSinceNow] + (NSTimeInterval)self.absoluteSessionLifetimeSeconds;
    keepSeconds = MIN(keepSeconds, MAX(remaining, 60.0));
  }
  NSString *keep = [NSString stringWithFormat:@"%lld", (long long)ceil(keepSeconds)];
  for (NSString *identifier in identifiers) {
    NSError *insertError = nil;
    NSInteger inserted = [[self database]
        executeCommand:@"INSERT INTO auth_revoked_sessions (session_id, subject, expires_at) "
                        "VALUES ($1, $2, NOW() + ($3::bigint * INTERVAL '1 second')) "
                        "ON CONFLICT (session_id) DO UPDATE "
                        "SET expires_at = GREATEST(auth_revoked_sessions.expires_at, EXCLUDED.expires_at)"
            parameters:@[ identifier, subject, keep ]
                 error:&insertError];
    if (inserted < 0 && ARErrorIsMissingRevokedSessionsTable(insertError)) {
      features.revokedSessions = NO;
      ARWarnMissingRevokedSessionsTable(context.logger, [self environmentName]);
      return YES;
    }
    if (inserted < 0) {
      if (error != NULL) {
        *error = ARTranslatedQueryError(insertError, [self environmentName]);
      }
      return NO;
    }
  }
  // Opportunistic cleanup; a failure here does not affect the sign-out.
  [[self database] executeCommand:@"DELETE FROM auth_revoked_sessions WHERE expires_at <= NOW()"
                       parameters:@[]
                            error:NULL];
  return YES;
}

- (BOOL)signOutOtherSessionsForContext:(ALNContext *)context error:(NSError **)error {
  NSString *subject = ARTrimmedString([ALNAuthSession subjectFromContext:context]);
  if ([subject length] == 0) {
    if (error != NULL) {
      *error = ARError(ALNAuthModuleErrorValidationFailed, @"a signed-in session is required", nil);
    }
    return NO;
  }
  NSError *bumpError = nil;
  if (![self bumpSessionStampForSubject:subject error:&bumpError]) {
    if (bumpError.code == ALNAuthModuleErrorNotFound && [bumpError.domain isEqualToString:ALNAuthModuleErrorDomain]) {
      // Not an auth_users subject: the module holds no other sessions for it.
      return YES;
    }
    if (error != NULL) {
      *error = bumpError;
    }
    return NO;
  }
  return [self recordCurrentSessionStampForContext:context error:error];
}

- (BOOL)canEndOtherSessions {
  if ([self database] == nil) {
    return NO;
  }
  ARAuthSchemaFeatures *features = [self authSchemaFeaturesWithLogger:nil error:NULL];
  return features != nil && features.sessionStamp;
}

- (BOOL)signOutAllSessionsForContext:(ALNContext *)context error:(NSError **)error {
  NSString *subject = ARTrimmedString([ALNAuthSession subjectFromContext:context]);
  if ([subject length] == 0) {
    return YES;
  }
  NSError *bumpError = nil;
  if (![self bumpSessionStampForSubject:subject error:&bumpError] &&
      !(bumpError.code == ALNAuthModuleErrorNotFound && [bumpError.domain isEqualToString:ALNAuthModuleErrorDomain])) {
    if (error != NULL) {
      *error = bumpError;
    }
    return NO;
  }
  return [self revokeCurrentSessionForContext:context error:error];
}

- (BOOL)sessionIsWithinAbsoluteLifetime:(ALNContext *)context {
  NSUInteger lifetime = self.absoluteSessionLifetimeSeconds;
  if (lifetime == 0) {
    return YES;
  }
  NSDate *authenticatedAt = [ALNAuthSession primaryAuthenticatedAtFromContext:context];
  if (authenticatedAt == nil) {
    // Every sign-in records its time; a session without one is treated as
    // expired rather than as unlimited.
    return NO;
  }
  return -[authenticatedAt timeIntervalSinceNow] <= (NSTimeInterval)lifetime;
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
    if (![self sessionIsWithinAbsoluteLifetime:context]) {
      [self signOutSessionForContext:context];
      return YES;
    }
    return [self refreshProviderSessionForContext:context
                                          subject:subject
                                         provider:provider
                                         resolver:oidcProvider.resolver
                                            error:error];
  }

  NSDictionary *record = ARSessionRecord(context);
  BOOL recordMatchesSubject = [ARTrimmedString(record[@"subject"]) isEqualToString:subject];
  if (!recordMatchesSubject && ![ARModuleSessionProviders() containsObject:provider]) {
    // Established by application code for an identity the module does not own.
    return YES;
  }
  if (![self sessionIsWithinAbsoluteLifetime:context]) {
    [self signOutSessionForContext:context];
    return YES;
  }
  if ([self database] == nil) {
    return YES;
  }

  NSString *userColumns = @"SELECT id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                          "COALESCE(roles_json, '[]') AS roles_json, "
                          "CASE WHEN email_verified_at IS NULL THEN '' ELSE email_verified_at::text END AS email_verified_at";
  NSArray<NSString *> *revocationIdentifiers = ARSessionRevocationIdentifiers(context, subject);
  ARAuthSchemaFeatures *features = [self authSchemaFeaturesWithLogger:context.logger error:error];
  if (features == nil) {
    return NO;
  }
  BOOL stampAvailable = features.sessionStamp;
  BOOL revocationAvailable = features.revokedSessions && ([revocationIdentifiers count] > 0);
  NSError *queryError = nil;
  NSArray *rows = nil;
  // One round trip. Objects a pending migration adds are left out; if one
  // disappears after the probe, it is dropped and the lookup retried.
  for (NSUInteger attempt = 0; attempt < 3; attempt++) {
    NSMutableString *sql = [NSMutableString stringWithString:userColumns];
    NSMutableArray *parameters = [NSMutableArray arrayWithObject:subject];
    if (stampAvailable) {
      [sql appendString:@", session_stamp::text AS session_stamp"];
    }
    if (revocationAvailable) {
      [sql appendFormat:@", CASE WHEN %@ THEN 't' ELSE 'f' END AS session_revoked", ARRevokedSessionPredicate];
      [parameters addObject:revocationIdentifiers[0]];
      [parameters addObject:revocationIdentifiers[([revocationIdentifiers count] > 1) ? 1 : 0]];
    }
    [sql appendString:@" FROM auth_users WHERE subject = $1 LIMIT 1"];
    queryError = nil;
    rows = [[self database] executeQuery:sql parameters:parameters error:&queryError];
    if (rows != nil) {
      break;
    }
    if (stampAvailable && ARErrorIsMissingSessionStampColumn(queryError)) {
      // Keep reading roles and existence live.
      features.sessionStamp = NO;
      ARWarnMissingSessionStampColumn(context.logger, [self environmentName]);
      stampAvailable = NO;
      continue;
    }
    if (revocationAvailable && ARErrorIsMissingRevokedSessionsTable(queryError)) {
      features.revokedSessions = NO;
      ARWarnMissingRevokedSessionsTable(context.logger, [self environmentName]);
      revocationAvailable = NO;
      continue;
    }
    break;
  }
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
  if (stampAvailable && ![sessionStamp isEqualToString:ARTrimmedString(row[@"session_stamp"])]) {
    [self signOutSessionForContext:context];
    return YES;
  }
  if (revocationAvailable && [ARTrimmedString(row[@"session_revoked"]) isEqualToString:@"t"]) {
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
