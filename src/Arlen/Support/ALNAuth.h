#ifndef ALN_AUTH_H
#define ALN_AUTH_H

#import <Foundation/Foundation.h>

@class ALNContext;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAuthErrorDomain;

typedef NS_ENUM(NSInteger, ALNAuthErrorCode) {
  ALNAuthErrorMissingBearerToken = 1,
  ALNAuthErrorInvalidAuthorizationHeader = 2,
  ALNAuthErrorInvalidTokenFormat = 3,
  ALNAuthErrorInvalidTokenHeader = 4,
  ALNAuthErrorUnsupportedAlgorithm = 5,
  ALNAuthErrorInvalidSignature = 6,
  ALNAuthErrorInvalidPayload = 7,
  ALNAuthErrorTokenExpired = 8,
  ALNAuthErrorTokenNotActive = 9,
  ALNAuthErrorInvalidAudience = 10,
  ALNAuthErrorInvalidIssuer = 11,
  ALNAuthErrorMissingVerifierSecret = 12,
  ALNAuthErrorMissingScope = 13,
  ALNAuthErrorMissingRole = 14,
};

@interface ALNAuth : NSObject

+ (nullable NSString *)bearerTokenFromAuthorizationHeader:(NSString *)authorizationHeader
                                                    error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)verifyJWTToken:(NSString *)token
                                   secret:(NSString *)secret
                                   issuer:(nullable NSString *)issuer
                                 audience:(nullable NSString *)audience
                                    error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)authenticateContext:(ALNContext *)context
                authConfig:(NSDictionary *)authConfig
                     error:(NSError *_Nullable *_Nullable)error;

+ (void)applyClaims:(NSDictionary *)claims toContext:(ALNContext *)context;
+ (NSArray *)scopesFromClaims:(NSDictionary *)claims;
+ (NSArray *)rolesFromClaims:(NSDictionary *)claims;
+ (BOOL)context:(ALNContext *)context hasRequiredScopes:(NSArray *)scopes;
+ (BOOL)context:(ALNContext *)context hasRequiredRoles:(NSArray *)roles;
/// YES when the context holds at least one of `roles`; NO for an empty list.
/// Reads `-[ALNContext authRoles]`, the same source as the route contract: the
/// current roles when a session refresh middleware (such as the auth module's)
/// has resolved them for this request.
+ (BOOL)context:(ALNContext *)context hasAnyRole:(NSArray *)roles;

@end

NS_ASSUME_NONNULL_END

#endif
