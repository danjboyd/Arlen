#import <Foundation/Foundation.h>
#import "ALNAuthProviderSessionBridge.h"

NS_ASSUME_NONNULL_BEGIN
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
