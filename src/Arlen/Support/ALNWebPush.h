#ifndef ALN_WEB_PUSH_H
#define ALN_WEB_PUSH_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Web Push protocol primitives: RFC 8291 message encryption (aes128gcm) and
// RFC 8292 VAPID application-server identification. Pure functions; no I/O.

extern NSString *const ALNWebPushErrorDomain;

typedef NS_ENUM(NSInteger, ALNWebPushErrorCode) {
  ALNWebPushErrorInvalidKey = 1,
  ALNWebPushErrorInvalidSubscription = 2,
  ALNWebPushErrorPayloadTooLarge = 3,
  ALNWebPushErrorCryptoFailed = 4,
  ALNWebPushErrorInvalidArgument = 5,
};

// Push services must accept 4096-octet bodies (RFC 8030 section 7.2). With the
// 86-octet aes128gcm header, the 16-octet tag and the padding delimiter, that
// leaves 3993 octets of plaintext in a single record.
extern const NSUInteger ALNWebPushMaxPlaintextLength;

/// Generates a P-256 VAPID key pair. Keys are base64url without padding:
/// publicKey is the 65-octet uncompressed point (the browser's
/// applicationServerKey), privateKey is the 32-octet scalar.
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *_Nullable ALNWebPushGenerateVAPIDKeyPair(
    NSError *_Nullable *_Nullable error);

/// The base64url public key for a base64url VAPID private key.
FOUNDATION_EXPORT NSString *_Nullable ALNWebPushVAPIDPublicKeyForPrivateKey(NSString *privateKey,
                                                                            NSError *_Nullable *_Nullable error);

/// Encrypts a push message for one subscription (RFC 8291, single record).
/// userAgentPublicKey is the subscription's 65-octet p256dh point and authSecret its
/// 16-octet auth value. senderPrivateKey (32-octet scalar) and salt (16 octets) are
/// generated fresh when nil; pass them only to reproduce known vectors.
FOUNDATION_EXPORT NSData *_Nullable ALNWebPushEncryptPayload(NSData *plaintext,
                                                              NSData *userAgentPublicKey,
                                                              NSData *authSecret,
                                                              NSData *_Nullable senderPrivateKey,
                                                              NSData *_Nullable salt,
                                                              NSError *_Nullable *_Nullable error);

/// Decrypts an aes128gcm body as a user agent would. Used by tests and tooling.
FOUNDATION_EXPORT NSData *_Nullable ALNWebPushDecryptPayload(NSData *body,
                                                              NSData *userAgentPrivateKey,
                                                              NSData *authSecret,
                                                              NSError *_Nullable *_Nullable error);

/// The VAPID audience for a push endpoint: its scheme and authority.
FOUNDATION_EXPORT NSString *_Nullable ALNWebPushAudienceForEndpoint(NSURL *endpoint);

/// Topic header values are at most 32 base64url characters (RFC 8030 section 5.4).
FOUNDATION_EXPORT BOOL ALNWebPushTopicIsValid(NSString *topic);

/// A VAPID signing identity. Thread-safe once created.
@interface ALNWebPushVAPIDKey : NSObject

@property(nonatomic, copy, readonly) NSString *publicKey;

/// Validates the base64url key pair; the public key must match the private scalar.
+ (nullable instancetype)keyWithPublicKey:(NSString *)publicKey
                               privateKey:(NSString *)privateKey
                                    error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;

/// An ES256 JWT with aud, exp and sub claims.
- (nullable NSString *)signedTokenForAudience:(NSString *)audience
                                      subject:(NSString *)subject
                                   expiration:(NSDate *)expiration
                                        error:(NSError *_Nullable *_Nullable)error;

/// The Authorization header value: "vapid t=<jwt>, k=<publicKey>".
- (nullable NSString *)authorizationHeaderForAudience:(NSString *)audience
                                              subject:(NSString *)subject
                                           expiration:(NSDate *)expiration
                                                error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
