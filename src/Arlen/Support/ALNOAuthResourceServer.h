#ifndef ALN_OAUTH_RESOURCE_SERVER_H
#define ALN_OAUTH_RESOURCE_SERVER_H
#import <Foundation/Foundation.h>
#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const ALNOAuthPrincipalStashKey;
/// Trusted transport injection for controlled fixtures. Never receives bearer tokens.
typedef NSDictionary *_Nullable (^ALNOAuthDocumentLoader)(NSURL *url, NSError *_Nullable *_Nullable error);
/// Return NO to suspend a principal or deny request/record access. Invoked on every dispatch.
typedef BOOL (^ALNOAuthAuthorizationPolicy)(NSDictionary *principal, ALNContext *context);

/// Opt-in, bearer-only resource server. Install before application policy middleware.
/// Configuration and hooks freeze when installed; one instance per resource/application.
@interface ALNOAuthResourceServer : NSObject <ALNPlugin, ALNMiddleware>
@property(nonatomic, copy, readonly) NSDictionary *configuration;
@property(nonatomic, copy, readonly) NSString *metadataPath;
@property(nonatomic, copy, readonly) NSString *metadataURL;
- (nullable instancetype)initWithConfiguration:(NSDictionary *)configuration
                               documentLoader:(nullable ALNOAuthDocumentLoader)loader
                          authorizationPolicy:(nullable ALNOAuthAuthorizationPolicy)policy
                                        error:(NSError *_Nullable *_Nullable)error;
/// Commercial-cloud, single-tenant preset. v2 audience is API application GUID;
/// v1 audience must be explicitly supplied (Application ID URI or GUID as issued).
+ (nullable NSDictionary *)entraConfigurationForTenant:(NSString *)tenant
                                        tokenVersion:(NSString *)version
                                            audience:(NSString *)audience
                                         resourceURL:(NSString *)resourceURL
                                              scopes:(NSArray *)scopes
                                               error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)principalForAccessToken:(nullable NSString *)token
                                            error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)protectedResourceMetadata;
- (NSString *)challengeForError:(nullable NSString *)error;
- (BOOL)protectsPath:(NSString *)path;
@end
NS_ASSUME_NONNULL_END
#endif
