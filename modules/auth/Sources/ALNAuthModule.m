#import "ALNConfig.h"
#import "ALNAuthModule.h"

#import <dispatch/dispatch.h>
#import "ALNAuthModuleOIDC.h"

#import "ALNHTTPCompat.h"
#import "ALNApplication.h"
#import "ALNAuthProviderPresets.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNJSONSerialization.h"
#import "ALNLogger.h"
#import "ALNPg.h"
#import "ALNPlatform.h"
#import "ALNPasswordHash.h"
#import "ALNRecoveryCodes.h"
#import "ALNSecurityPrimitives.h"
#import "ALNServices.h"
#import "ALNTOTP.h"

#include <ctype.h>

NSString *const ALNAuthModuleErrorDomain = @"Arlen.Modules.Auth.Error";
NSString *const ALNAuthModuleRetryAfterSecondsKey = @"retry_after_seconds";

static NSString *const AMAttemptScopeMFA = @"mfa";
// auth_password_attempts.client_ip value for the account-wide row.
static NSString *const AMPasswordAccountRowAddress = @"*";
// Failure counts older than this start over at the next failure.
static const NSTimeInterval AMAttemptFailureWindowSeconds = 86400.0;

static NSString *const ALNAuthModuleProviderStateSessionKey = @"aln.auth_module.stub_provider_state";
static NSString *const ALNAuthModuleVerificationNoticeSessionKey = @"aln.auth_module.notice.verify";
static NSString *const ALNAuthModuleProviderErrorSessionKey = @"aln.auth_module.notice.provider_error";
static NSString *const ALNAuthModuleResetNoticeSessionKey = @"aln.auth_module.notice.reset";
static NSString *const ALNAuthModuleSMSStateSessionKey = @"aln.auth_module.sms_state";

static NSString *AMTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// Clamps a caller-supplied `return_to` to a same-origin path.
///
/// `return_to` arrives from the query string or a form field and is handed back
/// to the browser as a `Location` after a successful sign-in, so a value
/// carrying its own origin turns a genuine authentication into an open
/// redirect. That is worth more to an attacker than an ordinary one: the victim
/// really did just authenticate on the legitimate host, which is exactly what
/// makes a "your session expired, sign in again" page served immediately
/// afterwards convincing.
///
/// Only a single-slash absolute path is accepted. Anything else yields an empty
/// string, and callers fall back to the configured default redirect. Apps that
/// genuinely need a cross-origin return use the session-policy hook, whose
/// override is deliberately not clamped.
static NSString *AMSafeReturnTo(id value) {
  NSString *candidate = AMTrimmedString(value);
  if ([candidate length] == 0) {
    return @"";
  }
  // A scheme-bearing target ("https://evil.example") or a bare relative path
  // both fail this: only a rooted path is a same-origin return.
  if (![candidate hasPrefix:@"/"]) {
    return @"";
  }
  // "//evil.example" is protocol-relative, and therefore off-origin.
  if ([candidate hasPrefix:@"//"]) {
    return @"";
  }
  // Browsers normalize a backslash to a slash, so "/\evil.example" is
  // protocol-relative once the browser is done with it.
  if ([candidate rangeOfString:@"\\"].location != NSNotFound) {
    return @"";
  }
  NSUInteger length = [candidate length];
  for (NSUInteger idx = 0; idx < length; idx++) {
    unichar c = [candidate characterAtIndex:idx];
    if (c < 0x20 || c == 0x7F) {
      return @"";
    }
  }
  return candidate;
}

static NSString *AMLowerTrimmedString(id value) {
  return [[AMTrimmedString(value) lowercaseString] copy];
}

static NSError *AMError(ALNAuthModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"auth module error";
  return [NSError errorWithDomain:ALNAuthModuleErrorDomain code:code userInfo:userInfo];
}

// Local absolute paths only: no scheme, no protocol-relative `//`, no backslashes,
// fragments or control characters.
static BOOL AMIsLocalRedirectPath(id value) {
  if (![value isKindOfClass:[NSString class]]) return NO;
  NSString *path = value;
  return [path hasPrefix:@"/"] && ![path hasPrefix:@"//"] &&
         [path rangeOfString:@"\\"].location == NSNotFound &&
         [path rangeOfString:@"#"].location == NSNotFound &&
         [path rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound &&
         [path rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location == NSNotFound;
}

// OIDC presets the auth module can expand. Presets that need a tenant-specific issuer
// or an unsupported client authentication method are deliberately not listed.
static NSArray *AMSupportedOIDCProviderPresets(void) {
  return @[ @"google" ];
}

static NSString *AMURLHost(id value) {
  NSString *url = [value isKindOfClass:[NSString class]] ? value : @"";
  return [[NSURL URLWithString:url].host lowercaseString] ?: @"";
}

// Expands `preset = "google"` into discovery-based provider keys, deriving the endpoint
// and JWKS allowed hosts from the preset's own endpoints. Explicit keys win.
static NSDictionary *AMExpandedOIDCProvider(NSString *identifier, NSDictionary *provider, NSError **error) {
  if (provider[@"preset"] == nil) {
    return provider;
  }
  NSString *presetName = AMLowerTrimmedString(provider[@"preset"]);
  NSDictionary *preset = [AMSupportedOIDCProviderPresets() containsObject:presetName]
                             ? [ALNAuthProviderPresets presetNamed:presetName error:NULL]
                             : nil;
  if (preset == nil) {
    if (error) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"authModule.providers.%@ has unknown OIDC preset \"%@\" (supported: %@)",
                                                  identifier, presetName ?: @"",
                                                  [AMSupportedOIDCProviderPresets() componentsJoinedByString:@", "]],
                       nil);
    }
    return nil;
  }
  NSString *issuer = preset[@"issuer"];
  NSMutableArray *endpointHosts = [NSMutableArray array];
  for (NSString *key in @[ @"issuer", @"authorizationEndpoint", @"tokenEndpoint" ]) {
    NSString *host = AMURLHost(preset[key]);
    if ([host length] > 0 && ![endpointHosts containsObject:host]) {
      [endpointHosts addObject:host];
    }
  }
  NSMutableDictionary *expanded = [NSMutableDictionary dictionaryWithDictionary:@{
    @"type" : @"oidc",
    @"issuer" : issuer,
    @"discoveryURL" : [issuer stringByAppendingString:@"/.well-known/openid-configuration"],
    @"scopes" : preset[@"defaultScopes"] ?: @[ @"openid", @"email", @"profile" ],
    @"tokenEndpointAuthMethod" : preset[@"tokenEndpointAuthMethod"] ?: @"client_secret_post",
    @"endpointAllowedHosts" : endpointHosts,
    @"jwksAllowedHosts" : @[ AMURLHost(preset[@"jwksURI"]) ],
    @"ctaLabel" : [NSString stringWithFormat:@"Continue with %@", preset[@"displayName"] ?: identifier],
  }];
  [expanded addEntriesFromDictionary:provider];
  [expanded removeObjectForKey:@"preset"];
  return expanded;
}

// YES when every '%' in `value` starts a two-hex-digit escape. Checked
// explicitly because Foundation implementations differ on what
// -stringByRemovingPercentEncoding returns for malformed escapes.
static BOOL AMPercentEscapesValid(NSString *value) {
  NSUInteger length = [value length];
  for (NSUInteger index = 0; index < length; index++) {
    if ([value characterAtIndex:index] != '%') {
      continue;
    }
    for (NSUInteger offset = 1; offset <= 2; offset++) {
      if (index + offset >= length) {
        return NO;
      }
      unichar digit = [value characterAtIndex:index + offset];
      BOOL hex = (digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f') || (digit >= 'A' && digit <= 'F');
      if (!hex) {
        return NO;
      }
    }
    index += 2;
  }
  return YES;
}

static BOOL AMHostCharactersValid(NSString *host, BOOL bracketed) {
  NSCharacterSet *allowed = bracketed
                                ? [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF:."]
                                : [NSCharacterSet characterSetWithCharactersInString:
                                                      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-."];
  return [host length] > 0 && [host rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

// `authModule.publicBaseURL`: the origin (plus optional path prefix) used for
// links in auth emails. Returns "" when unset, nil (with an error) when invalid.
// Parsed from the raw string rather than through NSURLComponents, whose port
// handling and host round-trip differ between Foundation implementations.
static NSString *AMNormalizedPublicBaseURL(id value, NSError **error) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  NSString *trimmed = [value isKindOfClass:[NSString class]] ? AMTrimmedString(value) : nil;
  if (trimmed != nil && [trimmed length] == 0) {
    return @"";
  }
  NSString *normalized = nil;
  NSRange separator = (trimmed != nil) ? [trimmed rangeOfString:@"://"] : NSMakeRange(NSNotFound, 0);
  if (separator.location != NSNotFound) {
    NSString *scheme = [[trimmed substringToIndex:separator.location] lowercaseString];
    NSString *rest = [trimmed substringFromIndex:NSMaxRange(separator)];
    BOOL noQueryOrFragment = [rest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]]
                                 .location == NSNotFound;
    NSRange slash = [rest rangeOfString:@"/"];
    NSString *authority = (slash.location == NSNotFound) ? rest : [rest substringToIndex:slash.location];
    NSString *path = (slash.location == NSNotFound) ? @"" : [rest substringFromIndex:slash.location];
    NSString *host = nil;
    NSString *portText = nil;
    BOOL bracketed = [authority hasPrefix:@"["];
    BOOL authorityValid = ([authority rangeOfString:@"@"].location == NSNotFound);
    if (bracketed) {
      NSRange close = [authority rangeOfString:@"]"];
      if (close.location == NSNotFound) {
        authorityValid = NO;
      } else {
        host = [authority substringWithRange:NSMakeRange(1, close.location - 1)];
        NSString *after = [authority substringFromIndex:NSMaxRange(close)];
        if ([after hasPrefix:@":"]) {
          portText = [after substringFromIndex:1];
        } else if ([after length] > 0) {
          authorityValid = NO;
        }
      }
    } else {
      NSRange colon = [authority rangeOfString:@":"];
      host = (colon.location == NSNotFound) ? authority : [authority substringToIndex:colon.location];
      portText = (colon.location == NSNotFound) ? nil : [authority substringFromIndex:NSMaxRange(colon)];
    }
    BOOL pathValid = YES;
    for (NSString *segment in [path componentsSeparatedByString:@"/"]) {
      // Compare the decoded segment so %2e forms are caught too.
      NSString *decoded = AMPercentEscapesValid(segment) ? [segment stringByRemovingPercentEncoding] : nil;
      if (decoded == nil || [decoded isEqualToString:@"."] || [decoded isEqualToString:@".."]) {
        pathValid = NO;
      }
    }
    BOOL portValid = YES;
    if (portText != nil) {
      NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
      portValid = [portText length] >= 1 && [portText length] <= 5 &&
                  [portText rangeOfCharacterFromSet:nonDigits].location == NSNotFound &&
                  [portText integerValue] >= 1 && [portText integerValue] <= 65535;
    }
    if (([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) && noQueryOrFragment &&
        authorityValid && portValid && pathValid && AMHostCharactersValid(host, bracketed)) {
      NSString *lowerHost = [host lowercaseString];
      NSString *hostPart = bracketed ? [NSString stringWithFormat:@"[%@]", lowerHost] : lowerHost;
      NSString *portPart = (portText != nil) ? [NSString stringWithFormat:@":%ld", (long)[portText integerValue]] : @"";
      normalized = [NSString stringWithFormat:@"%@://%@%@%@", scheme, hostPart, portPart, path];
    }
  }
  if (normalized == nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       @"authModule.publicBaseURL must be an absolute http(s) URL with a valid host and port and no "
                       @"user info, query, fragment or dot segments, for example \"https://app.example.com\"",
                       @{ @"key_path" : @"authModule.publicBaseURL" });
    }
    return nil;
  }
  while ([normalized hasSuffix:@"/"]) {
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  return normalized;
}

static NSString *AMEffectiveEnvironmentName(NSString *environmentName) {
  NSString *trimmed = AMTrimmedString(environmentName);
  return ([trimmed length] > 0) ? trimmed : @"development";
}

static BOOL AMErrorLooksLikeMissingAuthModuleTables(NSError *error) {
  if (![error isKindOfClass:[NSError class]] ||
      ![error.domain isEqualToString:ALNPgErrorDomain]) {
    return NO;
  }

  NSString *sqlState = AMTrimmedString(error.userInfo[ALNPgErrorSQLStateKey]);
  if ([sqlState isEqualToString:@"42P01"]) {
    return YES;
  }

  NSString *serverTable = AMLowerTrimmedString(error.userInfo[ALNPgErrorServerTableKey]);
  if ([serverTable hasPrefix:@"auth_"]) {
    return YES;
  }

  NSString *detail = AMLowerTrimmedString(error.userInfo[@"detail"]);
  NSString *serverDetail = AMLowerTrimmedString(error.userInfo[ALNPgErrorServerDetailKey]);
  return ([detail containsString:@"relation \"auth_"] ||
          [serverDetail containsString:@"relation \"auth_"]);
}

static NSError *AMTranslateMissingAuthModuleTablesError(NSError *error,
                                                        NSString *environmentName) {
  if (!AMErrorLooksLikeMissingAuthModuleTables(error)) {
    return error;
  }

  NSString *environment = AMEffectiveEnvironmentName(environmentName);
  NSString *fixCommand =
      [NSString stringWithFormat:@"./bin/arlen module migrate --env %@", environment];
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : environment,
    @"fix_command" : fixCommand,
  }];
  if ([error isKindOfClass:[NSError class]]) {
    details[NSUnderlyingErrorKey] = error;
  }
  return AMError(ALNAuthModuleErrorInvalidConfiguration,
                 [NSString stringWithFormat:@"Auth module tables are missing. Run %@.", fixCommand],
                 details);
}

// Migration 004 adds auth_attempt_limits and auth_mfa_enrollments.last_used_step.
static BOOL AMErrorLooksLikeMissingAttemptLimitSchema(NSError *error) {
  if (![error isKindOfClass:[NSError class]] || ![error.domain isEqualToString:ALNPgErrorDomain]) {
    return NO;
  }
  NSString *sqlState = AMTrimmedString(error.userInfo[ALNPgErrorSQLStateKey]);
  return [sqlState isEqualToString:@"42P01"] || [sqlState isEqualToString:@"42703"];
}

// The database could not be reached or had no free connection, as opposed to
// a query that ran and failed. Callers answer 503 instead of treating the user
// as signed out.
static BOOL AMErrorIsDatabaseUnavailable(NSError *error) {
  NSError *current = error;
  for (NSUInteger depth = 0; depth < 4 && [current isKindOfClass:[NSError class]]; depth++) {
    if ([current.domain isEqualToString:ALNAuthModuleErrorDomain] &&
        current.code == ALNAuthModuleErrorDatabaseUnavailable) {
      return YES;
    }
    if ([current.domain isEqualToString:ALNPgErrorDomain]) {
      if (current.code == ALNPgErrorConnectionFailed || current.code == ALNPgErrorPoolExhausted) {
        return YES;
      }
      NSString *sqlState = AMTrimmedString(current.userInfo[ALNPgErrorSQLStateKey]);
      if ([sqlState hasPrefix:@"08"] || [sqlState hasPrefix:@"57P"] || [sqlState isEqualToString:@"53300"]) {
        return YES;
      }
      // A statement that failed without a SQLSTATE never got a server answer
      // (the connection broke): not a query error and not a failed sign-in.
      if ([sqlState length] == 0 &&
          (current.code == ALNPgErrorQueryFailed || current.code == ALNPgErrorTransactionFailed)) {
        return YES;
      }
    }
    current = current.userInfo[NSUnderlyingErrorKey];
  }
  return NO;
}

static NSString *const AMDatabaseUnavailableMessage =
    @"The sign-in service is temporarily unavailable. Try again shortly.";

// YES when the error came from the database driver; its text is for logs only.
static BOOL AMErrorInvolvesDatabase(NSError *error) {
  NSError *current = error;
  for (NSUInteger depth = 0; depth < 4 && [current isKindOfClass:[NSError class]]; depth++) {
    if ([current.domain isEqualToString:ALNPgErrorDomain]) {
      return YES;
    }
    current = current.userInfo[NSUnderlyingErrorKey];
  }
  return NO;
}

static NSError *AMRateLimitedError(NSUInteger retryAfterSeconds, NSString *message) {
  return AMError(ALNAuthModuleErrorRateLimited,
                 message,
                 @{ ALNAuthModuleRetryAfterSecondsKey : @(MAX(retryAfterSeconds, (NSUInteger)1)) });
}

static NSString *AMPasswordAttemptKeyForEmail(NSString *normalizedEmail) {
  NSData *digest = ALNSHA256([(normalizedEmail ?: @"") dataUsingEncoding:NSUTF8StringEncoding]);
  return ALNLowercaseHexStringFromData(digest) ?: @"";
}

// One-time bearer links have high-entropy random tokens. Keep only a digest in
// the database so reading a token table does not grant access to the link.
static NSString *AMStoredBearerToken(NSString *token) {
  NSData *digest = ALNSHA256([(token ?: @"") dataUsingEncoding:NSUTF8StringEncoding]);
  return [@"sha256:" stringByAppendingString:ALNLowercaseHexStringFromData(digest) ?: @""];
}

static NSString *AMPasswordAttemptAddress(NSString *clientAddress) {
  NSString *address = AMLowerTrimmedString(clientAddress);
  if ([address length] == 0 || [address isEqualToString:AMPasswordAccountRowAddress]) {
    return @"unknown";
  }
  return ([address length] > 128) ? [address substringToIndex:128] : address;
}

static NSUInteger AMDoublingDelay(NSUInteger baseSeconds, NSUInteger exponent, NSUInteger maxSeconds) {
  double scaled = (double)baseSeconds * pow(2.0, (double)MIN(exponent, (NSUInteger)20U));
  return (NSUInteger)MIN(scaled, (double)maxSeconds);
}

static BOOL AMLooksLikeTOTPCode(NSString *code) {
  if ([code length] != 6) {
    return NO;
  }
  NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
  return [code rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

static NSString *AMJSONString(id object) {
  if (object == nil) {
    return @"{}";
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  if (data == nil) {
    return @"{}";
  }
  NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return string ?: @"{}";
}

static NSArray *AMJSONArrayFromJSONString(id value) {
  NSString *json = AMTrimmedString(value);
  if ([json length] == 0) {
    return @[];
  }
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  id object = [ALNJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  if (![object isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray *normalized = [NSMutableArray array];
  for (id entry in (NSArray *)object) {
    NSString *string = AMLowerTrimmedString(entry);
    if ([string length] == 0 || [normalized containsObject:string]) {
      continue;
    }
    [normalized addObject:string];
  }
  return [NSArray arrayWithArray:normalized];
}

// Unlike AMJSONArrayFromJSONString, keeps case and order (encoded hashes are case-sensitive).
static NSArray *AMJSONStringArrayFromJSONString(id value) {
  NSString *json = AMTrimmedString(value);
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  id object = ([data length] > 0) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  NSMutableArray *strings = [NSMutableArray array];
  for (id entry in [object isKindOfClass:[NSArray class]] ? (NSArray *)object : @[]) {
    if ([entry isKindOfClass:[NSString class]] && [(NSString *)entry length] > 0) {
      [strings addObject:entry];
    }
  }
  return [NSArray arrayWithArray:strings];
}

static BOOL AMBoolFromDatabaseValue(id value) {
  NSString *string = AMLowerTrimmedString(value);
  return [string isEqualToString:@"t"] || [string isEqualToString:@"true"] || [string isEqualToString:@"1"] ||
         [string isEqualToString:@"yes"];
}

static NSString *AMRandomToken(NSUInteger byteCount) {
  NSData *random = ALNSecureRandomData(byteCount);
  return ALNLowercaseHexStringFromData(random) ?: @"";
}

// Unknown-email logins verify against this throwaway hash so they spend about
// as long as a wrong password for a real account.
static NSString *AMDummyPasswordHash(void) {
  static NSString *dummyHash = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dummyHash = [ALNPasswordHash hashPasswordString:AMRandomToken(32)
                                            options:[ALNPasswordHash defaultArgon2idOptions]
                                              error:NULL];
  });
  return dummyHash;
}

static NSUInteger AMDummyPasswordVerifications = 0;
static NSLock *AMDummyPasswordVerificationLock(void) {
  static NSLock *lock = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static void AMSpendDummyPasswordVerification(NSString *password) {
  NSString *dummyHash = AMDummyPasswordHash();
  if ([dummyHash length] > 0) {
    (void)[ALNPasswordHash verifyPasswordString:(password ?: @"") againstEncodedHash:dummyHash error:NULL];
  }
  NSLock *lock = AMDummyPasswordVerificationLock();
  [lock lock];
  AMDummyPasswordVerifications += 1;
  [lock unlock];
}

static NSDictionary *AMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [ALNJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSString *AMPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = AMTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/auth";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = AMTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *AMConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = AMTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/auth";
  }
  NSString *override = AMTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return AMPathJoin(prefix, override);
  }
  return AMPathJoin(prefix, defaultSuffix);
}

static NSArray *AMNormalizedEmailArray(id rawValues) {
  NSArray *values = [rawValues isKindOfClass:[NSArray class]] ? rawValues : @[];
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in values) {
    NSString *email = AMLowerTrimmedString(value);
    if ([email length] == 0 || [normalized containsObject:email]) {
      continue;
    }
    [normalized addObject:email];
  }
  return [NSArray arrayWithArray:normalized];
}

static BOOL AMConfigBool(id value, BOOL fallbackValue) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return fallbackValue;
}

static NSUInteger AMConfigUnsignedInteger(id value, NSUInteger fallbackValue) {
  NSUInteger converted = ALNUnsignedIntegerValueOrDefault(value, 0U);
  return (converted > 0U) ? converted : fallbackValue;
}

static NSString *AMNormalizePhoneNumber(id value) {
  NSString *raw = AMTrimmedString(value);
  if ([raw length] == 0) {
    return @"";
  }
  NSMutableString *digits = [NSMutableString string];
  for (NSUInteger index = 0; index < [raw length]; index++) {
    unichar c = [raw characterAtIndex:index];
    if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:c]) {
      [digits appendFormat:@"%C", c];
    }
  }
  if ([digits length] < 8 || [digits length] > 15) {
    return @"";
  }
  return [@"+" stringByAppendingString:digits];
}

static NSString *AMMaskedPhoneNumber(id value) {
  NSString *phone = AMNormalizePhoneNumber(value);
  if ([phone length] == 0) {
    return @"";
  }
  NSString *digits = [phone substringFromIndex:1];
  if ([digits length] <= 4) {
    return phone;
  }
  NSString *suffix = [digits substringFromIndex:([digits length] - 4)];
  NSMutableString *masked = [NSMutableString stringWithString:@"+"];
  NSUInteger visiblePrefixLength = ([digits length] > 10) ? ([digits length] - 10) : 1U;
  [masked appendString:[digits substringToIndex:visiblePrefixLength]];
  [masked appendString:@" "];
  NSUInteger hiddenDigits = [digits length] - visiblePrefixLength - 4U;
  for (NSUInteger index = 0; index < hiddenDigits; index++) {
    [masked appendString:@"•"];
    if ((index + 1U) % 3U == 0U && index + 1U < hiddenDigits) {
      [masked appendString:@" "];
    }
  }
  [masked appendFormat:@" %@", suffix];
  return masked;
}

static NSString *AMFormURLEncodedString(NSDictionary *parameters) {
  NSDictionary *source = [parameters isKindOfClass:[NSDictionary class]] ? parameters : @{};
  NSMutableArray<NSString *> *pairs = [NSMutableArray array];
  NSCharacterSet *allowed = [[NSCharacterSet characterSetWithCharactersInString:@"-._~"] invertedSet];
  for (id rawKey in [[source allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *key = AMTrimmedString(rawKey);
    NSString *value = AMTrimmedString(source[rawKey]);
    if ([key length] == 0) {
      continue;
    }
    NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[allowed invertedSet]] ?: @"";
    NSString *encodedValue = [(value ?: @"") stringByAddingPercentEncodingWithAllowedCharacters:[allowed invertedSet]] ?: @"";
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
  }
  return [pairs componentsJoinedByString:@"&"];
}

static NSDictionary *AMSMSSessionState(ALNContext *context) {
  if (context == nil) {
    return @{};
  }
  NSDictionary *state = [context.session[ALNAuthModuleSMSStateSessionKey] isKindOfClass:[NSDictionary class]]
                            ? context.session[ALNAuthModuleSMSStateSessionKey]
                            : @{};
  return state ?: @{};
}

static void AMSetSMSSessionState(ALNContext *context, NSDictionary *state) {
  if (context == nil) {
    return;
  }
  if ([state isKindOfClass:[NSDictionary class]] && [state count] > 0) {
    context.session[ALNAuthModuleSMSStateSessionKey] = state;
  } else {
    [context.session removeObjectForKey:ALNAuthModuleSMSStateSessionKey];
  }
  [context markSessionDirty];
}

static NSString *AMNormalizedTemplateIdentifier(id value) {
  NSString *raw = AMTrimmedString(value);
  if ([raw length] == 0) {
    return @"";
  }
  NSMutableString *normalized = [NSMutableString string];
  unichar previous = 0;
  for (NSUInteger idx = 0; idx < [raw length]; idx++) {
    unichar c = [raw characterAtIndex:idx];
    if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
      if ([normalized length] > 0 && previous != '_') {
        [normalized appendString:@"_"];
      }
      [normalized appendFormat:@"%c", (char)tolower((int)c)];
      previous = '_';
      continue;
    }
    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
      [normalized appendFormat:@"%c", (char)tolower((int)c)];
      previous = c;
      continue;
    }
    if ([normalized length] > 0 && previous != '_') {
      [normalized appendString:@"_"];
      previous = '_';
    }
  }
  NSString *candidate = [normalized copy];
  while ([candidate hasPrefix:@"_"]) {
    candidate = [candidate substringFromIndex:1];
  }
  while ([candidate hasSuffix:@"_"]) {
    candidate = [candidate substringToIndex:([candidate length] - 1)];
  }
  while ([candidate containsString:@"__"]) {
    candidate = [candidate stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
  }
  return candidate ?: @"";
}

static NSString *AMNormalizedTemplatePrefix(id value) {
  NSString *prefix = AMTrimmedString(value);
  while ([prefix hasPrefix:@"/"]) {
    prefix = [prefix substringFromIndex:1];
  }
  while ([prefix hasSuffix:@"/"]) {
    prefix = [prefix substringToIndex:([prefix length] - 1)];
  }
  return ([prefix length] > 0) ? prefix : @"auth";
}

static NSString *AMModulePageTemplatePathForIdentifier(NSString *pageIdentifier) {
  NSString *normalized = AMNormalizedTemplateIdentifier(pageIdentifier);
  if ([normalized isEqualToString:@"login"]) {
    return @"modules/auth/login/index";
  }
  if ([normalized isEqualToString:@"register"]) {
    return @"modules/auth/register/index";
  }
  if ([normalized isEqualToString:@"forgot_password"]) {
    return @"modules/auth/password/forgot";
  }
  if ([normalized isEqualToString:@"reset_password"]) {
    return @"modules/auth/password/reset";
  }
  if ([normalized isEqualToString:@"mfa_manage"]) {
    return @"modules/auth/mfa/manage";
  }
  if ([normalized isEqualToString:@"totp_enrollment"]) {
    return @"modules/auth/mfa/totp_enrollment";
  }
  if ([normalized isEqualToString:@"totp_challenge"]) {
    return @"modules/auth/mfa/totp";
  }
  if ([normalized isEqualToString:@"sms_challenge"]) {
    return @"modules/auth/mfa/sms";
  }
  if ([normalized isEqualToString:@"totp_recovery_codes"]) {
    return @"modules/auth/mfa/totp_recovery_codes";
  }
  return @"modules/auth/result/index";
}

static NSString *AMGeneratedPageTemplatePath(NSString *prefix, NSString *pageIdentifier) {
  NSString *normalizedPrefix = AMNormalizedTemplatePrefix(prefix);
  NSString *normalized = AMNormalizedTemplateIdentifier(pageIdentifier);
  if ([normalized isEqualToString:@"login"]) {
    return [NSString stringWithFormat:@"%@/login", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"register"]) {
    return [NSString stringWithFormat:@"%@/register", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"forgot_password"]) {
    return [NSString stringWithFormat:@"%@/password/forgot", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"reset_password"]) {
    return [NSString stringWithFormat:@"%@/password/reset", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"mfa_manage"]) {
    return [NSString stringWithFormat:@"%@/mfa/manage", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"totp_enrollment"]) {
    return [NSString stringWithFormat:@"%@/mfa/totp_enrollment", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"totp_challenge"]) {
    return [NSString stringWithFormat:@"%@/mfa/totp", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"sms_challenge"]) {
    return [NSString stringWithFormat:@"%@/mfa/sms", normalizedPrefix];
  }
  if ([normalized isEqualToString:@"totp_recovery_codes"]) {
    return [NSString stringWithFormat:@"%@/mfa/totp_recovery_codes", normalizedPrefix];
  }
  return [NSString stringWithFormat:@"%@/result", normalizedPrefix];
}

static NSString *AMModuleBodyTemplatePathForIdentifier(NSString *pageIdentifier) {
  NSString *normalized = AMNormalizedTemplateIdentifier(pageIdentifier);
  if ([normalized isEqualToString:@"login"]) {
    return @"modules/auth/partials/bodies/login_body";
  }
  if ([normalized isEqualToString:@"register"]) {
    return @"modules/auth/partials/bodies/register_body";
  }
  if ([normalized isEqualToString:@"forgot_password"]) {
    return @"modules/auth/partials/bodies/forgot_password_body";
  }
  if ([normalized isEqualToString:@"reset_password"]) {
    return @"modules/auth/partials/bodies/reset_password_body";
  }
  if ([normalized isEqualToString:@"mfa_manage"]) {
    return @"modules/auth/partials/bodies/mfa_manage_body";
  }
  if ([normalized isEqualToString:@"totp_enrollment"]) {
    return @"modules/auth/partials/bodies/totp_enrollment_body";
  }
  if ([normalized isEqualToString:@"totp_challenge"]) {
    return @"modules/auth/partials/bodies/totp_challenge_body";
  }
  if ([normalized isEqualToString:@"sms_challenge"]) {
    return @"modules/auth/partials/bodies/sms_challenge_body";
  }
  if ([normalized isEqualToString:@"totp_recovery_codes"]) {
    return @"modules/auth/partials/bodies/totp_recovery_codes_body";
  }
  return @"modules/auth/partials/bodies/result_body";
}

static NSString *AMGeneratedBodyTemplatePath(NSString *prefix, NSString *pageIdentifier) {
  return [NSString stringWithFormat:@"%@/partials/bodies/%@",
                                    AMNormalizedTemplatePrefix(prefix),
                                    [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"forgot_password"]
                                        ? @"forgot_password_body"
                                        : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"reset_password"]
                                              ? @"reset_password_body"
                                              : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"mfa_manage"]
                                                    ? @"mfa_manage_body"
                                              : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"totp_enrollment"]
                                                    ? @"totp_enrollment_body"
                                              : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"totp_challenge"]
                                                    ? @"totp_challenge_body"
                                              : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"sms_challenge"]
                                                    ? @"sms_challenge_body"
                                              : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"totp_recovery_codes"]
                                                    ? @"totp_recovery_codes_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"result"] ? @"result_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"verify_result"] ? @"result_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"provider_result"] ? @"result_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"register"] ? @"register_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"login"] ? @"login_body"
                                                    : @"result_body"];
}

static NSString *AMModuleFragmentTemplatePathForIdentifier(NSString *fragmentIdentifier) {
  NSString *normalized = AMNormalizedTemplateIdentifier(fragmentIdentifier);
  if ([normalized length] == 0) {
    return @"";
  }
  return [NSString stringWithFormat:@"modules/auth/fragments/%@", normalized];
}

static NSString *AMGeneratedFragmentTemplatePath(NSString *prefix, NSString *fragmentIdentifier) {
  NSString *normalized = AMNormalizedTemplateIdentifier(fragmentIdentifier);
  if ([normalized length] == 0) {
    return @"";
  }
  return [NSString stringWithFormat:@"%@/fragments/%@", AMNormalizedTemplatePrefix(prefix), normalized];
}

static NSString *AMModulePartialTemplatePathForIdentifier(NSString *partialIdentifier) {
  NSString *normalized = AMNormalizedTemplateIdentifier(partialIdentifier);
  if ([normalized length] == 0) {
    return @"";
  }
  return [NSString stringWithFormat:@"modules/auth/partials/%@", normalized];
}

static NSString *AMGeneratedPartialTemplatePath(NSString *prefix, NSString *partialIdentifier) {
  NSString *normalized = AMNormalizedTemplateIdentifier(partialIdentifier);
  if ([normalized length] == 0) {
    return @"";
  }
  return [NSString stringWithFormat:@"%@/partials/%@", AMNormalizedTemplatePrefix(prefix), normalized];
}

static NSDictionary *AMNormalizedTemplateOverrideMap(id value) {
  NSDictionary *raw = [value isKindOfClass:[NSDictionary class]] ? value : @{};
  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  for (id key in raw) {
    NSString *normalizedKey = AMNormalizedTemplateIdentifier(key);
    NSString *path = AMTrimmedString(raw[key]);
    if ([normalizedKey length] == 0 || [path length] == 0) {
      continue;
    }
    normalized[normalizedKey] = path;
  }
  return [NSDictionary dictionaryWithDictionary:normalized];
}

static NSDictionary *AMUserDictionaryFromRow(NSDictionary *row) {
  if (![row isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *subject = AMTrimmedString(row[@"subject"]);
  if ([subject length] == 0) {
    return nil;
  }
  NSString *email = AMLowerTrimmedString(row[@"email"]);
  NSArray *roles = AMJSONArrayFromJSONString(row[@"roles_json"]);
  BOOL emailVerified = ([AMTrimmedString(row[@"email_verified_at"]) length] > 0);
  return @{
    @"id" : AMTrimmedString(row[@"id"]),
    @"subject" : subject,
    @"email" : email ?: @"",
    @"display_name" : AMTrimmedString(row[@"display_name"]),
    @"roles" : roles ?: @[],
    @"email_verified" : @(emailVerified),
    @"email_verified_at" : AMTrimmedString(row[@"email_verified_at"]),
  };
}

static NSString *AMBase64URLForJSONObject(NSDictionary *object) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:NULL];
  return ALNBase64URLStringFromData(data) ?: @"";
}

static NSString *AMStubHS256JWT(NSDictionary *claims, NSString *sharedSecret) {
  NSDictionary *header = @{ @"alg" : @"HS256", @"typ" : @"JWT" };
  NSString *headerPart = AMBase64URLForJSONObject(header);
  NSString *payloadPart = AMBase64URLForJSONObject(claims ?: @{});
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, payloadPart];
  NSData *digest = ALNHMACSHA256([signingInput dataUsingEncoding:NSUTF8StringEncoding],
                                 [sharedSecret dataUsingEncoding:NSUTF8StringEncoding]);
  NSString *signaturePart = ALNBase64URLStringFromData(digest) ?: @"";
  return [NSString stringWithFormat:@"%@.%@.%@", headerPart, payloadPart, signaturePart];
}

@interface ALNAuthModuleTwilioVerifyClient : NSObject

@property(nonatomic, copy) NSString *accountSID;
@property(nonatomic, copy) NSString *authToken;
@property(nonatomic, copy) NSString *apiKeySID;
@property(nonatomic, copy) NSString *apiKeySecret;
@property(nonatomic, copy) NSString *verifyServiceSID;
@property(nonatomic, copy) NSString *defaultLocale;
@property(nonatomic, copy) NSString *testVerificationCode;

- (BOOL)isConfigured;
- (BOOL)sendVerificationToPhoneNumber:(NSString *)phoneNumber
                               locale:(nullable NSString *)locale
                                error:(NSError **)error;
- (BOOL)checkVerificationCode:(NSString *)code
                  phoneNumber:(NSString *)phoneNumber
                     approved:(BOOL *)approved
                        error:(NSError **)error;

@end

@interface ALNAuthModuleRuntime ()
@property(nonatomic, copy) NSDictionary<NSString *, ALNAuthModuleOIDC *> *oidcProviders;
@property(nonatomic, assign, readwrite) BOOL localPasswordEnabled;


@property(nonatomic, strong) ALNPg *database;
@property(nonatomic, strong) id<ALNMailAdapter> mailAdapter;
@property(nonatomic, strong, nullable) ALNLogger *logger;
@property(nonatomic, copy, readwrite) NSString *publicBaseURL;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, copy) NSString *environmentName;
@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSString *loginPath;
@property(nonatomic, copy, readwrite) NSString *registerPath;
@property(nonatomic, copy, readwrite) NSString *logoutPath;
@property(nonatomic, copy, readwrite) NSString *logoutAllPath;
@property(nonatomic, assign, readwrite) NSUInteger absoluteSessionLifetimeSeconds;
@property(nonatomic, assign) NSUInteger sessionCookieMaxAgeSeconds;
@property(nonatomic, copy, readwrite) NSString *sessionPath;
@property(nonatomic, copy, readwrite) NSString *verifyPath;
@property(nonatomic, copy, readwrite) NSString *forgotPasswordPath;
@property(nonatomic, copy, readwrite) NSString *resetPasswordPath;
@property(nonatomic, copy, readwrite) NSString *changePasswordPath;
@property(nonatomic, copy, readwrite) NSString *mfaManagePath;
@property(nonatomic, copy, readwrite) NSString *totpPath;
@property(nonatomic, copy, readwrite) NSString *stepUpPath;
@property(nonatomic, copy, readwrite) NSString *totpVerifyPath;
@property(nonatomic, copy, readwrite) NSString *smsPath;
@property(nonatomic, copy, readwrite) NSString *smsStartPath;
@property(nonatomic, copy, readwrite) NSString *smsVerifyPath;
@property(nonatomic, copy, readwrite) NSString *smsResendPath;
@property(nonatomic, copy, readwrite) NSString *smsRemovePath;
@property(nonatomic, copy, readwrite) NSString *providerStubLoginPath;
@property(nonatomic, copy, readwrite) NSString *providerStubAuthorizePath;
@property(nonatomic, copy, readwrite) NSString *providerStubCallbackPath;
@property(nonatomic, copy, readwrite) NSString *defaultRedirect;
@property(nonatomic, copy) NSString *failureRedirect;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *providerFailureRedirects;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *loginProviders;
@property(nonatomic, copy, readwrite) NSString *uiMode;
@property(nonatomic, copy, readwrite) NSString *layoutTemplate;
@property(nonatomic, copy, readwrite) NSString *generatedPagePrefix;
@property(nonatomic, copy, readwrite) NSString *uiAssetPrefix;
- (void)mountUIAssetsForApplication:(ALNApplication *)application;
@property(nonatomic, assign, readwrite) BOOL smsEnabled;
@property(nonatomic, assign) BOOL smsAllowEnrollment;
@property(nonatomic, assign) BOOL smsAllowChallenge;
@property(nonatomic, assign) BOOL smsAllowPrimaryFactor;
@property(nonatomic, assign) BOOL smsPhoneManagementRequiresMFA;
@property(nonatomic, assign) NSUInteger smsRecentMFAMaxAgeSeconds;
@property(nonatomic, assign) NSUInteger smsResendCooldownSeconds;
@property(nonatomic, assign) NSUInteger smsMaxSendAttemptsPerSession;
@property(nonatomic, assign) NSUInteger smsMaxVerifyAttemptsPerSession;
@property(nonatomic, copy) NSString *smsLocale;
@property(nonatomic, assign) NSUInteger mfaMaxFailures;
@property(nonatomic, assign) NSUInteger mfaLockoutSeconds;
@property(nonatomic, assign) NSUInteger mfaMaxLockoutSeconds;
@property(nonatomic, assign) NSUInteger passwordMaxFailures;
@property(nonatomic, assign) NSUInteger passwordDelaySeconds;
@property(nonatomic, assign) NSUInteger passwordMaxDelaySeconds;
@property(nonatomic, assign) NSUInteger passwordAccountMaxFailures;
@property(nonatomic, assign) NSUInteger passwordAccountWindowSeconds;
@property(nonatomic, assign) NSUInteger passwordAccountDelaySeconds;
@property(nonatomic, assign) NSUInteger passwordMaxTrackedEntries;
@property(nonatomic, assign) NSUInteger passwordPruneBatchSize;
@property(nonatomic, assign) NSUInteger passwordTrustedPairDays;
@property(nonatomic, assign) NSUInteger mailMaxPerEmail;
@property(nonatomic, assign) NSUInteger mailMaxPerAddress;
@property(nonatomic, assign) NSUInteger mailWindowSeconds;
@property(nonatomic, assign) NSTimeInterval passwordAttemptsLastPrunedAt;
@property(nonatomic, strong) id attemptLimitSchemaDatabase;
@property(nonatomic, assign) BOOL attemptLimitSchemaAvailable;
@property(nonatomic, assign) BOOL attemptLimitSchemaWarningLogged;
@property(nonatomic, strong) NSLock *attemptLimitSchemaLock;
@property(nonatomic, strong) ALNAuthModuleTwilioVerifyClient *smsVerifyClient;
@property(nonatomic, copy) NSDictionary *partialTemplateOverrides;
@property(nonatomic, copy) NSString *stubProviderEmail;
@property(nonatomic, copy) NSString *stubProviderDisplayName;
@property(nonatomic, copy) NSString *stubProviderSharedSecret;
@property(nonatomic, copy) NSArray *bootstrapAdminEmails;
@property(nonatomic, strong) id<ALNAuthModuleRegistrationPolicy> registrationPolicyHook;
@property(nonatomic, strong) id<ALNAuthModulePasswordPolicy> passwordPolicyHook;
@property(nonatomic, strong) id<ALNAuthModuleUserProvisioningHook> userProvisioningHook;
@property(nonatomic, strong) id<ALNAuthModuleNotificationHook> notificationHook;
@property(nonatomic, strong) id<ALNAuthModuleSessionPolicyHook> sessionPolicyHook;
@property(nonatomic, strong) id<ALNAuthModuleProviderMappingHook> providerMappingHook;
@property(nonatomic, strong) id<ALNAuthModuleUIContextHook> uiContextHook;

- (nullable NSDictionary *)loadUserBySQL:(NSString *)sql
                              parameters:(NSArray *)parameters
                                   error:(NSError **)error;
- (nullable NSDictionary *)userForEmail:(NSString *)email
                                  error:(NSError **)error;
- (nullable NSDictionary *)userForSubject:(NSString *)subject
                                    error:(NSError **)error;
- (nullable NSDictionary *)userForProvider:(NSString *)provider
                             providerSub:(NSString *)providerSubject
                                   error:(NSError **)error;
- (BOOL)insertProviderIdentityForUserID:(NSString *)userID
                               provider:(NSString *)provider
                        providerSubject:(NSString *)providerSubject
                               profile:(NSDictionary *)profile
                                  error:(NSError **)error;
- (nullable NSDictionary *)createLocalUserWithEmail:(NSString *)email
                                        displayName:(NSString *)displayName
                                           password:(NSString *)password
                                             source:(NSString *)source
                                              error:(NSError **)error;
- (nullable NSDictionary *)createTrustedEmailClaimUserWithEmail:(NSString *)email
                                                    displayName:(NSString *)displayName
                                                         source:(NSString *)source
                                                          error:(NSError **)error;
- (nullable NSDictionary *)createFederatedUserForIdentity:(NSDictionary *)normalizedIdentity
                                                    error:(NSError **)error;
- (nullable NSDictionary *)authenticateLocalEmail:(NSString *)email
                                         password:(NSString *)password
                                            error:(NSError **)error;
- (nullable NSDictionary *)authenticateLocalEmail:(NSString *)email
                                         password:(NSString *)password
                                    clientAddress:(nullable NSString *)clientAddress
                                            error:(NSError **)error;
- (NSInteger)prunePasswordAttempts;
- (BOOL)allowMailSendForEmail:(NSString *)email
                clientAddress:(nullable NSString *)clientAddress
                         flow:(NSString *)flow;
- (NSUInteger)dummyPasswordVerificationCount;
- (nullable NSDictionary *)startSessionForUser:(NSDictionary *)user
                                      provider:(NSString *)provider
                                       methods:(NSArray *)methods
                                       context:(ALNContext *)context
                                         error:(NSError **)error;
- (BOOL)sendNotificationEvent:(NSString *)event
                         user:(NSDictionary *)user
                        token:(NSString *)token
                      baseURL:(NSString *)baseURL
                        error:(NSError **)error;
- (nullable NSString *)issueVerificationTokenForUserID:(NSString *)userID
                                                 error:(NSError **)error;
- (nullable NSString *)issuePasswordResetTokenForUserID:(NSString *)userID
                                                  error:(NSError **)error;
- (BOOL)markEmailVerifiedForUserID:(NSString *)userID
                             error:(NSError **)error;
- (BOOL)updateLocalPasswordHash:(NSString *)encodedHash
                      forUserID:(NSString *)userID
                          error:(NSError **)error;
- (BOOL)consumeVerificationToken:(NSString *)token
                            user:(NSDictionary *_Nullable *_Nullable)user
                           error:(NSError **)error;
- (BOOL)consumePasswordResetToken:(NSString *)token
                         password:(NSString *)password
                             user:(NSDictionary *_Nullable *_Nullable)user
                            error:(NSError **)error;
- (nullable NSDictionary *)totpEnrollmentForUserID:(NSString *)userID
                                             error:(NSError **)error;
- (nullable NSDictionary *)smsEnrollmentForUserID:(NSString *)userID
                                            error:(NSError **)error;
- (nullable NSDictionary *)totpProvisioningPayloadForUser:(NSDictionary *)user
                                                    error:(NSError **)error;
- (nullable NSDictionary *)totpFragmentContextForUser:(NSDictionary *)user
                                             returnTo:(NSString *)returnTo
                                                error:(NSError **)error;
- (NSDictionary *)mfaFactorStateForUser:(NSDictionary *)user
                                context:(ALNContext *)context
                               returnTo:(NSString *)returnTo
                                  error:(NSError **)error;
- (nullable NSDictionary *)mfaManagementFragmentContextForUser:(NSDictionary *)user
                                                       context:(ALNContext *)context
                                                      returnTo:(NSString *)returnTo
                                                         error:(NSError **)error;
- (nullable NSDictionary *)smsChallengeFragmentContextForUser:(NSDictionary *)user
                                                      context:(ALNContext *)context
                                                     returnTo:(NSString *)returnTo
                                                     autoSend:(BOOL)autoSend
                                                        error:(NSError **)error;
- (nullable NSDictionary *)issueSMSVerificationForUser:(NSDictionary *)user
                                                 phone:(nullable NSString *)phoneNumber
                                               purpose:(NSString *)purpose
                                               context:(ALNContext *)context
                                                 error:(NSError **)error;
- (nullable NSDictionary *)verifySMSCode:(NSString *)code
                                     user:(NSDictionary *)user
                                  context:(ALNContext *)context
                                    error:(NSError **)error;
- (BOOL)removeSMSEnrollmentForUser:(NSDictionary *)user
                           context:(ALNContext *)context
                             error:(NSError **)error;
- (nullable NSDictionary *)verifyTOTPCode:(NSString *)code
                                      user:(NSDictionary *)user
                                   context:(ALNContext *)context
                                     error:(NSError **)error;
- (NSDictionary *)totpRecoveryCodesFragmentContextWithCodes:(NSArray<NSString *> *)recoveryCodes
                                                   returnTo:(NSString *)returnTo;
- (NSDictionary *)stubProviderConfigurationForBaseURL:(NSString *)baseURL;
- (BOOL)isDevelopmentOrTestEnvironment;
- (nullable NSString *)emailLinkBaseURLWithRequestBaseURL:(NSString *)requestBaseURL
                                                    event:(NSString *)event;

@end

// Implemented in ALNAuthModuleSessionRefresh.m.
@interface ALNAuthModuleRuntime (ALNAuthModuleSessionStampInternal)
- (BOOL)bumpSessionStampForUserID:(NSString *)userID
                       connection:(ALNPgConnection *)connection
                            error:(NSError **)error;
- (BOOL)recordCurrentSessionStampForContext:(ALNContext *)context error:(NSError **)error;
@end

@interface ALNAuthModuleController : ALNController
@end

static id AMInstantiateHookClass(NSDictionary *hooksConfig,
                                 NSString *configKey,
                                 Protocol *protocol,
                                 NSError **error) {
  NSString *className = AMTrimmedString(hooksConfig[configKey]);
  if ([className length] == 0) {
    return nil;
  }
  Class klass = NSClassFromString(className);
  if (klass == Nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"hook class %@ could not be resolved", className],
                       @{ @"hook" : configKey ?: @"" });
    }
    return nil;
  }
  if (protocol != NULL && ![klass conformsToProtocol:protocol]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"%@ must conform to %@", className, NSStringFromProtocol(protocol)],
                       @{ @"hook" : configKey ?: @"" });
    }
    return nil;
  }
  return [[klass alloc] init];
}

@implementation ALNAuthModuleTwilioVerifyClient

- (BOOL)isConfigured {
  if ([AMTrimmedString(self.testVerificationCode) length] > 0) {
    return YES;
  }
  if ([AMTrimmedString(self.verifyServiceSID) length] == 0) {
    return NO;
  }
  BOOL hasAccountCredentials = ([AMTrimmedString(self.accountSID) length] > 0 && [AMTrimmedString(self.authToken) length] > 0);
  BOOL hasAPIKeyCredentials = ([AMTrimmedString(self.apiKeySID) length] > 0 && [AMTrimmedString(self.apiKeySecret) length] > 0);
  return (hasAccountCredentials || hasAPIKeyCredentials);
}

- (NSDictionary *)performRequestWithPath:(NSString *)path
                              parameters:(NSDictionary *)parameters
                                   error:(NSError **)error {
  if ([AMTrimmedString(self.testVerificationCode) length] > 0) {
    return @{ @"status" : @"pending", @"sid" : @"VE_TEST" };
  }
  NSString *serviceSID = AMTrimmedString(self.verifyServiceSID);
  NSString *endpoint = [NSString stringWithFormat:@"https://verify.twilio.com/v2/Services/%@/%@",
                                                  serviceSID ?: @"",
                                                  AMTrimmedString(path) ?: @""];
  NSURL *url = [NSURL URLWithString:endpoint];
  if (url == nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"Twilio Verify endpoint is invalid", nil);
    }
    return nil;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setHTTPMethod:@"POST"];
  [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  NSString *username = [AMTrimmedString(self.apiKeySID) length] > 0 ? AMTrimmedString(self.apiKeySID) : AMTrimmedString(self.accountSID);
  NSString *password = [AMTrimmedString(self.apiKeySecret) length] > 0 ? AMTrimmedString(self.apiKeySecret) : AMTrimmedString(self.authToken);
  NSString *credentials = [NSString stringWithFormat:@"%@:%@", username ?: @"", password ?: @""];
  NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
  NSString *base64 = [credentialsData base64EncodedStringWithOptions:0] ?: @"";
  [request setValue:[NSString stringWithFormat:@"Basic %@", base64] forHTTPHeaderField:@"Authorization"];
  NSString *bodyText = AMFormURLEncodedString(parameters);
  [request setHTTPBody:[bodyText dataUsingEncoding:NSUTF8StringEncoding]];

  NSHTTPURLResponse *response = nil;
  NSError *requestError = nil;
  NSData *bodyData = ALNSynchronousURLRequest(request, (NSURLResponse **)&response, &requestError);
  if (bodyData == nil) {
    if (error != NULL) {
      *error = requestError ?: AMError(ALNAuthModuleErrorPolicyRejected, @"Twilio Verify request failed", nil);
    }
    return nil;
  }
  NSDictionary *json = [ALNJSONSerialization JSONObjectWithData:bodyData options:0 error:NULL];
  NSInteger statusCode = response.statusCode;
  if (statusCode < 200 || statusCode >= 300) {
    NSString *message = AMTrimmedString(json[@"message"]);
    if ([message length] == 0) {
      message = @"Twilio Verify rejected the request";
    }
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected, message, @{
        @"status_code" : @(statusCode),
        @"provider" : @"twilio_verify",
      });
    }
    return nil;
  }
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (BOOL)sendVerificationToPhoneNumber:(NSString *)phoneNumber
                               locale:(NSString *)locale
                                error:(NSError **)error {
  if (![self isConfigured]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"SMS MFA is not configured", nil);
    }
    return NO;
  }
  if ([AMTrimmedString(self.testVerificationCode) length] > 0) {
    return YES;
  }
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
    @"To" : AMNormalizePhoneNumber(phoneNumber) ?: @"",
    @"Channel" : @"sms",
  }];
  NSString *resolvedLocale = [AMTrimmedString(locale) length] > 0 ? AMTrimmedString(locale) : AMTrimmedString(self.defaultLocale);
  if ([resolvedLocale length] > 0) {
    parameters[@"Locale"] = resolvedLocale;
  }
  NSDictionary *response = [self performRequestWithPath:@"Verifications" parameters:parameters error:error];
  return (response != nil);
}

- (BOOL)checkVerificationCode:(NSString *)code
                  phoneNumber:(NSString *)phoneNumber
                     approved:(BOOL *)approved
                        error:(NSError **)error {
  if (approved != NULL) {
    *approved = NO;
  }
  if (![self isConfigured]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"SMS MFA is not configured", nil);
    }
    return NO;
  }
  NSString *normalizedCode = AMTrimmedString(code);
  if ([AMTrimmedString(self.testVerificationCode) length] > 0) {
    BOOL ok = [normalizedCode isEqualToString:AMTrimmedString(self.testVerificationCode)];
    if (approved != NULL) {
      *approved = ok;
    }
    if (!ok && error != NULL) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"The verification code is invalid", nil);
    }
    return ok;
  }
  NSDictionary *response = [self performRequestWithPath:@"VerificationCheck"
                                             parameters:@{
                                               @"To" : AMNormalizePhoneNumber(phoneNumber) ?: @"",
                                               @"Code" : normalizedCode ?: @"",
                                             }
                                                  error:error];
  if (response == nil) {
    return NO;
  }
  BOOL ok = [AMLowerTrimmedString(response[@"status"]) isEqualToString:@"approved"] ||
            [AMLowerTrimmedString(response[@"valid"]) isEqualToString:@"true"];
  if (approved != NULL) {
    *approved = ok;
  }
  if (!ok && error != NULL) {
    *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"The verification code is invalid", nil);
  }
  return ok;
}

@end

@implementation ALNAuthModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNAuthModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNAuthModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _moduleConfig = @{};
    _prefix = @"/auth";
    _apiPrefix = @"/auth/api";
    _loginPath = @"/auth/login";
    _registerPath = @"/auth/register";
    _logoutPath = @"/auth/logout";
    _logoutAllPath = @"/auth/logout/all";
    _absoluteSessionLifetimeSeconds = 1209600U;
    _sessionCookieMaxAgeSeconds = 1209600U;
    _sessionPath = @"/auth/session";
    _verifyPath = @"/auth/verify";
    _forgotPasswordPath = @"/auth/password/forgot";
    _resetPasswordPath = @"/auth/password/reset";
    _changePasswordPath = @"/auth/password/change";
    _mfaManagePath = @"/auth/mfa";
    _totpPath = @"/auth/mfa/totp";
    _stepUpPath = @"/auth/mfa/totp";
    _totpVerifyPath = @"/auth/mfa/totp/verify";
    _smsPath = @"/auth/mfa/sms";
    _smsStartPath = @"/auth/mfa/sms/start";
    _smsVerifyPath = @"/auth/mfa/sms/verify";
    _smsResendPath = @"/auth/mfa/sms/resend";
    _smsRemovePath = @"/auth/mfa/sms/remove";
    _providerStubLoginPath = @"/auth/provider/stub/login";
    _providerStubAuthorizePath = @"/auth/provider/stub/authorize";
    _providerStubCallbackPath = @"/auth/provider/stub/callback";
    _defaultRedirect = @"/";
    _loginProviders = @[ @{
      @"identifier" : @"stub",
      @"kind" : @"oidc",
      @"ctaLabel" : @"Continue with Stub OIDC",
      @"loginPath" : @"/auth/provider/stub/login",
      @"apiLoginPath" : @"/auth/api/provider/stub/login",
    } ];
    _uiMode = @"module-ui";
    _layoutTemplate = @"modules/auth/layouts/main";
    _generatedPagePrefix = @"auth";
    _smsEnabled = NO;
    _smsAllowEnrollment = YES;
    _smsAllowChallenge = YES;
    _smsAllowPrimaryFactor = NO;
    _smsPhoneManagementRequiresMFA = YES;
    _smsRecentMFAMaxAgeSeconds = 900U;
    _smsResendCooldownSeconds = 30U;
    _smsMaxSendAttemptsPerSession = 5U;
    _smsMaxVerifyAttemptsPerSession = 8U;
    _smsLocale = @"";
    _smsVerifyClient = [[ALNAuthModuleTwilioVerifyClient alloc] init];
    _partialTemplateOverrides = @{};
    _stubProviderEmail = @"stub-user@example.test";
    _stubProviderDisplayName = @"Stub Provider User";
    _stubProviderSharedSecret = @"auth-module-stub-provider-secret-0123456789abcdef";
    _bootstrapAdminEmails = @[];
    _environmentName = @"development";
    _attemptLimitSchemaLock = [[NSLock alloc] init];
    _mfaMaxFailures = 5U;
    _mfaLockoutSeconds = 30U;
    _mfaMaxLockoutSeconds = 900U;
    _passwordMaxFailures = 5U;
    _passwordDelaySeconds = 30U;
    _passwordMaxDelaySeconds = 900U;
    _passwordAccountMaxFailures = 50U;
    _passwordAccountWindowSeconds = 3600U;
    _passwordAccountDelaySeconds = 30U;
    _passwordMaxTrackedEntries = 100000U;
    _passwordPruneBatchSize = 1000U;
    _passwordTrustedPairDays = 30U;
    _mailMaxPerEmail = 5U;
    _mailMaxPerAddress = 20U;
    _mailWindowSeconds = 3600U;
    _publicBaseURL = @"";
  }
  return self;
}

- (BOOL)configureHooksWithModuleConfig:(NSDictionary *)moduleConfig
                                 error:(NSError **)error {
  self.moduleConfig = [moduleConfig isKindOfClass:[NSDictionary class]] ? moduleConfig : @{};
  NSDictionary *paths = [self.moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"paths"] : @{};
  self.prefix = AMPathJoin(AMTrimmedString(paths[@"prefix"]), @"");
  self.uiAssetPrefix = @"/modules/auth";
  self.apiPrefix = AMConfiguredPath(self.moduleConfig, @"apiPrefix", @"api");
  self.loginPath = AMConfiguredPath(self.moduleConfig, @"login", @"login");
  self.registerPath = AMConfiguredPath(self.moduleConfig, @"register", @"register");
  self.logoutPath = AMConfiguredPath(self.moduleConfig, @"logout", @"logout");
  self.logoutAllPath = AMConfiguredPath(self.moduleConfig, @"logoutAll", @"logout/all");
  self.sessionPath = AMConfiguredPath(self.moduleConfig, @"session", @"session");
  self.verifyPath = AMConfiguredPath(self.moduleConfig, @"verify", @"verify");
  self.forgotPasswordPath = AMConfiguredPath(self.moduleConfig, @"forgotPassword", @"password/forgot");
  self.resetPasswordPath = AMConfiguredPath(self.moduleConfig, @"resetPassword", @"password/reset");
  self.changePasswordPath = AMConfiguredPath(self.moduleConfig, @"changePassword", @"password/change");
  self.mfaManagePath = AMConfiguredPath(self.moduleConfig, @"mfa", @"mfa");
  self.totpPath = AMConfiguredPath(self.moduleConfig, @"totp", @"mfa/totp");
  // The step-up target may carry a query (for example "?prompt=login"); the
  // step-up redirect appends its own parameters with "&" in that case.
  NSString *configuredStepUp = AMTrimmedString(paths[@"stepUp"]);
  NSString *stepUpPath = ([configuredStepUp length] > 0)
                             ? AMConfiguredPath(self.moduleConfig, @"stepUp", @"")
                             : self.totpPath;
  // A relative value is joined to the prefix like every other path, so an
  // absolute URL would quietly become "/auth/https://..."; refuse it instead.
  if ([configuredStepUp containsString:@"://"] || !AMIsLocalRedirectPath(stepUpPath)) {
    if (error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                                @"authModule.paths.stepUp must be a local absolute path", nil);
    return NO;
  }
  self.stepUpPath = stepUpPath;
  self.totpVerifyPath = AMConfiguredPath(self.moduleConfig, @"totpVerify", @"mfa/totp/verify");
  self.smsPath = AMConfiguredPath(self.moduleConfig, @"sms", @"mfa/sms");
  self.smsStartPath = AMConfiguredPath(self.moduleConfig, @"smsStart", @"mfa/sms/start");
  self.smsVerifyPath = AMConfiguredPath(self.moduleConfig, @"smsVerify", @"mfa/sms/verify");
  self.smsResendPath = AMConfiguredPath(self.moduleConfig, @"smsResend", @"mfa/sms/resend");
  self.smsRemovePath = AMConfiguredPath(self.moduleConfig, @"smsRemove", @"mfa/sms/remove");
  self.providerStubLoginPath = AMConfiguredPath(self.moduleConfig, @"providerStubLogin", @"provider/stub/login");
  self.providerStubAuthorizePath =
      AMConfiguredPath(self.moduleConfig, @"providerStubAuthorize", @"provider/stub/authorize");
  self.providerStubCallbackPath =
      AMConfiguredPath(self.moduleConfig, @"providerStubCallback", @"provider/stub/callback");
  self.defaultRedirect = AMTrimmedString(self.moduleConfig[@"defaultRedirect"]);
  if ([self.defaultRedirect length] == 0) {
    self.defaultRedirect = @"/";
  }
  id failureRedirect = self.moduleConfig[@"failureRedirect"];
  if (failureRedirect != nil && !AMIsLocalRedirectPath(failureRedirect)) {
    if (error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                                @"authModule.failureRedirect must be a local absolute path", nil);
    return NO;
  }
  self.failureRedirect = failureRedirect;
  NSString *publicBaseURL = AMNormalizedPublicBaseURL(self.moduleConfig[@"publicBaseURL"], error);
  if (publicBaseURL == nil) {
    return NO;
  }
  self.publicBaseURL = publicBaseURL;
  NSDictionary *uiConfig = [self.moduleConfig[@"ui"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"ui"] : @{};
  NSString *uiMode = AMLowerTrimmedString(uiConfig[@"mode"]);
  if (![uiMode isEqualToString:@"headless"] && ![uiMode isEqualToString:@"generated-app-ui"]) {
    uiMode = @"module-ui";
  }
  self.uiMode = uiMode;
  NSString *layoutTemplate = AMTrimmedString(uiConfig[@"layout"]);
  self.layoutTemplate = ([layoutTemplate length] > 0) ? layoutTemplate : @"modules/auth/layouts/main";
  self.generatedPagePrefix = AMNormalizedTemplatePrefix(uiConfig[@"generatedPagePrefix"]);
  self.partialTemplateOverrides = AMNormalizedTemplateOverrideMap(uiConfig[@"partials"]);

  NSDictionary *sessionConfig =
      [self.moduleConfig[@"session"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"session"] : @{};
  self.absoluteSessionLifetimeSeconds = AMConfigUnsignedInteger(sessionConfig[@"absoluteLifetimeSeconds"], 1209600U);

  NSDictionary *mfaConfig = [self.moduleConfig[@"mfa"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"mfa"] : @{};
  NSDictionary *smsConfig = [mfaConfig[@"sms"] isKindOfClass:[NSDictionary class]] ? mfaConfig[@"sms"] : @{};
  self.smsEnabled = AMConfigBool(smsConfig[@"enabled"], NO);
  self.smsAllowEnrollment = AMConfigBool(smsConfig[@"allowEnrollment"], YES);
  self.smsAllowChallenge = AMConfigBool(smsConfig[@"allowChallenge"], YES);
  self.smsAllowPrimaryFactor = AMConfigBool(smsConfig[@"allowPrimaryFactor"], NO);
  self.smsPhoneManagementRequiresMFA = AMConfigBool(smsConfig[@"phoneManagementRequiresMFA"], YES);
  self.smsRecentMFAMaxAgeSeconds = AMConfigUnsignedInteger(smsConfig[@"recentMFAMaxAgeSeconds"], 900U);
  self.smsResendCooldownSeconds = AMConfigUnsignedInteger(smsConfig[@"resendCooldownSeconds"], 30U);
  self.smsMaxSendAttemptsPerSession = AMConfigUnsignedInteger(smsConfig[@"maxSendAttemptsPerSession"], 5U);
  self.smsMaxVerifyAttemptsPerSession = AMConfigUnsignedInteger(smsConfig[@"maxVerifyAttemptsPerSession"], 8U);
  self.smsLocale = AMTrimmedString(smsConfig[@"locale"]) ?: @"";
  NSDictionary *limitsConfig = [self.moduleConfig[@"attemptLimits"] isKindOfClass:[NSDictionary class]]
                                   ? self.moduleConfig[@"attemptLimits"]
                                   : @{};
  NSDictionary *mfaLimits = [limitsConfig[@"mfa"] isKindOfClass:[NSDictionary class]] ? limitsConfig[@"mfa"] : @{};
  NSDictionary *passwordLimits =
      [limitsConfig[@"password"] isKindOfClass:[NSDictionary class]] ? limitsConfig[@"password"] : @{};
  // maxFailures = 0 turns a scope's limit off; the durations must be positive.
  self.mfaMaxFailures = ALNUnsignedIntegerValueOrDefault(mfaLimits[@"maxFailures"], 5U);
  self.mfaLockoutSeconds = AMConfigUnsignedInteger(mfaLimits[@"lockoutSeconds"], 30U);
  self.mfaMaxLockoutSeconds = MAX(self.mfaLockoutSeconds, AMConfigUnsignedInteger(mfaLimits[@"maxLockoutSeconds"], 900U));
  // Password failures are counted per (submitted email, client address) pair
  // and per email across all addresses (accountMaxFailures = 0 turns only the
  // latter off; maxFailures = 0 turns both off).
  self.passwordMaxFailures = ALNUnsignedIntegerValueOrDefault(passwordLimits[@"maxFailures"], 5U);
  self.passwordDelaySeconds = AMConfigUnsignedInteger(passwordLimits[@"delaySeconds"], 30U);
  self.passwordMaxDelaySeconds =
      MAX(self.passwordDelaySeconds, AMConfigUnsignedInteger(passwordLimits[@"maxDelaySeconds"], 900U));
  self.passwordAccountMaxFailures = ALNUnsignedIntegerValueOrDefault(passwordLimits[@"accountMaxFailures"], 50U);
  self.passwordAccountWindowSeconds = AMConfigUnsignedInteger(passwordLimits[@"accountWindowSeconds"], 3600U);
  self.passwordAccountDelaySeconds = AMConfigUnsignedInteger(passwordLimits[@"accountDelaySeconds"], 30U);
  self.passwordMaxTrackedEntries = AMConfigUnsignedInteger(passwordLimits[@"maxTrackedEntries"], 100000U);
  self.passwordPruneBatchSize = AMConfigUnsignedInteger(passwordLimits[@"pruneBatchSize"], 1000U);
  // 0 turns the known-device exemption from the account-wide ceiling off.
  self.passwordTrustedPairDays = ALNUnsignedIntegerValueOrDefault(passwordLimits[@"trustedPairDays"], 30U);
  NSDictionary *mailLimits = [limitsConfig[@"mail"] isKindOfClass:[NSDictionary class]] ? limitsConfig[@"mail"] : @{};
  // 0 turns that mail limit off.
  self.mailMaxPerEmail = ALNUnsignedIntegerValueOrDefault(mailLimits[@"maxPerEmail"], 5U);
  self.mailMaxPerAddress = ALNUnsignedIntegerValueOrDefault(mailLimits[@"maxPerAddress"], 20U);
  self.mailWindowSeconds = AMConfigUnsignedInteger(mailLimits[@"windowSeconds"], 3600U);
  self.smsVerifyClient.accountSID = AMTrimmedString(smsConfig[@"accountSID"]) ?: @"";
  self.smsVerifyClient.authToken = AMTrimmedString(smsConfig[@"authToken"]) ?: @"";
  self.smsVerifyClient.apiKeySID = AMTrimmedString(smsConfig[@"apiKeySID"]) ?: @"";
  self.smsVerifyClient.apiKeySecret = AMTrimmedString(smsConfig[@"apiKeySecret"]) ?: @"";
  self.smsVerifyClient.verifyServiceSID = AMTrimmedString(smsConfig[@"verifyServiceSID"]) ?: @"";
  self.smsVerifyClient.defaultLocale = self.smsLocale ?: @"";
  self.smsVerifyClient.testVerificationCode = AMTrimmedString(smsConfig[@"testVerificationCode"]) ?: @"";
  if (self.smsEnabled && ![self.smsVerifyClient isConfigured]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       @"SMS MFA requires Twilio Verify credentials or authModule.mfa.sms.testVerificationCode",
                       @{ @"key_path" : @"authModule.mfa.sms" });
    }
    return NO;
  }

  NSDictionary *providers = [self.moduleConfig[@"providers"] isKindOfClass:[NSDictionary class]]
                                ? self.moduleConfig[@"providers"]
                                : @{};
  NSDictionary *stubProvider = [providers[@"stub"] isKindOfClass:[NSDictionary class]] ? providers[@"stub"] : @{};
  BOOL hasOIDC = NO;
  for (NSString *identifier in providers) {
    if ([identifier isEqual:@"stub"]) continue;
    NSDictionary *provider = providers[identifier];
    if (![provider isKindOfClass:[NSDictionary class]]) {
      if (error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"Provider configuration must be a dictionary", nil);
      return NO;
    }
    if (AMConfigBool(provider[@"enabled"], NO)) hasOIDC = YES;
  }
  id localPasswordConfig = self.moduleConfig[@"localPassword"];
  if (localPasswordConfig && ![localPasswordConfig isKindOfClass:[NSDictionary class]]) {
    if (error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"localPassword must be a dictionary", nil);
    return NO;
  }
  self.localPasswordEnabled = AMConfigBool(localPasswordConfig[@"enabled"], !hasOIDC);
  // The stub provider signs anyone in without credentials, so it is a
  // development and test convenience only. Elsewhere it defaults off, and an
  // explicit `providers.stub.enabled = YES` stops configuration.
  BOOL developmentOrTest = [self isDevelopmentOrTestEnvironment];
  BOOL stubEnabled = AMConfigBool(stubProvider[@"enabled"], !hasOIDC && developmentOrTest);
  if (stubEnabled && !developmentOrTest) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"authModule.providers.stub.enabled is only allowed in the development "
                                                  @"and test environments (current environment: %@)",
                                                  AMEffectiveEnvironmentName(self.environmentName)],
                       @{ @"key_path" : @"authModule.providers.stub.enabled" });
    }
    return NO;
  }
  NSString *stubEmail = AMLowerTrimmedString(stubProvider[@"email"]);
  if ([stubEmail length] > 0) {
    self.stubProviderEmail = stubEmail;
  }
  NSString *stubDisplayName = AMTrimmedString(stubProvider[@"displayName"]);
  if ([stubDisplayName length] > 0) {
    self.stubProviderDisplayName = stubDisplayName;
  }
  NSString *sharedSecret = AMTrimmedString(stubProvider[@"clientSecret"]);
  if ([sharedSecret length] > 0) {
    self.stubProviderSharedSecret = sharedSecret;
  }
  if (stubEnabled) {
    self.loginProviders = @[ @{
      @"identifier" : @"stub",
      @"kind" : @"oidc",
      @"ctaLabel" : @"Continue with Stub OIDC",
      @"loginPath" : self.providerStubLoginPath ?: @"/auth/provider/stub/login",
      @"apiLoginPath" : AMPathJoin(self.apiPrefix, @"provider/stub/login"),
    } ];
  } else {
    self.loginProviders = @[];
  }

  NSDictionary *providerHooks = [self.moduleConfig[@"hooks"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"hooks"] : @{};
  id resolver = hasOIDC ? AMInstantiateHookClass(providerHooks, @"providerSessionResolverClass",
                                                @protocol(ALNAuthProviderSessionResolver), error) : nil;
  if (hasOIDC && !resolver) {
    if (error && !*error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"OIDC requires hooks.providerSessionResolverClass", nil);
    return NO;
  }
  id transport = hasOIDC ? AMInstantiateHookClass(providerHooks, @"oidcTransportClass",
                                                 @protocol(ALNAuthModuleOIDCTransport), error) : nil;
  if (hasOIDC && AMTrimmedString(providerHooks[@"oidcTransportClass"]).length && !transport) return NO;
  BOOL allowLoopbackHTTPRedirect = ALNEnvironmentIsDevelopmentLike(self.environmentName);
  NSMutableDictionary *oidcProviders = [NSMutableDictionary dictionary];
  NSMutableDictionary *providerFailureRedirects = [NSMutableDictionary dictionary];
  NSMutableArray *loginProviders = [self.loginProviders mutableCopy];
  for (NSString *identifier in [[providers allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if ([identifier isEqual:@"stub"] || !AMConfigBool(providers[identifier][@"enabled"], NO)) continue;
    NSDictionary *provider = AMExpandedOIDCProvider(identifier, providers[identifier], error);
    if (!provider) return NO;
    if (![provider[@"type"] isEqual:@"oidc"]) {
      if (error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"Enabled provider requires type oidc", nil);
      return NO;
    }
    ALNAuthModuleOIDC *oidc = [[ALNAuthModuleOIDC alloc] initWithIdentifier:identifier configuration:provider
                                                               resolver:resolver transport:transport
                                              allowLoopbackHTTPRedirect:allowLoopbackHTTPRedirect
                                                                  error:error];
    if (!oidc) return NO;
    oidcProviders[identifier] = oidc;
    if (provider[@"failureRedirect"] != nil) {
      if (!AMIsLocalRedirectPath(provider[@"failureRedirect"])) {
        if (error) *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                                    [NSString stringWithFormat:@"authModule.providers.%@.failureRedirect must be a local absolute path",
                                                               identifier], nil);
        return NO;
      }
      providerFailureRedirects[identifier] = provider[@"failureRedirect"];
    }
    NSString *suffix = [NSString stringWithFormat:@"provider/%@/login", identifier];
    [loginProviders addObject:@{ @"identifier": identifier, @"kind": @"oidc",
       @"ctaLabel": AMTrimmedString(provider[@"ctaLabel"]).length ? provider[@"ctaLabel"] : [@"Continue with " stringByAppendingString:identifier],
       @"loginPath": AMPathJoin(self.prefix, suffix), @"apiLoginPath": AMPathJoin(self.apiPrefix, suffix) }];
  }
  self.oidcProviders = oidcProviders;
  self.providerFailureRedirects = providerFailureRedirects;
  self.loginProviders = loginProviders;

  self.bootstrapAdminEmails = AMNormalizedEmailArray(self.moduleConfig[@"bootstrapAdminEmails"]);
  NSDictionary *hooksConfig = [self.moduleConfig[@"hooks"] isKindOfClass:[NSDictionary class]]
                                  ? self.moduleConfig[@"hooks"]
                                  : @{};
  self.registrationPolicyHook =
      AMInstantiateHookClass(hooksConfig, @"registrationPolicyClass", @protocol(ALNAuthModuleRegistrationPolicy), error);
  if (self.registrationPolicyHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  self.passwordPolicyHook =
      AMInstantiateHookClass(hooksConfig, @"passwordPolicyClass", @protocol(ALNAuthModulePasswordPolicy), error);
  if (self.passwordPolicyHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  self.userProvisioningHook = AMInstantiateHookClass(hooksConfig,
                                                     @"userProvisioningClass",
                                                     @protocol(ALNAuthModuleUserProvisioningHook),
                                                     error);
  if (self.userProvisioningHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  self.notificationHook =
      AMInstantiateHookClass(hooksConfig, @"notificationClass", @protocol(ALNAuthModuleNotificationHook), error);
  if (self.notificationHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  self.sessionPolicyHook =
      AMInstantiateHookClass(hooksConfig, @"sessionPolicyClass", @protocol(ALNAuthModuleSessionPolicyHook), error);
  if (self.sessionPolicyHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  self.providerMappingHook = AMInstantiateHookClass(hooksConfig,
                                                    @"providerMappingClass",
                                                    @protocol(ALNAuthModuleProviderMappingHook),
                                                    error);
  if (self.providerMappingHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  self.uiContextHook =
      AMInstantiateHookClass(uiConfig, @"contextClass", @protocol(ALNAuthModuleUIContextHook), error);
  if (self.uiContextHook == nil && error != NULL && *error != NULL) {
    return NO;
  }
  return YES;
}

- (BOOL)isDevelopmentOrTestEnvironment {
  NSString *environment = AMEffectiveEnvironmentName(self.environmentName);
  return [environment isEqualToString:@"development"] || [environment isEqualToString:@"test"];
}

- (BOOL)configureHooksWithModuleConfig:(NSDictionary *)moduleConfig
                           environment:(NSString *)environment
                                 error:(NSError **)error {
  self.environmentName = AMEffectiveEnvironmentName(environment);
  return [self configureHooksWithModuleConfig:moduleConfig error:error];
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  NSDictionary *moduleConfig = [application.config[@"authModule"] isKindOfClass:[NSDictionary class]]
                                   ? application.config[@"authModule"]
                                   : @{};
  // Provider validation depends on the environment (loopback redirect URIs).
  self.environmentName = AMEffectiveEnvironmentName(application.environment);
  if (![self configureHooksWithModuleConfig:moduleConfig error:error]) {
    return NO;
  }
  NSDictionary *appSessionConfig = [application.config[@"session"] isKindOfClass:[NSDictionary class]]
                                       ? application.config[@"session"]
                                       : @{};
  self.sessionCookieMaxAgeSeconds = AMConfigUnsignedInteger(appSessionConfig[@"maxAgeSeconds"], 1209600U);
  // The module's forms and JSON endpoints rely on CSRF protection whenever
  // they run on a session cookie. An explicit csrf.enabled = NO (older
  // generated app.plist files wrote one) would leave them open to cross-site
  // posts, so refuse it unless the app opts out deliberately.
  NSDictionary *session = [application.config[@"session"] isKindOfClass:[NSDictionary class]]
                              ? application.config[@"session"]
                              : @{};
  NSDictionary *csrf = [application.config[@"csrf"] isKindOfClass:[NSDictionary class]]
                           ? application.config[@"csrf"]
                           : @{};
  BOOL sessionEnabled = [session[@"enabled"] respondsToSelector:@selector(boolValue)] &&
                        [session[@"enabled"] boolValue];
  BOOL csrfEnabled = [csrf[@"enabled"] respondsToSelector:@selector(boolValue)]
                         ? [csrf[@"enabled"] boolValue]
                         : sessionEnabled;
  BOOL allowWithoutCSRF = [moduleConfig[@"allowWithoutCSRF"] respondsToSelector:@selector(boolValue)] &&
                          [moduleConfig[@"allowWithoutCSRF"] boolValue];
  if (sessionEnabled && !csrfEnabled && !allowWithoutCSRF) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       @"auth module requires csrf.enabled when session.enabled is YES; remove "
                       @"csrf.enabled = NO from config/app.plist (CSRF then follows session.enabled), "
                       @"or set authModule.allowWithoutCSRF = YES to opt out",
                       @{ @"key_path" : @"csrf.enabled" });
    }
    return NO;
  }
  NSString *environment = [application.environment lowercaseString] ?: @"";
  if (sessionEnabled && !csrfEnabled && allowWithoutCSRF &&
      ![environment isEqualToString:@"development"] && ![environment isEqualToString:@"test"]) {
    [application.logger warn:@"auth module is running with CSRF protection off (authModule.allowWithoutCSRF = YES)"
                      fields:@{ @"environment" : environment, @"key_path" : @"csrf.enabled" }];
  }
  NSDictionary *database = [application.config[@"database"] isKindOfClass:[NSDictionary class]]
                               ? application.config[@"database"]
                               : @{};
  NSString *connectionString = AMTrimmedString(database[@"connectionString"]);
  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                       @"auth module requires database.connectionString",
                       @{ @"key_path" : @"database.connectionString" });
    }
    return NO;
  }
  NSError *dbError = nil;
  NSDictionary *poolConfig = [moduleConfig[@"database"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"database"] : @{};
  NSUInteger maxConnections = AMConfigUnsignedInteger(poolConfig[@"maxConnections"], 8U);
  id rawAcquireTimeout = poolConfig[@"acquireTimeoutSeconds"];
  NSTimeInterval acquireTimeout = [rawAcquireTimeout respondsToSelector:@selector(doubleValue)]
                                      ? [rawAcquireTimeout doubleValue]
                                      : 2.0;
  self.database = [[ALNPg alloc] initWithConnectionString:connectionString maxConnections:maxConnections error:&dbError];
  // Wait briefly for a busy pool instead of failing at once; requests that
  // still cannot get a connection answer 503 (see AMErrorIsDatabaseUnavailable).
  self.database.acquireTimeout = (acquireTimeout >= 0.0) ? acquireTimeout : 2.0;
  if (self.database == nil) {
    if (error != NULL) {
      *error = dbError ?: AMError(ALNAuthModuleErrorDatabaseUnavailable, @"failed to initialize auth database adapter", nil);
    }
    return NO;
  }
  self.mailAdapter = application.mailAdapter;
  self.logger = application.logger;
  [self.attemptLimitSchemaLock lock];
  self.attemptLimitSchemaAvailable = NO;
  self.attemptLimitSchemaWarningLogged = NO;
  [self.attemptLimitSchemaLock unlock];
  if ([self.publicBaseURL length] == 0 && ![self isDevelopmentOrTestEnvironment] && self.localPasswordEnabled &&
      self.mailAdapter != nil) {
    [self.logger warn:@"authModule.publicBaseURL is not set; password-reset and email-verification links will not be sent"
               fields:@{ @"environment" : AMEffectiveEnvironmentName(self.environmentName),
                         @"key_path" : @"authModule.publicBaseURL" }];
  }
  if ([self.publicBaseURL hasPrefix:@"http://"] && ![self isDevelopmentOrTestEnvironment]) {
    [self.logger warn:@"authModule.publicBaseURL uses http; password-reset and verification links will carry tokens "
                       "over plain HTTP. Use an https URL."
               fields:@{ @"environment" : AMEffectiveEnvironmentName(self.environmentName),
                         @"key_path" : @"authModule.publicBaseURL" }];
  }
  return YES;
}

- (NSString *)emailLinkBaseURLWithRequestBaseURL:(NSString *)requestBaseURL
                                           event:(NSString *)event {
  if ([self.publicBaseURL length] > 0) {
    return self.publicBaseURL;
  }
  // Without a configured base URL the request Host is the only source, and it
  // is client-supplied. Use it only for local development and tests.
  if ([self isDevelopmentOrTestEnvironment]) {
    return requestBaseURL;
  }
  [self.logger error:@"auth email link not sent: authModule.publicBaseURL is not set"
              fields:@{ @"event" : event ?: @"",
                        @"environment" : AMEffectiveEnvironmentName(self.environmentName),
                        @"key_path" : @"authModule.publicBaseURL" }];
  return nil;
}

- (NSDictionary *)resolvedHookSummary {
  NSMutableDictionary *summary = [NSMutableDictionary dictionary];
  summary[@"apiPrefix"] = self.apiPrefix ?: @"/auth/api";
  summary[@"loginProviders"] = self.loginProviders ?: @[];
  summary[@"registrationPolicy"] = self.registrationPolicyHook ? NSStringFromClass([self.registrationPolicyHook class]) : @"";
  summary[@"passwordPolicy"] = self.passwordPolicyHook ? NSStringFromClass([self.passwordPolicyHook class]) : @"";
  summary[@"userProvisioning"] = self.userProvisioningHook ? NSStringFromClass([self.userProvisioningHook class]) : @"";
  summary[@"notification"] = self.notificationHook ? NSStringFromClass([self.notificationHook class]) : @"";
  summary[@"sessionPolicy"] = self.sessionPolicyHook ? NSStringFromClass([self.sessionPolicyHook class]) : @"";
  summary[@"providerMapping"] = self.providerMappingHook ? NSStringFromClass([self.providerMappingHook class]) : @"";
  summary[@"ui"] = @{
    @"mode" : self.uiMode ?: @"module-ui",
    @"layout" : self.layoutTemplate ?: @"modules/auth/layouts/main",
    @"generatedPagePrefix" : self.generatedPagePrefix ?: @"auth",
    @"partials" : self.partialTemplateOverrides ?: @{},
    @"contextHook" : self.uiContextHook ? NSStringFromClass([self.uiContextHook class]) : @"",
  };
  summary[@"session"] = @{
    @"absoluteLifetimeSeconds" : @(self.absoluteSessionLifetimeSeconds),
  };
  summary[@"mfa"] = @{
    @"sms" : @{
      @"enabled" : @(self.smsEnabled),
      @"allowEnrollment" : @(self.smsAllowEnrollment),
      @"allowChallenge" : @(self.smsAllowChallenge),
      @"allowPrimaryFactor" : @(self.smsAllowPrimaryFactor),
      @"phoneManagementRequiresMFA" : @(self.smsPhoneManagementRequiresMFA),
      @"recentMFAMaxAgeSeconds" : @(self.smsRecentMFAMaxAgeSeconds),
      @"resendCooldownSeconds" : @(self.smsResendCooldownSeconds),
      @"maxSendAttemptsPerSession" : @(self.smsMaxSendAttemptsPerSession),
      @"maxVerifyAttemptsPerSession" : @(self.smsMaxVerifyAttemptsPerSession),
      @"locale" : self.smsLocale ?: @"",
    },
  };
  summary[@"attemptLimits"] = @{
    @"mfa" : @{
      @"maxFailures" : @(self.mfaMaxFailures),
      @"lockoutSeconds" : @(self.mfaLockoutSeconds),
      @"maxLockoutSeconds" : @(self.mfaMaxLockoutSeconds),
    },
    @"password" : @{
      @"maxFailures" : @(self.passwordMaxFailures),
      @"delaySeconds" : @(self.passwordDelaySeconds),
      @"maxDelaySeconds" : @(self.passwordMaxDelaySeconds),
      @"accountMaxFailures" : @(self.passwordAccountMaxFailures),
      @"accountWindowSeconds" : @(self.passwordAccountWindowSeconds),
      @"accountDelaySeconds" : @(self.passwordAccountDelaySeconds),
      @"maxTrackedEntries" : @(self.passwordMaxTrackedEntries),
      @"pruneBatchSize" : @(self.passwordPruneBatchSize),
      @"trustedPairDays" : @(self.passwordTrustedPairDays),
    },
    @"mail" : @{
      @"maxPerEmail" : @(self.mailMaxPerEmail),
      @"maxPerAddress" : @(self.mailMaxPerAddress),
      @"windowSeconds" : @(self.mailWindowSeconds),
    },
  };
  return summary;
}

- (BOOL)isProviderEnabled:(NSString *)identifier {
  NSString *providerID = AMLowerTrimmedString(identifier);
  if ([providerID length] == 0) {
    return NO;
  }
  for (NSDictionary *descriptor in self.loginProviders ?: @[]) {
    NSString *configuredID = AMLowerTrimmedString(descriptor[@"identifier"]);
    if ([configuredID isEqualToString:providerID]) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)registrationAllowedForRequest:(NSDictionary *)registrationRequest
                                error:(NSError **)error {
  if (self.registrationPolicyHook == nil) {
    return YES;
  }
  return [self.registrationPolicyHook authModuleShouldAllowRegistration:(registrationRequest ?: @{}) error:error];
}

- (BOOL)validatePassword:(NSString *)password
            errorMessage:(NSString **)errorMessage {
  NSString *normalizedPassword = password ?: @"";
  if (self.passwordPolicyHook != nil) {
    return [self.passwordPolicyHook authModuleValidatePassword:normalizedPassword errorMessage:errorMessage];
  }
  if ([normalizedPassword length] < 8) {
    if (errorMessage != NULL) {
      *errorMessage = @"Password must be at least 8 characters long";
    }
    return NO;
  }
  return YES;
}

- (NSDictionary *)provisionedUserValuesForEvent:(NSString *)event
                                 proposedValues:(NSDictionary *)proposedValues {
  NSDictionary *base = [proposedValues isKindOfClass:[NSDictionary class]] ? proposedValues : @{};
  if (self.userProvisioningHook == nil) {
    return base;
  }
  NSDictionary *override = [self.userProvisioningHook authModuleUserValuesForEvent:(event ?: @"")
                                                                     proposedValues:base];
  return [override isKindOfClass:[NSDictionary class]] ? override : base;
}

- (NSDictionary *)providerMappingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                               defaultDescriptor:(NSDictionary *)defaultDescriptor {
  NSDictionary *base = [defaultDescriptor isKindOfClass:[NSDictionary class]] ? defaultDescriptor : @{};
  if (self.providerMappingHook == nil) {
    return base;
  }
  NSDictionary *override =
      [self.providerMappingHook authModuleProviderMappingDescriptorForNormalizedIdentity:(normalizedIdentity ?: @{})
                                                                       defaultDescriptor:base];
  return [override isKindOfClass:[NSDictionary class]] ? override : base;
}

- (NSDictionary *)sessionDescriptorForUser:(NSDictionary *)user
                         defaultDescriptor:(NSDictionary *)defaultDescriptor {
  NSDictionary *base = [defaultDescriptor isKindOfClass:[NSDictionary class]] ? defaultDescriptor : @{};
  if (self.sessionPolicyHook != nil &&
      [self.sessionPolicyHook respondsToSelector:@selector(authModuleSessionDescriptorForUser:defaultDescriptor:)]) {
    NSDictionary *override = [self.sessionPolicyHook authModuleSessionDescriptorForUser:(user ?: @{})
                                                                      defaultDescriptor:base];
    if ([override isKindOfClass:[NSDictionary class]]) {
      return override;
    }
  }
  return base;
}

- (NSString *)postLoginRedirectForContext:(ALNContext *)context
                                     user:(NSDictionary *)user
                          defaultRedirect:(NSString *)defaultRedirect {
  // Clamped here as well as where `return_to` is read, so a future caller that
  // passes an unsanitized target cannot reopen the redirect. The hook's own
  // override is intentionally left alone: an app that returns a cross-origin
  // target from its session policy has said so explicitly.
  NSString *requested = AMSafeReturnTo(defaultRedirect);
  NSString *fallback = ([requested length] > 0) ? requested : self.defaultRedirect;
  if (self.sessionPolicyHook != nil &&
      [self.sessionPolicyHook respondsToSelector:@selector(authModulePostLoginRedirectForContext:user:defaultRedirect:)]) {
    NSString *override = [self.sessionPolicyHook authModulePostLoginRedirectForContext:context
                                                                                  user:(user ?: @{})
                                                                       defaultRedirect:fallback];
    if ([AMTrimmedString(override) length] > 0) {
      return override;
    }
  }
  return fallback;
}

- (BOOL)isHeadlessUIMode {
  return [[self.uiMode lowercaseString] isEqualToString:@"headless"];
}

- (NSString *)pageTemplatePathForIdentifier:(NSString *)pageIdentifier
                                defaultPath:(NSString *)defaultPath {
  NSString *normalized = AMNormalizedTemplateIdentifier(pageIdentifier);
  if ([normalized length] == 0) {
    return defaultPath ?: AMModulePageTemplatePathForIdentifier(@"result");
  }
  if ([[self.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    return AMGeneratedPageTemplatePath(self.generatedPagePrefix, normalized);
  }
  return ([AMTrimmedString(defaultPath) length] > 0) ? defaultPath : AMModulePageTemplatePathForIdentifier(normalized);
}

- (NSString *)bodyTemplatePathForIdentifier:(NSString *)pageIdentifier
                                defaultPath:(NSString *)defaultPath {
  NSString *normalized = AMNormalizedTemplateIdentifier(pageIdentifier);
  if ([normalized length] == 0) {
    return defaultPath ?: AMModuleBodyTemplatePathForIdentifier(@"result");
  }
  if ([[self.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    return AMGeneratedBodyTemplatePath(self.generatedPagePrefix, normalized);
  }
  return ([AMTrimmedString(defaultPath) length] > 0) ? defaultPath : AMModuleBodyTemplatePathForIdentifier(normalized);
}

- (NSString *)fragmentTemplatePathForIdentifier:(NSString *)fragmentIdentifier
                                    defaultPath:(NSString *)defaultPath {
  NSString *normalized = AMNormalizedTemplateIdentifier(fragmentIdentifier);
  if ([normalized length] == 0) {
    return defaultPath ?: @"";
  }
  if ([[self.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    return AMGeneratedFragmentTemplatePath(self.generatedPagePrefix, normalized);
  }
  return ([AMTrimmedString(defaultPath) length] > 0) ? defaultPath : AMModuleFragmentTemplatePathForIdentifier(normalized);
}

- (NSString *)partialTemplatePathForIdentifier:(NSString *)partialIdentifier
                                   defaultPath:(NSString *)defaultPath {
  NSString *normalized = AMNormalizedTemplateIdentifier(partialIdentifier);
  NSString *explicitOverride = AMTrimmedString(self.partialTemplateOverrides[normalized]);
  if ([explicitOverride length] > 0) {
    return explicitOverride;
  }
  if ([[self.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    return AMGeneratedPartialTemplatePath(self.generatedPagePrefix, normalized);
  }
  return ([AMTrimmedString(defaultPath) length] > 0) ? defaultPath : AMModulePartialTemplatePathForIdentifier(normalized);
}

- (NSString *)authUIAssetPathForFilename:(NSString *)filename {
  NSString *normalized = AMTrimmedString(filename);
  if ([normalized length] == 0) {
    return @"";
  }
  if ([[self.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    return [NSString stringWithFormat:@"/%@/%@", self.generatedPagePrefix ?: @"auth", normalized];
  }
  return [NSString stringWithFormat:@"%@/%@", self.uiAssetPrefix ?: @"/modules/auth", normalized];
}

// The framework mounts Resources/Public at /modules/auth, outside paths.prefix, so
// an app behind a path-scoped proxy cannot reach it. Serve the same directory
// under the module's own prefix too and link pages there; /modules/auth keeps working.
- (void)mountUIAssetsForApplication:(ALNApplication *)application {
  NSDictionary *moduleMount = nil;
  for (NSDictionary *mount in application.staticMounts) {
    if ([mount[@"prefix"] isEqual:@"/modules/auth"]) {
      moduleMount = mount;
    }
  }
  NSString *directory = moduleMount[@"directory"];
  if ([directory length] == 0) {
    return;
  }
  NSString *prefix = [self.prefix length] > 0 && ![self.prefix isEqualToString:@"/"] ? self.prefix : @"/auth";
  NSString *assetPrefix = AMPathJoin(prefix, @"assets");
  if ([application mountStaticDirectory:directory atPrefix:assetPrefix allowExtensions:moduleMount[@"allowExtensions"]]) {
    self.uiAssetPrefix = assetPrefix;
  }
}

- (NSString *)layoutTemplateForPage:(NSString *)pageIdentifier
                            context:(ALNContext *)context {
  NSString *defaultLayout = ([AMTrimmedString(self.layoutTemplate) length] > 0) ? self.layoutTemplate : @"modules/auth/layouts/main";
  if (self.uiContextHook != nil &&
      [self.uiContextHook respondsToSelector:@selector(authModuleUILayoutForPage:defaultLayout:context:)]) {
    NSString *override = [self.uiContextHook authModuleUILayoutForPage:AMNormalizedTemplateIdentifier(pageIdentifier)
                                                         defaultLayout:defaultLayout
                                                               context:context];
    if ([AMTrimmedString(override) length] > 0) {
      return override;
    }
  }
  return defaultLayout;
}

- (NSDictionary *)uiContextForPage:(NSString *)pageIdentifier
                    defaultContext:(NSDictionary *)defaultContext
                           context:(ALNContext *)context {
  NSMutableDictionary *resolved = [NSMutableDictionary dictionaryWithDictionary:defaultContext ?: @{}];
  if (self.uiContextHook != nil &&
      [self.uiContextHook respondsToSelector:@selector(authModuleUIContextForPage:defaultContext:context:)]) {
    NSDictionary *override = [self.uiContextHook authModuleUIContextForPage:AMNormalizedTemplateIdentifier(pageIdentifier)
                                                             defaultContext:defaultContext ?: @{}
                                                                    context:context];
    if ([override isKindOfClass:[NSDictionary class]]) {
      [resolved addEntriesFromDictionary:override];
    }
  }
  return [NSDictionary dictionaryWithDictionary:resolved];
}

- (NSDictionary *)loadUserBySQL:(NSString *)sql
                      parameters:(NSArray *)parameters
                           error:(NSError **)error {
  if (self.database == nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorDatabaseUnavailable, @"auth database is not configured", nil);
    }
    return nil;
  }
  NSArray *rows = [self.database executeQuery:(sql ?: @"") parameters:(parameters ?: @[]) error:error];
  if (rows == nil && error != NULL && *error != NULL) {
    *error = AMTranslateMissingAuthModuleTablesError(*error, self.environmentName);
  }
  NSDictionary *row = [rows firstObject];
  return AMUserDictionaryFromRow(row);
}

- (NSDictionary *)userForEmail:(NSString *)email
                         error:(NSError **)error {
  NSString *normalizedEmail = AMLowerTrimmedString(email);
  if ([normalizedEmail length] == 0) {
    return nil;
  }
  return [self loadUserBySQL:@"SELECT id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                             "COALESCE(roles_json, '[]') AS roles_json, "
                             "CASE WHEN email_verified_at IS NULL THEN '' ELSE email_verified_at::text END AS email_verified_at "
                             "FROM auth_users WHERE lower(email) = $1 LIMIT 1"
                   parameters:@[ normalizedEmail ]
                        error:error];
}

- (NSDictionary *)userForSubject:(NSString *)subject
                           error:(NSError **)error {
  NSString *normalizedSubject = AMTrimmedString(subject);
  if ([normalizedSubject length] == 0) {
    return nil;
  }
  return [self loadUserBySQL:@"SELECT id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                             "COALESCE(roles_json, '[]') AS roles_json, "
                             "CASE WHEN email_verified_at IS NULL THEN '' ELSE email_verified_at::text END AS email_verified_at "
                             "FROM auth_users WHERE subject = $1 LIMIT 1"
                   parameters:@[ normalizedSubject ]
                        error:error];
}

- (NSDictionary *)userForProvider:(NSString *)provider
                      providerSub:(NSString *)providerSubject
                            error:(NSError **)error {
  NSString *providerID = AMTrimmedString(provider);
  NSString *subject = AMTrimmedString(providerSubject);
  if ([providerID length] == 0 || [subject length] == 0) {
    return nil;
  }
  return [self loadUserBySQL:@"SELECT u.id::text AS id, u.subject, u.email, COALESCE(u.display_name, '') AS display_name, "
                             "COALESCE(u.roles_json, '[]') AS roles_json, "
                             "CASE WHEN u.email_verified_at IS NULL THEN '' ELSE u.email_verified_at::text END AS email_verified_at "
                             "FROM auth_provider_identities i "
                             "JOIN auth_users u ON u.id = i.user_id "
                             "WHERE i.provider = $1 AND i.provider_subject = $2 LIMIT 1"
                   parameters:@[ providerID, subject ]
                        error:error];
}

- (BOOL)insertProviderIdentityForUserID:(NSString *)userID
                               provider:(NSString *)provider
                        providerSubject:(NSString *)providerSubject
                                profile:(NSDictionary *)profile
                                  error:(NSError **)error {
  if (self.database == nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorDatabaseUnavailable, @"auth database is not configured", nil);
    }
    return NO;
  }
  NSInteger result = [self.database executeCommand:@"INSERT INTO auth_provider_identities "
                                               "(user_id, provider, provider_subject, profile_json, created_at, updated_at) "
                                               "VALUES ($1, $2, $3, $4, NOW(), NOW()) "
                                               "ON CONFLICT (provider, provider_subject) DO UPDATE "
                                               "SET user_id = EXCLUDED.user_id, profile_json = EXCLUDED.profile_json, updated_at = NOW()"
                                         parameters:@[ userID ?: @"", provider ?: @"", providerSubject ?: @"", AMJSONString(profile ?: @{}) ]
                                              error:error];
  return result >= 0;
}

- (NSDictionary *)createLocalUserWithEmail:(NSString *)email
                               displayName:(NSString *)displayName
                                  password:(NSString *)password
                                    source:(NSString *)source
                                     error:(NSError **)error {
  NSString *normalizedEmail = AMLowerTrimmedString(email);
  if ([normalizedEmail length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"Email is required", @{ @"field" : @"email" });
    }
    return nil;
  }
  NSString *passwordMessage = nil;
  if (![self validatePassword:(password ?: @"") errorMessage:&passwordMessage]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed,
                       passwordMessage ?: @"Password does not satisfy policy",
                       @{ @"field" : @"password" });
    }
    return nil;
  }
  if (![self registrationAllowedForRequest:@{
        @"email" : normalizedEmail,
        @"display_name" : AMTrimmedString(displayName),
        @"source" : source ?: @"local",
      }
                                 error:error]) {
    if (error != NULL && *error == NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected, @"Registration was rejected by policy", nil);
    }
    return nil;
  }
  NSError *lookupError = nil;
  NSDictionary *existingUser = [self userForEmail:normalizedEmail error:&lookupError];
  if (lookupError != nil) {
    if (error != NULL) {
      *error = lookupError;
    }
    return nil;
  }
  if (existingUser != nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"Email is already registered", @{ @"field" : @"email" });
    }
    return nil;
  }

  NSString *subject = [NSString stringWithFormat:@"user:%@", [[NSUUID UUID] UUIDString].lowercaseString];
  NSMutableArray *roles = [NSMutableArray arrayWithObject:@"user"];
  if ([self.bootstrapAdminEmails containsObject:normalizedEmail] && ![roles containsObject:@"admin"]) {
    [roles addObject:@"admin"];
  }
  NSDictionary *proposedValues = @{
    @"subject" : subject,
    @"email" : normalizedEmail,
    @"display_name" : AMTrimmedString(displayName),
    @"roles" : roles,
  };
  NSDictionary *userValues = [self provisionedUserValuesForEvent:(source ?: @"local_registration")
                                                  proposedValues:proposedValues];
  NSString *finalSubject = AMTrimmedString(userValues[@"subject"]);
  if ([finalSubject length] == 0) {
    finalSubject = subject;
  }
  NSString *finalEmail = AMLowerTrimmedString(userValues[@"email"]);
  if ([finalEmail length] == 0) {
    finalEmail = normalizedEmail;
  }
  NSString *finalDisplayName = AMTrimmedString(userValues[@"display_name"]);
  NSArray *finalRoles = AMJSONArrayFromJSONString(AMJSONString(userValues[@"roles"] ?: roles));

  NSError *hashError = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:(password ?: @"")
                                                      options:[ALNPasswordHash defaultArgon2idOptions]
                                                        error:&hashError];
  if ([encodedHash length] == 0) {
    if (error != NULL) {
      *error = hashError ?: AMError(ALNAuthModuleErrorValidationFailed, @"Failed to hash password", nil);
    }
    return nil;
  }

  __block NSDictionary *createdUser = nil;
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    NSDictionary *row = [connection executeQueryOne:@"INSERT INTO auth_users "
                                                 "(subject, email, display_name, roles_json, created_at, updated_at) "
                                                 "VALUES ($1, $2, $3, $4, NOW(), NOW()) "
                                                 "RETURNING id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                                                 "COALESCE(roles_json, '[]') AS roles_json, '' AS email_verified_at"
                                       parameters:@[ finalSubject, finalEmail, finalDisplayName ?: @"", AMJSONString(finalRoles ?: @[]) ]
                                            error:txError];
    if (row == nil) {
      return NO;
    }
    NSString *userID = AMTrimmedString(row[@"id"]);
    NSInteger insertedCredential = [connection executeCommand:@"INSERT INTO auth_local_credentials "
                                                         "(user_id, password_hash, created_at, updated_at) "
                                                         "VALUES ($1, $2, NOW(), NOW())"
                                                   parameters:@[ userID ?: @"", encodedHash ]
                                                        error:txError];
    if (insertedCredential < 0) {
      return NO;
    }
    createdUser = AMUserDictionaryFromRow(row);
    return (createdUser != nil);
  } error:error];
  if (!ok && error != NULL && *error != NULL) {
    *error = AMTranslateMissingAuthModuleTablesError(*error, self.environmentName);
  }
  return ok ? createdUser : nil;
}

- (NSDictionary *)createTrustedEmailClaimUserWithEmail:(NSString *)email
                                           displayName:(NSString *)displayName
                                                source:(NSString *)source
                                                 error:(NSError **)error {
  NSString *normalizedEmail = AMLowerTrimmedString(email);
  if ([normalizedEmail length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"Email is required", @{ @"field" : @"email" });
    }
    return nil;
  }
  if (![self registrationAllowedForRequest:@{
        @"email" : normalizedEmail,
        @"display_name" : AMTrimmedString(displayName),
        @"source" : source ?: @"trusted_email_claim",
      }
                                 error:error]) {
    if (error != NULL && *error == NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected, @"Registration was rejected by policy", nil);
    }
    return nil;
  }
  NSError *lookupError = nil;
  NSDictionary *existingUser = [self userForEmail:normalizedEmail error:&lookupError];
  if (lookupError != nil) {
    if (error != NULL) {
      *error = lookupError;
    }
    return nil;
  }
  if (existingUser != nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"Email is already registered", @{ @"field" : @"email" });
    }
    return nil;
  }

  NSString *subject = [NSString stringWithFormat:@"user:%@", [[NSUUID UUID] UUIDString].lowercaseString];
  NSMutableArray *roles = [NSMutableArray arrayWithObject:@"user"];
  if ([self.bootstrapAdminEmails containsObject:normalizedEmail] && ![roles containsObject:@"admin"]) {
    [roles addObject:@"admin"];
  }
  NSDictionary *proposedValues = @{
    @"subject" : subject,
    @"email" : normalizedEmail,
    @"display_name" : AMTrimmedString(displayName),
    @"roles" : roles,
  };
  NSDictionary *userValues = [self provisionedUserValuesForEvent:(source ?: @"trusted_email_claim")
                                                  proposedValues:proposedValues];
  NSString *finalSubject = AMTrimmedString(userValues[@"subject"]);
  if ([finalSubject length] == 0) {
    finalSubject = subject;
  }
  NSString *finalEmail = AMLowerTrimmedString(userValues[@"email"]);
  if ([finalEmail length] == 0) {
    finalEmail = normalizedEmail;
  }
  NSString *finalDisplayName = AMTrimmedString(userValues[@"display_name"]);
  NSArray *finalRoles = AMJSONArrayFromJSONString(AMJSONString(userValues[@"roles"] ?: roles));

  NSError *hashError = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:AMRandomToken(32)
                                                      options:[ALNPasswordHash defaultArgon2idOptions]
                                                        error:&hashError];
  if ([encodedHash length] == 0) {
    if (error != NULL) {
      *error = hashError ?: AMError(ALNAuthModuleErrorValidationFailed, @"Failed to provision claim credential", nil);
    }
    return nil;
  }

  __block NSDictionary *createdUser = nil;
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    NSDictionary *row = [connection executeQueryOne:@"INSERT INTO auth_users "
                                                 "(subject, email, display_name, roles_json, created_at, updated_at) "
                                                 "VALUES ($1, $2, $3, $4, NOW(), NOW()) "
                                                 "RETURNING id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                                                 "COALESCE(roles_json, '[]') AS roles_json, '' AS email_verified_at"
                                       parameters:@[ finalSubject, finalEmail, finalDisplayName ?: @"", AMJSONString(finalRoles ?: @[]) ]
                                            error:txError];
    if (row == nil) {
      return NO;
    }
    NSString *userID = AMTrimmedString(row[@"id"]);
    NSInteger insertedCredential = [connection executeCommand:@"INSERT INTO auth_local_credentials "
                                                         "(user_id, password_hash, created_at, updated_at) "
                                                         "VALUES ($1, $2, NOW(), NOW())"
                                                   parameters:@[ userID ?: @"", encodedHash ]
                                                        error:txError];
    if (insertedCredential < 0) {
      return NO;
    }
    createdUser = AMUserDictionaryFromRow(row);
    return (createdUser != nil);
  } error:error];
  if (!ok && error != NULL && *error != NULL) {
    *error = AMTranslateMissingAuthModuleTablesError(*error, self.environmentName);
  }
  return ok ? createdUser : nil;
}

- (NSDictionary *)createFederatedUserForIdentity:(NSDictionary *)normalizedIdentity
                                           error:(NSError **)error {
  NSString *email = AMLowerTrimmedString(normalizedIdentity[@"email"]);
  NSString *displayName = AMTrimmedString(normalizedIdentity[@"display_name"]);
  if ([email length] == 0) {
    email = [NSString stringWithFormat:@"user+%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  }
  NSMutableArray *roles = [NSMutableArray arrayWithObject:@"user"];
  if ([self.bootstrapAdminEmails containsObject:email] && ![roles containsObject:@"admin"]) {
    [roles addObject:@"admin"];
  }
  NSDictionary *values = [self provisionedUserValuesForEvent:@"provider_registration"
                                              proposedValues:@{
                                                @"subject" : [NSString stringWithFormat:@"user:%@", [[NSUUID UUID] UUIDString].lowercaseString],
                                                @"email" : email,
                                                @"display_name" : displayName ?: @"",
                                                @"roles" : roles,
                                              }];
  NSString *subject = AMTrimmedString(values[@"subject"]);
  if ([subject length] == 0) {
    subject = [NSString stringWithFormat:@"user:%@", [[NSUUID UUID] UUIDString].lowercaseString];
  }
  NSString *finalEmail = AMLowerTrimmedString(values[@"email"]);
  if ([finalEmail length] == 0) {
    finalEmail = email;
  }
  NSString *finalDisplayName = AMTrimmedString(values[@"display_name"]);
  NSArray *finalRoles = AMJSONArrayFromJSONString(AMJSONString(values[@"roles"] ?: roles));
  NSDictionary *row = [[self.database executeQuery:@"INSERT INTO auth_users "
                                               "(subject, email, display_name, roles_json, email_verified_at, created_at, updated_at) "
                                               "VALUES ($1, $2, $3, $4, NOW(), NOW(), NOW()) "
                                               "RETURNING id::text AS id, subject, email, COALESCE(display_name, '') AS display_name, "
                                               "COALESCE(roles_json, '[]') AS roles_json, NOW()::text AS email_verified_at"
                                         parameters:@[ subject, finalEmail, finalDisplayName ?: @"", AMJSONString(finalRoles ?: @[]) ]
                                              error:error] firstObject];
  return AMUserDictionaryFromRow(row);
}

- (NSUInteger)dummyPasswordVerificationCount {
  NSLock *lock = AMDummyPasswordVerificationLock();
  [lock lock];
  NSUInteger count = AMDummyPasswordVerifications;
  [lock unlock];
  return count;
}

- (NSDictionary *)authenticateLocalEmail:(NSString *)email
                                password:(NSString *)password
                                   error:(NSError **)error {
  return [self authenticateLocalEmail:email password:password clientAddress:nil error:error];
}

// Known and unknown emails take the same path: the limiter is keyed by the
// submitted email, runs before the account lookup, and both outcomes spend
// one Argon2 verification and return the same error.
- (NSDictionary *)authenticateLocalEmail:(NSString *)email
                                password:(NSString *)password
                           clientAddress:(NSString *)clientAddress
                                   error:(NSError **)error {
  NSString *normalizedEmail = AMLowerTrimmedString(email) ?: @"";
  NSString *emailKey = AMPasswordAttemptKeyForEmail(normalizedEmail);
  NSString *address = AMPasswordAttemptAddress(clientAddress);
  BOOL countedOnAccount = NO;
  NSString *armedAccountDelay = nil;
  if (![self reservePasswordAttemptForEmailKey:emailKey
                                 clientAddress:address
                              countedOnAccount:&countedOnAccount
                             armedAccountDelay:&armedAccountDelay
                                         error:error]) {
    return nil;
  }
  NSError *lookupError = nil;
  NSArray *rows = [self.database executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                                              "COALESCE(u.display_name, '') AS display_name, "
                                              "COALESCE(u.roles_json, '[]') AS roles_json, "
                                              "CASE WHEN u.email_verified_at IS NULL THEN '' ELSE u.email_verified_at::text END AS email_verified_at, "
                                              "c.password_hash "
                                              "FROM auth_users u "
                                              "JOIN auth_local_credentials c ON c.user_id = u.id "
                                              "WHERE lower(u.email) = $1 LIMIT 1"
                                    parameters:@[ normalizedEmail ]
                                         error:&lookupError];
  if (rows == nil && lookupError != nil) {
    // The lookup did not run (for example, the database is unavailable);
    // report that rather than a wrong password.
    if (error != NULL) {
      *error = AMTranslateMissingAuthModuleTablesError(lookupError, self.environmentName);
    }
    return nil;
  }
  NSDictionary *row = [rows firstObject];
  NSString *encodedHash = AMTrimmedString(row[@"password_hash"]);
  BOOL verified = NO;
  if ([encodedHash length] == 0) {
    AMSpendDummyPasswordVerification(password);
  } else {
    verified = [ALNPasswordHash verifyPasswordString:(password ?: @"")
                                  againstEncodedHash:encodedHash
                                               error:NULL];
  }
  if (!verified) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"Invalid email or password", nil);
    }
    return nil;
  }
  [self recordPasswordSuccessForEmailKey:emailKey
                          clientAddress:address
                       countedOnAccount:countedOnAccount
                      armedAccountDelay:armedAccountDelay];
  return AMUserDictionaryFromRow(row);
}

- (NSDictionary *)startSessionForUser:(NSDictionary *)user
                             provider:(NSString *)provider
                              methods:(NSArray *)methods
                              context:(ALNContext *)context
                                error:(NSError **)error {
  NSDictionary *defaultDescriptor = @{
    @"subject" : AMTrimmedString(user[@"subject"]),
    @"provider" : AMTrimmedString(provider),
    @"methods" : methods ?: @[ @"pwd" ],
    @"roles" : [user[@"roles"] isKindOfClass:[NSArray class]] ? user[@"roles"] : @[],
    @"scopes" : @[],
    @"assuranceLevel" : @1,
  };
  NSDictionary *descriptor = [self sessionDescriptorForUser:user defaultDescriptor:defaultDescriptor];
  BOOL ok = [ALNAuthSession establishAuthenticatedSessionForSubject:AMTrimmedString(descriptor[@"subject"])
                                                          provider:AMTrimmedString(descriptor[@"provider"])
                                                           methods:descriptor[@"methods"]
                                                            scopes:descriptor[@"scopes"]
                                                             roles:descriptor[@"roles"]
                                                    assuranceLevel:[descriptor[@"assuranceLevel"] respondsToSelector:@selector(integerValue)] ? [descriptor[@"assuranceLevel"] unsignedIntegerValue] : 1U
                                                   authenticatedAt:nil
                                                           context:context
                                                             error:error];
  if (!ok) {
    return nil;
  }
  if (![self recordSessionStampForContext:context error:error]) {
    [ALNAuthSession clearAuthenticatedSessionForContext:context];
    return nil;
  }
  return [self sessionPayloadForContext:context includeUser:YES error:error];
}

- (BOOL)sendNotificationEvent:(NSString *)event
                         user:(NSDictionary *)user
                        token:(NSString *)token
                      baseURL:(NSString *)baseURL
                        error:(NSError **)error {
  if (self.mailAdapter == nil) {
    return YES;
  }
  NSString *email = AMLowerTrimmedString(user[@"email"]);
  if ([email length] == 0) {
    return YES;
  }
  if ([AMTrimmedString(baseURL) length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorInvalidConfiguration, @"A base URL is required to send auth email links",
                       @{ @"key_path" : @"authModule.publicBaseURL" });
    }
    return NO;
  }
  NSString *eventName = AMTrimmedString(event);
  NSString *path = [eventName isEqualToString:@"password_reset"] ? self.resetPasswordPath : self.verifyPath;
  if ([self isHeadlessUIMode]) {
    if ([eventName isEqualToString:@"password_reset"]) {
      path = AMPathJoin(self.apiPrefix, @"password/reset");
    } else {
      path = AMPathJoin(self.apiPrefix, @"verify");
    }
  }
  NSString *link = [NSString stringWithFormat:@"%@%@?token=%@", baseURL ?: @"", path ?: @"", token ?: @""];
  NSString *subject = [eventName isEqualToString:@"password_reset"] ? @"Reset your password" : @"Verify your email";
  NSString *body = [eventName isEqualToString:@"password_reset"]
                        ? [NSString stringWithFormat:@"Open %@ to reset your password.", link]
                        : [NSString stringWithFormat:@"Open %@ to verify your email.", link];
  ALNMailMessage *defaultMessage = [[ALNMailMessage alloc] initWithFrom:@"noreply@arlen.local"
                                                                     to:@[ email ]
                                                                     cc:nil
                                                                    bcc:nil
                                                                subject:subject
                                                               textBody:body
                                                               htmlBody:nil
                                                                headers:nil
                                                               metadata:@{
                                                                 @"event" : eventName ?: @"",
                                                                 @"user_subject" : AMTrimmedString(user[@"subject"]),
                                                               }];
  ALNMailMessage *message = defaultMessage;
  if (self.notificationHook != nil &&
      [self.notificationHook respondsToSelector:@selector(authModuleMailMessageForEvent:user:token:baseURL:defaultMessage:)]) {
    ALNMailMessage *override = [self.notificationHook authModuleMailMessageForEvent:eventName
                                                                               user:(user ?: @{})
                                                                              token:(token ?: @"")
                                                                            baseURL:(baseURL ?: @"")
                                                                     defaultMessage:defaultMessage];
    if ([override isKindOfClass:[ALNMailMessage class]]) {
      message = override;
    }
  }
  NSString *deliveryID = [self.mailAdapter deliverMessage:message error:error];
  return ([deliveryID length] > 0);
}

- (NSString *)issueVerificationTokenForUserID:(NSString *)userID
                                        error:(NSError **)error {
  NSString *token = AMRandomToken(24);
  NSInteger result = [self.database executeCommand:@"INSERT INTO auth_verification_tokens "
                                               "(user_id, token, purpose, expires_at, created_at) "
                                               "VALUES ($1, $2, 'email_verify', NOW() + INTERVAL '1 day', NOW())"
                                         parameters:@[ userID ?: @"", AMStoredBearerToken(token) ]
                                              error:error];
  return (result >= 0) ? token : nil;
}

- (NSString *)issuePasswordResetTokenForUserID:(NSString *)userID
                                         error:(NSError **)error {
  NSString *token = AMRandomToken(24);
  NSInteger result = [self.database executeCommand:@"INSERT INTO auth_password_reset_tokens "
                                               "(user_id, token, expires_at, created_at) "
                                               "VALUES ($1, $2, NOW() + INTERVAL '30 minutes', NOW())"
                                         parameters:@[ userID ?: @"", AMStoredBearerToken(token) ]
                                              error:error];
  return (result >= 0) ? token : nil;
}

- (BOOL)markEmailVerifiedForUserID:(NSString *)userID
                             error:(NSError **)error {
  NSString *normalizedUserID = AMTrimmedString(userID);
  if ([normalizedUserID length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"User identifier is required", @{ @"field" : @"user_id" });
    }
    return NO;
  }
  NSInteger updated = [self.database executeCommand:@"UPDATE auth_users "
                                                "SET email_verified_at = COALESCE(email_verified_at, NOW()), updated_at = NOW() "
                                                "WHERE id = $1"
                                          parameters:@[ normalizedUserID ]
                                               error:error];
  return (updated >= 0);
}

// Any password change retires every outstanding reset token for the user, so a
// link issued before the change cannot be used afterwards.
- (BOOL)invalidatePasswordResetTokensForUserID:(NSString *)userID
                                    connection:(ALNPgConnection *)connection
                                         error:(NSError **)error {
  NSInteger invalidated = [connection executeCommand:@"UPDATE auth_password_reset_tokens SET consumed_at = NOW() "
                                                 "WHERE user_id = $1 AND consumed_at IS NULL"
                                           parameters:@[ userID ?: @"" ]
                                                error:error];
  return (invalidated >= 0);
}

- (BOOL)updateLocalPasswordHash:(NSString *)encodedHash
                      forUserID:(NSString *)userID
                          error:(NSError **)error {
  NSString *normalizedUserID = AMTrimmedString(userID);
  return [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    NSInteger updated = [connection executeCommand:@"UPDATE auth_local_credentials "
                                               "SET password_hash = $2, updated_at = NOW() WHERE user_id = $1"
                                         parameters:@[ normalizedUserID, encodedHash ?: @"" ]
                                              error:txError];
    if (updated < 0) {
      return NO;
    }
    // A new password ends the user's existing sessions.
    if (![self bumpSessionStampForUserID:normalizedUserID connection:connection error:txError]) {
      return NO;
    }
    return [self invalidatePasswordResetTokensForUserID:normalizedUserID connection:connection error:txError];
  } error:error];
}

- (BOOL)consumeVerificationToken:(NSString *)token
                            user:(NSDictionary **)user
                           error:(NSError **)error {
  NSString *normalizedToken = AMTrimmedString(token);
  NSString *storedToken = AMStoredBearerToken(normalizedToken);
  NSDictionary *row = [[self.database executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                                                 "COALESCE(u.display_name, '') AS display_name, "
                                                 "COALESCE(u.roles_json, '[]') AS roles_json, '' AS email_verified_at "
                                                 "FROM auth_verification_tokens t "
                                                 "JOIN auth_users u ON u.id = t.user_id "
                                                 "WHERE t.token = $1 AND t.consumed_at IS NULL AND t.expires_at > NOW() "
                                                 "ORDER BY t.id DESC LIMIT 1"
                                       parameters:@[ storedToken ]
                                            error:error] firstObject];
  NSString *userID = AMTrimmedString(row[@"id"]);
  if ([userID length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"Verification token is invalid or expired", nil);
    }
    return NO;
  }
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    // The conditional UPDATE is the single-use gate: of several concurrent
    // requests with one token, only one sees a row come back.
    NSDictionary *claimed = [connection executeQueryOne:@"UPDATE auth_verification_tokens SET consumed_at = NOW() "
                                                     "WHERE token = $1 AND consumed_at IS NULL AND expires_at > NOW() "
                                                     "RETURNING user_id::text AS user_id"
                                             parameters:@[ storedToken ]
                                                  error:txError];
    if (![AMTrimmedString(claimed[@"user_id"]) isEqualToString:userID]) {
      if (txError != NULL && *txError == nil) {
        *txError = AMError(ALNAuthModuleErrorNotFound, @"Verification token is invalid or expired", nil);
      }
      return NO;
    }
    NSInteger updated = [connection executeCommand:@"UPDATE auth_users SET email_verified_at = NOW(), updated_at = NOW() "
                                               "WHERE id = $1"
                                         parameters:@[ userID ]
                                              error:txError];
    return (updated >= 0);
  } error:error];
  if (ok && user != NULL) {
    *user = [self userForSubject:AMTrimmedString(row[@"subject"]) error:NULL];
  }
  return ok;
}

- (BOOL)consumePasswordResetToken:(NSString *)token
                         password:(NSString *)password
                             user:(NSDictionary **)user
                            error:(NSError **)error {
  NSString *passwordMessage = nil;
  if (![self validatePassword:(password ?: @"") errorMessage:&passwordMessage]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, passwordMessage ?: @"Password does not satisfy policy", nil);
    }
    return NO;
  }
  NSString *normalizedToken = AMTrimmedString(token);
  NSString *storedToken = AMStoredBearerToken(normalizedToken);
  NSDictionary *row = [[self.database executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                                                 "COALESCE(u.display_name, '') AS display_name, "
                                                 "COALESCE(u.roles_json, '[]') AS roles_json, "
                                                 "CASE WHEN u.email_verified_at IS NULL THEN '' ELSE u.email_verified_at::text END AS email_verified_at "
                                                 "FROM auth_password_reset_tokens t "
                                                 "JOIN auth_users u ON u.id = t.user_id "
                                                 "WHERE t.token = $1 AND t.consumed_at IS NULL AND t.expires_at > NOW() "
                                                 "ORDER BY t.id DESC LIMIT 1"
                                       parameters:@[ storedToken ]
                                            error:error] firstObject];
  NSString *userID = AMTrimmedString(row[@"id"]);
  if ([userID length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"Password reset token is invalid or expired", nil);
    }
    return NO;
  }
  NSError *hashError = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:(password ?: @"")
                                                      options:[ALNPasswordHash defaultArgon2idOptions]
                                                        error:&hashError];
  if ([encodedHash length] == 0) {
    if (error != NULL) {
      *error = hashError;
    }
    return NO;
  }
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    // The conditional UPDATE is the single-use gate: of several concurrent
    // requests with one token, only one sees a row come back and goes on to
    // change the password.
    NSDictionary *claimed = [connection executeQueryOne:@"UPDATE auth_password_reset_tokens SET consumed_at = NOW() "
                                                     "WHERE token = $1 AND consumed_at IS NULL AND expires_at > NOW() "
                                                     "RETURNING user_id::text AS user_id"
                                             parameters:@[ storedToken ]
                                                  error:txError];
    if (![AMTrimmedString(claimed[@"user_id"]) isEqualToString:userID]) {
      if (txError != NULL && *txError == nil) {
        *txError = AMError(ALNAuthModuleErrorNotFound, @"Password reset token is invalid or expired", nil);
      }
      return NO;
    }
    NSInteger updated = [connection executeCommand:@"INSERT INTO auth_local_credentials "
                                               "(user_id, password_hash, created_at, updated_at) "
                                               "VALUES ($1, $2, NOW(), NOW()) "
                                               "ON CONFLICT (user_id) DO UPDATE "
                                               "SET password_hash = EXCLUDED.password_hash, updated_at = NOW()"
                                         parameters:@[ userID, encodedHash ]
                                              error:txError];
    if (updated < 0) {
      return NO;
    }
    // A reset ends the user's existing sessions; the reset flow signs the
    // resetting browser in afresh.
    if (![self bumpSessionStampForUserID:userID connection:connection error:txError]) {
      return NO;
    }
    return [self invalidatePasswordResetTokensForUserID:userID connection:connection error:txError];
  } error:error];
  if (ok && user != NULL) {
    *user = [self userForSubject:AMTrimmedString(row[@"subject"]) error:NULL];
  }
  return ok;
}

#pragma mark - Attempt limits and TOTP replay protection

- (BOOL)attemptLimitSchemaIsAvailable {
  [self.attemptLimitSchemaLock lock];
  BOOL known = self.attemptLimitSchemaAvailable && self.attemptLimitSchemaDatabase == self.database;
  [self.attemptLimitSchemaLock unlock];
  if (known) {
    return YES;
  }
  NSArray *rows = [self.database executeQuery:@"SELECT CASE WHEN to_regclass('auth_attempt_limits') IS NOT NULL "
                                         "AND to_regclass('auth_password_attempts') IS NOT NULL "
                                         "AND to_regclass('auth_mail_sends') IS NOT NULL "
                                         "AND EXISTS (SELECT 1 FROM pg_attribute "
                                         "WHERE attrelid = to_regclass('auth_mfa_enrollments') "
                                         "AND attname = 'last_used_step' AND NOT attisdropped) "
                                         "THEN 't' ELSE 'f' END AS available"
                                   parameters:@[]
                                        error:NULL];
  if (rows == nil) {
    // The check itself failed (for example, no free connection); the caller's
    // next query reports that. Do not warn about the migration.
    return NO;
  }
  BOOL available = AMBoolFromDatabaseValue([rows firstObject][@"available"]);
  BOOL shouldWarn = NO;
  [self.attemptLimitSchemaLock lock];
  if (available) {
    self.attemptLimitSchemaAvailable = YES;
    self.attemptLimitSchemaDatabase = self.database;
  } else if (!self.attemptLimitSchemaWarningLogged) {
    self.attemptLimitSchemaWarningLogged = YES;
    shouldWarn = YES;
  }
  [self.attemptLimitSchemaLock unlock];
  if (shouldWarn) {
    NSString *fixCommand = [NSString stringWithFormat:@"./bin/arlen module migrate --env %@",
                                                      AMEffectiveEnvironmentName(self.environmentName)];
    NSString *message =
        [NSString stringWithFormat:@"auth module migration 004_auth_totp_limits is not applied; TOTP codes can be "
                                   "reused within their window and MFA/password attempts are not limited until "
                                   "you run %@",
                                   fixCommand];
    if (self.logger != nil) {
      [self.logger warn:message fields:@{ @"module" : @"auth", @"fix_command" : fixCommand }];
    } else {
      NSLog(@"%@", message);
    }
  }
  return available;
}

- (void)markAttemptLimitSchemaUnavailable {
  [self.attemptLimitSchemaLock lock];
  self.attemptLimitSchemaAvailable = NO;
  [self.attemptLimitSchemaLock unlock];
}

// Counts the attempt as a failure before the secret is checked, so parallel
// requests cannot run more checks than the limit allows; a successful check
// clears the count. Returns NO with an ALNAuthModuleErrorRateLimited error while
// the account is locked.
- (BOOL)reserveAttemptForUserID:(NSString *)userID
                          scope:(NSString *)scope
                    maxFailures:(NSUInteger)maxFailures
                 lockoutSeconds:(NSUInteger)lockoutSeconds
              maxLockoutSeconds:(NSUInteger)maxLockoutSeconds
                          error:(NSError **)error {
  NSString *normalizedUserID = AMTrimmedString(userID);
  if (maxFailures == 0 || [normalizedUserID length] == 0 || self.database == nil) {
    return YES;
  }
  if (![self attemptLimitSchemaIsAvailable]) {
    return YES;
  }
  __block NSUInteger retryAfter = 0;
  NSError *dbError = nil;
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    if ([connection executeCommand:@"INSERT INTO auth_attempt_limits (user_id, scope) VALUES ($1::bigint, $2) "
                                   "ON CONFLICT (user_id, scope) DO NOTHING"
                        parameters:@[ normalizedUserID, scope ]
                             error:txError] < 0) {
      return NO;
    }
    NSArray *rows = [connection executeQuery:@"SELECT failure_count::text AS failure_count, "
                                             "COALESCE(CEIL(EXTRACT(EPOCH FROM (locked_until - NOW()))), 0)::bigint::text "
                                             "AS lock_remaining, "
                                             "COALESCE(EXTRACT(EPOCH FROM (NOW() - last_failure_at)), -1)::float8::text "
                                             "AS since_failure "
                                             "FROM auth_attempt_limits WHERE user_id = $1::bigint AND scope = $2 "
                                             "FOR UPDATE"
                                  parameters:@[ normalizedUserID, scope ]
                                       error:txError];
    NSDictionary *row = [rows firstObject];
    if (row == nil) {
      return NO;
    }
    long long lockRemaining = [AMTrimmedString(row[@"lock_remaining"]) longLongValue];
    if (lockRemaining > 0) {
      retryAfter = (NSUInteger)lockRemaining;
      return YES;
    }
    double sinceFailure = [AMTrimmedString(row[@"since_failure"]) doubleValue];
    long long storedCount = [AMTrimmedString(row[@"failure_count"]) longLongValue];
    NSUInteger count = (sinceFailure < 0.0 || sinceFailure > AMAttemptFailureWindowSeconds || storedCount < 0)
                           ? 0U
                           : (NSUInteger)storedCount;
    NSUInteger nextCount = count + 1U;
    NSUInteger lockSeconds = 0;
    if (nextCount >= maxFailures) {
      NSUInteger exponent = MIN(nextCount - maxFailures, (NSUInteger)20U);
      double scaled = (double)lockoutSeconds * pow(2.0, (double)exponent);
      lockSeconds = (NSUInteger)MIN(scaled, (double)maxLockoutSeconds);
    }
    return [connection executeCommand:@"UPDATE auth_attempt_limits SET failure_count = $3::integer, "
                                      "last_failure_at = NOW(), "
                                      "locked_until = CASE WHEN $4::integer > 0 "
                                      "THEN NOW() + ($4::integer * INTERVAL '1 second') ELSE NULL END, "
                                      "updated_at = NOW() "
                                      "WHERE user_id = $1::bigint AND scope = $2"
                           parameters:@[
                             normalizedUserID,
                             scope,
                             [NSString stringWithFormat:@"%lu", (unsigned long)nextCount],
                             [NSString stringWithFormat:@"%lu", (unsigned long)lockSeconds],
                           ]
                                error:txError] >= 0;
  } error:&dbError];
  if (!ok) {
    if (AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
      [self markAttemptLimitSchemaUnavailable];
      (void)[self attemptLimitSchemaIsAvailable];
      return YES;
    }
    if (error != NULL) {
      *error = dbError ?: AMError(ALNAuthModuleErrorDatabaseUnavailable, @"Failed to record the verification attempt", nil);
    }
    return NO;
  }
  if (retryAfter > 0) {
    if (error != NULL) {
      *error = AMRateLimitedError(retryAfter,
                                  [NSString stringWithFormat:@"Too many failed attempts. Try again in %lu seconds.",
                                                             (unsigned long)retryAfter]);
    }
    return NO;
  }
  return YES;
}

- (void)clearAttemptFailuresForUserID:(NSString *)userID scope:(NSString *)scope {
  NSString *normalizedUserID = AMTrimmedString(userID);
  if ([normalizedUserID length] == 0 || self.database == nil || ![self attemptLimitSchemaIsAvailable]) {
    return;
  }
  NSError *dbError = nil;
  NSInteger updated = [self.database executeCommand:@"UPDATE auth_attempt_limits SET failure_count = 0, "
                                                    "last_failure_at = NULL, locked_until = NULL, updated_at = NOW() "
                                                    "WHERE user_id = $1::bigint AND scope = $2"
                                         parameters:@[ normalizedUserID, scope ]
                                              error:&dbError];
  if (updated < 0 && AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
    [self markAttemptLimitSchemaUnavailable];
  }
}

// Stores `step` as the enrollment's last accepted TOTP step. Returns NO and sets
// *replayed when that step (or a later one) was already accepted.
- (BOOL)recordAcceptedTOTPStep:(NSUInteger)step
                  enrollmentID:(NSString *)enrollmentID
                      replayed:(BOOL *)replayed
                         error:(NSError **)error {
  if (replayed != NULL) {
    *replayed = NO;
  }
  if (![self attemptLimitSchemaIsAvailable]) {
    return YES;
  }
  NSError *dbError = nil;
  NSInteger updated = [self.database executeCommand:@"UPDATE auth_mfa_enrollments SET last_used_step = $2::bigint "
                                                    "WHERE id = $1::bigint "
                                                    "AND (last_used_step IS NULL OR last_used_step < $2::bigint)"
                                         parameters:@[
                                           AMTrimmedString(enrollmentID) ?: @"",
                                           [NSString stringWithFormat:@"%lu", (unsigned long)step],
                                         ]
                                              error:&dbError];
  if (updated < 0) {
    if (AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
      [self markAttemptLimitSchemaUnavailable];
      (void)[self attemptLimitSchemaIsAvailable];
      return YES;
    }
    if (error != NULL) {
      *error = dbError;
    }
    return NO;
  }
  if (updated == 0) {
    if (replayed != NULL) {
      *replayed = YES;
    }
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed,
                       @"That authenticator code was already used. Wait for the next code and try again.",
                       nil);
    }
    return NO;
  }
  return YES;
}

// Removes `code` from the enrollment's stored recovery codes with a
// compare-and-set update. When another request changed the stored set first
// (it used a different code), the set is read again and the update retried,
// up to three times, so two different valid codes used at once both succeed.
- (BOOL)consumeRecoveryCode:(NSString *)code
                 enrollment:(NSDictionary *)enrollment
                      error:(NSError **)error {
  NSString *enrollmentID = AMTrimmedString(enrollment[@"id"]) ?: @"";
  NSString *storedJSON = AMTrimmedString(enrollment[@"recovery_codes_json"]) ?: @"[]";
  for (NSUInteger attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      NSError *readError = nil;
      NSArray *rows = [self.database executeQuery:@"SELECT COALESCE(recovery_codes_json, '[]') AS recovery_codes_json "
                                                  "FROM auth_mfa_enrollments WHERE id = $1::bigint"
                                       parameters:@[ enrollmentID ]
                                            error:&readError];
      if (rows == nil) {
        if (error != NULL) {
          *error = readError;
        }
        return NO;
      }
      storedJSON = AMTrimmedString([rows firstObject][@"recovery_codes_json"]) ?: @"[]";
    }
    NSArray *hashes = AMJSONStringArrayFromJSONString(storedJSON);
    NSArray *remaining = nil;
    BOOL matched = ([hashes count] > 0) &&
                   [ALNRecoveryCodes consumeCode:(code ?: @"")
                            againstEncodedHashes:hashes
                          remainingEncodedHashes:&remaining
                                           error:NULL];
    if (!matched) {
      break;
    }
    NSError *dbError = nil;
    NSInteger updated = [self.database executeCommand:@"UPDATE auth_mfa_enrollments SET recovery_codes_json = $2, "
                                                      "updated_at = NOW() "
                                                      "WHERE id = $1::bigint AND COALESCE(recovery_codes_json, '[]') = $3"
                                           parameters:@[ enrollmentID, AMJSONString(remaining ?: @[]), storedJSON ]
                                                error:&dbError];
    if (updated < 0) {
      if (error != NULL) {
        *error = dbError;
      }
      return NO;
    }
    if (updated == 1) {
      return YES;
    }
  }
  if (error != NULL) {
    *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"Invalid authenticator or recovery code", nil);
  }
  return NO;
}

#pragma mark - Password attempt delays and mail send limits

// Deletes at most passwordPruneBatchSize rows per call, across
// auth_password_attempts and auth_mail_sends, in this order:
//   1. expired rows with no active wait: account-wide ('*') rows untouched for
//      a whole accountWindowSeconds (their count would restart anyway), pair
//      rows untouched for 24 hours whose last successful sign-in (if any) is
//      older than passwordTrustedPairDays, and mail rows past their window;
//   2. while the password table holds more than passwordMaxTrackedEntries
//      rows: pair rows still in the free tier (fewer than
//      passwordMaxFailures failures, no active wait), oldest first, pairs
//      without a recent successful sign-in before those with one.
// Account-wide rows and rows with an active wait are never removed to meet
// the cap; if only those are left, the table stays over the cap until they
// expire, and a warning is logged. Every statement is bounded by LIMIT and
// walks the updated_at indexes; the only count reads at most
// passwordMaxTrackedEntries + passwordPruneBatchSize rows. Returns rows
// removed, or -1 when the tables are unavailable. The request path runs it on
// a background queue.
- (NSInteger)prunePasswordAttempts {
  if (self.database == nil || ![self attemptLimitSchemaIsAvailable]) {
    return -1;
  }
  NSUInteger budget = MAX(self.passwordPruneBatchSize, (NSUInteger)1U);
  NSString *(^number)(NSUInteger) = ^NSString *(NSUInteger value) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)value];
  };
  NSString *accountWindow = number(MAX(self.passwordAccountWindowSeconds, (NSUInteger)1U));
  NSString *trustedSeconds = number(self.passwordTrustedPairDays * 86400U);
  NSString *mailWindow = number(MAX(self.mailWindowSeconds, (NSUInteger)1U));
  NSString *pairMax = number(MAX(self.passwordMaxFailures, (NSUInteger)1U));
  NSInteger removed = 0;
  __block NSInteger budgetLeft = (NSInteger)budget;

  NSArray *expirySteps = @[
    @[ @"DELETE FROM auth_password_attempts WHERE ctid IN ("
       "SELECT ctid FROM auth_password_attempts "
       "WHERE updated_at < NOW() - ($1::integer * INTERVAL '1 second') AND client_ip = '*' "
       "AND (delayed_until IS NULL OR delayed_until <= NOW()) "
       "ORDER BY updated_at LIMIT $2::integer)",
       accountWindow ],
    @[ @"DELETE FROM auth_password_attempts WHERE ctid IN ("
       "SELECT ctid FROM auth_password_attempts "
       "WHERE updated_at < NOW() - INTERVAL '24 hours' AND client_ip <> '*' "
       "AND (delayed_until IS NULL OR delayed_until <= NOW()) "
       "AND (last_success_at IS NULL OR last_success_at < NOW() - ($1::integer * INTERVAL '1 second')) "
       "ORDER BY updated_at LIMIT $2::integer)",
       trustedSeconds ],
    @[ @"DELETE FROM auth_mail_sends WHERE ctid IN ("
       "SELECT ctid FROM auth_mail_sends "
       "WHERE updated_at < NOW() - ($1::integer * INTERVAL '1 second') "
       "ORDER BY updated_at LIMIT $2::integer)",
       mailWindow ],
  ];
  for (NSArray *step in expirySteps) {
    if (budgetLeft <= 0) {
      break;
    }
    NSError *dbError = nil;
    NSInteger deleted = [self.database executeCommand:step[0]
                                           parameters:@[ step[1], number((NSUInteger)budgetLeft) ]
                                                error:&dbError];
    if (deleted < 0) {
      if (AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
        [self markAttemptLimitSchemaUnavailable];
        return -1;
      }
      continue;
    }
    removed += deleted;
    budgetLeft -= deleted;
  }
  if (budgetLeft <= 0) {
    return removed;
  }

  NSUInteger cap = self.passwordMaxTrackedEntries;
  NSArray *rows = [self.database executeQuery:@"SELECT COUNT(*)::text AS total FROM "
                                              "(SELECT 1 FROM auth_password_attempts LIMIT $1::bigint) bounded"
                                   parameters:@[ number(cap + budget) ]
                                        error:NULL];
  long long total = [AMTrimmedString([rows firstObject][@"total"]) longLongValue];
  if (total <= (long long)cap) {
    return removed;
  }
  NSInteger overflow = (NSInteger)MIN((long long)budgetLeft, total - (long long)cap);
  NSArray *evictionSteps = @[
    @"DELETE FROM auth_password_attempts WHERE ctid IN ("
     "SELECT ctid FROM auth_password_attempts "
     "WHERE client_ip <> '*' AND failure_count < $1::integer "
     "AND (delayed_until IS NULL OR delayed_until <= NOW()) "
     "AND (last_success_at IS NULL OR last_success_at < NOW() - ($2::integer * INTERVAL '1 second')) "
     "ORDER BY updated_at LIMIT $3::integer)",
    @"DELETE FROM auth_password_attempts WHERE ctid IN ("
     "SELECT ctid FROM auth_password_attempts "
     "WHERE client_ip <> '*' AND failure_count < $1::integer "
     "AND (delayed_until IS NULL OR delayed_until <= NOW()) "
     "AND $2::integer >= 0 "
     "ORDER BY updated_at LIMIT $3::integer)",
  ];
  for (NSString *sql in evictionSteps) {
    if (overflow <= 0) {
      break;
    }
    NSInteger deleted = [self.database executeCommand:sql
                                           parameters:@[ pairMax, trustedSeconds, number((NSUInteger)overflow) ]
                                                error:NULL];
    if (deleted > 0) {
      removed += deleted;
      overflow -= deleted;
    }
  }
  if (overflow > 0 && (NSUInteger)removed < budget) {
    // Only account-wide rows and rows with an active wait are left over the
    // cap. They are kept; the table shrinks again as they expire.
    NSString *message = @"auth module sign-in counters are over maxTrackedEntries; account-wide and "
                         "waiting entries are kept until they expire";
    NSDictionary *fields = @{ @"module" : @"auth", @"cap" : @(cap), @"over_by_at_least" : @(overflow) };
    if (self.logger != nil) {
      [self.logger warn:message fields:fields];
    } else {
      NSLog(@"%@ %@", message, fields);
    }
  }
  return removed;
}

- (void)prunePasswordAttemptsIfDue {
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  BOOL due = NO;
  [self.attemptLimitSchemaLock lock];
  if (now - self.passwordAttemptsLastPrunedAt >= 60.0) {
    self.passwordAttemptsLastPrunedAt = now;
    due = YES;
  }
  [self.attemptLimitSchemaLock unlock];
  if (!due) {
    return;
  }
  static dispatch_queue_t pruneQueue;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    pruneQueue = dispatch_queue_create("arlen.auth.prune-attempts", DISPATCH_QUEUE_SERIAL);
  });
  dispatch_async(pruneQueue, ^{
    (void)[self prunePasswordAttempts];
  });
}

// Counts the attempt for the (email, address) pair before the password is
// checked and, unless that pair signed in successfully within
// passwordTrustedPairDays or the ceiling is off, for the email across all
// addresses. Locks the pair row, then the account row, so concurrent attempts
// cannot deadlock. Returns NO with an ALNAuthModuleErrorRateLimited error
// while a wait applies. *countedOnAccount says whether the account-wide count
// was raised (a success then takes it back).
- (BOOL)reservePasswordAttemptForEmailKey:(NSString *)emailKey
                            clientAddress:(NSString *)address
                         countedOnAccount:(BOOL *)countedOnAccount
                       armedAccountDelay:(NSString **)armedAccountDelay
                                    error:(NSError **)error {
  if (countedOnAccount != NULL) {
    *countedOnAccount = NO;
  }
  if (armedAccountDelay != NULL) {
    *armedAccountDelay = nil;
  }
  if (self.passwordMaxFailures == 0 || self.database == nil || ![self attemptLimitSchemaIsAvailable]) {
    return YES;
  }
  [self prunePasswordAttemptsIfDue];
  NSUInteger pairMax = self.passwordMaxFailures;
  NSUInteger accountMax = self.passwordAccountMaxFailures;
  NSUInteger accountWindow = self.passwordAccountWindowSeconds;
  NSUInteger delayBase = self.passwordDelaySeconds;
  NSUInteger accountDelayBase = self.passwordAccountDelaySeconds;
  NSUInteger maxDelay = self.passwordMaxDelaySeconds;
  NSUInteger trustedSeconds = self.passwordTrustedPairDays * 86400U;
  __block NSUInteger retryAfter = 0;
  __block BOOL accountCounted = NO;
  __block NSString *accountDelayArmed = nil;
  NSError *dbError = nil;
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    if ([connection executeCommand:@"INSERT INTO auth_password_attempts (key_hash, client_ip) VALUES ($1, $2) "
                                   "ON CONFLICT (key_hash, client_ip) DO NOTHING"
                        parameters:@[ emailKey, address ]
                             error:txError] < 0) {
      return NO;
    }
    NSDictionary *pairRow = [[connection executeQuery:@"SELECT failure_count::text AS failure_count, "
                                                      "COALESCE(CEIL(EXTRACT(EPOCH FROM (delayed_until - NOW()))), 0)::bigint::text "
                                                      "AS delay_remaining, "
                                                      "COALESCE(EXTRACT(EPOCH FROM (NOW() - last_failure_at)), -1)::float8::text "
                                                      "AS since_failure, "
                                                      "COALESCE(EXTRACT(EPOCH FROM (NOW() - last_success_at)), -1)::float8::text "
                                                      "AS since_success "
                                                      "FROM auth_password_attempts WHERE key_hash = $1 AND client_ip = $2 "
                                                      "FOR UPDATE"
                                           parameters:@[ emailKey, address ]
                                                error:txError] firstObject];
    if (pairRow == nil) {
      return NO;
    }
    long long pairRemaining = [AMTrimmedString(pairRow[@"delay_remaining"]) longLongValue];
    double sinceSuccess = [AMTrimmedString(pairRow[@"since_success"]) doubleValue];
    BOOL trustedPair = (trustedSeconds > 0 && sinceSuccess >= 0.0 && sinceSuccess <= (double)trustedSeconds);
    BOOL trackAccount = (accountMax > 0 && !trustedPair);

    NSDictionary *accountRow = nil;
    if (trackAccount) {
      if ([connection executeCommand:@"INSERT INTO auth_password_attempts (key_hash, client_ip) VALUES ($1, $2) "
                                     "ON CONFLICT (key_hash, client_ip) DO NOTHING"
                          parameters:@[ emailKey, AMPasswordAccountRowAddress ]
                               error:txError] < 0) {
        return NO;
      }
      accountRow = [[connection executeQuery:@"SELECT failure_count::text AS failure_count, "
                                             "COALESCE(CEIL(EXTRACT(EPOCH FROM (delayed_until - NOW()))), 0)::bigint::text "
                                             "AS delay_remaining, "
                                             "COALESCE(EXTRACT(EPOCH FROM (NOW() - window_started_at)), -1)::float8::text "
                                             "AS window_age "
                                             "FROM auth_password_attempts WHERE key_hash = $1 AND client_ip = $2 "
                                             "FOR UPDATE"
                                  parameters:@[ emailKey, AMPasswordAccountRowAddress ]
                                       error:txError] firstObject];
      if (accountRow == nil) {
        return NO;
      }
    }
    long long accountRemaining = [AMTrimmedString(accountRow[@"delay_remaining"]) longLongValue];
    long long longest = MAX(pairRemaining, accountRemaining);
    if (longest > 0) {
      retryAfter = (NSUInteger)longest;
      return YES;
    }

    double sinceFailure = [AMTrimmedString(pairRow[@"since_failure"]) doubleValue];
    long long pairStored = [AMTrimmedString(pairRow[@"failure_count"]) longLongValue];
    NSUInteger pairCount = (sinceFailure < 0.0 || sinceFailure > AMAttemptFailureWindowSeconds || pairStored < 0)
                               ? 0U
                               : (NSUInteger)pairStored;
    NSUInteger pairNext = pairCount + 1U;
    NSUInteger pairDelay = (pairNext >= pairMax) ? AMDoublingDelay(delayBase, pairNext - pairMax, maxDelay) : 0U;
    if ([connection executeCommand:@"UPDATE auth_password_attempts SET failure_count = $3::integer, "
                                   "last_failure_at = NOW(), "
                                   "delayed_until = CASE WHEN $4::integer > 0 "
                                   "THEN NOW() + ($4::integer * INTERVAL '1 second') ELSE NULL END, "
                                   "updated_at = NOW() WHERE key_hash = $1 AND client_ip = $2"
                        parameters:@[
                          emailKey,
                          address,
                          [NSString stringWithFormat:@"%lu", (unsigned long)pairNext],
                          [NSString stringWithFormat:@"%lu", (unsigned long)pairDelay],
                        ]
                             error:txError] < 0) {
      return NO;
    }
    if (accountRow == nil) {
      return YES;
    }
    double windowAge = [AMTrimmedString(accountRow[@"window_age"]) doubleValue];
    long long accountStored = [AMTrimmedString(accountRow[@"failure_count"]) longLongValue];
    BOOL newWindow = (windowAge < 0.0 || windowAge > (double)accountWindow || accountStored < 0);
    NSUInteger accountNext = (newWindow ? 0U : (NSUInteger)accountStored) + 1U;
    NSUInteger accountDelay =
        (accountNext > accountMax) ? AMDoublingDelay(accountDelayBase, accountNext - accountMax - 1U, maxDelay) : 0U;
    accountCounted = YES;
    NSArray *armed = [connection executeQuery:@"UPDATE auth_password_attempts SET failure_count = $2::integer, "
                                              "window_started_at = CASE WHEN $4::boolean THEN NOW() ELSE window_started_at END, "
                                              "last_failure_at = NOW(), "
                                              "delayed_until = CASE WHEN $3::integer > 0 "
                                              "THEN NOW() + ($3::integer * INTERVAL '1 second') ELSE NULL END, "
                                              "updated_at = NOW() WHERE key_hash = $1 AND client_ip = '*' "
                                              "RETURNING COALESCE(delayed_until::text, '') AS delayed_until"
                                   parameters:@[
                                     emailKey,
                                     [NSString stringWithFormat:@"%lu", (unsigned long)accountNext],
                                     [NSString stringWithFormat:@"%lu", (unsigned long)accountDelay],
                                     newWindow ? @"true" : @"false",
                                   ]
                                        error:txError];
    if (armed == nil) {
      return NO;
    }
    NSString *armedValue = AMTrimmedString([armed firstObject][@"delayed_until"]);
    accountDelayArmed = ([armedValue length] > 0) ? armedValue : nil;
    return YES;
  } error:&dbError];
  if (!ok) {
    if (AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
      [self markAttemptLimitSchemaUnavailable];
      (void)[self attemptLimitSchemaIsAvailable];
      return YES;
    }
    if (error != NULL) {
      *error = dbError ?: AMError(ALNAuthModuleErrorDatabaseUnavailable, @"Failed to record the sign-in attempt", nil);
    }
    return NO;
  }
  if (retryAfter > 0) {
    if (error != NULL) {
      *error = AMRateLimitedError(retryAfter,
                                  [NSString stringWithFormat:@"Too many failed attempts. Try again in %lu seconds.",
                                                             (unsigned long)retryAfter]);
    }
    return NO;
  }
  if (countedOnAccount != NULL) {
    *countedOnAccount = accountCounted;
  }
  if (armedAccountDelay != NULL) {
    *armedAccountDelay = accountDelayArmed;
  }
  return YES;
}

// A successful sign-in clears its own pair and records when it succeeded
// (which exempts the pair from the account-wide ceiling for
// passwordTrustedPairDays). On the account-wide row it only takes back the
// count it reserved and removes the wait its own reservation armed, if any
// (matched exactly, so a wait set by another attempt is kept). It never adds
// to, extends or re-arms that row's wait.
- (void)recordPasswordSuccessForEmailKey:(NSString *)emailKey
                           clientAddress:(NSString *)address
                        countedOnAccount:(BOOL)countedOnAccount
                       armedAccountDelay:(NSString *)armedAccountDelay {
  if (self.passwordMaxFailures == 0 || self.database == nil || ![self attemptLimitSchemaIsAvailable]) {
    return;
  }
  NSError *dbError = nil;
  NSInteger updated = [self.database executeCommand:@"UPDATE auth_password_attempts SET failure_count = 0, "
                                                    "last_failure_at = NULL, delayed_until = NULL, "
                                                    "last_success_at = NOW(), updated_at = NOW() "
                                                    "WHERE key_hash = $1 AND client_ip = $2"
                                         parameters:@[ emailKey, address ]
                                              error:&dbError];
  if (updated < 0) {
    if (AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
      [self markAttemptLimitSchemaUnavailable];
    }
    return;
  }
  if (!countedOnAccount) {
    return;
  }
  (void)[self.database executeCommand:@"UPDATE auth_password_attempts SET "
                                      "failure_count = GREATEST(failure_count - 1, 0), "
                                      "delayed_until = CASE WHEN $2 <> '' AND delayed_until::text = $2 "
                                      "THEN NULL ELSE delayed_until END "
                                      "WHERE key_hash = $1 AND client_ip = '*'"
                           parameters:@[ emailKey, armedAccountDelay ?: @"" ]
                                error:NULL];
}

// Counts a request that may send mail (forgot-password) per submitted email
// and per client address, both hashed. Returns NO when either has reached its
// limit for the window; the caller then answers as usual but sends nothing.
// Known and unknown emails are counted alike.
- (BOOL)allowMailSendForEmail:(NSString *)email
                clientAddress:(NSString *)clientAddress
                         flow:(NSString *)flow {
  if ((self.mailMaxPerEmail == 0 && self.mailMaxPerAddress == 0) || self.database == nil ||
      ![self attemptLimitSchemaIsAvailable]) {
    return YES;
  }
  NSString *emailKey = AMPasswordAttemptKeyForEmail(AMLowerTrimmedString(email) ?: @"");
  NSData *addressDigest =
      ALNSHA256([[@"address:" stringByAppendingString:AMPasswordAttemptAddress(clientAddress)]
          dataUsingEncoding:NSUTF8StringEncoding]);
  NSString *addressKey = ALNLowercaseHexStringFromData(addressDigest) ?: @"";
  NSArray *entries = @[
    @[ emailKey, @"email", @(self.mailMaxPerEmail) ],
    @[ addressKey, @"address", @(self.mailMaxPerAddress) ],
  ];
  NSUInteger window = MAX(self.mailWindowSeconds, (NSUInteger)1U);
  __block NSString *exceeded = nil;
  NSError *dbError = nil;
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    for (NSArray *entry in entries) {
      NSUInteger limit = [entry[2] unsignedIntegerValue];
      if (limit == 0) {
        continue;
      }
      NSArray *rows = [connection executeQuery:@"INSERT INTO auth_mail_sends AS m (key_hash, kind, send_count, window_started_at) "
                                               "VALUES ($1, $2, 1, NOW()) "
                                               "ON CONFLICT (key_hash, kind) DO UPDATE SET "
                                               "send_count = CASE WHEN m.window_started_at IS NULL "
                                               "OR m.window_started_at < NOW() - ($3::integer * INTERVAL '1 second') "
                                               "THEN 1 ELSE m.send_count + 1 END, "
                                               "window_started_at = CASE WHEN m.window_started_at IS NULL "
                                               "OR m.window_started_at < NOW() - ($3::integer * INTERVAL '1 second') "
                                               "THEN NOW() ELSE m.window_started_at END, "
                                               "updated_at = NOW() "
                                               "RETURNING send_count::text AS send_count"
                                    parameters:@[ entry[0], entry[1], [NSString stringWithFormat:@"%lu", (unsigned long)window] ]
                                         error:txError];
      if (rows == nil) {
        return NO;
      }
      if ([AMTrimmedString([rows firstObject][@"send_count"]) longLongValue] > (long long)limit && exceeded == nil) {
        exceeded = entry[1];
      }
    }
    return YES;
  } error:&dbError];
  if (!ok) {
    if (AMErrorLooksLikeMissingAttemptLimitSchema(dbError)) {
      [self markAttemptLimitSchemaUnavailable];
      (void)[self attemptLimitSchemaIsAvailable];
      return YES;
    }
    exceeded = @"unavailable";
  }
  if (exceeded == nil) {
    return YES;
  }
  NSString *message = [exceeded isEqualToString:@"unavailable"]
                          ? @"auth module did not send mail: the send limit could not be checked"
                          : @"auth module did not send mail: send limit reached";
  NSDictionary *fields = @{ @"module" : @"auth", @"flow" : flow ?: @"", @"limit" : exceeded };
  if (self.logger != nil) {
    [self.logger warn:message fields:fields];
  } else {
    NSLog(@"%@ %@", message, fields);
  }
  return NO;
}

- (NSDictionary *)totpEnrollmentForUserID:(NSString *)userID
                                    error:(NSError **)error {
  NSArray *rows = [self.database executeQuery:@"SELECT id::text AS id, secret, COALESCE(recovery_codes_json, '[]') AS recovery_codes_json, "
                                         "CASE WHEN verified_at IS NULL THEN '' ELSE verified_at::text END AS verified_at, "
                                         "CASE WHEN enabled THEN 't' ELSE 'f' END AS enabled "
                                         "FROM auth_mfa_enrollments WHERE user_id = $1 AND type = 'totp' "
                                         "ORDER BY id DESC LIMIT 1"
                                   parameters:@[ userID ?: @"" ]
                                        error:error];
  NSDictionary *row = [rows firstObject];
  if (row == nil) {
    return nil;
  }
  return @{
    @"id" : AMTrimmedString(row[@"id"]),
    @"secret" : AMTrimmedString(row[@"secret"]),
    @"recovery_codes_json" : AMTrimmedString(row[@"recovery_codes_json"]),
    @"verified_at" : AMTrimmedString(row[@"verified_at"]),
    @"enabled" : @(AMBoolFromDatabaseValue(row[@"enabled"])),
  };
}

- (NSDictionary *)smsEnrollmentForUserID:(NSString *)userID
                                   error:(NSError **)error {
  NSArray *rows = [self.database executeQuery:@"SELECT id::text AS id, secret AS phone_number, "
                                         "CASE WHEN verified_at IS NULL THEN '' ELSE verified_at::text END AS verified_at, "
                                         "CASE WHEN enabled THEN 't' ELSE 'f' END AS enabled "
                                         "FROM auth_mfa_enrollments WHERE user_id = $1 AND type = 'sms' "
                                         "ORDER BY id DESC LIMIT 1"
                                   parameters:@[ userID ?: @"" ]
                                        error:error];
  NSDictionary *row = [rows firstObject];
  if (row == nil) {
    return nil;
  }
  NSString *phoneNumber = AMNormalizePhoneNumber(row[@"phone_number"]);
  return @{
    @"id" : AMTrimmedString(row[@"id"]),
    @"phone_number" : phoneNumber ?: @"",
    @"masked_phone" : AMMaskedPhoneNumber(phoneNumber),
    @"verified_at" : AMTrimmedString(row[@"verified_at"]),
    @"enabled" : @(AMBoolFromDatabaseValue(row[@"enabled"])),
  };
}

- (NSDictionary *)totpProvisioningPayloadForUser:(NSDictionary *)user
                                           error:(NSError **)error {
  NSString *userID = AMTrimmedString(user[@"id"]);
  NSDictionary *enrollment = [self totpEnrollmentForUserID:userID error:error];
  NSString *secret = AMTrimmedString(enrollment[@"secret"]);
  if ([secret length] == 0) {
    secret = [ALNTOTP generateSecretWithError:error];
    if ([secret length] == 0) {
      return nil;
    }
    NSInteger inserted = [self.database executeCommand:@"INSERT INTO auth_mfa_enrollments "
                                                   "(user_id, type, secret, recovery_codes_json, enabled, created_at, updated_at) "
                                                   "VALUES ($1, 'totp', $2, '[]', FALSE, NOW(), NOW())"
                                             parameters:@[ userID ?: @"", secret ]
                                                  error:error];
    if (inserted < 0) {
      return nil;
    }
    enrollment = [self totpEnrollmentForUserID:userID error:error];
  }
  NSString *accountName = AMTrimmedString(user[@"email"]);
  NSString *issuer = @"Arlen Auth Module";
  BOOL factorVerified = ([AMTrimmedString(enrollment[@"verified_at"]) length] > 0 || AMBoolFromDatabaseValue(enrollment[@"enabled"]));
  NSString *uri = @"";
  if (!factorVerified) {
    uri = [ALNTOTP provisioningURIForSecret:secret accountName:accountName issuer:issuer error:error];
    if ([uri length] == 0) {
      return nil;
    }
  }
  NSArray *configuredRecoveryCodes = [AMJSONArrayFromJSONString(enrollment[@"recovery_codes_json"]) copy];
  return @{
    @"factor" : @"totp",
    @"secret" : factorVerified ? @"" : secret,
    @"manual_entry_key" : factorVerified ? @"" : secret,
    @"account_name" : accountName ?: @"",
    @"issuer" : issuer,
    @"otpauth_uri" : uri ?: @"",
    @"enrolled" : @YES,
    @"verified" : @(factorVerified),
    @"recovery_codes_configured" : @([configuredRecoveryCodes count] > 0),
    @"enrollment_id" : AMTrimmedString(enrollment[@"id"]),
  };
}

- (NSDictionary *)totpFragmentContextForUser:(NSDictionary *)user
                                     returnTo:(NSString *)returnTo
                                        error:(NSError **)error {
  NSDictionary *provisioning = [self totpProvisioningPayloadForUser:user error:error];
  if (provisioning == nil) {
    return nil;
  }
  BOOL verified = [provisioning[@"verified"] boolValue];
  NSString *normalizedReturnTo = AMTrimmedString(returnTo);
  NSDictionary *smsEnrollment = [self smsEnrollmentForUserID:AMTrimmedString(user[@"id"]) error:NULL] ?: @{};
  BOOL smsChallengeAvailable = self.smsEnabled && self.smsAllowChallenge &&
                               ([AMTrimmedString(smsEnrollment[@"phone_number"]) length] > 0) &&
                               ([AMTrimmedString(smsEnrollment[@"verified_at"]) length] > 0 || [smsEnrollment[@"enabled"] boolValue]);
  NSMutableArray *links = [NSMutableArray array];
  if (smsChallengeAvailable) {
    [links addObject:@{
      @"label" : @"Use SMS instead",
      @"href" : [NSString stringWithFormat:@"%@?return_to=%@", self.smsPath ?: @"/auth/mfa/sms", normalizedReturnTo ?: @""],
    }];
  }
  return @{
    @"authMFAFactor" : @"totp",
    @"authMFAFlowState" : verified ? @"challenge" : @"enrollment",
    @"authMFAVerified" : provisioning[@"verified"] ?: @NO,
    @"authTOTPPath" : self.totpPath ?: @"/auth/mfa/totp",
    @"authTOTPVerifyPath" : self.totpVerifyPath ?: @"/auth/mfa/totp/verify",
    @"authTOTPProvisioning" : provisioning,
    @"authTOTPQRCodeScriptPath" : [self authUIAssetPathForFilename:@"auth_totp_qr.js"],
    @"authTOTPFormDescriptor" : @{
      @"action" : self.totpVerifyPath ?: @"/auth/mfa/totp/verify",
      @"method" : @"post",
      @"submitLabel" : verified ? @"Verify TOTP" : @"Finish Setup",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"links" : links,
      @"fields" : @[
        @{
          @"name" : @"code",
          @"label" : verified ? @"Authenticator or recovery code" : @"Enter the 6-digit code from your app",
          @"type" : @"text",
          @"autocomplete" : @"one-time-code",
          @"inputmode" : verified ? @"text" : @"numeric",
        },
      ],
    },
  };
}

- (NSDictionary *)verifyTOTPCode:(NSString *)code
                             user:(NSDictionary *)user
                          context:(ALNContext *)context
                            error:(NSError **)error {
  NSString *userID = AMTrimmedString(user[@"id"]);
  NSDictionary *enrollment = [self totpEnrollmentForUserID:userID error:error];
  NSString *secret = AMTrimmedString(enrollment[@"secret"]);
  if ([secret length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"No TOTP enrollment is available", nil);
    }
    return nil;
  }
  BOOL enrollmentVerified = ([AMTrimmedString(enrollment[@"verified_at"]) length] > 0 || AMBoolFromDatabaseValue(enrollment[@"enabled"]));
  NSString *submittedCode = AMTrimmedString(code) ?: @"";
  // A verified enrollment also accepts one of its recovery codes in place of an
  // authenticator code. Both share the per-account MFA failure counter.
  BOOL useRecoveryCode = enrollmentVerified && [submittedCode length] > 0 && !AMLooksLikeTOTPCode(submittedCode);
  if (![self reserveAttemptForUserID:userID
                               scope:AMAttemptScopeMFA
                         maxFailures:self.mfaMaxFailures
                      lockoutSeconds:self.mfaLockoutSeconds
                   maxLockoutSeconds:self.mfaMaxLockoutSeconds
                               error:error]) {
    return nil;
  }
  NSString *method = @"totp";
  if (useRecoveryCode) {
    if (![self consumeRecoveryCode:submittedCode enrollment:enrollment error:error]) {
      return nil;
    }
    method = @"recovery_code";
  } else {
    NSError *totpError = nil;
    NSUInteger step = [ALNTOTP matchedTimeStepForCode:submittedCode
                                               secret:secret
                                               atDate:[NSDate date]
                                               digits:6
                                               period:30
                                 allowedPastIntervals:1
                               allowedFutureIntervals:1
                                                error:&totpError];
    if (step == NSNotFound) {
      if (error != NULL) {
        *error = totpError;
      }
      return nil;
    }
    if (![self recordAcceptedTOTPStep:step
                         enrollmentID:AMTrimmedString(enrollment[@"id"])
                             replayed:NULL
                                error:error]) {
      return nil;
    }
  }
  [self clearAttemptFailuresForUserID:userID scope:AMAttemptScopeMFA];

  NSArray *plainRecoveryCodes = nil;
  if (!enrollmentVerified) {
    plainRecoveryCodes = [ALNRecoveryCodes generateCodesWithCount:6 error:error];
    if (plainRecoveryCodes == nil) {
      return nil;
    }
    NSArray *hashedRecoveryCodes = [ALNRecoveryCodes hashCodes:plainRecoveryCodes error:error];
    if (hashedRecoveryCodes == nil) {
      return nil;
    }
    NSInteger updated = [self.database executeCommand:@"UPDATE auth_mfa_enrollments "
                                                  "SET enabled = TRUE, verified_at = NOW(), recovery_codes_json = $2, updated_at = NOW() "
                                                  "WHERE id = $1"
                                            parameters:@[ AMTrimmedString(enrollment[@"id"]), AMJSONString(hashedRecoveryCodes) ]
                                                 error:error];
    if (updated < 0) {
      return nil;
    }
  }

  if (![ALNAuthSession elevateAuthenticatedSessionForMethod:method
                                             assuranceLevel:2
                                            authenticatedAt:nil
                                                    context:context
                                                      error:error]) {
    return nil;
  }
  NSMutableDictionary *payload =
      [NSMutableDictionary dictionaryWithDictionary:[self sessionPayloadForContext:context includeUser:YES error:NULL] ?: @{}];
  if ([plainRecoveryCodes count] > 0) {
    payload[@"recovery_codes"] = plainRecoveryCodes;
  }
  return payload;
}

- (NSDictionary *)totpRecoveryCodesFragmentContextWithCodes:(NSArray<NSString *> *)recoveryCodes
                                                   returnTo:(NSString *)returnTo {
  NSMutableArray *normalizedCodes = [NSMutableArray array];
  for (id value in recoveryCodes ?: @[]) {
    NSString *code = AMTrimmedString(value);
    if ([code length] == 0) {
      continue;
    }
    [normalizedCodes addObject:code];
  }
  NSString *continueTarget = ([AMTrimmedString(returnTo) length] > 0) ? AMTrimmedString(returnTo) : (self.defaultRedirect ?: @"/");
  return @{
    @"authMFAFactor" : @"totp",
    @"authMFAFlowState" : @"recovery_codes",
    @"authRecoveryCodes" : [NSArray arrayWithArray:normalizedCodes],
    @"authRecoveryContinuePath" : continueTarget,
    @"authResultActions" : @[ @{
      @"label" : @"Continue",
      @"href" : continueTarget,
    } ],
  };
}

- (NSDictionary *)stubProviderConfigurationForBaseURL:(NSString *)baseURL {
  return @{
    @"identifier" : @"stub",
    @"displayName" : @"Stub OIDC",
    @"protocol" : @"oidc",
    @"issuer" : @"https://stub.auth-module.invalid",
    @"authorizationEndpoint" : [NSString stringWithFormat:@"%@%@", baseURL ?: @"", self.providerStubAuthorizePath ?: @""],
    @"clientID" : @"auth-module-stub-client",
    @"clientSecret" : self.stubProviderSharedSecret ?: @"",
    @"callbackMaxAgeSeconds" : @300,
    @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
  };
}

- (NSDictionary *)currentUserForSubject:(NSString *)subject
                                  error:(NSError **)error {
  return [self userForSubject:subject error:error];
}

- (NSDictionary *)currentUserForContext:(ALNContext *)context
                                  error:(NSError **)error {
  return [self userForSubject:[context authSubject] error:error];
}

- (NSDictionary *)totpFragmentContextForCurrentUserInContext:(ALNContext *)context
                                                    returnTo:(NSString *)returnTo
                                                       error:(NSError **)error {
  NSDictionary *user = [self currentUserForContext:context error:error];
  if (user == nil) {
    if (error != NULL && *error == nil) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"Authentication required", nil);
    }
    return nil;
  }
  return [self totpFragmentContextForUser:user returnTo:returnTo error:error];
}

- (NSDictionary *)mfaFactorStateForUser:(NSDictionary *)user
                                context:(ALNContext *)context
                               returnTo:(NSString *)returnTo
                                  error:(NSError **)error {
  NSString *userID = AMTrimmedString(user[@"id"]);
  NSDictionary *totpProvisioning = [self totpProvisioningPayloadForUser:user error:NULL] ?: @{};
  BOOL totpVerified = [totpProvisioning[@"verified"] boolValue];
  BOOL totpEnrolled = [totpProvisioning[@"enrolled"] boolValue];

  NSDictionary *smsEnrollment = [self smsEnrollmentForUserID:userID error:error] ?: @{};
  NSString *smsPhone = AMNormalizePhoneNumber(smsEnrollment[@"phone_number"]);
  BOOL smsEnrolled = ([smsPhone length] > 0);
  BOOL smsVerified = ([AMTrimmedString(smsEnrollment[@"verified_at"]) length] > 0 || [smsEnrollment[@"enabled"] boolValue]);

  NSDictionary *smsSession = AMSMSSessionState(context);
  NSString *pendingPurpose = AMLowerTrimmedString(smsSession[@"purpose"]);
  NSString *pendingPhone = AMNormalizePhoneNumber(smsSession[@"phone"]);
  NSString *maskedPendingPhone = AMMaskedPhoneNumber(pendingPhone);
  BOOL pendingEnrollment = ([pendingPhone length] > 0 && [pendingPurpose isEqualToString:@"enrollment"]);
  BOOL pendingChallenge = ([pendingPhone length] > 0 && [pendingPurpose isEqualToString:@"challenge"]);
  BOOL recentMFA = [ALNAuthSession context:context
             satisfiesMinimumAssuranceLevel:2
           maximumAuthenticationAgeSeconds:self.smsRecentMFAMaxAgeSeconds
                              referenceDate:nil];

  BOOL canManageSMS = NO;
  NSString *smsManagementGuardMessage = @"";
  if (self.smsEnabled && self.smsAllowEnrollment) {
    if (!self.smsPhoneManagementRequiresMFA || recentMFA) {
      canManageSMS = YES;
    } else if (!totpVerified && !smsVerified && self.smsAllowPrimaryFactor) {
      canManageSMS = YES;
    } else {
      smsManagementGuardMessage = @"Verify an existing MFA factor before adding, changing, or removing a phone number.";
    }
  }

  BOOL smsChallengeAvailable = (self.smsEnabled && self.smsAllowChallenge && smsVerified);
  NSString *preferredFactor = totpVerified ? @"totp" : (smsChallengeAvailable ? @"sms" : @"totp");
  NSMutableArray *availableChallengeFactors = [NSMutableArray array];
  if (totpVerified) {
    [availableChallengeFactors addObject:@"totp"];
  }
  if (smsChallengeAvailable) {
    [availableChallengeFactors addObject:@"sms"];
  }

  NSString *normalizedReturnTo = AMTrimmedString(returnTo);
  NSString *smsFallbackHref = [NSString stringWithFormat:@"%@?return_to=%@",
                                                         self.smsPath ?: @"/auth/mfa/sms",
                                                         normalizedReturnTo ?: @""];
  NSString *totpFallbackHref = [NSString stringWithFormat:@"%@?return_to=%@",
                                                          self.totpPath ?: @"/auth/mfa/totp",
                                                          normalizedReturnTo ?: @""];

  NSDictionary *totpFactor = @{
    @"identifier" : @"totp",
    @"label" : @"Authenticator app",
    @"kind" : @"authenticator_app",
    @"recommended" : @YES,
    @"weaker" : @NO,
    @"enrolled" : @(totpEnrolled),
    @"verified" : @(totpVerified),
    @"preferred_for_step_up" : @([preferredFactor isEqualToString:@"totp"]),
    @"challenge_available" : @(totpVerified),
    @"manage_path" : self.mfaManagePath ?: @"/auth/mfa",
    @"challenge_path" : self.totpPath ?: @"/auth/mfa/totp",
    @"summary" : totpVerified ? @"Ready for step-up authentication." : @"Recommended. Set up an authenticator app for stronger MFA.",
  };
  NSDictionary *smsFactor = @{
    @"identifier" : @"sms",
    @"label" : @"SMS",
    @"kind" : @"sms",
    @"recommended" : @NO,
    @"weaker" : @YES,
    @"enabled" : @(self.smsEnabled),
    @"enrolled" : @(smsEnrolled),
    @"verified" : @(smsVerified),
    @"preferred_for_step_up" : @([preferredFactor isEqualToString:@"sms"]),
    @"challenge_available" : @(smsChallengeAvailable),
    @"manage_path" : self.mfaManagePath ?: @"/auth/mfa",
    @"challenge_path" : smsFallbackHref,
    @"masked_phone" : AMMaskedPhoneNumber(smsPhone),
    @"pending_enrollment" : @(pendingEnrollment),
    @"pending_challenge" : @(pendingChallenge),
    @"pending_masked_phone" : maskedPendingPhone ?: @"",
    @"management_allowed" : @(canManageSMS),
    @"management_guard_message" : smsManagementGuardMessage ?: @"",
    @"summary" : self.smsEnabled ? (smsVerified ? @"Available as a weaker fallback factor." : @"Optional fallback factor. Disabled by default.") : @"SMS MFA is disabled by app policy.",
  };
  NSMutableArray *factors = [NSMutableArray arrayWithObject:totpFactor];
  if (self.smsEnabled) {
    [factors addObject:smsFactor];
  }
  return @{
    @"preferred_factor" : preferredFactor ?: @"totp",
    @"available_challenge_factors" : availableChallengeFactors,
    @"factors" : factors,
    @"policy" : @{
      @"sms" : @{
        @"enabled" : @(self.smsEnabled),
        @"allow_enrollment" : @(self.smsAllowEnrollment),
        @"allow_challenge" : @(self.smsAllowChallenge),
        @"allow_primary_factor" : @(self.smsAllowPrimaryFactor),
        @"phone_management_requires_recent_mfa" : @(self.smsPhoneManagementRequiresMFA),
        @"recent_mfa_max_age_seconds" : @(self.smsRecentMFAMaxAgeSeconds),
        @"resend_cooldown_seconds" : @(self.smsResendCooldownSeconds),
      },
    },
    @"totp" : @{
      @"enrolled" : @(totpEnrolled),
      @"verified" : @(totpVerified),
      @"provisioning" : totpProvisioning ?: @{},
      @"fallback_href" : smsChallengeAvailable ? smsFallbackHref : @"",
    },
    @"sms" : @{
      @"enabled" : @(self.smsEnabled),
      @"enrolled" : @(smsEnrolled),
      @"verified" : @(smsVerified),
      @"challenge_available" : @(smsChallengeAvailable),
      @"phone_number" : smsPhone ?: @"",
      @"masked_phone" : AMMaskedPhoneNumber(smsPhone),
      @"pending_enrollment" : @(pendingEnrollment),
      @"pending_challenge" : @(pendingChallenge),
      @"pending_phone" : pendingPhone ?: @"",
      @"pending_masked_phone" : maskedPendingPhone ?: @"",
      @"management_allowed" : @(canManageSMS),
      @"management_guard_message" : smsManagementGuardMessage ?: @"",
      @"fallback_href" : totpVerified ? totpFallbackHref : @"",
    },
  };
}

- (NSDictionary *)mfaManagementFragmentContextForUser:(NSDictionary *)user
                                              context:(ALNContext *)context
                                             returnTo:(NSString *)returnTo
                                                error:(NSError **)error {
  NSDictionary *factorState = [self mfaFactorStateForUser:user context:context returnTo:returnTo error:error] ?: @{};
  NSDictionary *totpState = [factorState[@"totp"] isKindOfClass:[NSDictionary class]] ? factorState[@"totp"] : @{};
  NSDictionary *smsState = [factorState[@"sms"] isKindOfClass:[NSDictionary class]] ? factorState[@"sms"] : @{};
  NSDictionary *policyState = [factorState[@"policy"] isKindOfClass:[NSDictionary class]] ? factorState[@"policy"] : @{};
  BOOL totpVerified = [totpState[@"verified"] boolValue];
  NSString *normalizedReturnTo = AMTrimmedString(returnTo);

  NSMutableDictionary *contextValues = [NSMutableDictionary dictionaryWithDictionary:@{
    @"authMFAFactors" : factorState[@"factors"] ?: @[],
    @"authMFAPreferredFactor" : factorState[@"preferred_factor"] ?: @"totp",
    @"authMFAAvailableChallengeFactors" : factorState[@"available_challenge_factors"] ?: @[],
    @"authMFAPolicy" : policyState ?: @{},
    @"authTOTPNeedsEnrollment" : @(!totpVerified),
    @"authTOTPVerified" : @(totpVerified),
    @"authSMSState" : smsState ?: @{},
    @"authSMSPolicy" : [policyState[@"sms"] isKindOfClass:[NSDictionary class]] ? policyState[@"sms"] : @{},
    @"authSMSPath" : self.smsPath ?: @"/auth/mfa/sms",
    @"authSMSStartPath" : self.smsStartPath ?: @"/auth/mfa/sms/start",
    @"authSMSVerifyPath" : self.smsVerifyPath ?: @"/auth/mfa/sms/verify",
    @"authSMSResendPath" : self.smsResendPath ?: @"/auth/mfa/sms/resend",
    @"authSMSRemovePath" : self.smsRemovePath ?: @"/auth/mfa/sms/remove",
    @"authMFAManagePath" : self.mfaManagePath ?: @"/auth/mfa",
    @"authSMSStartFormDescriptor" : @{
      @"action" : self.smsStartPath ?: @"/auth/mfa/sms/start",
      @"method" : @"post",
      @"submitLabel" : ([smsState[@"verified"] boolValue] ? @"Verify New Number" : @"Send SMS Code"),
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"fields" : @[ @{
        @"name" : @"phone_number",
        @"label" : ([smsState[@"verified"] boolValue] ? @"Replace phone number" : @"Mobile phone number"),
        @"type" : @"tel",
        @"autocomplete" : @"tel",
      } ],
    },
    @"authSMSVerifyFormDescriptor" : @{
      @"action" : self.smsVerifyPath ?: @"/auth/mfa/sms/verify",
      @"method" : @"post",
      @"submitLabel" : @"Verify SMS Code",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"fields" : @[ @{
        @"name" : @"code",
        @"label" : @"Text message code",
        @"type" : @"text",
        @"autocomplete" : @"one-time-code",
        @"inputmode" : @"numeric",
      } ],
    },
    @"authSMSResendFormDescriptor" : @{
      @"action" : self.smsResendPath ?: @"/auth/mfa/sms/resend",
      @"method" : @"post",
      @"submitLabel" : @"Send another code",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"fields" : @[],
    },
    @"authSMSRemoveFormDescriptor" : @{
      @"action" : self.smsRemovePath ?: @"/auth/mfa/sms/remove",
      @"method" : @"post",
      @"submitLabel" : @"Remove SMS factor",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"fields" : @[],
    },
  }];

  if (!totpVerified) {
    NSDictionary *totpContext = [self totpFragmentContextForUser:user returnTo:returnTo error:NULL] ?: @{};
    [contextValues addEntriesFromDictionary:totpContext];
  }
  return contextValues;
}

- (NSDictionary *)mfaManagementFragmentContextForCurrentUserInContext:(ALNContext *)context
                                                             returnTo:(NSString *)returnTo
                                                                error:(NSError **)error {
  NSDictionary *user = [self currentUserForContext:context error:error];
  if (user == nil) {
    if (error != NULL && *error == nil) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"Authentication required", nil);
    }
    return nil;
  }
  return [self mfaManagementFragmentContextForUser:user context:context returnTo:returnTo error:error];
}

- (NSDictionary *)issueSMSVerificationForUser:(NSDictionary *)user
                                        phone:(NSString *)phoneNumber
                                      purpose:(NSString *)purpose
                                      context:(ALNContext *)context
                                        error:(NSError **)error {
  if (!self.smsEnabled) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected, @"SMS MFA is disabled", nil);
    }
    return nil;
  }
  NSString *normalizedPurpose = AMLowerTrimmedString(purpose);
  NSString *userID = AMTrimmedString(user[@"id"]);
  NSDictionary *smsEnrollment = [self smsEnrollmentForUserID:userID error:NULL] ?: @{};
  NSDictionary *totpEnrollment = [self totpEnrollmentForUserID:userID error:NULL] ?: @{};
  BOOL totpVerified = ([AMTrimmedString(totpEnrollment[@"verified_at"]) length] > 0 || [totpEnrollment[@"enabled"] boolValue]);
  BOOL smsVerified = ([AMTrimmedString(smsEnrollment[@"verified_at"]) length] > 0 || [smsEnrollment[@"enabled"] boolValue]);
  BOOL recentMFA = [ALNAuthSession context:context
             satisfiesMinimumAssuranceLevel:2
           maximumAuthenticationAgeSeconds:self.smsRecentMFAMaxAgeSeconds
                              referenceDate:nil];

  NSString *resolvedPhone = @"";
  if ([normalizedPurpose isEqualToString:@"challenge"]) {
    if (!self.smsAllowChallenge) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorPolicyRejected, @"SMS step-up is disabled", nil);
      }
      return nil;
    }
    resolvedPhone = AMNormalizePhoneNumber(smsEnrollment[@"phone_number"]);
    if ([resolvedPhone length] == 0 || !smsVerified) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorNotFound, @"No verified SMS factor is available", nil);
      }
      return nil;
    }
  } else {
    if (!self.smsAllowEnrollment) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorPolicyRejected, @"SMS enrollment is disabled", nil);
      }
      return nil;
    }
    resolvedPhone = AMNormalizePhoneNumber(phoneNumber);
    if ([resolvedPhone length] == 0) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorValidationFailed, @"Enter a valid mobile phone number in international format", nil);
      }
      return nil;
    }
    BOOL allowed = (!self.smsPhoneManagementRequiresMFA || recentMFA ||
                    (!totpVerified && !smsVerified && self.smsAllowPrimaryFactor));
    if (!allowed) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorPolicyRejected,
                         @"Verify an existing MFA factor before adding or changing a phone number",
                         nil);
      }
      return nil;
    }
  }

  NSDictionary *existingState = AMSMSSessionState(context);
  NSString *existingPhone = AMNormalizePhoneNumber(existingState[@"phone"]);
  NSString *existingPurpose = AMLowerTrimmedString(existingState[@"purpose"]);
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSTimeInterval lastSend = [existingState[@"last_send_at"] respondsToSelector:@selector(doubleValue)]
                                ? [existingState[@"last_send_at"] doubleValue]
                                : 0.0;
  NSUInteger sendCount = [existingState[@"send_count"] respondsToSelector:@selector(unsignedIntegerValue)]
                             ? [existingState[@"send_count"] unsignedIntegerValue]
                             : 0U;
  NSUInteger verifyCount = [existingState[@"verify_count"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [existingState[@"verify_count"] unsignedIntegerValue]
                               : 0U;
  BOOL sameFlow = ([existingPhone isEqualToString:resolvedPhone] && [existingPurpose isEqualToString:normalizedPurpose]);
  if (!sameFlow) {
    sendCount = 0U;
    verifyCount = 0U;
    lastSend = 0.0;
  }
  if (sameFlow && self.smsResendCooldownSeconds > 0U && (now - lastSend) < (NSTimeInterval)self.smsResendCooldownSeconds) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected,
                       @"A text message was sent recently. Please wait a moment before requesting another code.",
                       nil);
    }
    return nil;
  }
  if (sendCount >= self.smsMaxSendAttemptsPerSession) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected, @"Too many SMS codes were requested in this session", nil);
    }
    return nil;
  }
  if (![self.smsVerifyClient sendVerificationToPhoneNumber:resolvedPhone locale:self.smsLocale error:error]) {
    return nil;
  }
  NSString *normalizedReturnTo = AMSafeReturnTo([context stringParamForName:@"return_to"]);
  NSDictionary *state = @{
    @"purpose" : normalizedPurpose ?: @"challenge",
    @"phone" : resolvedPhone ?: @"",
    @"masked_phone" : AMMaskedPhoneNumber(resolvedPhone),
    @"send_count" : @(sendCount + 1U),
    @"verify_count" : @(verifyCount),
    @"last_send_at" : @(now),
    @"return_to" : normalizedReturnTo ?: @"",
  };
  AMSetSMSSessionState(context, state);
  return state;
}

- (NSDictionary *)smsChallengeFragmentContextForUser:(NSDictionary *)user
                                             context:(ALNContext *)context
                                            returnTo:(NSString *)returnTo
                                            autoSend:(BOOL)autoSend
                                               error:(NSError **)error {
  NSDictionary *factorState = [self mfaFactorStateForUser:user context:context returnTo:returnTo error:error] ?: @{};
  NSDictionary *smsState = [factorState[@"sms"] isKindOfClass:[NSDictionary class]] ? factorState[@"sms"] : @{};
  if (![smsState[@"challenge_available"] boolValue]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"No verified SMS factor is available", nil);
    }
    return nil;
  }
  NSDictionary *challengeState = AMSMSSessionState(context);
  if (autoSend) {
    NSDictionary *issued = [self issueSMSVerificationForUser:user phone:nil purpose:@"challenge" context:context error:error];
    if (issued != nil) {
      challengeState = issued;
    }
  }
  NSString *normalizedReturnTo = AMTrimmedString(returnTo);
  NSMutableArray *links = [NSMutableArray array];
  NSDictionary *totpState = [factorState[@"totp"] isKindOfClass:[NSDictionary class]] ? factorState[@"totp"] : @{};
  if ([totpState[@"verified"] boolValue]) {
    [links addObject:@{
      @"label" : @"Use authenticator app instead",
      @"href" : [NSString stringWithFormat:@"%@?return_to=%@", self.totpPath ?: @"/auth/mfa/totp", normalizedReturnTo ?: @""],
    }];
  }
  return @{
    @"authMFAFactor" : @"sms",
    @"authMFAFlowState" : @"challenge",
    @"authSMSState" : smsState ?: @{},
    @"authSMSChallengeMessage" : [NSString stringWithFormat:@"Enter the code sent to %@.",
                                                            AMTrimmedString(challengeState[@"masked_phone"]) ?: (smsState[@"masked_phone"] ?: @"your phone")],
    @"authSMSVerifyFormDescriptor" : @{
      @"action" : self.smsVerifyPath ?: @"/auth/mfa/sms/verify",
      @"method" : @"post",
      @"submitLabel" : @"Verify SMS Code",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"links" : links,
      @"fields" : @[ @{
        @"name" : @"code",
        @"label" : @"Text message code",
        @"type" : @"text",
        @"autocomplete" : @"one-time-code",
        @"inputmode" : @"numeric",
      } ],
    },
    @"authSMSResendFormDescriptor" : @{
      @"action" : self.smsResendPath ?: @"/auth/mfa/sms/resend",
      @"method" : @"post",
      @"submitLabel" : @"Send another code",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : normalizedReturnTo ?: @"",
      } ],
      @"fields" : @[],
    },
  };
}

- (NSDictionary *)smsChallengeFragmentContextForCurrentUserInContext:(ALNContext *)context
                                                            returnTo:(NSString *)returnTo
                                                               error:(NSError **)error {
  NSDictionary *user = [self currentUserForContext:context error:error];
  if (user == nil) {
    if (error != NULL && *error == nil) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"Authentication required", nil);
    }
    return nil;
  }
  return [self smsChallengeFragmentContextForUser:user context:context returnTo:returnTo autoSend:NO error:error];
}

- (NSDictionary *)verifySMSCode:(NSString *)code
                            user:(NSDictionary *)user
                         context:(ALNContext *)context
                           error:(NSError **)error {
  NSDictionary *state = AMSMSSessionState(context);
  NSString *purpose = AMLowerTrimmedString(state[@"purpose"]);
  NSString *phone = AMNormalizePhoneNumber(state[@"phone"]);
  if ([purpose length] == 0 || [phone length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"Request a text message code before verifying", nil);
    }
    return nil;
  }
  NSUInteger verifyCount = [state[@"verify_count"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [state[@"verify_count"] unsignedIntegerValue]
                               : 0U;
  if (verifyCount >= self.smsMaxVerifyAttemptsPerSession) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected, @"Too many SMS verification attempts were made in this session", nil);
    }
    return nil;
  }

  BOOL approved = NO;
  NSError *providerError = nil;
  BOOL ok = [self.smsVerifyClient checkVerificationCode:code phoneNumber:phone approved:&approved error:&providerError];
  if (!ok || !approved) {
    NSMutableDictionary *updatedState = [state mutableCopy] ?: [NSMutableDictionary dictionary];
    updatedState[@"verify_count"] = @(verifyCount + 1U);
    AMSetSMSSessionState(context, updatedState);
    if (error != NULL) {
      *error = providerError ?: AMError(ALNAuthModuleErrorAuthenticationFailed, @"The verification code is invalid", nil);
    }
    return nil;
  }

  NSString *userID = AMTrimmedString(user[@"id"]);
  if ([purpose isEqualToString:@"enrollment"]) {
    NSDictionary *existing = [self smsEnrollmentForUserID:userID error:NULL];
    NSInteger result = 0;
    if (existing != nil) {
      result = [self.database executeCommand:@"UPDATE auth_mfa_enrollments "
                                             "SET secret = $2, enabled = TRUE, verified_at = NOW(), updated_at = NOW() "
                                             "WHERE id = $1"
                                       parameters:@[ AMTrimmedString(existing[@"id"]), phone ]
                                            error:error];
    } else {
      result = [self.database executeCommand:@"INSERT INTO auth_mfa_enrollments "
                                             "(user_id, type, secret, recovery_codes_json, enabled, verified_at, created_at, updated_at) "
                                             "VALUES ($1, 'sms', $2, '[]', TRUE, NOW(), NOW(), NOW())"
                                       parameters:@[ userID ?: @"", phone ]
                                            error:error];
    }
    if (result < 0) {
      return nil;
    }
  }

  AMSetSMSSessionState(context, nil);
  if (![ALNAuthSession elevateAuthenticatedSessionForMethod:@"sms"
                                             assuranceLevel:2
                                            authenticatedAt:nil
                                                    context:context
                                                      error:error]) {
    return nil;
  }
  NSMutableDictionary *payload =
      [NSMutableDictionary dictionaryWithDictionary:[self sessionPayloadForContext:context includeUser:YES error:NULL] ?: @{}];
  payload[@"factor"] = @"sms";
  payload[@"phone_masked"] = AMMaskedPhoneNumber(phone);
  payload[@"enrollment_completed"] = @([purpose isEqualToString:@"enrollment"]);
  return payload;
}

- (BOOL)removeSMSEnrollmentForUser:(NSDictionary *)user
                           context:(ALNContext *)context
                             error:(NSError **)error {
  if (!self.smsEnabled) {
    return YES;
  }
  BOOL recentMFA = [ALNAuthSession context:context
             satisfiesMinimumAssuranceLevel:2
           maximumAuthenticationAgeSeconds:self.smsRecentMFAMaxAgeSeconds
                              referenceDate:nil];
  if (self.smsPhoneManagementRequiresMFA && !recentMFA) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected,
                       @"Verify an existing MFA factor before removing the SMS factor",
                       nil);
    }
    return NO;
  }
  NSInteger deleted = [self.database executeCommand:@"DELETE FROM auth_mfa_enrollments WHERE user_id = $1 AND type = 'sms'"
                                         parameters:@[ AMTrimmedString(user[@"id"]) ?: @"" ]
                                              error:error];
  if (deleted < 0) {
    return NO;
  }
  AMSetSMSSessionState(context, nil);
  // Removing a factor ends the user's other sessions; this one stays signed in.
  if (deleted > 0 && ![self signOutOtherSessionsForContext:context error:error]) {
    return NO;
  }
  return YES;
}

- (NSDictionary *)sessionPayloadForContext:(ALNContext *)context
                               includeUser:(BOOL)includeUser
                                     error:(NSError **)error {
  NSString *subject = [context authSubject] ?: @"";
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"authenticated"] = @([subject length] > 0);
  payload[@"subject"] = subject;
  payload[@"provider"] = [context authProvider] ?: @"";
  payload[@"aal"] = @([context authAssuranceLevel]);
  payload[@"mfa"] = @([context isMFAAuthenticated]);
  payload[@"methods"] = [context authMethods] ?: @[];
  payload[@"scopes"] = [context authScopes] ?: @[];
  payload[@"roles"] = [context authRoles] ?: @[];
  payload[@"session_id"] = [context authSessionIdentifier] ?: @"";
  payload[@"csrf_token"] = [context csrfToken] ?: @"";
  payload[@"login_providers"] = self.loginProviders ?: @[];
  payload[@"ui_mode"] = self.uiMode ?: @"module-ui";
  payload[@"local_password_enabled"] = @(self.localPasswordEnabled);
  if (includeUser && [subject length] > 0 && self.oidcProviders[[context authProvider]] == nil) {
    NSDictionary *user = [self currentUserForSubject:subject error:error];
    if (user != nil) {
      payload[@"user"] = user;
    }
  }
  return payload;
}

- (NSDictionary *)claimTrustedEmail:(NSString *)email
                        displayName:(NSString *)displayName
                             source:(NSString *)source
             sendPasswordSetupEmail:(BOOL)sendPasswordSetupEmail
                            baseURL:(NSString *)baseURL
                            context:(ALNContext *)context
                              error:(NSError **)error {
  NSString *normalizedEmail = AMLowerTrimmedString(email);
  if ([normalizedEmail length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"Email is required", @{ @"field" : @"email" });
    }
    return nil;
  }
  if (context == nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorValidationFailed, @"Context is required for email-link session claim", nil);
    }
    return nil;
  }
  NSString *claimSource = ([AMTrimmedString(source) length] > 0) ? AMTrimmedString(source) : @"trusted_email_claim";
  NSError *lookupError = nil;
  NSDictionary *user = [self userForEmail:normalizedEmail error:&lookupError];
  BOOL createdUser = NO;
  if (user == nil) {
    if (lookupError != nil) {
      if (error != NULL) {
        *error = lookupError;
      }
      return nil;
    }
    user = [self createTrustedEmailClaimUserWithEmail:normalizedEmail
                                          displayName:displayName
                                               source:claimSource
                                                error:error];
    if (user == nil) {
      return nil;
    }
    createdUser = YES;
  }

  NSString *userID = AMTrimmedString(user[@"id"]);
  if ([userID length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"Unable to resolve claimed user", @{ @"email" : normalizedEmail });
    }
    return nil;
  }
  if (![self markEmailVerifiedForUserID:userID error:error]) {
    return nil;
  }
  user = [self userForSubject:AMTrimmedString(user[@"subject"]) error:error] ?: user;

  BOOL passwordSetupIssued = NO;
  if (sendPasswordSetupEmail) {
    if (self.mailAdapter == nil) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorInvalidConfiguration,
                         @"Mail adapter is required when sendPasswordSetupEmail is enabled",
                         nil);
      }
      return nil;
    }
    // A configured authModule.publicBaseURL takes precedence; the caller's
    // baseURL is used only when it is unset, so callers must not derive it
    // from request headers.
    NSString *resolvedBaseURL =
        ([self.publicBaseURL length] > 0) ? self.publicBaseURL : AMTrimmedString(baseURL);
    if ([resolvedBaseURL length] == 0) {
      if (error != NULL) {
        *error = AMError(ALNAuthModuleErrorValidationFailed,
                         @"baseURL is required when sending a password setup email",
                         @{ @"field" : @"baseURL" });
      }
      return nil;
    }
    NSString *token = [self issuePasswordResetTokenForUserID:userID error:error];
    if ([token length] == 0) {
      return nil;
    }
    if (![self sendNotificationEvent:@"password_reset"
                                user:user
                               token:token
                             baseURL:resolvedBaseURL
                               error:error]) {
      return nil;
    }
    passwordSetupIssued = YES;
  }

  NSDictionary *session = [self startSessionForUser:user
                                           provider:@"email_link"
                                            methods:@[ @"email_link" ]
                                            context:context
                                              error:error];
  if (session == nil) {
    return nil;
  }
  return @{
    @"user" : user ?: @{},
    @"session" : session ?: @{},
    @"created_user" : @(createdUser),
    @"email_verified" : @([AMTrimmedString(user[@"email_verified_at"]) length] > 0),
    @"password_setup_issued" : @(passwordSetupIssued),
    @"source" : claimSource,
  };
}

- (BOOL)isAdminContext:(ALNContext *)context
                 error:(NSError **)error {
  NSDictionary *user = [self currentUserForContext:context error:error];
  if (user != nil) {
    return [[user[@"roles"] isKindOfClass:[NSArray class]] ? user[@"roles"] : @[] containsObject:@"admin"];
  }
  return [[context authRoles] containsObject:@"admin"];
}

- (NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                          providerConfiguration:(NSDictionary *)providerConfiguration
                                                          error:(NSError **)error {
  NSString *provider = AMTrimmedString(providerConfiguration[@"identifier"]);
  if ([provider isEqualToString:@"stub"] && ![self isDevelopmentOrTestEnvironment]) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorPolicyRejected,
                       @"The stub provider is only available in the development and test environments", nil);
    }
    return nil;
  }
  NSString *providerSubject = AMTrimmedString(normalizedIdentity[@"provider_subject"]);
  NSDictionary *matchedUser = [self userForProvider:provider providerSub:providerSubject error:error];
  NSString *matchedBy = @"provider_identity";
  if (matchedUser == nil) {
    matchedUser = [self userForEmail:AMLowerTrimmedString(normalizedIdentity[@"email"]) error:error];
    matchedBy = ([matchedUser count] > 0) ? @"email" : @"new_user";
  }
  NSDictionary *defaultDescriptor = @{
    @"matched_by" : matchedBy,
    @"create_user" : @((matchedUser == nil)),
    @"subject" : AMTrimmedString(matchedUser[@"subject"]),
    @"provider" : provider ?: @"stub",
    @"email" : AMLowerTrimmedString(normalizedIdentity[@"email"]),
    @"display_name" : AMTrimmedString(normalizedIdentity[@"display_name"]),
  };
  NSDictionary *descriptor =
      [self providerMappingDescriptorForNormalizedIdentity:(normalizedIdentity ?: @{}) defaultDescriptor:defaultDescriptor];
  BOOL createUser = [descriptor[@"create_user"] respondsToSelector:@selector(boolValue)] ? [descriptor[@"create_user"] boolValue] : (matchedUser == nil);
  NSString *descriptorSubject = AMTrimmedString(descriptor[@"subject"]);
  if ([descriptorSubject length] > 0) {
    matchedUser = [self userForSubject:descriptorSubject error:error];
  }
  if (matchedUser == nil && createUser) {
    matchedUser = [self createFederatedUserForIdentity:normalizedIdentity error:error];
  }
  if (matchedUser == nil) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"Unable to map provider identity to a local user", nil);
    }
    return nil;
  }
  if (![self insertProviderIdentityForUserID:AMTrimmedString(matchedUser[@"id"])
                                    provider:provider
                             providerSubject:providerSubject
                                     profile:normalizedIdentity
                                       error:error]) {
    return nil;
  }
  return @{
    @"subject" : AMTrimmedString(matchedUser[@"subject"]),
    @"provider" : provider ?: @"stub",
    @"methods" : @[ @"federated" ],
    @"roles" : [matchedUser[@"roles"] isKindOfClass:[NSArray class]] ? matchedUser[@"roles"] : @[],
    @"assuranceLevel" : @1,
  };
}

- (NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                          providerConfiguration:(NSDictionary *)providerConfiguration
                                                          error:(NSError **)error {
  (void)error;
  return @{
    @"strategy" : @"provider_or_email",
    @"provider" : AMTrimmedString(providerConfiguration[@"identifier"]),
    @"email" : AMLowerTrimmedString(normalizedIdentity[@"email"]),
    @"provider_subject" : AMTrimmedString(normalizedIdentity[@"provider_subject"]),
  };
}

@end

@implementation ALNAuthModuleController

- (ALNAuthModuleRuntime *)runtime {
  return [ALNAuthModuleRuntime sharedRuntime];
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:self.context.request.queryParams ?: @{}];
  NSString *contentType = [[[self headerValueForName:@"content-type"] lowercaseString]
      componentsSeparatedByString:@";"][0];
  NSDictionary *bodyParameters = @{};
  if ([contentType containsString:@"application/json"]) {
    bodyParameters = AMJSONParametersFromBody(self.context.request.body);
  } else if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
    bodyParameters = self.context.request.formParams;
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (BOOL)shouldReturnJSON:(ALNContext *)ctx {
  NSString *path = AMTrimmedString(ctx.request.path);
  NSString *apiPrefix = self.runtime.apiPrefix ?: @"/auth/api";
  return [ctx wantsJSON] || ([path length] > 0 && [path hasPrefix:apiPrefix]);
}

- (NSString *)requestBaseURL:(ALNContext *)ctx {
  NSString *host = AMTrimmedString([self headerValueForName:@"host"]);
  if ([host length] == 0) {
    host = @"127.0.0.1";
  }
  NSString *scheme = ([AMLowerTrimmedString(ctx.request.scheme) length] > 0) ? AMLowerTrimmedString(ctx.request.scheme) : @"http";
  return [NSString stringWithFormat:@"%@://%@", scheme, host];
}

- (BOOL)shouldPreferJSONForHeadlessRequest:(ALNContext *)ctx {
  return ([self shouldReturnJSON:ctx] || [self.runtime isHeadlessUIMode]);
}

- (NSString *)stylesheetPathForRuntime {
  return [self.runtime authUIAssetPathForFilename:@"auth.css"];
}

- (NSDictionary *)pageContextForIdentifier:(NSString *)pageIdentifier
                                     title:(NSString *)title
                                   message:(NSString *)message
                                    errors:(NSArray *)errors
                                  formData:(NSDictionary *)formData
                                  extraCtx:(NSDictionary *)extraCtx {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  NSString *normalizedIdentifier = AMNormalizedTemplateIdentifier(pageIdentifier);
  context[@"pageTitle"] = title ?: @"Auth";
  context[@"authPageIdentifier"] = normalizedIdentifier ?: @"result";
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"formData"] = [formData isKindOfClass:[NSDictionary class]] ? formData : @{};
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"authPrefix"] = self.runtime.prefix ?: @"/auth";
  context[@"authAPIPrefix"] = self.runtime.apiPrefix ?: @"/auth/api";
  context[@"authLoginPath"] = self.runtime.loginPath ?: @"/auth/login";
  context[@"authRegisterPath"] = self.runtime.registerPath ?: @"/auth/register";
  context[@"authForgotPasswordPath"] = self.runtime.forgotPasswordPath ?: @"/auth/password/forgot";
  context[@"authResetPasswordPath"] = self.runtime.resetPasswordPath ?: @"/auth/password/reset";
  context[@"authMFAManagePath"] = self.runtime.mfaManagePath ?: @"/auth/mfa";
  context[@"authTOTPPath"] = self.runtime.totpPath ?: @"/auth/mfa/totp";
  context[@"authSMSPath"] = self.runtime.smsPath ?: @"/auth/mfa/sms";
  context[@"authSMSStartPath"] = self.runtime.smsStartPath ?: @"/auth/mfa/sms/start";
  context[@"authSMSVerifyPath"] = self.runtime.smsVerifyPath ?: @"/auth/mfa/sms/verify";
  context[@"authSMSResendPath"] = self.runtime.smsResendPath ?: @"/auth/mfa/sms/resend";
  context[@"authSMSRemovePath"] = self.runtime.smsRemovePath ?: @"/auth/mfa/sms/remove";
  context[@"authProviders"] = self.runtime.loginProviders ?: @[];
  context[@"authLocalPasswordEnabled"] = @(self.runtime.localPasswordEnabled);
  context[@"authUIMode"] = self.runtime.uiMode ?: @"module-ui";
  context[@"authStylesheetPath"] = [self stylesheetPathForRuntime];
  context[@"authTOTPQRCodeScriptPath"] = [self.runtime authUIAssetPathForFilename:@"auth_totp_qr.js"];
  context[@"authPageBodyTemplate"] =
      [self.runtime bodyTemplatePathForIdentifier:normalizedIdentifier
                                      defaultPath:AMModuleBodyTemplatePathForIdentifier(normalizedIdentifier)];
  context[@"authPartialPageWrapper"] =
      [self.runtime partialTemplatePathForIdentifier:@"page_wrapper"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"page_wrapper")];
  context[@"authPartialMessageBlock"] =
      [self.runtime partialTemplatePathForIdentifier:@"message_block"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"message_block")];
  context[@"authPartialErrorBlock"] =
      [self.runtime partialTemplatePathForIdentifier:@"error_block"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"error_block")];
  context[@"authPartialFormShell"] =
      [self.runtime partialTemplatePathForIdentifier:@"form_shell"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"form_shell")];
  context[@"authPartialFieldRow"] =
      [self.runtime partialTemplatePathForIdentifier:@"field_row"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"field_row")];
  context[@"authPartialProviderRow"] =
      [self.runtime partialTemplatePathForIdentifier:@"provider_row"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"provider_row")];
  context[@"authPartialResultActions"] =
      [self.runtime partialTemplatePathForIdentifier:@"result_actions"
                                         defaultPath:AMModulePartialTemplatePathForIdentifier(@"result_actions")];
  context[@"authFragmentProviderLoginButtons"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"provider_login_buttons"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"provider_login_buttons")];
  context[@"authFragmentMFAEnrollmentPanel"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"mfa_enrollment_panel"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"mfa_enrollment_panel")];
  context[@"authFragmentMFAChallengeForm"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"mfa_challenge_form"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"mfa_challenge_form")];
  context[@"authFragmentMFARecoveryCodesPanel"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"mfa_recovery_codes_panel"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"mfa_recovery_codes_panel")];
  context[@"authFragmentMFAFactorInventoryPanel"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"mfa_factor_inventory_panel"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"mfa_factor_inventory_panel")];
  context[@"authFragmentMFASMSEnrollmentPanel"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"mfa_sms_enrollment_panel"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"mfa_sms_enrollment_panel")];
  context[@"authFragmentMFASMSChallengeForm"] =
      [self.runtime fragmentTemplatePathForIdentifier:@"mfa_sms_challenge_form"
                                          defaultPath:AMModuleFragmentTemplatePathForIdentifier(@"mfa_sms_challenge_form")];
  if ([extraCtx isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extraCtx];
  }
  return [self.runtime uiContextForPage:normalizedIdentifier defaultContext:context context:self.context];
}

- (NSString *)apiTOTPVerifyPath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa/totp/verify");
}

- (NSString *)apiMFAPath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa");
}

- (NSString *)apiSMSPath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa/sms");
}

- (NSString *)apiSMSStartPath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa/sms/start");
}

- (NSString *)apiSMSVerifyPath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa/sms/verify");
}

- (NSString *)apiSMSResendPath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa/sms/resend");
}

- (NSString *)apiSMSRemovePath {
  return AMPathJoin(self.runtime.apiPrefix, @"mfa/sms/remove");
}

- (NSDictionary *)totpJSONFlowForProvisioning:(NSDictionary *)provisioning
                                     returnTo:(NSString *)returnTo {
  BOOL verified = [provisioning[@"verified"] boolValue];
  NSString *normalizedReturnTo = AMTrimmedString(returnTo);
  return @{
    @"factor" : @"totp",
    @"state" : verified ? @"challenge" : @"enrollment",
    @"return_to" : normalizedReturnTo ?: @"",
    @"verify_path" : [self apiTOTPVerifyPath],
  };
}

- (NSDictionary *)totpJSONStateForProvisioning:(NSDictionary *)provisioning {
  BOOL verified = [provisioning[@"verified"] boolValue];
  return @{
    @"factor" : @"totp",
    @"enrolled" : provisioning[@"enrolled"] ?: @NO,
    @"verified" : provisioning[@"verified"] ?: @NO,
    @"recovery_codes_configured" : provisioning[@"recovery_codes_configured"] ?: @NO,
    @"provisioning" : verified ? @{} : (provisioning ?: @{}),
  };
}

- (NSDictionary *)totpJSONResponseForContext:(ALNContext *)ctx
                                 provisioning:(NSDictionary *)provisioning
                                     returnTo:(NSString *)returnTo {
  return @{
    @"status" : @"ok",
    @"flow" : [self totpJSONFlowForProvisioning:(provisioning ?: @{}) returnTo:returnTo],
    @"mfa" : [self totpJSONStateForProvisioning:(provisioning ?: @{})],
    @"session" : [self.runtime sessionPayloadForContext:ctx includeUser:YES error:NULL] ?: @{},
  };
}

- (NSDictionary *)mfaJSONResponseForContext:(ALNContext *)ctx
                                   returnTo:(NSString *)returnTo {
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:NULL];
  NSDictionary *factorState = (user != nil) ? ([self.runtime mfaFactorStateForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{}) : @{};
  NSDictionary *paths = @{
    @"manage" : [self apiMFAPath],
    @"totp" : AMPathJoin(self.runtime.apiPrefix, @"mfa/totp"),
    @"totp_verify" : [self apiTOTPVerifyPath],
    @"sms" : self.runtime.smsEnabled ? [self apiSMSPath] : @"",
    @"sms_start" : self.runtime.smsEnabled ? [self apiSMSStartPath] : @"",
    @"sms_verify" : self.runtime.smsEnabled ? [self apiSMSVerifyPath] : @"",
    @"sms_resend" : self.runtime.smsEnabled ? [self apiSMSResendPath] : @"",
    @"sms_remove" : self.runtime.smsEnabled ? [self apiSMSRemovePath] : @"",
  };
  return @{
    @"status" : @"ok",
    @"preferred_factor" : factorState[@"preferred_factor"] ?: @"totp",
    @"available_challenge_factors" : factorState[@"available_challenge_factors"] ?: @[],
    @"factors" : factorState[@"factors"] ?: @[],
    @"policy" : factorState[@"policy"] ?: @{},
    @"mfa" : @{
      @"totp" : [factorState[@"totp"] isKindOfClass:[NSDictionary class]] ? factorState[@"totp"] : @{},
      @"sms" : [factorState[@"sms"] isKindOfClass:[NSDictionary class]] ? factorState[@"sms"] : @{},
    },
    @"paths" : paths,
    @"session" : [self.runtime sessionPayloadForContext:ctx includeUser:YES error:NULL] ?: @{},
  };
}

- (NSDictionary *)smsJSONChallengeResponseForContext:(ALNContext *)ctx
                                            returnTo:(NSString *)returnTo
                                             autoSend:(BOOL)autoSend
                                               error:(NSError **)error {
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:error];
  if (user == nil) {
    return nil;
  }
  NSDictionary *fragmentCtx = [self.runtime smsChallengeFragmentContextForUser:user
                                                                       context:ctx
                                                                      returnTo:returnTo
                                                                      autoSend:autoSend
                                                                         error:error];
  if (fragmentCtx == nil) {
    return nil;
  }
  return @{
    @"status" : @"ok",
    @"flow" : @{
      @"factor" : @"sms",
      @"state" : @"challenge",
      @"return_to" : AMTrimmedString(returnTo) ?: @"",
      @"verify_path" : [self apiSMSVerifyPath],
      @"resend_path" : [self apiSMSResendPath],
    },
    @"mfa" : @{
      @"factor" : @"sms",
      @"challenge" : [fragmentCtx[@"authSMSState"] isKindOfClass:[NSDictionary class]] ? fragmentCtx[@"authSMSState"] : @{},
    },
    @"session" : [self.runtime sessionPayloadForContext:ctx includeUser:YES error:NULL] ?: @{},
  };
}

- (NSDictionary *)totpJSONSuccessPayloadFromSessionPayload:(NSDictionary *)sessionPayload
                                                  returnTo:(NSString *)returnTo {
  NSArray *recoveryCodes = [sessionPayload[@"recovery_codes"] isKindOfClass:[NSArray class]] ? sessionPayload[@"recovery_codes"] : @[];
  NSString *continueTarget =
      ([AMTrimmedString(returnTo) length] > 0) ? AMTrimmedString(returnTo) : (self.runtime.defaultRedirect ?: @"/");
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:sessionPayload ?: @{}];
  payload[@"status"] = @"ok";
  payload[@"session"] = sessionPayload ?: @{};
  payload[@"flow"] = @{
    @"factor" : @"totp",
    @"state" : ([recoveryCodes count] > 0) ? @"recovery_codes" : @"complete",
    @"return_to" : AMTrimmedString(returnTo) ?: @"",
    @"continue_to" : continueTarget,
    @"verify_path" : [self apiTOTPVerifyPath],
  };
  payload[@"mfa"] = @{
    @"factor" : @"totp",
    @"enrolled" : @YES,
    @"verified" : @YES,
    @"recovery_codes_configured" : @YES,
    @"recovery_codes_present" : @([recoveryCodes count] > 0),
    @"recovery_codes" : recoveryCodes ?: @[],
  };
  return payload;
}

- (BOOL)renderAuthPageIdentifier:(NSString *)pageIdentifier
                           title:(NSString *)title
                         message:(NSString *)message
                          errors:(NSArray *)errors
                        formData:(NSDictionary *)formData
                        extraCtx:(NSDictionary *)extraCtx
                           error:(NSError **)error {
  NSString *normalizedIdentifier = AMNormalizedTemplateIdentifier(pageIdentifier);
  NSString *defaultTemplate = AMModulePageTemplatePathForIdentifier(normalizedIdentifier);
  NSString *templateName = [self.runtime pageTemplatePathForIdentifier:normalizedIdentifier defaultPath:defaultTemplate];
  NSString *layoutName = [self.runtime layoutTemplateForPage:normalizedIdentifier context:self.context];
  NSDictionary *context = [self pageContextForIdentifier:normalizedIdentifier
                                                   title:title
                                                 message:message
                                                  errors:errors
                                                formData:formData
                                                extraCtx:extraCtx];
  return [self renderTemplate:templateName context:context layout:layoutName error:error];
}

// The server's proxy-aware client address (never a raw forwarding header).
- (NSString *)clientAddressForContext:(ALNContext *)ctx {
  NSString *address = AMTrimmedString(ctx.request.effectiveRemoteAddress);
  return ([address length] > 0) ? address : (AMTrimmedString(ctx.request.remoteAddress) ?: @"");
}

// 429 with Retry-After for a locked account; otherwise `fallbackStatus`.
// Text for the client. Database driver errors never reach the client: they
// get a generic message and the detail goes to the log.
- (NSString *)clientMessageForError:(NSError *)error fallback:(NSString *)fallback {
  if (error == nil) {
    return fallback;
  }
  // Messages the module wrote itself (for example the missing-migration
  // guidance, which wraps the driver error) are safe to show.
  BOOL moduleMessage = [error.domain isEqualToString:ALNAuthModuleErrorDomain] &&
                       error.code != ALNAuthModuleErrorDatabaseUnavailable;
  if (AMErrorIsDatabaseUnavailable(error) || (!moduleMessage && AMErrorInvolvesDatabase(error))) {
    [self.context.logger warn:@"auth module request failed on a database error"
                       fields:@{
                         @"error" : error.localizedDescription ?: @"",
                         @"code" : @(error.code),
                         @"sqlstate" : AMTrimmedString(error.userInfo[ALNPgErrorSQLStateKey]) ?: @"",
                       }];
    return AMErrorIsDatabaseUnavailable(error) ? AMDatabaseUnavailableMessage
                                               : @"The request could not be completed. Try again shortly.";
  }
  return error.localizedDescription ?: fallback;
}

- (void)setStatusForAuthError:(NSError *)error fallbackStatus:(NSInteger)fallbackStatus {
  if ([error.domain isEqualToString:ALNAuthModuleErrorDomain] && error.code == ALNAuthModuleErrorRateLimited) {
    NSUInteger retryAfter = ALNUnsignedIntegerValueOrDefault(error.userInfo[ALNAuthModuleRetryAfterSecondsKey], 1U);
    [self setStatus:429];
    [self.context.response setHeader:@"Retry-After"
                               value:[NSString stringWithFormat:@"%lu", (unsigned long)MAX(retryAfter, (NSUInteger)1)]];
    return;
  }
  if (AMErrorIsDatabaseUnavailable(error)) {
    [self setStatus:503];
    [self.context.response setHeader:@"Retry-After" value:@"2"];
    return;
  }
  [self setStatus:fallbackStatus];
}

// 503 with Retry-After when the user lookup failed because the database was
// unavailable. The session is left alone: the user is not signed out.
- (id)authStoreUnavailableResponse:(ALNContext *)ctx {
  [self setStatus:503];
  [self.context.response setHeader:@"Retry-After" value:@"2"];
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return @{ @"status" : @"error", @"message" : AMDatabaseUnavailableMessage };
  }
  [self renderText:AMDatabaseUnavailableMessage];
  return nil;
}

- (NSArray *)errorEntriesForError:(NSError *)error
                            field:(NSString *)field {
  if (error == nil) {
    return @[];
  }
  return @[ @{
    @"field" : field ?: @"",
    @"message" : [self clientMessageForError:error fallback:@"Request failed"],
  } ];
}

- (id)sessionState:(ALNContext *)ctx {
  NSDictionary *payload = [self.runtime sessionPayloadForContext:ctx includeUser:YES error:NULL] ?: @{};
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return payload;
  }
  if ([[ctx authSubject] length] > 0) {
    [self redirectTo:self.runtime.defaultRedirect status:302];
    return nil;
  }
  [self redirectTo:self.runtime.loginPath status:302];
  return nil;
}

- (id)loginForm:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSDictionary *extraCtx = @{
    @"authFormDescriptor" : @{
      @"action" : self.runtime.loginPath ?: @"/auth/login",
      @"method" : @"post",
      @"submitLabel" : @"Sign In",
      @"hidden" : @[ @{
        @"name" : @"return_to",
        @"value" : AMSafeReturnTo(parameters[@"return_to"]),
      } ],
      @"fields" : @[
        @{
          @"name" : @"email",
          @"label" : @"Email",
          @"type" : @"email",
          @"autocomplete" : @"email",
          @"value" : @"",
        },
        @{
          @"name" : @"password",
          @"label" : @"Password",
          @"type" : @"password",
          @"autocomplete" : @"current-password",
        },
      ],
      @"links" : @[
        @{
          @"label" : @"Create account",
          @"href" : self.runtime.registerPath ?: @"/auth/register",
        },
        @{
          @"label" : @"Forgot password",
          @"href" : self.runtime.forgotPasswordPath ?: @"/auth/password/forgot",
        },
      ],
    },
  };
  NSString *providerError = AMTrimmedString(ctx.session[ALNAuthModuleProviderErrorSessionKey]);
  BOOL rendered = [self renderAuthPageIdentifier:@"login"
                                           title:@"Sign In"
                                         message:AMTrimmedString(ctx.session[ALNAuthModuleVerificationNoticeSessionKey])
                                          errors:([providerError length] > 0
                                                      ? @[ @{ @"field" : @"", @"message" : providerError } ]
                                                      : nil)
                                        formData:@{ @"return_to" : AMSafeReturnTo(parameters[@"return_to"]) }
                                        extraCtx:extraCtx
                                           error:NULL];
  [ctx.session removeObjectForKey:ALNAuthModuleVerificationNoticeSessionKey];
  if ([providerError length] > 0) {
    [ctx.session removeObjectForKey:ALNAuthModuleProviderErrorSessionKey];
    [ctx markSessionDirty];
  }
  if (!rendered) {
    [self setStatus:500];
    [self renderText:@"render failed\n"];
  }
  return nil;
}

- (id)login:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSString *email = AMLowerTrimmedString(parameters[@"email"]);
  NSString *password = AMTrimmedString(parameters[@"password"]);
  NSString *returnTo = AMSafeReturnTo(parameters[@"return_to"]);
  NSError *error = nil;
  NSDictionary *user = [self.runtime authenticateLocalEmail:email
                                                   password:password
                                              clientAddress:[self clientAddressForContext:ctx]
                                                      error:&error];
  if (user == nil) {
    [self setStatusForAuthError:error fallbackStatus:401];
    NSArray *errors = [self errorEntriesForError:(error ?: AMError(ALNAuthModuleErrorAuthenticationFailed, @"Invalid email or password", nil))
                                           field:@"email"];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      return @{ @"status" : @"error", @"errors" : errors };
    }
    [self renderAuthPageIdentifier:@"login"
                             title:@"Sign In"
                           message:@""
                            errors:errors
                          formData:@{ @"email" : email ?: @"", @"return_to" : returnTo ?: @"" }
                          extraCtx:@{
                            @"authFormDescriptor" : @{
                              @"action" : self.runtime.loginPath ?: @"/auth/login",
                              @"method" : @"post",
                              @"submitLabel" : @"Sign In",
                              @"hidden" : @[ @{
                                @"name" : @"return_to",
                                @"value" : returnTo ?: @"",
                              } ],
                              @"fields" : @[
                                @{
                                  @"name" : @"email",
                                  @"label" : @"Email",
                                  @"type" : @"email",
                                  @"autocomplete" : @"email",
                                  @"value" : email ?: @"",
                                },
                                @{
                                  @"name" : @"password",
                                  @"label" : @"Password",
                                  @"type" : @"password",
                                  @"autocomplete" : @"current-password",
                                },
                              ],
                              @"links" : @[
                                @{
                                  @"label" : @"Create account",
                                  @"href" : self.runtime.registerPath ?: @"/auth/register",
                                },
                                @{
                                  @"label" : @"Forgot password",
                                  @"href" : self.runtime.forgotPasswordPath ?: @"/auth/password/forgot",
                                },
                              ],
                            },
                          }
                             error:NULL];
    return nil;
  }
  NSDictionary *session = [self.runtime startSessionForUser:user provider:@"local" methods:@[ @"pwd" ] context:ctx error:&error];
  if (session == nil) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : [self clientMessageForError:error fallback:@"Failed to create session"] };
  }
  NSString *redirectTarget = [self.runtime postLoginRedirectForContext:ctx
                                                                  user:user
                                                       defaultRedirect:returnTo];
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:session];
    payload[@"redirect_to"] = redirectTarget ?: self.runtime.defaultRedirect;
    return payload;
  }
  [self redirectTo:redirectTarget status:302];
  return nil;
}

- (id)logout:(ALNContext *)ctx {
  NSError *error = nil;
  if (![self.runtime revokeCurrentSessionForContext:ctx error:&error]) {
    // The session is cleared either way; only the server-side record failed.
    [ctx.logger error:@"auth logout could not record the ended session"
               fields:@{ @"module" : @"auth", @"error" : error.localizedDescription ?: @"" }];
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return @{ @"status" : @"ok" };
  }
  [self redirectTo:self.runtime.loginPath status:302];
  return nil;
}

- (id)logoutAll:(ALNContext *)ctx {
  if ([[ctx authSubject] length] == 0) {
    [self setStatus:401];
    return @{ @"status" : @"error", @"message" : @"Authentication required" };
  }
  NSError *error = nil;
  BOOL endsOtherSessions = [self.runtime canEndOtherSessions];
  if (![self.runtime signOutAllSessionsForContext:ctx error:&error]) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : error.localizedDescription ?: @"Failed to sign out other sessions" };
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    if (!endsOtherSessions) {
      return @{
        @"status" : @"partial",
        @"scope" : @"current_session",
        @"message" : @"Signed out of this session only. Other sessions can be ended after the auth module "
                     @"migrations are applied (arlen module migrate).",
      };
    }
    return @{ @"status" : @"ok", @"scope" : @"all_sessions" };
  }
  [self redirectTo:self.runtime.loginPath status:302];
  return nil;
}

- (id)registerForm:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  BOOL rendered = [self renderAuthPageIdentifier:@"register"
                                           title:@"Create Account"
                                         message:@""
                                          errors:nil
                                        formData:@{ @"return_to" : AMSafeReturnTo(parameters[@"return_to"]) }
                                        extraCtx:@{
                                          @"authFormDescriptor" : @{
                                            @"action" : self.runtime.registerPath ?: @"/auth/register",
                                            @"method" : @"post",
                                            @"submitLabel" : @"Create Account",
                                            @"hidden" : @[ @{
                                              @"name" : @"return_to",
                                              @"value" : AMSafeReturnTo(parameters[@"return_to"]),
                                            } ],
                                            @"fields" : @[
                                              @{
                                                @"name" : @"email",
                                                @"label" : @"Email",
                                                @"type" : @"email",
                                                @"autocomplete" : @"email",
                                              },
                                              @{
                                                @"name" : @"display_name",
                                                @"label" : @"Display Name",
                                                @"type" : @"text",
                                                @"autocomplete" : @"name",
                                              },
                                              @{
                                                @"name" : @"password",
                                                @"label" : @"Password",
                                                @"type" : @"password",
                                                @"autocomplete" : @"new-password",
                                              },
                                            ],
                                            @"links" : @[
                                              @{
                                                @"label" : @"Back to sign in",
                                                @"href" : self.runtime.loginPath ?: @"/auth/login",
                                              },
                                            ],
                                          },
                                        }
                                           error:NULL];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:@"render failed\n"];
  }
  return nil;
}

- (id)register:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSString *email = AMLowerTrimmedString(parameters[@"email"]);
  NSString *displayName = AMTrimmedString(parameters[@"display_name"]);
  NSString *password = AMTrimmedString(parameters[@"password"]);
  NSString *returnTo = AMSafeReturnTo(parameters[@"return_to"]);
  NSError *error = nil;
  NSDictionary *user =
      [self.runtime createLocalUserWithEmail:email displayName:displayName password:password source:@"local_registration" error:&error];
  if (user == nil) {
    [self setStatus:422];
    NSArray *errors = [self errorEntriesForError:(error ?: AMError(ALNAuthModuleErrorValidationFailed, @"Registration failed", nil))
                                           field:AMTrimmedString(error.userInfo[@"field"])];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      return @{ @"status" : @"error", @"errors" : errors };
    }
    [self renderAuthPageIdentifier:@"register"
                             title:@"Create Account"
                           message:@""
                            errors:errors
                          formData:@{
                            @"email" : email ?: @"",
                            @"display_name" : displayName ?: @"",
                            @"return_to" : returnTo ?: @"",
                          }
                          extraCtx:@{
                            @"authFormDescriptor" : @{
                              @"action" : self.runtime.registerPath ?: @"/auth/register",
                              @"method" : @"post",
                              @"submitLabel" : @"Create Account",
                              @"hidden" : @[ @{
                                @"name" : @"return_to",
                                @"value" : returnTo ?: @"",
                              } ],
                              @"fields" : @[
                                @{
                                  @"name" : @"email",
                                  @"label" : @"Email",
                                  @"type" : @"email",
                                  @"autocomplete" : @"email",
                                  @"value" : email ?: @"",
                                },
                                @{
                                  @"name" : @"display_name",
                                  @"label" : @"Display Name",
                                  @"type" : @"text",
                                  @"autocomplete" : @"name",
                                  @"value" : displayName ?: @"",
                                },
                                @{
                                  @"name" : @"password",
                                  @"label" : @"Password",
                                  @"type" : @"password",
                                  @"autocomplete" : @"new-password",
                                },
                              ],
                              @"links" : @[
                                @{
                                  @"label" : @"Back to sign in",
                                  @"href" : self.runtime.loginPath ?: @"/auth/login",
                                },
                              ],
                            },
                          }
                             error:NULL];
    return nil;
  }

  NSString *verificationBaseURL = [self.runtime emailLinkBaseURLWithRequestBaseURL:[self requestBaseURL:ctx]
                                                                             event:@"email_verification"];
  NSString *verificationToken = ([verificationBaseURL length] > 0)
                                    ? [self.runtime issueVerificationTokenForUserID:AMTrimmedString(user[@"id"]) error:&error]
                                    : nil;
  if ([verificationToken length] > 0) {
    (void)[self.runtime sendNotificationEvent:@"email_verification"
                                         user:user
                                        token:verificationToken
                                      baseURL:verificationBaseURL
                                        error:NULL];
  }
  NSDictionary *session = [self.runtime startSessionForUser:user provider:@"local" methods:@[ @"pwd" ] context:ctx error:&error];
  if (session == nil) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : [self clientMessageForError:error fallback:@"Failed to create session"] };
  }
  NSString *redirectTarget = [self.runtime postLoginRedirectForContext:ctx user:user defaultRedirect:returnTo];
  ctx.session[ALNAuthModuleVerificationNoticeSessionKey] = @"Account created. Check your email for a verification link.";
  [ctx markSessionDirty];
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:session];
    payload[@"verification_required"] = @YES;
    payload[@"redirect_to"] = redirectTarget ?: self.runtime.defaultRedirect;
    return payload;
  }
  [self redirectTo:redirectTarget status:302];
  return nil;
}

- (id)verifyEmail:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *user = nil;
  BOOL ok = [self.runtime consumeVerificationToken:parameters[@"token"] user:&user error:&error];
  NSString *message = ok ? @"Your email address has been verified." : ([self clientMessageForError:error fallback:@"Verification failed."]);
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    [self setStatus:ok ? 200 : 422];
    return @{
      @"status" : ok ? @"ok" : @"error",
      @"message" : message,
      @"user" : user ?: @{},
    };
  }
  [self renderAuthPageIdentifier:@"verify_result"
                           title:@"Email Verification"
                         message:message
                          errors:nil
                        formData:nil
                        extraCtx:@{
                          @"authResultActions" : @[ @{
                            @"label" : @"Back to sign in",
                            @"href" : self.runtime.loginPath ?: @"/auth/login",
                          } ],
                          @"resultTitle" : ok ? @"Email verified" : @"Verification failed",
                        }
                           error:NULL];
  return nil;
}

- (id)forgotPasswordForm:(ALNContext *)ctx {
  [self renderAuthPageIdentifier:@"forgot_password"
                           title:@"Reset Password"
                         message:AMTrimmedString(ctx.session[ALNAuthModuleResetNoticeSessionKey])
                          errors:nil
                        formData:nil
                        extraCtx:@{
                          @"authFormDescriptor" : @{
                            @"action" : self.runtime.forgotPasswordPath ?: @"/auth/password/forgot",
                            @"method" : @"post",
                            @"submitLabel" : @"Send Reset Link",
                            @"fields" : @[
                              @{
                                @"name" : @"email",
                                @"label" : @"Email",
                                @"type" : @"email",
                                @"autocomplete" : @"email",
                              },
                            ],
                            @"links" : @[
                              @{
                                @"label" : @"Back to sign in",
                                @"href" : self.runtime.loginPath ?: @"/auth/login",
                              },
                            ],
                          },
                        }
                           error:NULL];
  [ctx.session removeObjectForKey:ALNAuthModuleResetNoticeSessionKey];
  [ctx markSessionDirty];
  return nil;
}

- (id)forgotPassword:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSString *email = AMLowerTrimmedString(parameters[@"email"]);
  // Not subject to the password delays, so the owner can always ask for a
  // reset. Its own per-email and per-address send limit stops the mail but
  // not the reply, which stays the same either way.
  BOOL maySend = [self.runtime allowMailSendForEmail:email
                                       clientAddress:[self clientAddressForContext:ctx]
                                                flow:@"password_reset"];
  NSDictionary *user = [self.runtime userForEmail:email error:NULL];
  NSString *resetBaseURL = (user != nil) ? [self.runtime emailLinkBaseURLWithRequestBaseURL:[self requestBaseURL:ctx]
                                                                                       event:@"password_reset"]
                                         : nil;
  if (maySend && user != nil && [resetBaseURL length] > 0) {
    NSError *error = nil;
    NSString *token = [self.runtime issuePasswordResetTokenForUserID:AMTrimmedString(user[@"id"]) error:&error];
    if ([token length] > 0) {
      (void)[self.runtime sendNotificationEvent:@"password_reset"
                                           user:user
                                          token:token
                                        baseURL:resetBaseURL
                                          error:NULL];
    }
  }
  NSString *message = @"If the account exists, a reset link has been issued.";
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return @{ @"status" : @"ok", @"message" : message };
  }
  ctx.session[ALNAuthModuleResetNoticeSessionKey] = message;
  [ctx markSessionDirty];
  [self redirectTo:self.runtime.forgotPasswordPath status:302];
  return nil;
}

- (id)resetPasswordForm:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  if ([self shouldReturnJSON:ctx]) {
    return @{
      @"status" : @"ok",
      @"token" : AMTrimmedString(parameters[@"token"]),
      @"message" : @"Submit the token and new password to complete reset.",
    };
  }
  [self renderAuthPageIdentifier:@"reset_password"
                           title:@"Set a New Password"
                         message:AMTrimmedString(ctx.session[ALNAuthModuleResetNoticeSessionKey])
                          errors:nil
                        formData:@{ @"token" : AMTrimmedString(parameters[@"token"]) }
                        extraCtx:@{
                          @"authFormDescriptor" : @{
                            @"action" : self.runtime.resetPasswordPath ?: @"/auth/password/reset",
                            @"method" : @"post",
                            @"submitLabel" : @"Update Password",
                            @"hidden" : @[ @{
                              @"name" : @"token",
                              @"value" : AMTrimmedString(parameters[@"token"]),
                            } ],
                            @"fields" : @[
                              @{
                                @"name" : @"password",
                                @"label" : @"New Password",
                                @"type" : @"password",
                                @"autocomplete" : @"new-password",
                              },
                            ],
                          },
                        }
                           error:NULL];
  [ctx.session removeObjectForKey:ALNAuthModuleResetNoticeSessionKey];
  [ctx markSessionDirty];
  return nil;
}

- (id)resetPassword:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *user = nil;
  BOOL ok = [self.runtime consumePasswordResetToken:parameters[@"token"]
                                           password:parameters[@"password"]
                                               user:&user
                                              error:&error];
  if (!ok) {
    [self setStatus:422];
    NSArray *errors = [self errorEntriesForError:error field:@"password"];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      return @{ @"status" : @"error", @"errors" : errors };
    }
    [self renderAuthPageIdentifier:@"reset_password"
                             title:@"Set a New Password"
                           message:@""
                            errors:errors
                          formData:@{ @"token" : AMTrimmedString(parameters[@"token"]) }
                          extraCtx:@{
                            @"authFormDescriptor" : @{
                              @"action" : self.runtime.resetPasswordPath ?: @"/auth/password/reset",
                              @"method" : @"post",
                              @"submitLabel" : @"Update Password",
                              @"hidden" : @[ @{
                                @"name" : @"token",
                                @"value" : AMTrimmedString(parameters[@"token"]),
                              } ],
                              @"fields" : @[
                                @{
                                  @"name" : @"password",
                                  @"label" : @"New Password",
                                  @"type" : @"password",
                                  @"autocomplete" : @"new-password",
                                },
                              ],
                            },
                          }
                             error:NULL];
    return nil;
  }
  NSDictionary *session = [self.runtime startSessionForUser:user provider:@"local" methods:@[ @"pwd" ] context:ctx error:NULL];
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return session ?: @{ @"status" : @"ok" };
  }
  [self redirectTo:[self.runtime postLoginRedirectForContext:ctx user:user defaultRedirect:@""]
            status:302];
  return nil;
}

- (id)changePassword:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    [self setStatus:401];
    return @{ @"status" : @"error", @"message" : @"Authentication required" };
  }
  NSDictionary *parameters = [self requestParameters];
  NSError *authError = nil;
  NSDictionary *authenticated = [self.runtime authenticateLocalEmail:user[@"email"]
                                                            password:parameters[@"current_password"]
                                                       clientAddress:[self clientAddressForContext:ctx]
                                                               error:&authError];
  if (authenticated == nil) {
    [self setStatusForAuthError:authError fallbackStatus:401];
    return @{ @"status" : @"error", @"message" : [self clientMessageForError:authError fallback:@"Current password is invalid"] };
  }
  NSError *updateError = nil;
  NSString *passwordMessage = nil;
  if (![self.runtime validatePassword:parameters[@"new_password"] errorMessage:&passwordMessage]) {
    [self setStatus:422];
    return @{ @"status" : @"error", @"message" : passwordMessage ?: @"Password does not satisfy policy" };
  }
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:AMTrimmedString(parameters[@"new_password"])
                                                      options:[ALNPasswordHash defaultArgon2idOptions]
                                                        error:&updateError];
  if ([encodedHash length] == 0) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : [self clientMessageForError:updateError fallback:@"Failed to hash password"] };
  }
  if (![self.runtime updateLocalPasswordHash:encodedHash forUserID:AMTrimmedString(user[@"id"]) error:&updateError]) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : [self clientMessageForError:updateError fallback:@"Failed to update password"] };
  }
  // The update ended every session of this user; keep this one signed in.
  if (![self.runtime recordCurrentSessionStampForContext:ctx error:&updateError]) {
    [ctx.logger warn:@"auth password change could not keep the current session signed in"
              fields:@{ @"module" : @"auth", @"error" : updateError.localizedDescription ?: @"" }];
  }
  return @{ @"status" : @"ok" };
}

- (id)mfaManage:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      [self setStatus:401];
      return @{ @"status" : @"error", @"message" : @"Authentication required" };
    }
    [self redirectTo:[NSString stringWithFormat:@"%@?return_to=%@", self.runtime.loginPath, self.runtime.mfaManagePath] status:302];
    return nil;
  }
  NSString *returnTo = AMSafeReturnTo([self requestParameters][@"return_to"]);
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return [self mfaJSONResponseForContext:ctx returnTo:returnTo];
  }
  NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
  [self renderAuthPageIdentifier:@"mfa_manage"
                           title:@"Security Factors"
                         message:@"Manage your authentication factors. Authenticator apps are recommended; SMS is optional and weaker when enabled."
                          errors:nil
                        formData:@{ @"return_to" : returnTo ?: @"" }
                        extraCtx:fragmentCtx
                           error:NULL];
  return nil;
}

- (id)smsForm:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      [self setStatus:401];
      return @{ @"status" : @"error", @"message" : @"Authentication required" };
    }
    [self redirectTo:[NSString stringWithFormat:@"%@?return_to=%@", self.runtime.loginPath, self.runtime.smsPath] status:302];
    return nil;
  }
  NSString *returnTo = AMSafeReturnTo([self requestParameters][@"return_to"]);
  NSError *error = nil;
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSDictionary *payload = [self smsJSONChallengeResponseForContext:ctx returnTo:returnTo autoSend:NO error:&error];
    if (payload == nil) {
      [self setStatus:404];
      return @{ @"status" : @"error", @"message" : [self clientMessageForError:error fallback:@"SMS factor unavailable"] };
    }
    return payload;
  }
  NSDictionary *fragmentCtx = [self.runtime smsChallengeFragmentContextForUser:user
                                                                       context:ctx
                                                                      returnTo:returnTo
                                                                      autoSend:YES
                                                                         error:&error] ?: @{};
  if ([fragmentCtx count] == 0) {
    [self setStatus:404];
    [self renderAuthPageIdentifier:@"provider_result"
                             title:@"SMS Challenge"
                           message:[self clientMessageForError:error fallback:@"SMS factor unavailable"]
                            errors:nil
                          formData:nil
                          extraCtx:@{
                            @"resultTitle" : @"SMS Challenge Unavailable",
                            @"authResultActions" : @[ @{
                              @"label" : @"Manage factors",
                              @"href" : self.runtime.mfaManagePath ?: @"/auth/mfa",
                            } ],
                          }
                             error:NULL];
    return nil;
  }
  [self renderAuthPageIdentifier:@"sms_challenge"
                           title:@"Verify by Text Message"
                         message:(error != nil
                                      ? ([self clientMessageForError:error fallback:@"Use the code we sent to your phone."])
                                      : ([fragmentCtx[@"authSMSChallengeMessage"] isKindOfClass:[NSString class]]
                                             ? fragmentCtx[@"authSMSChallengeMessage"]
                                             : @"Use the code we sent to your phone."))
                          errors:nil
                        formData:@{ @"return_to" : returnTo ?: @"" }
                        extraCtx:fragmentCtx
                           error:NULL];
  return nil;
}

- (id)smsStart:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    [self setStatus:401];
    return [self shouldPreferJSONForHeadlessRequest:ctx] ? @{ @"status" : @"error", @"message" : @"Authentication required" } : nil;
  }
  NSDictionary *parameters = [self requestParameters];
  NSString *returnTo = AMSafeReturnTo(parameters[@"return_to"]);
  NSError *error = nil;
  NSDictionary *state = [self.runtime issueSMSVerificationForUser:user
                                                            phone:parameters[@"phone_number"]
                                                          purpose:@"enrollment"
                                                          context:ctx
                                                            error:&error];
  if (state == nil) {
    [self setStatus:422];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      NSMutableDictionary *payload = [[self mfaJSONResponseForContext:ctx returnTo:returnTo] mutableCopy];
      payload[@"status"] = @"error";
      payload[@"message"] = [self clientMessageForError:error fallback:@"Unable to send SMS code"];
      return payload;
    }
    NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
    [self renderAuthPageIdentifier:@"mfa_manage"
                             title:@"Security Factors"
                           message:@""
                            errors:[self errorEntriesForError:error field:@"phone_number"]
                          formData:@{ @"phone_number" : AMTrimmedString(parameters[@"phone_number"]) ?: @"", @"return_to" : returnTo ?: @"" }
                          extraCtx:fragmentCtx
                             error:NULL];
    return nil;
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSMutableDictionary *payload = [[self mfaJSONResponseForContext:ctx returnTo:returnTo] mutableCopy];
    payload[@"message"] = [NSString stringWithFormat:@"We sent a code to %@.", state[@"masked_phone"] ?: @"your phone"];
    return payload;
  }
  NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
  [self renderAuthPageIdentifier:@"mfa_manage"
                           title:@"Security Factors"
                         message:[NSString stringWithFormat:@"We sent a code to %@. Enter it below to finish adding SMS MFA.",
                                                            state[@"masked_phone"] ?: @"your phone"]
                          errors:nil
                        formData:@{ @"return_to" : returnTo ?: @"" }
                        extraCtx:fragmentCtx
                           error:NULL];
  return nil;
}

- (id)smsResend:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    [self setStatus:401];
    return [self shouldPreferJSONForHeadlessRequest:ctx] ? @{ @"status" : @"error", @"message" : @"Authentication required" } : nil;
  }
  NSDictionary *smsState = AMSMSSessionState(ctx);
  NSString *purpose = AMLowerTrimmedString(smsState[@"purpose"]);
  NSString *phone = AMNormalizePhoneNumber(smsState[@"phone"]);
  NSString *returnTo = AMSafeReturnTo([self requestParameters][@"return_to"]);
  NSError *error = nil;
  NSDictionary *state = [self.runtime issueSMSVerificationForUser:user
                                                            phone:([purpose isEqualToString:@"enrollment"] ? phone : nil)
                                                          purpose:([purpose length] > 0 ? purpose : @"challenge")
                                                          context:ctx
                                                            error:&error];
  if (state == nil) {
    [self setStatus:422];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      NSMutableDictionary *payload = [[self mfaJSONResponseForContext:ctx returnTo:returnTo] mutableCopy];
      payload[@"status"] = @"error";
      payload[@"message"] = [self clientMessageForError:error fallback:@"Unable to resend SMS code"];
      return payload;
    }
    NSDictionary *fragmentCtx = nil;
    NSString *pageIdentifier = @"mfa_manage";
    if ([purpose isEqualToString:@"challenge"]) {
      fragmentCtx = [self.runtime smsChallengeFragmentContextForUser:user context:ctx returnTo:returnTo autoSend:NO error:NULL];
      pageIdentifier = @"sms_challenge";
    } else {
      fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL];
    }
    [self renderAuthPageIdentifier:pageIdentifier
                             title:([pageIdentifier isEqualToString:@"sms_challenge"] ? @"Verify by Text Message" : @"Security Factors")
                           message:@""
                            errors:[self errorEntriesForError:error field:@"code"]
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:(fragmentCtx ?: @{})
                             error:NULL];
    return nil;
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSDictionary *basePayload = [purpose isEqualToString:@"challenge"]
                                    ? [self smsJSONChallengeResponseForContext:ctx returnTo:returnTo autoSend:NO error:NULL]
                                    : [self mfaJSONResponseForContext:ctx returnTo:returnTo];
    NSMutableDictionary *payload = [(basePayload ?: @{}) mutableCopy];
    payload[@"message"] = [NSString stringWithFormat:@"We sent another code to %@.", state[@"masked_phone"] ?: @"your phone"];
    return payload;
  }
  if ([purpose isEqualToString:@"challenge"]) {
    NSDictionary *fragmentCtx = [self.runtime smsChallengeFragmentContextForUser:user context:ctx returnTo:returnTo autoSend:NO error:NULL] ?: @{};
    [self renderAuthPageIdentifier:@"sms_challenge"
                             title:@"Verify by Text Message"
                           message:[NSString stringWithFormat:@"We sent another code to %@.", state[@"masked_phone"] ?: @"your phone"]
                            errors:nil
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:fragmentCtx
                             error:NULL];
    return nil;
  }
  NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
  [self renderAuthPageIdentifier:@"mfa_manage"
                           title:@"Security Factors"
                         message:[NSString stringWithFormat:@"We sent another code to %@.", state[@"masked_phone"] ?: @"your phone"]
                          errors:nil
                        formData:@{ @"return_to" : returnTo ?: @"" }
                        extraCtx:fragmentCtx
                           error:NULL];
  return nil;
}

- (id)smsVerify:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    [self setStatus:401];
    return [self shouldPreferJSONForHeadlessRequest:ctx] ? @{ @"status" : @"error", @"message" : @"Authentication required" } : nil;
  }
  NSDictionary *parameters = [self requestParameters];
  NSString *returnTo = AMSafeReturnTo(parameters[@"return_to"]);
  NSString *purpose = AMLowerTrimmedString(AMSMSSessionState(ctx)[@"purpose"]);
  NSError *error = nil;
  NSDictionary *payload = [self.runtime verifySMSCode:parameters[@"code"] user:user context:ctx error:&error];
  if (payload == nil) {
    [self setStatus:422];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      NSMutableDictionary *response = [[([purpose isEqualToString:@"challenge"] ? [self smsJSONChallengeResponseForContext:ctx returnTo:returnTo autoSend:NO error:NULL]
                                                                                : [self mfaJSONResponseForContext:ctx returnTo:returnTo]) mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
      response[@"status"] = @"error";
      response[@"errors"] = [self errorEntriesForError:error field:@"code"];
      return response;
    }
    if ([purpose isEqualToString:@"challenge"]) {
      NSDictionary *fragmentCtx = [self.runtime smsChallengeFragmentContextForUser:user context:ctx returnTo:returnTo autoSend:NO error:NULL] ?: @{};
      [self renderAuthPageIdentifier:@"sms_challenge"
                               title:@"Verify by Text Message"
                             message:@""
                              errors:[self errorEntriesForError:error field:@"code"]
                            formData:@{ @"return_to" : returnTo ?: @"" }
                            extraCtx:fragmentCtx
                               error:NULL];
      return nil;
    }
    NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
    [self renderAuthPageIdentifier:@"mfa_manage"
                             title:@"Security Factors"
                           message:@""
                            errors:[self errorEntriesForError:error field:@"code"]
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:fragmentCtx
                             error:NULL];
    return nil;
  }

  BOOL enrollmentCompleted = [payload[@"enrollment_completed"] boolValue];
  NSString *continueTarget = ([returnTo length] > 0) ? returnTo : (self.runtime.defaultRedirect ?: @"/");
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:payload ?: @{}];
    response[@"status"] = @"ok";
    response[@"flow"] = @{
      @"factor" : @"sms",
      @"state" : @"complete",
      @"return_to" : returnTo ?: @"",
      @"continue_to" : continueTarget,
      @"verify_path" : [self apiSMSVerifyPath],
    };
    response[@"mfa"] = [self mfaJSONResponseForContext:ctx returnTo:returnTo][@"mfa"] ?: @{};
    return response;
  }

  if (enrollmentCompleted) {
    NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
    [self renderAuthPageIdentifier:@"mfa_manage"
                             title:@"Security Factors"
                           message:[NSString stringWithFormat:@"SMS MFA is now enabled for %@.", payload[@"phone_masked"] ?: @"your phone"]
                            errors:nil
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:fragmentCtx
                             error:NULL];
    return nil;
  }
  [self redirectTo:continueTarget status:302];
  return nil;
}

- (id)smsRemove:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    [self setStatus:401];
    return [self shouldPreferJSONForHeadlessRequest:ctx] ? @{ @"status" : @"error", @"message" : @"Authentication required" } : nil;
  }
  NSString *returnTo = AMSafeReturnTo([self requestParameters][@"return_to"]);
  NSError *error = nil;
  BOOL ok = [self.runtime removeSMSEnrollmentForUser:user context:ctx error:&error];
  if (!ok) {
    [self setStatus:422];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      NSMutableDictionary *payload = [[self mfaJSONResponseForContext:ctx returnTo:returnTo] mutableCopy];
      payload[@"status"] = @"error";
      payload[@"message"] = [self clientMessageForError:error fallback:@"Unable to remove SMS factor"];
      return payload;
    }
    NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
    [self renderAuthPageIdentifier:@"mfa_manage"
                             title:@"Security Factors"
                           message:@""
                            errors:[self errorEntriesForError:error field:@"sms"]
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:fragmentCtx
                             error:NULL];
    return nil;
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    NSMutableDictionary *payload = [[self mfaJSONResponseForContext:ctx returnTo:returnTo] mutableCopy];
    payload[@"message"] = @"SMS MFA was removed.";
    return payload;
  }
  NSDictionary *fragmentCtx = [self.runtime mfaManagementFragmentContextForUser:user context:ctx returnTo:returnTo error:NULL] ?: @{};
  [self renderAuthPageIdentifier:@"mfa_manage"
                           title:@"Security Factors"
                         message:@"SMS MFA was removed."
                          errors:nil
                        formData:@{ @"return_to" : returnTo ?: @"" }
                        extraCtx:fragmentCtx
                           error:NULL];
  return nil;
}

- (id)totpForm:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      [self setStatus:401];
      return @{ @"status" : @"error", @"message" : @"Authentication required" };
    }
    [self redirectTo:[NSString stringWithFormat:@"%@?return_to=%@", self.runtime.loginPath, self.runtime.totpPath] status:302];
    return nil;
  }
  NSString *returnTo = AMSafeReturnTo([self requestParameters][@"return_to"]);
  NSDictionary *payload = [self.runtime totpProvisioningPayloadForUser:user error:NULL] ?: @{};
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return [self totpJSONResponseForContext:ctx provisioning:payload returnTo:returnTo];
  }
  NSDictionary *fragmentCtx = [self.runtime totpFragmentContextForUser:user returnTo:returnTo error:NULL] ?: @{};
  BOOL verified = [payload[@"verified"] boolValue];
  [self renderAuthPageIdentifier:(verified ? @"totp_challenge" : @"totp_enrollment")
                           title:(verified ? @"Verify Your Authenticator" : @"Set Up Authenticator")
                         message:(verified ? @"Use your authenticator app to complete step-up authentication."
                                           : @"Scan the QR code or use the manual setup key, then enter the 6-digit code to finish setup.")
                          errors:nil
                        formData:@{ @"return_to" : returnTo ?: @"" }
                        extraCtx:fragmentCtx
                           error:NULL];
  return nil;
}

- (id)totpVerify:(ALNContext *)ctx {
  NSError *userError = nil;
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:&userError];
  if (user == nil && [[ctx authSubject] length] > 0 && AMErrorIsDatabaseUnavailable(userError)) {
    return [self authStoreUnavailableResponse:ctx];
  }
  if (user == nil) {
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      [self setStatus:401];
      return @{ @"status" : @"error", @"message" : @"Authentication required" };
    }
    [self redirectTo:[NSString stringWithFormat:@"%@?return_to=%@", self.runtime.loginPath, self.runtime.totpPath] status:302];
    return nil;
  }
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *payload = [self.runtime verifyTOTPCode:parameters[@"code"] user:user context:ctx error:&error];
  NSString *returnTo = AMSafeReturnTo(parameters[@"return_to"]);
  if (payload == nil) {
    [self setStatusForAuthError:error fallbackStatus:422];
    NSArray *errors = [self errorEntriesForError:error field:@"code"];
    NSDictionary *provisioning = [self.runtime totpProvisioningPayloadForUser:user error:NULL] ?: @{};
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      return @{
        @"status" : @"error",
        @"errors" : errors,
        @"flow" : [self totpJSONFlowForProvisioning:provisioning returnTo:returnTo],
        @"mfa" : [self totpJSONStateForProvisioning:provisioning],
      };
    }
    NSDictionary *fragmentCtx = [self.runtime totpFragmentContextForUser:user returnTo:returnTo error:NULL] ?: @{};
    BOOL verified = [provisioning[@"verified"] boolValue];
    [self renderAuthPageIdentifier:(verified ? @"totp_challenge" : @"totp_enrollment")
                             title:(verified ? @"Verify Your Authenticator" : @"Set Up Authenticator")
                           message:@""
                            errors:errors
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:fragmentCtx
                             error:NULL];
    return nil;
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return [self totpJSONSuccessPayloadFromSessionPayload:payload returnTo:returnTo];
  }
  NSArray *recoveryCodes = [payload[@"recovery_codes"] isKindOfClass:[NSArray class]] ? payload[@"recovery_codes"] : @[];
  if ([recoveryCodes count] > 0) {
    [self renderAuthPageIdentifier:@"totp_recovery_codes"
                             title:@"Save Your Recovery Codes"
                           message:@"Keep these one-time recovery codes somewhere safe. Each code can be used once if you lose access to your authenticator app."
                            errors:nil
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:[self.runtime totpRecoveryCodesFragmentContextWithCodes:recoveryCodes returnTo:returnTo]
                             error:NULL];
    return nil;
  }
  [self redirectTo:([returnTo length] > 0 ? returnTo : self.runtime.defaultRedirect) status:302];
  return nil;
}

- (ALNAuthModuleOIDC *)oidcProviderForContext:(ALNContext *)ctx {
  NSArray *parts = [ctx.request.path componentsSeparatedByString:@"/"];
  return parts.count >= 2 ? self.runtime.oidcProviders[parts[parts.count - 2]] : nil;
}

- (id)providerOIDCLogin:(ALNContext *)ctx {
  ALNAuthModuleOIDC *provider = [self oidcProviderForContext:ctx];
  if (!provider) { [self setStatus:404]; return nil; }
  NSError *error = nil;
  NSString *prompt = AMTrimmedString([self requestParameters][@"prompt"]);
  NSMutableDictionary *state = [[provider beginLoginWithPrompt:prompt error:&error] mutableCopy];
  if (!state) { [self setStatus:502]; return @{ @"status": @"error", @"message": @"Provider login unavailable" }; }
  state[@"return_to"] = AMSafeReturnTo([self requestParameters][@"return_to"]);
  NSString *authorizeURL = state[@"authorizationURL"];
  [state removeObjectForKey:@"authorizationURL"];
  ctx.session[ALNAuthModuleProviderStateSessionKey] = state;
  [ctx markSessionDirty];
  if ([self shouldReturnJSON:ctx]) return @{ @"status": @"ok", @"authorize_url": authorizeURL };
  [self redirectTo:authorizeURL status:302];
  return nil;
}

- (id)providerOIDCCallback:(ALNContext *)ctx {
  ALNAuthModuleOIDC *provider = [self oidcProviderForContext:ctx];
  if (!provider) { [self setStatus:404]; return nil; }
  NSDictionary *state = [ctx.session[ALNAuthModuleProviderStateSessionKey] isKindOfClass:[NSDictionary class]] ?
                        ctx.session[ALNAuthModuleProviderStateSessionKey] : @{};
  [ctx.session removeObjectForKey:ALNAuthModuleProviderStateSessionKey];
  [ctx markSessionDirty];
  NSError *error = nil;
  NSDictionary *result = [provider completeLoginWithParameters:[self requestParameters] callbackState:state context:ctx error:&error];
  NSString *failureCode = [error.userInfo[ALNAuthModuleOIDCFailureCodeKey] isKindOfClass:[NSString class]]
                              ? error.userInfo[ALNAuthModuleOIDCFailureCodeKey]
                              : @"rejected";
  NSString *identifier = AMTrimmedString(provider.configuration[@"identifier"]);
  NSString *failureRedirect = self.runtime.providerFailureRedirects[identifier] ?: self.runtime.failureRedirect;
  if (!result && [failureRedirect length] > 0 && ![self shouldReturnJSON:ctx]) {
    // Codes and identifiers are restricted to URL-safe characters.
    NSString *separator = [failureRedirect rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
    [self redirectTo:[NSString stringWithFormat:@"%@%@error=%@&provider=%@", failureRedirect, separator,
                                                failureCode, identifier]
              status:302];
    return nil;
  }
  if (!result && [error.domain isEqual:ALNAuthModuleOIDCErrorDomain] &&
      error.code == ALNAuthModuleOIDCErrorAdmissionDenied) {
    NSString *message = [self clientMessageForError:error fallback:@"This account is not permitted to sign in."];
    if ([self shouldReturnJSON:ctx]) {
      [self setStatus:403];
      return @{ @"status": @"error", @"code": @"admission_denied", @"message": message };
    }
    // Show the message on the stock login page rather than a bare error body.
    ctx.session[ALNAuthModuleProviderErrorSessionKey] = message;
    [ctx markSessionDirty];
    [self redirectTo:self.runtime.loginPath ?: @"/auth/login" status:302];
    return nil;
  }
  if (!result) {
    [self setStatus:401];
    return @{ @"status": @"error", @"code": failureCode, @"message": @"Provider login rejected" };
  }
  NSString *redirect = AMSafeReturnTo(state[@"return_to"]);
  if (!redirect.length) redirect = self.runtime.defaultRedirect;
  if ([self shouldReturnJSON:ctx]) return @{ @"status": @"ok", @"redirect_to": redirect,
      @"session": [self.runtime sessionPayloadForContext:ctx includeUser:NO error:NULL] };
  [self redirectTo:redirect status:302];
  return nil;
}

- (id)providerStubLogin:(ALNContext *)ctx {
  if (![self.runtime isProviderEnabled:@"stub"] || ![self.runtime isDevelopmentOrTestEnvironment]) {
    [self setStatus:404];
    return [self shouldReturnJSON:ctx] ? @{ @"status" : @"error", @"message" : @"Provider not found" } : nil;
  }
  NSString *baseURL = [self requestBaseURL:ctx];
  NSDictionary *providerConfiguration = [self.runtime stubProviderConfigurationForBaseURL:baseURL];
  NSString *state = AMRandomToken(12);
  NSString *nonce = AMRandomToken(12);
  NSString *returnTo = AMSafeReturnTo([self requestParameters][@"return_to"]);
  ctx.session[ALNAuthModuleProviderStateSessionKey] = @{
    @"state" : state ?: @"",
    @"nonce" : nonce ?: @"",
    @"issuedAt" : @([[NSDate date] timeIntervalSince1970]),
    @"return_to" : returnTo ?: @"",
  };
  [ctx markSessionDirty];
  NSString *authorizeURL = [NSString stringWithFormat:@"%@?state=%@", providerConfiguration[@"authorizationEndpoint"], state ?: @""];
  if ([self shouldReturnJSON:ctx]) {
    return @{
      @"status" : @"ok",
      @"provider" : providerConfiguration,
      @"authorize_url" : authorizeURL ?: @"",
      @"return_to" : returnTo ?: @"",
    };
  }
  [self redirectTo:authorizeURL status:302];
  return nil;
}

- (id)providerStubAuthorize:(ALNContext *)ctx {
  if (![self.runtime isProviderEnabled:@"stub"] || ![self.runtime isDevelopmentOrTestEnvironment]) {
    [self setStatus:404];
    return [self shouldReturnJSON:ctx] ? @{ @"status" : @"error", @"message" : @"Provider not found" } : nil;
  }
  NSString *state = AMTrimmedString([self requestParameters][@"state"]);
  NSString *callbackURL = [NSString stringWithFormat:@"%@?code=stub-code&state=%@", self.runtime.providerStubCallbackPath, state ?: @""];
  if ([self shouldReturnJSON:ctx]) {
    return @{
      @"status" : @"ok",
      @"callback_url" : callbackURL ?: @"",
    };
  }
  [self redirectTo:callbackURL status:302];
  return nil;
}

- (id)providerStubCallback:(ALNContext *)ctx {
  if (![self.runtime isProviderEnabled:@"stub"] || ![self.runtime isDevelopmentOrTestEnvironment]) {
    [self setStatus:404];
    return [self shouldReturnJSON:ctx] ? @{ @"status" : @"error", @"message" : @"Provider not found" } : nil;
  }
  NSDictionary *callbackState = [ctx.session[ALNAuthModuleProviderStateSessionKey] isKindOfClass:[NSDictionary class]]
                                    ? ctx.session[ALNAuthModuleProviderStateSessionKey]
                                    : @{};
  [ctx.session removeObjectForKey:ALNAuthModuleProviderStateSessionKey];
  [ctx markSessionDirty];

  NSString *baseURL = [self requestBaseURL:ctx];
  NSDictionary *providerConfiguration = [self.runtime stubProviderConfigurationForBaseURL:baseURL];
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSString *providerSubject = [NSString stringWithFormat:@"stub:%@", self.runtime.stubProviderEmail ?: @"user"];
  NSDictionary *claims = @{
    @"iss" : providerConfiguration[@"issuer"] ?: @"",
    @"aud" : providerConfiguration[@"clientID"] ?: @"",
    @"sub" : providerSubject,
    @"email" : self.runtime.stubProviderEmail ?: @"stub-user@example.test",
    @"email_verified" : @YES,
    @"name" : self.runtime.stubProviderDisplayName ?: @"Stub Provider User",
    @"nonce" : callbackState[@"nonce"] ?: @"",
    @"iat" : @((NSInteger)now),
    @"exp" : @((NSInteger)(now + 300)),
    @"auth_time" : @((NSInteger)now),
    @"amr" : @[ @"federated" ],
  };
  NSString *idToken = AMStubHS256JWT(claims, providerConfiguration[@"clientSecret"]);
  NSError *error = nil;
  NSDictionary *result = [ALNAuthProviderSessionBridge completeLoginWithCallbackParameters:[self requestParameters]
                                                                             callbackState:callbackState
                                                                             tokenResponse:@{
                                                                               @"id_token" : idToken ?: @"",
                                                                               @"access_token" : @"stub-access-token",
                                                                               @"token_type" : @"Bearer",
                                                                             }
                                                                          userInfoResponse:nil
                                                                     providerConfiguration:providerConfiguration
                                                                              jwksDocument:nil
                                                                                  resolver:self.runtime
                                                                                   context:ctx
                                                                                     error:&error];
  if (result == nil) {
    [self setStatus:422];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      return @{ @"status" : @"error", @"message" : [self clientMessageForError:error fallback:@"Provider login failed"] };
    }
    [self renderAuthPageIdentifier:@"provider_result"
                             title:@"Provider Login"
                           message:[self clientMessageForError:error fallback:@"Provider login failed"]
                            errors:nil
                          formData:nil
                          extraCtx:@{
                            @"resultTitle" : @"Provider login failed",
                            @"authResultActions" : @[ @{
                              @"label" : @"Back to sign in",
                              @"href" : self.runtime.loginPath ?: @"/auth/login",
                            } ],
                          }
                             error:NULL];
    return nil;
  }
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:NULL] ?: @{};
  NSString *redirectTarget = [self.runtime postLoginRedirectForContext:ctx
                                                                  user:user
                                                       defaultRedirect:AMSafeReturnTo(callbackState[@"return_to"])];
  if ([self shouldReturnJSON:ctx]) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:result[@"session"] ?: @{}];
    payload[@"normalized_identity"] = result[@"normalizedIdentity"] ?: @{};
    payload[@"redirect_to"] = redirectTarget ?: self.runtime.defaultRedirect;
    return payload;
  }
  [self redirectTo:redirectTarget status:302];
  return nil;
}

@end

@implementation ALNAuthModule

- (NSString *)moduleIdentifier {
  return @"auth";
}

- (BOOL)registerWithApplication:(ALNApplication *)application
                          error:(NSError **)error {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }
  ALNAuthModuleInstallSessionRefresh(application);

  if (![runtime isHeadlessUIMode] &&
      ![[runtime.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    [runtime mountUIAssetsForApplication:application];
  }
  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.loginPath
                                name:@"auth_login_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"loginForm"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:runtime.loginPath
                                name:@"auth_login"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"login"];
  }
  [application registerRouteMethod:@"POST"
                              path:runtime.logoutPath
                              name:@"auth_logout"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"logout"];
  [application registerRouteMethod:@"POST"
                              path:runtime.logoutAllPath
                              name:@"auth_logout_all"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"logoutAll"];
  if (![runtime isHeadlessUIMode] && runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"GET"
                                  path:runtime.registerPath
                                  name:@"auth_register_form"
                       controllerClass:[ALNAuthModuleController class]
                                 action:@"registerForm"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:runtime.registerPath
                                name:@"auth_register"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"register"];
  }
  [application registerRouteMethod:@"GET"
                              path:runtime.sessionPath
                              name:@"auth_session"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"sessionState"];
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"GET"
                                path:runtime.verifyPath
                                name:@"auth_verify"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"verifyEmail"];
  }
  if (![runtime isHeadlessUIMode] && runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"GET"
                                  path:runtime.forgotPasswordPath
                                  name:@"auth_password_forgot_form"
                       controllerClass:[ALNAuthModuleController class]
                                 action:@"forgotPasswordForm"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:runtime.forgotPasswordPath
                                name:@"auth_password_forgot"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"forgotPassword"];
  }
  if (![runtime isHeadlessUIMode] && runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"GET"
                                  path:runtime.resetPasswordPath
                                  name:@"auth_password_reset_form"
                       controllerClass:[ALNAuthModuleController class]
                                 action:@"resetPasswordForm"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:runtime.resetPasswordPath
                                name:@"auth_password_reset"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"resetPassword"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:runtime.changePasswordPath
                                name:@"auth_password_change"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"changePassword"];
  }
  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.mfaManagePath
                                name:@"auth_mfa_manage"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"mfaManage"];
    if (runtime.smsEnabled) {
      [application registerRouteMethod:@"GET"
                                  path:runtime.smsPath
                                  name:@"auth_sms_form"
                       controllerClass:[ALNAuthModuleController class]
                                 action:@"smsForm"];
    }
    [application registerRouteMethod:@"GET"
                                path:runtime.totpPath
                                name:@"auth_totp_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"totpForm"];
  }
  if (runtime.smsEnabled) {
    [application registerRouteMethod:@"POST"
                                path:runtime.smsStartPath
                                name:@"auth_sms_start"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsStart"];
    [application registerRouteMethod:@"POST"
                                path:runtime.smsVerifyPath
                                name:@"auth_sms_verify"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsVerify"];
    [application registerRouteMethod:@"POST"
                                path:runtime.smsResendPath
                                name:@"auth_sms_resend"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsResend"];
    [application registerRouteMethod:@"POST"
                                path:runtime.smsRemovePath
                                name:@"auth_sms_remove"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsRemove"];
  }
  [application registerRouteMethod:@"POST"
                              path:runtime.totpVerifyPath
                              name:@"auth_totp_verify"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"totpVerify"];
  if ([runtime isProviderEnabled:@"stub"]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.providerStubLoginPath
                                name:@"auth_provider_stub_login"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"providerStubLogin"];
    [application registerRouteMethod:@"GET"
                                path:runtime.providerStubAuthorizePath
                                name:@"auth_provider_stub_authorize"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"providerStubAuthorize"];
    [application registerRouteMethod:@"GET"
                                path:runtime.providerStubCallbackPath
                                name:@"auth_provider_stub_callback"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"providerStubCallback"];
  }
  for (NSString *identifier in [[runtime.oidcProviders allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    for (NSString *prefix in @[ runtime.prefix, runtime.apiPrefix ]) {
      for (NSString *suffix in @[ @"login", @"callback" ]) {
        NSString *path = AMPathJoin(prefix, [NSString stringWithFormat:@"provider/%@/%@", identifier, suffix]);
        NSString *name = [NSString stringWithFormat:@"auth_%@provider_%@_%@",
                          [prefix isEqual:runtime.apiPrefix] ? @"api_" : @"", identifier, suffix];
        [application registerRouteMethod:@"GET" path:path name:name controllerClass:[ALNAuthModuleController class]
                                  action:[suffix isEqual:@"login"] ? @"providerOIDCLogin" : @"providerOIDCCallback"];
      }
    }
  }
  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/session"
                              name:@"auth_api_session"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"sessionState"];
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:@"/login"
                                name:@"auth_api_login"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"login"];
  }
  [application registerRouteMethod:@"POST"
                              path:@"/logout"
                              name:@"auth_api_logout"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"logout"];
  [application registerRouteMethod:@"POST"
                              path:@"/logout/all"
                              name:@"auth_api_logout_all"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"logoutAll"];
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:@"/register"
                                name:@"auth_api_register"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"register"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"GET"
                                path:@"/verify"
                                name:@"auth_api_verify"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"verifyEmail"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:@"/password/forgot"
                                name:@"auth_api_password_forgot"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"forgotPassword"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"GET"
                                path:@"/password/reset"
                                name:@"auth_api_password_reset_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"resetPasswordForm"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:@"/password/reset"
                                name:@"auth_api_password_reset"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"resetPassword"];
  }
  if (runtime.localPasswordEnabled) {
    [application registerRouteMethod:@"POST"
                                path:@"/password/change"
                                name:@"auth_api_password_change"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"changePassword"];
  }
  [application registerRouteMethod:@"GET"
                              path:@"/mfa"
                              name:@"auth_api_mfa"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"mfaManage"];
  if (runtime.smsEnabled) {
    [application registerRouteMethod:@"GET"
                                path:@"/mfa/sms"
                                name:@"auth_api_sms"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsForm"];
    [application registerRouteMethod:@"POST"
                                path:@"/mfa/sms/start"
                                name:@"auth_api_sms_start"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsStart"];
    [application registerRouteMethod:@"POST"
                                path:@"/mfa/sms/verify"
                                name:@"auth_api_sms_verify"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsVerify"];
    [application registerRouteMethod:@"POST"
                                path:@"/mfa/sms/resend"
                                name:@"auth_api_sms_resend"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsResend"];
    [application registerRouteMethod:@"POST"
                                path:@"/mfa/sms/remove"
                                name:@"auth_api_sms_remove"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"smsRemove"];
  }
  [application registerRouteMethod:@"GET"
                              path:@"/mfa/totp"
                              name:@"auth_api_totp"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"totpForm"];
  [application registerRouteMethod:@"POST"
                              path:@"/mfa/totp/verify"
                              name:@"auth_api_totp_verify"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"totpVerify"];
  if ([runtime isProviderEnabled:@"stub"]) {
    [application registerRouteMethod:@"GET"
                                path:@"/provider/stub/login"
                                name:@"auth_api_provider_stub_login"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"providerStubLogin"];
    [application registerRouteMethod:@"GET"
                                path:@"/provider/stub/authorize"
                                name:@"auth_api_provider_stub_authorize"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"providerStubAuthorize"];
    [application registerRouteMethod:@"GET"
                                path:@"/provider/stub/callback"
                                name:@"auth_api_provider_stub_callback"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"providerStubCallback"];
  }
  [application endRouteGroup];

  NSError *routeError = nil;
  NSMutableDictionary *apiRouteSchemas = [NSMutableDictionary dictionaryWithDictionary:@{
    @"auth_api_session" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"auth_api_login" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"email" : @{ @"type" : @"string", @"source" : @"body" },
          @"password" : @{ @"type" : @"string", @"source" : @"body" },
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"email", @"password" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_logout" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"auth_api_logout_all" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"auth_api_register" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"email" : @{ @"type" : @"string", @"source" : @"body" },
          @"display_name" : @{ @"type" : @"string", @"source" : @"body" },
          @"password" : @{ @"type" : @"string", @"source" : @"body" },
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"email", @"password" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_verify" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"token" : @{ @"type" : @"string", @"source" : @"query" },
        },
        @"required" : @[ @"token" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_password_forgot" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"email" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"email" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_password_reset" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"token" : @{ @"type" : @"string", @"source" : @"body" },
          @"password" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"token", @"password" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_password_reset_form" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"token" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_password_change" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"current_password" : @{ @"type" : @"string", @"source" : @"body" },
          @"new_password" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"current_password", @"new_password" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"auth_api_mfa" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"auth_api_totp" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"auth_api_totp_verify" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"code" : @{ @"type" : @"string", @"source" : @"body" },
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"code" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
  }];
  if (runtime.smsEnabled) {
    apiRouteSchemas[@"auth_api_sms"] = @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } };
    apiRouteSchemas[@"auth_api_sms_start"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"phone_number" : @{ @"type" : @"string", @"source" : @"body" },
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"phone_number" ],
      },
      @"response" : @{ @"type" : @"object" },
    };
    apiRouteSchemas[@"auth_api_sms_verify"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"code" : @{ @"type" : @"string", @"source" : @"body" },
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"code" ],
      },
      @"response" : @{ @"type" : @"object" },
    };
    apiRouteSchemas[@"auth_api_sms_resend"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
    apiRouteSchemas[@"auth_api_sms_remove"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"return_to" : @{ @"type" : @"string", @"source" : @"body" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
  }
  if ([runtime isProviderEnabled:@"stub"]) {
    apiRouteSchemas[@"auth_api_provider_stub_login"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"return_to" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
    apiRouteSchemas[@"auth_api_provider_stub_authorize"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"state" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
    apiRouteSchemas[@"auth_api_provider_stub_callback"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"code" : @{ @"type" : @"string", @"source" : @"query" },
          @"state" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
  }
  if (!runtime.localPasswordEnabled) {
    [apiRouteSchemas removeObjectsForKeys:@[ @"auth_api_login", @"auth_api_register", @"auth_api_verify",
       @"auth_api_password_forgot", @"auth_api_password_reset_form", @"auth_api_password_reset", @"auth_api_password_change" ]];
  }
  for (NSString *identifier in runtime.oidcProviders) {
    for (NSString *suffix in @[ @"login", @"callback" ]) {
      apiRouteSchemas[[NSString stringWithFormat:@"auth_api_provider_%@_%@", identifier, suffix]] =
        @{ @"request": [NSNull null], @"response": @{ @"type": @"object" } };
    }
  }
  for (NSString *routeName in [apiRouteSchemas allKeys]) {
    NSDictionary *schema = apiRouteSchemas[routeName];
    NSDictionary *requestSchema = [schema[@"request"] isKindOfClass:[NSDictionary class]] ? schema[@"request"] : nil;
    NSDictionary *responseSchema = [schema[@"response"] isKindOfClass:[NSDictionary class]] ? schema[@"response"] : nil;
    if (![application configureRouteNamed:routeName
                            requestSchema:requestSchema
                           responseSchema:responseSchema
                                  summary:@"Auth API route"
                              operationID:routeName
                                     tags:@[ @"auth" ]
                            requiredScopes:nil
                             requiredRoles:nil
                           includeInOpenAPI:YES
                                     error:&routeError]) {
      if (error != NULL) {
        *error = routeError;
      }
      return NO;
    }
  }
  return YES;
}

@end
