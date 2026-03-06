#ifndef ALN_WEBAUTHN_H
#define ALN_WEBAUTHN_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNWebAuthnErrorDomain;

typedef NS_ENUM(NSInteger, ALNWebAuthnErrorCode) {
  ALNWebAuthnErrorInvalidArgument = 1,
  ALNWebAuthnErrorRandomGenerationFailed = 2,
  ALNWebAuthnErrorChallengeExpired = 3,
  ALNWebAuthnErrorChallengeMismatch = 4,
  ALNWebAuthnErrorOriginMismatch = 5,
  ALNWebAuthnErrorRPIDMismatch = 6,
  ALNWebAuthnErrorMalformedResponse = 7,
  ALNWebAuthnErrorUnsupportedAttestationFormat = 8,
  ALNWebAuthnErrorUnsupportedCredentialKey = 9,
  ALNWebAuthnErrorUserPresenceRequired = 10,
  ALNWebAuthnErrorUserVerificationRequired = 11,
  ALNWebAuthnErrorCredentialNotAllowed = 12,
  ALNWebAuthnErrorSignatureVerificationFailed = 13,
  ALNWebAuthnErrorSignCountReplay = 14,
  ALNWebAuthnErrorMalformedCBOR = 15,
};

@interface ALNWebAuthn : NSObject

+ (nullable NSDictionary *)registrationOptionsForRelyingPartyID:(NSString *)relyingPartyID
                                               relyingPartyName:(NSString *)relyingPartyName
                                                         origin:(NSString *)origin
                                                 userIdentifier:(NSString *)userIdentifier
                                                       userName:(NSString *)userName
                                                userDisplayName:(nullable NSString *)userDisplayName
                                        requireUserVerification:(BOOL)requireUserVerification
                                                 timeoutSeconds:(NSUInteger)timeoutSeconds
                                                          error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)assertionOptionsForRelyingPartyID:(NSString *)relyingPartyID
                                                      origin:(NSString *)origin
                                        allowedCredentialIDs:(nullable NSArray *)allowedCredentialIDs
                                     requireUserVerification:(BOOL)requireUserVerification
                                              timeoutSeconds:(NSUInteger)timeoutSeconds
                                                       error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)verifyRegistrationResponse:(NSDictionary *)response
                                      expectedOptions:(NSDictionary *)expectedOptions
                                                error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary *)verifyAssertionResponse:(NSDictionary *)response
                                   expectedOptions:(NSDictionary *)expectedOptions
                                 storedCredentialID:(nullable NSString *)storedCredentialID
                                  storedPublicKeyPEM:(NSString *)storedPublicKeyPEM
                                  previousSignCount:(NSUInteger)previousSignCount
                                              error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
