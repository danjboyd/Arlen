#import <Foundation/Foundation.h>
#import "ALNAuthProviderSessionBridge.h"

NS_ASSUME_NONNULL_BEGIN
extern NSString *const ALNAuthModuleOIDCErrorDomain;
/// NSError userInfo key carrying a stable, non-sensitive failure code for a rejected
/// callback: `rejected`, `admission_denied`, `expired_state`, `provider_error`,
/// `verification_failed`, or `provider_unavailable`. An application resolver may set
/// its own code (lowercase letters, digits, underscore; at most 64 characters) on the
/// NSError it returns to distinguish, for example, `not_invited` from `rejected`.
extern NSString *const ALNAuthModuleOIDCFailureCodeKey;
typedef NS_ENUM(NSInteger, ALNAuthModuleOIDCErrorCode) {
  ALNAuthModuleOIDCErrorRejected = 1,
  /// The verified identity failed the provider's `admission` policy.
  ALNAuthModuleOIDCErrorAdmissionDenied = 2,
};
/// Trusted application transport seam for deterministic OIDC fixtures or custom networking.
/// Implementations must enforce TLS, no redirects/cookies, HTTP 200, response size and deadline.
@protocol ALNAuthModuleOIDCTransport <NSObject>
- (nullable NSData *)performOIDCRequest:(NSURLRequest *)request error:(NSError *_Nullable *_Nullable)error;
@end

/// Auth module OIDC orchestration. Instantiate once per enabled provider at configuration time.
@interface ALNAuthModuleOIDC : NSObject <ALNAuthProviderSessionResolver>
@property(nonatomic, copy, readonly) NSDictionary *configuration;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                            configuration:(NSDictionary *)configuration
                                 resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                transport:(nullable id<ALNAuthModuleOIDCTransport>)transport
                                    error:(NSError *_Nullable *_Nullable)error;
/// allowLoopbackHTTPRedirect permits an http://localhost, http://127.0.0.1 or
/// http://[::1] redirectURI. The auth module enables it only in development and
/// test. Issuer, discovery, token and JWKS endpoints are always HTTPS-only.
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                            configuration:(NSDictionary *)configuration
                                 resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                transport:(nullable id<ALNAuthModuleOIDCTransport>)transport
                allowLoopbackHTTPRedirect:(BOOL)allowLoopbackHTTPRedirect
                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)beginLoginWithError:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)completeLoginWithParameters:(NSDictionary *)parameters
                                       callbackState:(NSDictionary *)state
                                             context:(ALNContext *)context
                                               error:(NSError *_Nullable *_Nullable)error;
@end
NS_ASSUME_NONNULL_END
