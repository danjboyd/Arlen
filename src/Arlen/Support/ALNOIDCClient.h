#ifndef ALN_OIDC_CLIENT_H
#define ALN_OIDC_CLIENT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNOIDCClientErrorDomain;

typedef NS_ENUM(NSInteger, ALNOIDCClientErrorCode) {
  ALNOIDCClientErrorInvalidArgument = 1,
  ALNOIDCClientErrorRandomGenerationFailed = 2,
  ALNOIDCClientErrorCallbackErrorResponse = 3,
  ALNOIDCClientErrorMissingAuthorizationCode = 4,
  ALNOIDCClientErrorCallbackStateMismatch = 5,
  ALNOIDCClientErrorCallbackExpired = 6,
  ALNOIDCClientErrorInvalidTokenResponse = 7,
  ALNOIDCClientErrorMissingIDToken = 8,
  ALNOIDCClientErrorInvalidIDTokenHeader = 9,
  ALNOIDCClientErrorUnsupportedIDTokenAlgorithm = 10,
  ALNOIDCClientErrorMissingVerificationKey = 11,
  ALNOIDCClientErrorInvalidIDTokenSignature = 12,
  ALNOIDCClientErrorInvalidIDTokenClaims = 13,
  ALNOIDCClientErrorNonceMismatch = 14,
  ALNOIDCClientErrorJWKSExpired = 15,
  ALNOIDCClientErrorJWKNotFound = 16,
  ALNOIDCClientErrorJWKMalformed = 17,
  ALNOIDCClientErrorUnsupportedJWKType = 18,
  ALNOIDCClientErrorMissingIdentitySubject = 19,
};

@interface ALNOIDCClient : NSObject

+ (nullable NSDictionary *)authorizationRequestForProviderConfiguration:(NSDictionary *)providerConfiguration
                                                            redirectURI:(NSString *)redirectURI
                                                                 scopes:(nullable NSArray *)scopes
                                                          referenceDate:(nullable NSDate *)referenceDate
                                                                  error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)validateAuthorizationCallbackParameters:(NSDictionary *)parameters
                                                     expectedState:(NSString *)expectedState
                                                       issuedAtDate:(nullable NSDate *)issuedAtDate
                                                      maxAgeSeconds:(NSUInteger)maxAgeSeconds
                                                              error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)tokenExchangeRequestForProviderConfiguration:(NSDictionary *)providerConfiguration
                                                      authorizationCode:(NSString *)authorizationCode
                                                            redirectURI:(NSString *)redirectURI
                                                           codeVerifier:(NSString *)codeVerifier
                                                                  error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)parseTokenResponseData:(NSData *)data
                                            error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)verifyIDToken:(NSString *)idToken
                   providerConfiguration:(NSDictionary *)providerConfiguration
                           expectedNonce:(nullable NSString *)expectedNonce
                            jwksDocument:(nullable NSDictionary *)jwksDocument
                           referenceDate:(nullable NSDate *)referenceDate
                                   error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)normalizedIdentityFromVerifiedClaims:(nullable NSDictionary *)verifiedClaims
                                                  tokenResponse:(nullable NSDictionary *)tokenResponse
                                               userInfoResponse:(nullable NSDictionary *)userInfoResponse
                                          providerConfiguration:(NSDictionary *)providerConfiguration
                                                          error:(NSError *_Nullable *_Nullable)error;

+ (NSDictionary *)redactedProviderConfiguration:(NSDictionary *)providerConfiguration;

@end

NS_ASSUME_NONNULL_END

#endif
