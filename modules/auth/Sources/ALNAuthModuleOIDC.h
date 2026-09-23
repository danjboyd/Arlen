#import <Foundation/Foundation.h>
#import "ALNAuthProviderSessionBridge.h"

NS_ASSUME_NONNULL_BEGIN
/// Trusted application transport seam for deterministic OIDC fixtures or custom networking.
/// Implementations must enforce TLS, no redirects/cookies, HTTP 200, response size and deadline.
@protocol ALNAuthModuleOIDCTransport <NSObject>
- (nullable NSData *)performOIDCRequest:(NSURLRequest *)request error:(NSError **)error;
@end

/// Auth module OIDC orchestration. Instantiate once per enabled provider at configuration time.
@interface ALNAuthModuleOIDC : NSObject <ALNAuthProviderSessionResolver>
@property(nonatomic, copy, readonly) NSDictionary *configuration;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                            configuration:(NSDictionary *)configuration
                                 resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                transport:(nullable id<ALNAuthModuleOIDCTransport>)transport
                                    error:(NSError **)error;
- (nullable NSDictionary *)beginLoginWithError:(NSError **)error;
- (nullable NSDictionary *)completeLoginWithParameters:(NSDictionary *)parameters
                                       callbackState:(NSDictionary *)state
                                             context:(ALNContext *)context
                                               error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
