#ifndef ALN_AUTH_PROVIDER_SESSION_BRIDGE_H
#define ALN_AUTH_PROVIDER_SESSION_BRIDGE_H

#import <Foundation/Foundation.h>

@class ALNContext;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAuthProviderSessionBridgeErrorDomain;

typedef NS_ENUM(NSInteger, ALNAuthProviderSessionBridgeErrorCode) {
  ALNAuthProviderSessionBridgeErrorInvalidArgument = 1,
  ALNAuthProviderSessionBridgeErrorResolverRejectedIdentity = 2,
  ALNAuthProviderSessionBridgeErrorMissingLocalSubject = 3,
};

@protocol ALNAuthProviderSessionResolver <NSObject>

- (nullable NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                                   providerConfiguration:(NSDictionary *)providerConfiguration
                                                                   error:(NSError *_Nullable *_Nullable)error;

@optional
- (nullable NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                                   providerConfiguration:(NSDictionary *)providerConfiguration
                                                                   error:(NSError *_Nullable *_Nullable)error;

/// Called after the bridge establishes the session for a resolved descriptor.
/// Returning NO signs the session out again and fails the login with `error`.
- (BOOL)providerSessionEstablishedForDescriptor:(NSDictionary *)sessionDescriptor
                                        context:(ALNContext *)context
                                          error:(NSError *_Nullable *_Nullable)error;

/// Re-resolves an established session for `subject` on later requests, so roles
/// follow the application's directory instead of the values stored at sign-in.
/// Return a descriptor whose `roles` replace the session's roles for the request,
/// or nil to sign the session out (nil with `error` fails the request instead).
- (nullable NSDictionary *)refreshSessionDescriptorForSubject:(NSString *)subject
                                                     provider:(NSString *)provider
                                                        error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNAuthProviderSessionBridge : NSObject

+ (nullable NSDictionary *)completeLoginWithCallbackParameters:(NSDictionary *)callbackParameters
                                                 callbackState:(NSDictionary *)callbackState
                                                 tokenResponse:(NSDictionary *)tokenResponse
                                              userInfoResponse:(nullable NSDictionary *)userInfoResponse
                                         providerConfiguration:(NSDictionary *)providerConfiguration
                                                  jwksDocument:(nullable NSDictionary *)jwksDocument
                                                      resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                                       context:(ALNContext *)context
                                                         error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                                   providerConfiguration:(NSDictionary *)providerConfiguration
                                                                resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                                                   error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
