#ifndef ALN_AUTH_MODULE_H
#define ALN_AUTH_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNAuthProviderSessionBridge.h"
#import "ALNModuleSystem.h"

@class ALNApplication;
@class ALNContext;
@class ALNMailMessage;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAuthModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNAuthModuleErrorCode) {
  ALNAuthModuleErrorInvalidConfiguration = 1,
  ALNAuthModuleErrorDatabaseUnavailable = 2,
  ALNAuthModuleErrorValidationFailed = 3,
  ALNAuthModuleErrorNotFound = 4,
  ALNAuthModuleErrorAuthenticationFailed = 5,
  ALNAuthModuleErrorPolicyRejected = 6,
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

@interface ALNAuthModuleRuntime : NSObject <ALNAuthProviderSessionResolver>

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, copy, readonly) NSString *loginPath;
@property(nonatomic, copy, readonly) NSString *registerPath;
@property(nonatomic, copy, readonly) NSString *logoutPath;
@property(nonatomic, copy, readonly) NSString *sessionPath;
@property(nonatomic, copy, readonly) NSString *verifyPath;
@property(nonatomic, copy, readonly) NSString *forgotPasswordPath;
@property(nonatomic, copy, readonly) NSString *resetPasswordPath;
@property(nonatomic, copy, readonly) NSString *changePasswordPath;
@property(nonatomic, copy, readonly) NSString *totpPath;
@property(nonatomic, copy, readonly) NSString *totpVerifyPath;
@property(nonatomic, copy, readonly) NSString *providerStubLoginPath;
@property(nonatomic, copy, readonly) NSString *providerStubAuthorizePath;
@property(nonatomic, copy, readonly) NSString *providerStubCallbackPath;
@property(nonatomic, copy, readonly) NSString *defaultRedirect;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)configureHooksWithModuleConfig:(NSDictionary *)moduleConfig
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
- (nullable NSDictionary *)currentUserForSubject:(NSString *)subject
                                           error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)currentUserForContext:(ALNContext *)context
                                           error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)sessionPayloadForContext:(ALNContext *)context
                                        includeUser:(BOOL)includeUser
                                              error:(NSError *_Nullable *_Nullable)error;
- (BOOL)isAdminContext:(ALNContext *)context
                 error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNAuthModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
