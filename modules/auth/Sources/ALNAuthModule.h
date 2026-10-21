#ifndef ALN_AUTH_MODULE_H
#define ALN_AUTH_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNAuthProviderSessionBridge.h"
#import "ALNAuthModuleOIDC.h"
#import "ALNModuleSystem.h"

@class ALNApplication;
@class ALNContext;
@class ALNMailMessage;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAuthModuleErrorDomain;
// userInfo key on ALNAuthModuleErrorRateLimited errors: seconds (NSNumber) until
// the account may try again.
extern NSString *const ALNAuthModuleRetryAfterSecondsKey;

typedef NS_ENUM(NSInteger, ALNAuthModuleErrorCode) {
  ALNAuthModuleErrorInvalidConfiguration = 1,
  ALNAuthModuleErrorDatabaseUnavailable = 2,
  ALNAuthModuleErrorValidationFailed = 3,
  ALNAuthModuleErrorNotFound = 4,
  ALNAuthModuleErrorAuthenticationFailed = 5,
  ALNAuthModuleErrorPolicyRejected = 6,
  ALNAuthModuleErrorRateLimited = 7,
};

@protocol ALNAuthModuleRegistrationPolicy <NSObject>
- (BOOL)authModuleShouldAllowRegistration:(NSDictionary *)registrationRequest
                                    error:(NSError *_Nullable *_Nullable)error;
@end

@protocol ALNAuthModulePasswordPolicy <NSObject>
- (BOOL)authModuleValidatePassword:(NSString *)password
                      errorMessage:(NSString *_Nullable *_Nullable)errorMessage;
@end

@protocol ALNAuthModuleUserProvisioningHook <NSObject>
- (nullable NSDictionary *)authModuleUserValuesForEvent:(NSString *)event
                                         proposedValues:(NSDictionary *)proposedValues;
@end

@protocol ALNAuthModuleNotificationHook <NSObject>
- (nullable ALNMailMessage *)authModuleMailMessageForEvent:(NSString *)event
                                                      user:(NSDictionary *)user
                                                     token:(NSString *)token
                                                   baseURL:(NSString *)baseURL
                                            defaultMessage:(ALNMailMessage *)defaultMessage;
@end

@protocol ALNAuthModuleSessionPolicyHook <NSObject>
@optional
- (nullable NSDictionary *)authModuleSessionDescriptorForUser:(NSDictionary *)user
                                             defaultDescriptor:(NSDictionary *)defaultDescriptor;
- (nullable NSString *)authModulePostLoginRedirectForContext:(ALNContext *)context
                                                        user:(NSDictionary *)user
                                             defaultRedirect:(NSString *)defaultRedirect;
@end

@protocol ALNAuthModuleProviderMappingHook <NSObject>
- (nullable NSDictionary *)authModuleProviderMappingDescriptorForNormalizedIdentity:
                                (NSDictionary *)normalizedIdentity
                                                           defaultDescriptor:
                                                               (NSDictionary *)defaultDescriptor;
@end

@protocol ALNAuthModuleUIContextHook <NSObject>
@optional
- (nullable NSString *)authModuleUILayoutForPage:(NSString *)pageIdentifier
                                   defaultLayout:(NSString *)defaultLayout
                                         context:(ALNContext *)context;
- (nullable NSDictionary *)authModuleUIContextForPage:(NSString *)pageIdentifier
                                       defaultContext:(NSDictionary *)defaultContext
                                              context:(ALNContext *)context;
@end

@interface ALNAuthModuleRuntime : NSObject <ALNAuthProviderSessionResolver>

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, copy, readonly) NSString *loginPath;
@property(nonatomic, copy, readonly) NSString *registerPath;
@property(nonatomic, copy, readonly) NSString *logoutPath;
/// POST target that signs the current user out on every device
/// (`authModule.paths.logoutAll`, default `/auth/logout/all`).
@property(nonatomic, copy, readonly) NSString *logoutAllPath;
/// `authModule.session.absoluteLifetimeSeconds` (default 1209600, 14 days):
/// how long after sign-in a module session stays signed in, however often it
/// is renewed.
@property(nonatomic, assign, readonly) NSUInteger absoluteSessionLifetimeSeconds;
@property(nonatomic, copy, readonly) NSString *sessionPath;
@property(nonatomic, copy, readonly) NSString *verifyPath;
@property(nonatomic, copy, readonly) NSString *forgotPasswordPath;
@property(nonatomic, copy, readonly) NSString *resetPasswordPath;
@property(nonatomic, copy, readonly) NSString *changePasswordPath;
@property(nonatomic, copy, readonly) NSString *mfaManagePath;
@property(nonatomic, copy, readonly) NSString *totpPath;
/// Where module surfaces send a user who needs higher assurance
/// (`authModule.paths.stepUp`). Defaults to `totpPath`. Apps whose users sign in
/// only through an identity provider point this at a provider login with
/// `prompt=login`, so a step-up is a fresh sign-in rather than a TOTP page the
/// user has no factor for.
@property(nonatomic, copy, readonly) NSString *stepUpPath;
@property(nonatomic, copy, readonly) NSString *totpVerifyPath;
@property(nonatomic, copy, readonly) NSString *smsPath;
@property(nonatomic, copy, readonly) NSString *smsStartPath;
@property(nonatomic, copy, readonly) NSString *smsVerifyPath;
@property(nonatomic, copy, readonly) NSString *smsResendPath;
@property(nonatomic, copy, readonly) NSString *smsRemovePath;
@property(nonatomic, copy, readonly) NSString *providerStubLoginPath;
@property(nonatomic, copy, readonly) NSString *providerStubAuthorizePath;
@property(nonatomic, copy, readonly) NSString *providerStubCallbackPath;
@property(nonatomic, copy, readonly) NSString *defaultRedirect;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *loginProviders;
@property(nonatomic, assign, readonly) BOOL localPasswordEnabled;
@property(nonatomic, copy, readonly) NSString *uiMode;
@property(nonatomic, copy, readonly) NSString *layoutTemplate;
@property(nonatomic, copy, readonly) NSString *generatedPagePrefix;
// URL prefix for module-ui assets (auth.css, auth_totp_qr.js): `<paths.prefix>/assets`
// once registration mounts them there, else the framework's `/modules/auth` mount.
@property(nonatomic, copy, readonly) NSString *uiAssetPrefix;
@property(nonatomic, assign, readonly) BOOL smsEnabled;
/// `authModule.publicBaseURL` without a trailing slash, or "" when unset. Links
/// in password-reset and email-verification mail start with it. When unset,
/// development and test fall back to the request's Host header; other
/// environments send no link.
@property(nonatomic, copy, readonly) NSString *publicBaseURL;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)configureHooksWithModuleConfig:(NSDictionary *)moduleConfig
                                 error:(NSError *_Nullable *_Nullable)error;
/// Sets the environment name (as `configureWithApplication:` does from the
/// application) before configuring. Environment-dependent defaults, such as the
/// development/test-only stub provider, follow it.
- (BOOL)configureHooksWithModuleConfig:(NSDictionary *)moduleConfig
                           environment:(NSString *)environment
                                 error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedHookSummary;
- (BOOL)registrationAllowedForRequest:(NSDictionary *)registrationRequest
                                error:(NSError *_Nullable *_Nullable)error;
- (BOOL)validatePassword:(NSString *)password
            errorMessage:(NSString *_Nullable *_Nullable)errorMessage;
- (NSDictionary *)provisionedUserValuesForEvent:(NSString *)event
                                 proposedValues:(NSDictionary *)proposedValues;
- (NSDictionary *)providerMappingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                               defaultDescriptor:
                                                   (NSDictionary *)defaultDescriptor;
- (NSDictionary *)sessionDescriptorForUser:(NSDictionary *)user
                         defaultDescriptor:(NSDictionary *)defaultDescriptor;
- (NSString *)postLoginRedirectForContext:(ALNContext *)context
                                     user:(NSDictionary *)user
                          defaultRedirect:(NSString *)defaultRedirect;
- (BOOL)isHeadlessUIMode;
- (BOOL)isProviderEnabled:(NSString *)identifier;
- (NSString *)pageTemplatePathForIdentifier:(NSString *)pageIdentifier
                                defaultPath:(NSString *)defaultPath;
- (NSString *)bodyTemplatePathForIdentifier:(NSString *)pageIdentifier
                                defaultPath:(NSString *)defaultPath;
- (NSString *)fragmentTemplatePathForIdentifier:(NSString *)fragmentIdentifier
                                    defaultPath:(NSString *)defaultPath;
- (NSString *)partialTemplatePathForIdentifier:(NSString *)partialIdentifier
                                   defaultPath:(NSString *)defaultPath;
- (NSString *)authUIAssetPathForFilename:(NSString *)filename;
- (NSString *)layoutTemplateForPage:(NSString *)pageIdentifier
                            context:(ALNContext *)context;
- (NSDictionary *)uiContextForPage:(NSString *)pageIdentifier
                    defaultContext:(NSDictionary *)defaultContext
                           context:(ALNContext *)context;
- (nullable NSDictionary *)currentUserForSubject:(NSString *)subject
                                           error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)currentUserForContext:(ALNContext *)context
                                           error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)totpProvisioningPayloadForUser:(NSDictionary *)user
                                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)totpProvisioningPayloadForUser:(NSDictionary *)user
                                                  context:(ALNContext *)context
                                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)totpFragmentContextForCurrentUserInContext:(ALNContext *)context
                                                             returnTo:(nullable NSString *)returnTo
                                                                error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)mfaManagementFragmentContextForCurrentUserInContext:(ALNContext *)context
                                                                      returnTo:(nullable NSString *)returnTo
                                                                         error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)smsChallengeFragmentContextForCurrentUserInContext:(ALNContext *)context
                                                                     returnTo:(nullable NSString *)returnTo
                                                                        error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)verifyTOTPCode:(NSString *)code
                                     user:(NSDictionary *)user
                                  context:(ALNContext *)context
                                    error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)totpRecoveryCodesFragmentContextWithCodes:(NSArray<NSString *> *)recoveryCodes
                                                   returnTo:(nullable NSString *)returnTo;
- (nullable NSDictionary *)sessionPayloadForContext:(ALNContext *)context
                                        includeUser:(BOOL)includeUser
                                              error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)claimTrustedEmail:(NSString *)email
                                 displayName:(nullable NSString *)displayName
                                      source:(nullable NSString *)source
                      sendPasswordSetupEmail:(BOOL)sendPasswordSetupEmail
                                     baseURL:(nullable NSString *)baseURL
                                     context:(ALNContext *)context
                                       error:(NSError *_Nullable *_Nullable)error;
- (BOOL)isAdminContext:(ALNContext *)context
                 error:(NSError *_Nullable *_Nullable)error;

@end

/// Session resolution against the current user record (see docs/AUTH_MODULE.md).
@interface ALNAuthModuleRuntime (ALNAuthModuleSessionRefresh)
/// Resolves the request's session identity against its current source of truth:
/// the `auth_users` row for module sign-ins (roles, session stamp, existence), or
/// the provider resolver's `refreshSessionDescriptorForSubject:provider:error:`
/// for configured OIDC providers. Live roles replace the session's roles for the
/// request; a missing user, a resolver that returns nil, or a stale session
/// stamp signs the session out. Returns NO with `error` when the lookup fails.
/// The module installs a middleware that calls this on every request.
- (BOOL)refreshAuthenticatedSessionForContext:(ALNContext *)context
                                        error:(NSError *_Nullable *_Nullable)error;
/// Stores the signed-in user's current session stamp in the session. Module
/// sign-ins call this; call it after establishing a session for an `auth_users`
/// subject yourself.
- (BOOL)recordSessionStampForContext:(ALNContext *)context
                               error:(NSError *_Nullable *_Nullable)error;
/// Increments the user's session stamp, which signs out every existing session
/// for `subject` on its next request.
- (BOOL)bumpSessionStampForSubject:(NSString *)subject
                             error:(NSError *_Nullable *_Nullable)error;
/// Signs the request's session out and records it as ended
/// (`auth_revoked_sessions`), so other copies of the same session cookie stop
/// working while the user's other sessions are unaffected. The session is
/// always cleared from the context; returns NO with `error` only when the
/// record could not be written.
- (BOOL)revokeCurrentSessionForContext:(ALNContext *)context
                                 error:(NSError *_Nullable *_Nullable)error;
/// Records the current session as ended before MFA rotates its identifier,
/// while keeping the context authenticated for that rotation.
- (BOOL)revokeSessionBeingElevatedForContext:(ALNContext *)context
                                      error:(NSError *_Nullable *_Nullable)error;
/// Ends every other session of the signed-in user (bumps the session stamp)
/// and keeps the request's session signed in by recording the new stamp in it.
- (BOOL)signOutOtherSessionsForContext:(ALNContext *)context
                                 error:(NSError *_Nullable *_Nullable)error;
/// Ends every session of the signed-in user, including the request's own.
// NO until the session stamp migration has been applied; sign-out-everywhere
// can then end only the current session.
- (BOOL)canEndOtherSessions;
- (BOOL)signOutAllSessionsForContext:(ALNContext *)context
                               error:(NSError *_Nullable *_Nullable)error;
@end

/// Adds the per-request middleware that calls
/// `refreshAuthenticatedSessionForContext:error:` once per application. Module
/// registration calls this.
FOUNDATION_EXPORT void ALNAuthModuleInstallSessionRefresh(ALNApplication *application);

@interface ALNAuthModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
