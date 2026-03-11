#import "ALNAuthModule.h"

#import "ALNApplication.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNJSONSerialization.h"
#import "ALNPg.h"
#import "ALNPasswordHash.h"
#import "ALNRecoveryCodes.h"
#import "ALNSecurityPrimitives.h"
#import "ALNServices.h"
#import "ALNTOTP.h"

#include <ctype.h>

NSString *const ALNAuthModuleErrorDomain = @"Arlen.Modules.Auth.Error";

static NSString *const ALNAuthModuleProviderStateSessionKey = @"aln.auth_module.stub_provider_state";
static NSString *const ALNAuthModuleVerificationNoticeSessionKey = @"aln.auth_module.notice.verify";
static NSString *const ALNAuthModuleResetNoticeSessionKey = @"aln.auth_module.notice.reset";

static NSString *AMTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *AMLowerTrimmedString(id value) {
  return [[AMTrimmedString(value) lowercaseString] copy];
}

static NSError *AMError(ALNAuthModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"auth module error";
  return [NSError errorWithDomain:ALNAuthModuleErrorDomain code:code userInfo:userInfo];
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
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
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

static BOOL AMBoolFromDatabaseValue(id value) {
  NSString *string = AMLowerTrimmedString(value);
  return [string isEqualToString:@"t"] || [string isEqualToString:@"true"] || [string isEqualToString:@"1"] ||
         [string isEqualToString:@"yes"];
}

static NSString *AMRandomToken(NSUInteger byteCount) {
  NSData *random = ALNSecureRandomData(byteCount);
  return ALNLowercaseHexStringFromData(random) ?: @"";
}

static NSString *AMQueryDecodeComponent(NSString *component) {
  NSString *withSpaces = [[component ?: @"" stringByReplacingOccurrencesOfString:@"+" withString:@" "]
      stringByRemovingPercentEncoding];
  return withSpaces ?: @"";
}

static NSDictionary *AMFormParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
  if ([raw length] == 0) {
    return @{};
  }
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSString *pair in [raw componentsSeparatedByString:@"&"]) {
    if ([pair length] == 0) {
      continue;
    }
    NSRange separator = [pair rangeOfString:@"="];
    NSString *name = nil;
    NSString *value = nil;
    if (separator.location == NSNotFound) {
      name = pair;
      value = @"";
    } else {
      name = [pair substringToIndex:separator.location];
      value = [pair substringFromIndex:(separator.location + 1)];
    }
    NSString *decodedName = AMQueryDecodeComponent(name);
    if ([decodedName length] == 0) {
      continue;
    }
    parameters[decodedName] = AMQueryDecodeComponent(value);
  }
  return parameters;
}

static NSDictionary *AMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
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
  if ([normalized isEqualToString:@"totp_challenge"]) {
    return @"modules/auth/mfa/totp";
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
  if ([normalized isEqualToString:@"totp_challenge"]) {
    return [NSString stringWithFormat:@"%@/mfa/totp", normalizedPrefix];
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
  if ([normalized isEqualToString:@"totp_challenge"]) {
    return @"modules/auth/partials/bodies/totp_challenge_body";
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
                                              : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"totp_challenge"]
                                                    ? @"totp_challenge_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"result"] ? @"result_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"verify_result"] ? @"result_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"provider_result"] ? @"result_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"register"] ? @"register_body"
                                                    : [AMNormalizedTemplateIdentifier(pageIdentifier) isEqualToString:@"login"] ? @"login_body"
                                                    : @"result_body"];
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

@interface ALNAuthModuleRuntime ()

@property(nonatomic, strong) ALNPg *database;
@property(nonatomic, strong) id<ALNMailAdapter> mailAdapter;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSString *loginPath;
@property(nonatomic, copy, readwrite) NSString *registerPath;
@property(nonatomic, copy, readwrite) NSString *logoutPath;
@property(nonatomic, copy, readwrite) NSString *sessionPath;
@property(nonatomic, copy, readwrite) NSString *verifyPath;
@property(nonatomic, copy, readwrite) NSString *forgotPasswordPath;
@property(nonatomic, copy, readwrite) NSString *resetPasswordPath;
@property(nonatomic, copy, readwrite) NSString *changePasswordPath;
@property(nonatomic, copy, readwrite) NSString *totpPath;
@property(nonatomic, copy, readwrite) NSString *totpVerifyPath;
@property(nonatomic, copy, readwrite) NSString *providerStubLoginPath;
@property(nonatomic, copy, readwrite) NSString *providerStubAuthorizePath;
@property(nonatomic, copy, readwrite) NSString *providerStubCallbackPath;
@property(nonatomic, copy, readwrite) NSString *defaultRedirect;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *loginProviders;
@property(nonatomic, copy, readwrite) NSString *uiMode;
@property(nonatomic, copy, readwrite) NSString *layoutTemplate;
@property(nonatomic, copy, readwrite) NSString *generatedPagePrefix;
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
- (BOOL)consumeVerificationToken:(NSString *)token
                            user:(NSDictionary *_Nullable *_Nullable)user
                           error:(NSError **)error;
- (BOOL)consumePasswordResetToken:(NSString *)token
                         password:(NSString *)password
                             user:(NSDictionary *_Nullable *_Nullable)user
                            error:(NSError **)error;
- (nullable NSDictionary *)totpEnrollmentForUserID:(NSString *)userID
                                             error:(NSError **)error;
- (nullable NSDictionary *)provisioningPayloadForUser:(NSDictionary *)user
                                                error:(NSError **)error;
- (nullable NSDictionary *)verifyTOTPCode:(NSString *)code
                                      user:(NSDictionary *)user
                                   context:(ALNContext *)context
                                     error:(NSError **)error;
- (NSDictionary *)stubProviderConfigurationForBaseURL:(NSString *)baseURL;

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

@implementation ALNAuthModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNAuthModuleRuntime *runtime = nil;
  @synchronized(self) {
    if (runtime == nil) {
      runtime = [[ALNAuthModuleRuntime alloc] init];
    }
  }
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
    _sessionPath = @"/auth/session";
    _verifyPath = @"/auth/verify";
    _forgotPasswordPath = @"/auth/password/forgot";
    _resetPasswordPath = @"/auth/password/reset";
    _changePasswordPath = @"/auth/password/change";
    _totpPath = @"/auth/mfa/totp";
    _totpVerifyPath = @"/auth/mfa/totp/verify";
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
    _partialTemplateOverrides = @{};
    _stubProviderEmail = @"stub-user@example.test";
    _stubProviderDisplayName = @"Stub Provider User";
    _stubProviderSharedSecret = @"auth-module-stub-provider-secret-0123456789abcdef";
    _bootstrapAdminEmails = @[];
  }
  return self;
}

- (BOOL)configureHooksWithModuleConfig:(NSDictionary *)moduleConfig
                                 error:(NSError **)error {
  self.moduleConfig = [moduleConfig isKindOfClass:[NSDictionary class]] ? moduleConfig : @{};
  NSDictionary *paths = [self.moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"paths"] : @{};
  self.prefix = AMPathJoin(AMTrimmedString(paths[@"prefix"]), @"");
  self.apiPrefix = AMConfiguredPath(self.moduleConfig, @"apiPrefix", @"api");
  self.loginPath = AMConfiguredPath(self.moduleConfig, @"login", @"login");
  self.registerPath = AMConfiguredPath(self.moduleConfig, @"register", @"register");
  self.logoutPath = AMConfiguredPath(self.moduleConfig, @"logout", @"logout");
  self.sessionPath = AMConfiguredPath(self.moduleConfig, @"session", @"session");
  self.verifyPath = AMConfiguredPath(self.moduleConfig, @"verify", @"verify");
  self.forgotPasswordPath = AMConfiguredPath(self.moduleConfig, @"forgotPassword", @"password/forgot");
  self.resetPasswordPath = AMConfiguredPath(self.moduleConfig, @"resetPassword", @"password/reset");
  self.changePasswordPath = AMConfiguredPath(self.moduleConfig, @"changePassword", @"password/change");
  self.totpPath = AMConfiguredPath(self.moduleConfig, @"totp", @"mfa/totp");
  self.totpVerifyPath = AMConfiguredPath(self.moduleConfig, @"totpVerify", @"mfa/totp/verify");
  self.providerStubLoginPath = AMConfiguredPath(self.moduleConfig, @"providerStubLogin", @"provider/stub/login");
  self.providerStubAuthorizePath =
      AMConfiguredPath(self.moduleConfig, @"providerStubAuthorize", @"provider/stub/authorize");
  self.providerStubCallbackPath =
      AMConfiguredPath(self.moduleConfig, @"providerStubCallback", @"provider/stub/callback");
  self.defaultRedirect = AMTrimmedString(self.moduleConfig[@"defaultRedirect"]);
  if ([self.defaultRedirect length] == 0) {
    self.defaultRedirect = @"/";
  }
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

  NSDictionary *providers = [self.moduleConfig[@"providers"] isKindOfClass:[NSDictionary class]]
                                ? self.moduleConfig[@"providers"]
                                : @{};
  NSDictionary *stubProvider = [providers[@"stub"] isKindOfClass:[NSDictionary class]] ? providers[@"stub"] : @{};
  BOOL stubEnabled = AMConfigBool(stubProvider[@"enabled"], YES);
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

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  NSDictionary *moduleConfig = [application.config[@"authModule"] isKindOfClass:[NSDictionary class]]
                                   ? application.config[@"authModule"]
                                   : @{};
  if (![self configureHooksWithModuleConfig:moduleConfig error:error]) {
    return NO;
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
  self.database = [[ALNPg alloc] initWithConnectionString:connectionString maxConnections:4 error:&dbError];
  if (self.database == nil) {
    if (error != NULL) {
      *error = dbError ?: AMError(ALNAuthModuleErrorDatabaseUnavailable, @"failed to initialize auth database adapter", nil);
    }
    return NO;
  }
  self.mailAdapter = application.mailAdapter;
  return YES;
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
  NSString *fallback = ([AMTrimmedString(defaultRedirect) length] > 0) ? AMTrimmedString(defaultRedirect) : self.defaultRedirect;
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
  if ([self userForEmail:normalizedEmail error:error] != nil) {
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
  if ([self userForEmail:normalizedEmail error:error] != nil) {
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

- (NSDictionary *)authenticateLocalEmail:(NSString *)email
                                password:(NSString *)password
                                   error:(NSError **)error {
  NSString *normalizedEmail = AMLowerTrimmedString(email);
  NSDictionary *row = [[self.database executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                                                 "COALESCE(u.display_name, '') AS display_name, "
                                                 "COALESCE(u.roles_json, '[]') AS roles_json, "
                                                 "CASE WHEN u.email_verified_at IS NULL THEN '' ELSE u.email_verified_at::text END AS email_verified_at, "
                                                 "c.password_hash "
                                                 "FROM auth_users u "
                                                 "JOIN auth_local_credentials c ON c.user_id = u.id "
                                                 "WHERE lower(u.email) = $1 LIMIT 1"
                                       parameters:@[ normalizedEmail ]
                                            error:error] firstObject];
  NSString *encodedHash = AMTrimmedString(row[@"password_hash"]);
  if ([encodedHash length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorAuthenticationFailed, @"Invalid email or password", nil);
    }
    return nil;
  }
  NSError *verifyError = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordString:(password ?: @"")
                                     againstEncodedHash:encodedHash
                                                  error:&verifyError];
  if (!verified) {
    if (error != NULL) {
      *error = verifyError ?: AMError(ALNAuthModuleErrorAuthenticationFailed, @"Invalid email or password", nil);
    }
    return nil;
  }
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
                                         parameters:@[ userID ?: @"", token ?: @"" ]
                                              error:error];
  return (result >= 0) ? token : nil;
}

- (NSString *)issuePasswordResetTokenForUserID:(NSString *)userID
                                         error:(NSError **)error {
  NSString *token = AMRandomToken(24);
  NSInteger result = [self.database executeCommand:@"INSERT INTO auth_password_reset_tokens "
                                               "(user_id, token, expires_at, created_at) "
                                               "VALUES ($1, $2, NOW() + INTERVAL '30 minutes', NOW())"
                                         parameters:@[ userID ?: @"", token ?: @"" ]
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

- (BOOL)consumeVerificationToken:(NSString *)token
                            user:(NSDictionary **)user
                           error:(NSError **)error {
  NSString *normalizedToken = AMTrimmedString(token);
  NSDictionary *row = [[self.database executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                                                 "COALESCE(u.display_name, '') AS display_name, "
                                                 "COALESCE(u.roles_json, '[]') AS roles_json, '' AS email_verified_at "
                                                 "FROM auth_verification_tokens t "
                                                 "JOIN auth_users u ON u.id = t.user_id "
                                                 "WHERE t.token = $1 AND t.consumed_at IS NULL AND t.expires_at > NOW() "
                                                 "ORDER BY t.id DESC LIMIT 1"
                                       parameters:@[ normalizedToken ]
                                            error:error] firstObject];
  NSString *userID = AMTrimmedString(row[@"id"]);
  if ([userID length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"Verification token is invalid or expired", nil);
    }
    return NO;
  }
  BOOL ok = [self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    NSInteger marked = [connection executeCommand:@"UPDATE auth_verification_tokens SET consumed_at = NOW() "
                                              "WHERE token = $1 AND consumed_at IS NULL"
                                        parameters:@[ normalizedToken ]
                                             error:txError];
    if (marked < 0) {
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
  NSDictionary *row = [[self.database executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                                                 "COALESCE(u.display_name, '') AS display_name, "
                                                 "COALESCE(u.roles_json, '[]') AS roles_json, "
                                                 "CASE WHEN u.email_verified_at IS NULL THEN '' ELSE u.email_verified_at::text END AS email_verified_at "
                                                 "FROM auth_password_reset_tokens t "
                                                 "JOIN auth_users u ON u.id = t.user_id "
                                                 "WHERE t.token = $1 AND t.consumed_at IS NULL AND t.expires_at > NOW() "
                                                 "ORDER BY t.id DESC LIMIT 1"
                                       parameters:@[ normalizedToken ]
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
    NSInteger marked = [connection executeCommand:@"UPDATE auth_password_reset_tokens SET consumed_at = NOW() "
                                              "WHERE token = $1 AND consumed_at IS NULL"
                                        parameters:@[ normalizedToken ]
                                             error:txError];
    if (marked < 0) {
      return NO;
    }
    NSInteger updated = [connection executeCommand:@"INSERT INTO auth_local_credentials "
                                               "(user_id, password_hash, created_at, updated_at) "
                                               "VALUES ($1, $2, NOW(), NOW()) "
                                               "ON CONFLICT (user_id) DO UPDATE "
                                               "SET password_hash = EXCLUDED.password_hash, updated_at = NOW()"
                                         parameters:@[ userID, encodedHash ]
                                              error:txError];
    return (updated >= 0);
  } error:error];
  if (ok && user != NULL) {
    *user = [self userForSubject:AMTrimmedString(row[@"subject"]) error:NULL];
  }
  return ok;
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

- (NSDictionary *)provisioningPayloadForUser:(NSDictionary *)user
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
  }
  NSString *uri = [ALNTOTP provisioningURIForSecret:secret
                                        accountName:AMTrimmedString(user[@"email"])
                                             issuer:@"Arlen Auth Module"
                                              error:error];
  if ([uri length] == 0) {
    return nil;
  }
  return @{
    @"secret" : secret,
    @"otpauth_uri" : uri,
    @"verified" : @([AMTrimmedString(enrollment[@"verified_at"]) length] > 0 || AMBoolFromDatabaseValue(enrollment[@"enabled"])),
  };
}

- (NSDictionary *)verifyTOTPCode:(NSString *)code
                             user:(NSDictionary *)user
                          context:(ALNContext *)context
                            error:(NSError **)error {
  NSDictionary *enrollment = [self totpEnrollmentForUserID:AMTrimmedString(user[@"id"]) error:error];
  NSString *secret = AMTrimmedString(enrollment[@"secret"]);
  if ([secret length] == 0) {
    if (error != NULL) {
      *error = AMError(ALNAuthModuleErrorNotFound, @"No TOTP enrollment is available", nil);
    }
    return nil;
  }
  BOOL verified = [ALNTOTP verifyCode:(code ?: @"")
                               secret:secret
                               atDate:[NSDate date]
                               digits:6
                               period:30
                 allowedPastIntervals:1
               allowedFutureIntervals:1
                                error:error];
  if (!verified) {
    return nil;
  }

  NSArray *plainRecoveryCodes = nil;
  BOOL enrollmentVerified = ([AMTrimmedString(enrollment[@"verified_at"]) length] > 0 || AMBoolFromDatabaseValue(enrollment[@"enabled"]));
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

  if (![ALNAuthSession elevateAuthenticatedSessionForMethod:@"totp"
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
  if (includeUser && [subject length] > 0) {
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
    NSString *resolvedBaseURL = AMTrimmedString(baseURL);
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
    bodyParameters = AMFormParametersFromBody(self.context.request.body);
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
  if ([[self.runtime.uiMode lowercaseString] isEqualToString:@"generated-app-ui"]) {
    return [NSString stringWithFormat:@"/%@/auth.css", self.runtime.generatedPagePrefix ?: @"auth"];
  }
  return @"/modules/auth/auth.css";
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
  context[@"authTOTPPath"] = self.runtime.totpPath ?: @"/auth/mfa/totp";
  context[@"authProviders"] = self.runtime.loginProviders ?: @[];
  context[@"authUIMode"] = self.runtime.uiMode ?: @"module-ui";
  context[@"authStylesheetPath"] = [self stylesheetPathForRuntime];
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
  if ([extraCtx isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extraCtx];
  }
  return [self.runtime uiContextForPage:normalizedIdentifier defaultContext:context context:self.context];
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

- (NSArray *)errorEntriesForError:(NSError *)error
                            field:(NSString *)field {
  if (error == nil) {
    return @[];
  }
  return @[ @{
    @"field" : field ?: @"",
    @"message" : error.localizedDescription ?: @"Request failed",
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
        @"value" : AMTrimmedString(parameters[@"return_to"]),
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
  BOOL rendered = [self renderAuthPageIdentifier:@"login"
                                           title:@"Sign In"
                                         message:AMTrimmedString(ctx.session[ALNAuthModuleVerificationNoticeSessionKey])
                                          errors:nil
                                        formData:@{ @"return_to" : AMTrimmedString(parameters[@"return_to"]) }
                                        extraCtx:extraCtx
                                           error:NULL];
  [ctx.session removeObjectForKey:ALNAuthModuleVerificationNoticeSessionKey];
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
  NSString *returnTo = AMTrimmedString(parameters[@"return_to"]);
  NSError *error = nil;
  NSDictionary *user = [self.runtime authenticateLocalEmail:email password:password error:&error];
  if (user == nil) {
    [self setStatus:401];
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
    return @{ @"status" : @"error", @"message" : error.localizedDescription ?: @"Failed to create session" };
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
  (void)ctx;
  [self clearAuthenticatedSession];
  if ([self shouldPreferJSONForHeadlessRequest:self.context]) {
    return @{ @"status" : @"ok" };
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
                                        formData:@{ @"return_to" : AMTrimmedString(parameters[@"return_to"]) }
                                        extraCtx:@{
                                          @"authFormDescriptor" : @{
                                            @"action" : self.runtime.registerPath ?: @"/auth/register",
                                            @"method" : @"post",
                                            @"submitLabel" : @"Create Account",
                                            @"hidden" : @[ @{
                                              @"name" : @"return_to",
                                              @"value" : AMTrimmedString(parameters[@"return_to"]),
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
  NSString *returnTo = AMTrimmedString(parameters[@"return_to"]);
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

  NSString *verificationToken = [self.runtime issueVerificationTokenForUserID:AMTrimmedString(user[@"id"]) error:&error];
  if ([verificationToken length] > 0) {
    (void)[self.runtime sendNotificationEvent:@"email_verification"
                                         user:user
                                        token:verificationToken
                                      baseURL:[self requestBaseURL:ctx]
                                        error:NULL];
  }
  NSDictionary *session = [self.runtime startSessionForUser:user provider:@"local" methods:@[ @"pwd" ] context:ctx error:&error];
  if (session == nil) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : error.localizedDescription ?: @"Failed to create session" };
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
  NSString *message = ok ? @"Your email address has been verified." : (error.localizedDescription ?: @"Verification failed.");
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
  NSDictionary *user = [self.runtime userForEmail:email error:NULL];
  if (user != nil) {
    NSError *error = nil;
    NSString *token = [self.runtime issuePasswordResetTokenForUserID:AMTrimmedString(user[@"id"]) error:&error];
    if ([token length] > 0) {
      (void)[self.runtime sendNotificationEvent:@"password_reset"
                                           user:user
                                          token:token
                                        baseURL:[self requestBaseURL:ctx]
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
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:NULL];
  if (user == nil) {
    [self setStatus:401];
    return @{ @"status" : @"error", @"message" : @"Authentication required" };
  }
  NSDictionary *parameters = [self requestParameters];
  NSError *authError = nil;
  NSDictionary *authenticated = [self.runtime authenticateLocalEmail:user[@"email"] password:parameters[@"current_password"] error:&authError];
  if (authenticated == nil) {
    [self setStatus:401];
    return @{ @"status" : @"error", @"message" : authError.localizedDescription ?: @"Current password is invalid" };
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
    return @{ @"status" : @"error", @"message" : updateError.localizedDescription ?: @"Failed to hash password" };
  }
  NSInteger command = [self.runtime.database executeCommand:@"UPDATE auth_local_credentials "
                                                        "SET password_hash = $2, updated_at = NOW() WHERE user_id = $1"
                                                  parameters:@[ AMTrimmedString(user[@"id"]), encodedHash ]
                                                       error:&updateError];
  if (command < 0) {
    [self setStatus:500];
    return @{ @"status" : @"error", @"message" : updateError.localizedDescription ?: @"Failed to update password" };
  }
  return @{ @"status" : @"ok" };
}

- (id)totpForm:(ALNContext *)ctx {
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:NULL];
  if (user == nil) {
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      [self setStatus:401];
      return @{ @"status" : @"error", @"message" : @"Authentication required" };
    }
    [self redirectTo:[NSString stringWithFormat:@"%@?return_to=%@", self.runtime.loginPath, self.runtime.totpPath] status:302];
    return nil;
  }
  NSDictionary *payload = [self.runtime provisioningPayloadForUser:user error:NULL] ?: @{};
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return @{
      @"status" : @"ok",
      @"provisioning" : payload,
      @"session" : [self.runtime sessionPayloadForContext:ctx includeUser:YES error:NULL] ?: @{},
    };
  }
  [self renderAuthPageIdentifier:@"totp_challenge"
                           title:@"TOTP Security"
                         message:@"Use your authenticator app to complete step-up authentication."
                          errors:nil
                        formData:@{
                          @"return_to" : AMTrimmedString([self requestParameters][@"return_to"]),
                        }
                        extraCtx:@{
                          @"otpauthURI" : AMTrimmedString(payload[@"otpauth_uri"]),
                          @"totpVerified" : payload[@"verified"] ?: @NO,
                          @"authFormDescriptor" : @{
                            @"action" : self.runtime.totpVerifyPath ?: @"/auth/mfa/totp/verify",
                            @"method" : @"post",
                            @"submitLabel" : @"Verify TOTP",
                            @"hidden" : @[ @{
                              @"name" : @"return_to",
                              @"value" : AMTrimmedString([self requestParameters][@"return_to"]),
                            } ],
                            @"fields" : @[
                              @{
                                @"name" : @"code",
                                @"label" : @"TOTP Code",
                                @"type" : @"text",
                                @"autocomplete" : @"one-time-code",
                              },
                            ],
                          },
                        }
                           error:NULL];
  return nil;
}

- (id)totpVerify:(ALNContext *)ctx {
  NSDictionary *user = [self.runtime currentUserForContext:ctx error:NULL];
  if (user == nil) {
    [self setStatus:401];
    return @{ @"status" : @"error", @"message" : @"Authentication required" };
  }
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *payload = [self.runtime verifyTOTPCode:parameters[@"code"] user:user context:ctx error:&error];
  NSString *returnTo = AMTrimmedString(parameters[@"return_to"]);
  if (payload == nil) {
    [self setStatus:422];
    NSArray *errors = [self errorEntriesForError:error field:@"code"];
    if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
      return @{ @"status" : @"error", @"errors" : errors };
    }
    NSDictionary *provisioning = [self.runtime provisioningPayloadForUser:user error:NULL] ?: @{};
    [self renderAuthPageIdentifier:@"totp_challenge"
                             title:@"TOTP Security"
                           message:@""
                            errors:errors
                          formData:@{ @"return_to" : returnTo ?: @"" }
                          extraCtx:@{
                            @"otpauthURI" : AMTrimmedString(provisioning[@"otpauth_uri"]),
                            @"totpVerified" : provisioning[@"verified"] ?: @NO,
                            @"authFormDescriptor" : @{
                              @"action" : self.runtime.totpVerifyPath ?: @"/auth/mfa/totp/verify",
                              @"method" : @"post",
                              @"submitLabel" : @"Verify TOTP",
                              @"hidden" : @[ @{
                                @"name" : @"return_to",
                                @"value" : returnTo ?: @"",
                              } ],
                              @"fields" : @[
                                @{
                                  @"name" : @"code",
                                  @"label" : @"TOTP Code",
                                  @"type" : @"text",
                                  @"autocomplete" : @"one-time-code",
                                },
                              ],
                            },
                          }
                             error:NULL];
    return nil;
  }
  if ([self shouldPreferJSONForHeadlessRequest:ctx]) {
    return payload;
  }
  [self redirectTo:([returnTo length] > 0 ? returnTo : self.runtime.defaultRedirect) status:302];
  return nil;
}

- (id)providerStubLogin:(ALNContext *)ctx {
  if (![self.runtime isProviderEnabled:@"stub"]) {
    [self setStatus:404];
    return [self shouldReturnJSON:ctx] ? @{ @"status" : @"error", @"message" : @"Provider not found" } : nil;
  }
  NSString *baseURL = [self requestBaseURL:ctx];
  NSDictionary *providerConfiguration = [self.runtime stubProviderConfigurationForBaseURL:baseURL];
  NSString *state = AMRandomToken(12);
  NSString *nonce = AMRandomToken(12);
  NSString *returnTo = AMTrimmedString([self requestParameters][@"return_to"]);
  ctx.session[ALNAuthModuleProviderStateSessionKey] = @{
    @"state" : state ?: @"",
    @"nonce" : nonce ?: @"",
    @"issuedAt" : [NSDate date],
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
  if (![self.runtime isProviderEnabled:@"stub"]) {
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
  if (![self.runtime isProviderEnabled:@"stub"]) {
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
      return @{ @"status" : @"error", @"message" : error.localizedDescription ?: @"Provider login failed" };
    }
    [self renderAuthPageIdentifier:@"provider_result"
                             title:@"Provider Login"
                           message:error.localizedDescription ?: @"Provider login failed"
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
                                                       defaultRedirect:AMTrimmedString(callbackState[@"return_to"])];
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

  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.loginPath
                                name:@"auth_login_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"loginForm"];
  }
  [application registerRouteMethod:@"POST"
                              path:runtime.loginPath
                              name:@"auth_login"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"login"];
  [application registerRouteMethod:@"POST"
                              path:runtime.logoutPath
                              name:@"auth_logout"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"logout"];
  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.registerPath
                                name:@"auth_register_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"registerForm"];
  }
  [application registerRouteMethod:@"POST"
                              path:runtime.registerPath
                              name:@"auth_register"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"register"];
  [application registerRouteMethod:@"GET"
                              path:runtime.sessionPath
                              name:@"auth_session"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"sessionState"];
  [application registerRouteMethod:@"GET"
                              path:runtime.verifyPath
                              name:@"auth_verify"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"verifyEmail"];
  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.forgotPasswordPath
                                name:@"auth_password_forgot_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"forgotPasswordForm"];
  }
  [application registerRouteMethod:@"POST"
                              path:runtime.forgotPasswordPath
                              name:@"auth_password_forgot"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"forgotPassword"];
  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.resetPasswordPath
                                name:@"auth_password_reset_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"resetPasswordForm"];
  }
  [application registerRouteMethod:@"POST"
                              path:runtime.resetPasswordPath
                              name:@"auth_password_reset"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"resetPassword"];
  [application registerRouteMethod:@"POST"
                              path:runtime.changePasswordPath
                              name:@"auth_password_change"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"changePassword"];
  if (![runtime isHeadlessUIMode]) {
    [application registerRouteMethod:@"GET"
                                path:runtime.totpPath
                                name:@"auth_totp_form"
                     controllerClass:[ALNAuthModuleController class]
                               action:@"totpForm"];
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
  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/session"
                              name:@"auth_api_session"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"sessionState"];
  [application registerRouteMethod:@"POST"
                              path:@"/login"
                              name:@"auth_api_login"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"login"];
  [application registerRouteMethod:@"POST"
                              path:@"/logout"
                              name:@"auth_api_logout"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"logout"];
  [application registerRouteMethod:@"POST"
                              path:@"/register"
                              name:@"auth_api_register"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"register"];
  [application registerRouteMethod:@"GET"
                              path:@"/verify"
                              name:@"auth_api_verify"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"verifyEmail"];
  [application registerRouteMethod:@"POST"
                              path:@"/password/forgot"
                              name:@"auth_api_password_forgot"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"forgotPassword"];
  [application registerRouteMethod:@"GET"
                              path:@"/password/reset"
                              name:@"auth_api_password_reset_form"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"resetPasswordForm"];
  [application registerRouteMethod:@"POST"
                              path:@"/password/reset"
                              name:@"auth_api_password_reset"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"resetPassword"];
  [application registerRouteMethod:@"POST"
                              path:@"/password/change"
                              name:@"auth_api_password_change"
                   controllerClass:[ALNAuthModuleController class]
                             action:@"changePassword"];
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
  NSDictionary *apiRouteSchemas = @{
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
  };
  if ([runtime isProviderEnabled:@"stub"]) {
    NSMutableDictionary *mutableRouteSchemas = [NSMutableDictionary dictionaryWithDictionary:apiRouteSchemas];
    mutableRouteSchemas[@"auth_api_provider_stub_login"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"return_to" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
    mutableRouteSchemas[@"auth_api_provider_stub_authorize"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"state" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
    mutableRouteSchemas[@"auth_api_provider_stub_callback"] = @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"code" : @{ @"type" : @"string", @"source" : @"query" },
          @"state" : @{ @"type" : @"string", @"source" : @"query" },
        },
      },
      @"response" : @{ @"type" : @"object" },
    };
    apiRouteSchemas = [NSDictionary dictionaryWithDictionary:mutableRouteSchemas];
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
