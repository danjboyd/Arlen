#import "ALNWebPush.h"

#import <Foundation/NSByteOrder.h>

#import <openssl/bn.h>
#import <openssl/ec.h>
#import <openssl/ecdsa.h>
#import <openssl/evp.h>
#import <openssl/x509.h>

#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
#include <openssl/core_names.h>
#endif

#import "ALNCryptoCompat.h"
#import "ALNSecurityPrimitives.h"

NSString *const ALNWebPushErrorDomain = @"Arlen.WebPush.Error";

const NSUInteger ALNWebPushMaxPlaintextLength = 4096 - 86 - 16 - 1;

static const uint32_t ALNWebPushRecordSize = 4096;
static const NSUInteger ALNWebPushHeaderLength = 16 + 4 + 1 + 65;

static NSError *ALNWebPushError(ALNWebPushErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNWebPushErrorDomain
                             code:code
                         userInfo:@{ NSLocalizedDescriptionKey : message ?: @"web push error" }];
}

static void ALNWebPushSetError(NSError **error, ALNWebPushErrorCode code, NSString *message) {
  if (error != NULL) {
    *error = ALNWebPushError(code, message);
  }
}

#pragma mark - Keys

// SEC1 ECPrivateKey for P-256 without the optional public key; OpenSSL derives the
// public point while parsing. The same DER parses on OpenSSL 1.1 and 3.
static EVP_PKEY *ALNWebPushCreatePrivateKey(NSData *scalar) {
  if ([scalar length] != 32) {
    return NULL;
  }
  static const uint8_t prefix[] = { 0x30, 0x31, 0x02, 0x01, 0x01, 0x04, 0x20 };
  static const uint8_t suffix[] = { 0xa0, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };
  NSMutableData *der = [NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
  [der appendData:scalar];
  [der appendBytes:suffix length:sizeof(suffix)];
  const unsigned char *cursor = [der bytes];
  EVP_PKEY *key = d2i_PrivateKey(EVP_PKEY_EC, NULL, &cursor, (long)[der length]);
  OPENSSL_cleanse([der mutableBytes], [der length]);
  return key;
}

static NSData *ALNWebPushPublicPoint(EVP_PKEY *key) {
  NSDictionary<NSString *, NSData *> *coordinates = ALNCryptoCopyES256PublicKeyCoordinates(key);
  NSData *x = coordinates[@"x"];
  NSData *y = coordinates[@"y"];
  if ([x length] != 32 || [y length] != 32) {
    return nil;
  }
  NSMutableData *point = [NSMutableData dataWithLength:1];
  ((uint8_t *)[point mutableBytes])[0] = 0x04;
  [point appendData:x];
  [point appendData:y];
  return point;
}

static NSData *ALNWebPushPrivateScalar(EVP_PKEY *key) {
  uint8_t bytes[32];
  BOOL ok = NO;
#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  BIGNUM *scalar = NULL;
  if (EVP_PKEY_get_bn_param(key, OSSL_PKEY_PARAM_PRIV_KEY, &scalar) == 1) {
    ok = (BN_bn2binpad(scalar, bytes, sizeof(bytes)) == sizeof(bytes));
  }
  BN_clear_free(scalar);
#else
  EC_KEY *ecKey = EVP_PKEY_get1_EC_KEY(key);
  const BIGNUM *scalar = (ecKey != NULL) ? EC_KEY_get0_private_key(ecKey) : NULL;
  if (scalar != NULL) {
    ok = (BN_bn2binpad(scalar, bytes, sizeof(bytes)) == sizeof(bytes));
  }
  EC_KEY_free(ecKey);
#endif
  NSData *result = ok ? [NSData dataWithBytes:bytes length:sizeof(bytes)] : nil;
  OPENSSL_cleanse(bytes, sizeof(bytes));
  return result;
}

// Rejects anything but an uncompressed point on P-256.
static EVP_PKEY *ALNWebPushCreatePublicKey(NSData *point) {
  if ([point length] != 65 || ((const uint8_t *)[point bytes])[0] != 0x04) {
    return NULL;
  }
  return ALNCryptoCreateES256PublicKeyFromCoordinates([point subdataWithRange:NSMakeRange(1, 32)],
                                                      [point subdataWithRange:NSMakeRange(33, 32)]);
}

NSDictionary<NSString *, NSString *> *ALNWebPushGenerateVAPIDKeyPair(NSError **error) {
  EVP_PKEY *key = ALNCryptoGenerateES256Key();
  NSData *publicPoint = (key != NULL) ? ALNWebPushPublicPoint(key) : nil;
  NSData *scalar = (key != NULL) ? ALNWebPushPrivateScalar(key) : nil;
  EVP_PKEY_free(key);
  if (publicPoint == nil || scalar == nil) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"could not generate a P-256 key pair");
    return nil;
  }
  return @{
    @"publicKey" : ALNBase64URLStringFromData(publicPoint) ?: @"",
    @"privateKey" : ALNBase64URLStringFromData(scalar) ?: @"",
  };
}

NSString *ALNWebPushVAPIDPublicKeyForPrivateKey(NSString *privateKey, NSError **error) {
  NSString *trimmed = [privateKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSData *scalar = ([trimmed length] > 0) ? ALNDataFromBase64URLString(trimmed) : nil;
  EVP_PKEY *key = ([scalar length] == 32) ? ALNWebPushCreatePrivateKey(scalar) : NULL;
  NSData *publicPoint = (key != NULL) ? ALNWebPushPublicPoint(key) : nil;
  EVP_PKEY_free(key);
  if (publicPoint == nil) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidKey, @"VAPID private key must be a base64url 32-byte P-256 scalar");
    return nil;
  }
  return ALNBase64URLStringFromData(publicPoint);
}

#pragma mark - Primitives

static NSData *ALNWebPushECDH(EVP_PKEY *privateKey, EVP_PKEY *peerKey) {
  EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(privateKey, NULL);
  NSMutableData *secret = nil;
  size_t length = 0;
  if (ctx != NULL && EVP_PKEY_derive_init(ctx) == 1 && EVP_PKEY_derive_set_peer(ctx, peerKey) == 1 &&
      EVP_PKEY_derive(ctx, NULL, &length) == 1 && length == 32) {
    secret = [NSMutableData dataWithLength:length];
    if (EVP_PKEY_derive(ctx, [secret mutableBytes], &length) != 1 || length != 32) {
      secret = nil;
    }
  }
  EVP_PKEY_CTX_free(ctx);
  return secret;
}

static NSData *ALNWebPushHKDFExtract(NSData *salt, NSData *inputKeyingMaterial) {
  return ALNHMACSHA256(inputKeyingMaterial, salt);
}

// Single-block HKDF-Expand; every length used here is at most 32 octets.
static NSData *ALNWebPushHKDFExpand(NSData *pseudorandomKey, NSData *info, NSUInteger length) {
  if (length == 0 || length > 32) {
    return nil;
  }
  NSMutableData *input = [NSMutableData dataWithData:info];
  uint8_t counter = 0x01;
  [input appendBytes:&counter length:1];
  NSData *block = ALNHMACSHA256(input, pseudorandomKey);
  return ([block length] >= length) ? [block subdataWithRange:NSMakeRange(0, length)] : nil;
}

static NSData *ALNWebPushASCIIInfo(const char *label) {
  // The trailing NUL is part of each RFC 8291 info string.
  return [NSData dataWithBytes:label length:strlen(label) + 1];
}

// Derives the content encryption key and nonce shared by both directions.
static BOOL ALNWebPushDeriveKeys(NSData *ecdhSecret,
                                 NSData *authSecret,
                                 NSData *userAgentPublicKey,
                                 NSData *senderPublicKey,
                                 NSData *salt,
                                 NSData **contentKey,
                                 NSData **nonce) {
  NSMutableData *keyInfo = [NSMutableData dataWithData:ALNWebPushASCIIInfo("WebPush: info")];
  [keyInfo appendData:userAgentPublicKey];
  [keyInfo appendData:senderPublicKey];
  NSData *combiningKey = ALNWebPushHKDFExtract(authSecret, ecdhSecret);
  NSData *inputKeyingMaterial = ALNWebPushHKDFExpand(combiningKey, keyInfo, 32);
  NSData *pseudorandomKey = ALNWebPushHKDFExtract(salt, inputKeyingMaterial ?: [NSData data]);
  NSData *derivedKey = ALNWebPushHKDFExpand(pseudorandomKey, ALNWebPushASCIIInfo("Content-Encoding: aes128gcm"), 16);
  NSData *derivedNonce = ALNWebPushHKDFExpand(pseudorandomKey, ALNWebPushASCIIInfo("Content-Encoding: nonce"), 12);
  if (inputKeyingMaterial == nil || [derivedKey length] != 16 || [derivedNonce length] != 12) {
    return NO;
  }
  *contentKey = derivedKey;
  *nonce = derivedNonce;
  return YES;
}

static NSData *ALNWebPushAESGCM(BOOL encrypt, NSData *input, NSData *key, NSData *nonce, NSData *tag, NSData **tagOut) {
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  NSMutableData *output = [NSMutableData dataWithLength:[input length] + 16];
  int length = 0;
  int finalLength = 0;
  BOOL ok = (ctx != NULL);
  ok = ok && EVP_CipherInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL, encrypt ? 1 : 0) == 1;
  ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)[nonce length], NULL) == 1;
  ok = ok && EVP_CipherInit_ex(ctx, NULL, NULL, [key bytes], [nonce bytes], encrypt ? 1 : 0) == 1;
  ok = ok && EVP_CipherUpdate(ctx, [output mutableBytes], &length, [input bytes], (int)[input length]) == 1;
  if (ok && !encrypt) {
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, (void *)[tag bytes]) == 1;
  }
  ok = ok && EVP_CipherFinal_ex(ctx, (unsigned char *)[output mutableBytes] + length, &finalLength) == 1;
  if (ok && encrypt) {
    NSMutableData *computedTag = [NSMutableData dataWithLength:16];
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, [computedTag mutableBytes]) == 1;
    if (ok && tagOut != NULL) {
      *tagOut = computedTag;
    }
  }
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) {
    return nil;
  }
  [output setLength:(NSUInteger)(length + finalLength)];
  return output;
}

#pragma mark - RFC 8291

NSData *ALNWebPushEncryptPayload(NSData *plaintext,
                                 NSData *userAgentPublicKey,
                                 NSData *authSecret,
                                 NSData *senderPrivateKey,
                                 NSData *salt,
                                 NSError **error) {
  if (plaintext == nil || [plaintext length] > ALNWebPushMaxPlaintextLength) {
    ALNWebPushSetError(error, ALNWebPushErrorPayloadTooLarge,
                       [NSString stringWithFormat:@"push payload exceeds %lu bytes",
                                                  (unsigned long)ALNWebPushMaxPlaintextLength]);
    return nil;
  }
  if ([authSecret length] != 16) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidSubscription, @"subscription auth secret must be 16 bytes");
    return nil;
  }
  NSData *recordSalt = salt ?: ALNSecureRandomData(16);
  if ([recordSalt length] != 16) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidArgument, @"salt must be 16 bytes");
    return nil;
  }
  EVP_PKEY *peerKey = ALNWebPushCreatePublicKey(userAgentPublicKey);
  if (peerKey == NULL) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidSubscription,
                       @"subscription p256dh key is not an uncompressed P-256 point");
    return nil;
  }
  EVP_PKEY *senderKey = (senderPrivateKey != nil) ? ALNWebPushCreatePrivateKey(senderPrivateKey)
                                                  : ALNCryptoGenerateES256Key();
  NSData *senderPublicKey = (senderKey != NULL) ? ALNWebPushPublicPoint(senderKey) : nil;
  NSData *ecdhSecret = (senderPublicKey != nil) ? ALNWebPushECDH(senderKey, peerKey) : nil;
  EVP_PKEY_free(senderKey);
  EVP_PKEY_free(peerKey);
  NSData *contentKey = nil;
  NSData *nonce = nil;
  if (ecdhSecret == nil ||
      !ALNWebPushDeriveKeys(ecdhSecret, authSecret, userAgentPublicKey, senderPublicKey, recordSalt, &contentKey,
                            &nonce)) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"push key agreement failed");
    return nil;
  }

  NSMutableData *record = [NSMutableData dataWithData:plaintext];
  uint8_t delimiter = 0x02;
  [record appendBytes:&delimiter length:1];
  NSData *tag = nil;
  NSData *ciphertext = ALNWebPushAESGCM(YES, record, contentKey, nonce, nil, &tag);
  if (ciphertext == nil || tag == nil) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"push payload encryption failed");
    return nil;
  }

  NSMutableData *body = [NSMutableData dataWithData:recordSalt];
  uint32_t recordSize = NSSwapHostIntToBig(ALNWebPushRecordSize);
  [body appendBytes:&recordSize length:4];
  uint8_t keyIDLength = 65;
  [body appendBytes:&keyIDLength length:1];
  [body appendData:senderPublicKey];
  [body appendData:ciphertext];
  [body appendData:tag];
  return body;
}

NSData *ALNWebPushDecryptPayload(NSData *body, NSData *userAgentPrivateKey, NSData *authSecret, NSError **error) {
  if ([body length] < ALNWebPushHeaderLength + 17 || [authSecret length] != 16) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidArgument, @"push body or auth secret is malformed");
    return nil;
  }
  const uint8_t *bytes = [body bytes];
  if (bytes[20] != 65) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidArgument, @"push body key ID must be a 65-byte point");
    return nil;
  }
  NSData *salt = [body subdataWithRange:NSMakeRange(0, 16)];
  NSData *senderPublicKey = [body subdataWithRange:NSMakeRange(21, 65)];
  NSData *sealed = [body subdataWithRange:NSMakeRange(ALNWebPushHeaderLength, [body length] - ALNWebPushHeaderLength - 16)];
  NSData *tag = [body subdataWithRange:NSMakeRange([body length] - 16, 16)];

  EVP_PKEY *receiverKey = ALNWebPushCreatePrivateKey(userAgentPrivateKey);
  EVP_PKEY *senderKey = ALNWebPushCreatePublicKey(senderPublicKey);
  NSData *receiverPublicKey = (receiverKey != NULL) ? ALNWebPushPublicPoint(receiverKey) : nil;
  NSData *ecdhSecret = (receiverPublicKey != nil && senderKey != NULL) ? ALNWebPushECDH(receiverKey, senderKey) : nil;
  EVP_PKEY_free(receiverKey);
  EVP_PKEY_free(senderKey);
  NSData *contentKey = nil;
  NSData *nonce = nil;
  if (ecdhSecret == nil ||
      !ALNWebPushDeriveKeys(ecdhSecret, authSecret, receiverPublicKey, senderPublicKey, salt, &contentKey, &nonce)) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"push key agreement failed");
    return nil;
  }
  NSData *record = ALNWebPushAESGCM(NO, sealed, contentKey, nonce, tag, NULL);
  if (record == nil) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"push payload authentication failed");
    return nil;
  }
  NSUInteger end = [record length];
  const uint8_t *recordBytes = [record bytes];
  while (end > 0 && recordBytes[end - 1] == 0x00) {
    end -= 1;
  }
  if (end == 0 || recordBytes[end - 1] != 0x02) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"push record is missing its final-record delimiter");
    return nil;
  }
  return [record subdataWithRange:NSMakeRange(0, end - 1)];
}

#pragma mark - RFC 8030 / RFC 8292

NSString *ALNWebPushAudienceForEndpoint(NSURL *endpoint) {
  NSString *scheme = [[endpoint scheme] lowercaseString];
  NSString *host = [[endpoint host] lowercaseString];
  if ([scheme length] == 0 || [host length] == 0) {
    return nil;
  }
  NSNumber *port = [endpoint port];
  BOOL defaultPort = (port == nil) || ([scheme isEqualToString:@"https"] && [port integerValue] == 443) ||
                     ([scheme isEqualToString:@"http"] && [port integerValue] == 80);
  if ([host containsString:@":"]) {
    host = [NSString stringWithFormat:@"[%@]", host];
  }
  return defaultPort ? [NSString stringWithFormat:@"%@://%@", scheme, host]
                     : [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port];
}

BOOL ALNWebPushTopicIsValid(NSString *topic) {
  if (![topic isKindOfClass:[NSString class]] || [topic length] == 0 || [topic length] > 32) {
    return NO;
  }
  NSCharacterSet *allowed = [NSCharacterSet
      characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
  return [[topic stringByTrimmingCharactersInSet:allowed] length] == 0;
}

// JSON string literal for a claim value; NSJSONSerialization escapes the content.
static NSString *ALNWebPushJSONString(NSString *value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[ value ?: @"" ] options:0 error:NULL];
  NSString *array = (data != nil) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
  if ([array length] < 2) {
    return @"\"\"";
  }
  return [array substringWithRange:NSMakeRange(1, [array length] - 2)];
}

@interface ALNWebPushVAPIDKey () {
  EVP_PKEY *_key;
}
@property(nonatomic, copy, readwrite) NSString *publicKey;
@end

@implementation ALNWebPushVAPIDKey

+ (instancetype)keyWithPublicKey:(NSString *)publicKey privateKey:(NSString *)privateKey error:(NSError **)error {
  NSString *trimmedPublic = [publicKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *trimmedPrivate = [privateKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSData *publicPoint = ([trimmedPublic length] > 0) ? ALNDataFromBase64URLString(trimmedPublic) : nil;
  NSData *scalar = ([trimmedPrivate length] > 0) ? ALNDataFromBase64URLString(trimmedPrivate) : nil;
  if ([publicPoint length] != 65 || [scalar length] != 32) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidKey,
                       @"VAPID keys must be base64url: a 65-byte public point and a 32-byte private key");
    return nil;
  }
  EVP_PKEY *key = ALNWebPushCreatePrivateKey(scalar);
  NSData *derivedPublic = (key != NULL) ? ALNWebPushPublicPoint(key) : nil;
  if (derivedPublic == nil || !ALNConstantTimeDataEquals(derivedPublic, publicPoint)) {
    EVP_PKEY_free(key);
    ALNWebPushSetError(error, ALNWebPushErrorInvalidKey, @"VAPID public key does not match the private key");
    return nil;
  }
  ALNWebPushVAPIDKey *result = [[self alloc] initWithKey:key];
  result.publicKey = ALNBase64URLStringFromData(publicPoint);
  return result;
}

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use +keyWithPublicKey:privateKey:error: to create a VAPID key"];
  return nil;
}

- (instancetype)initWithKey:(EVP_PKEY *)key {
  self = [super init];
  if (self != nil) {
    _key = key;
  }
  return self;
}

- (void)dealloc {
  EVP_PKEY_free(_key);
}

- (NSData *)rawSignatureForData:(NSData *)input {
  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  size_t length = 0;
  NSMutableData *der = nil;
  if (ctx != NULL && EVP_DigestSignInit(ctx, NULL, EVP_sha256(), NULL, _key) == 1 &&
      EVP_DigestSign(ctx, NULL, &length, [input bytes], [input length]) == 1 && length > 0) {
    der = [NSMutableData dataWithLength:length];
    if (EVP_DigestSign(ctx, [der mutableBytes], &length, [input bytes], [input length]) == 1) {
      [der setLength:length];
    } else {
      der = nil;
    }
  }
  EVP_MD_CTX_free(ctx);
  if (der == nil) {
    return nil;
  }
  // JWS ES256 uses the fixed-width r || s form, not DER.
  const unsigned char *cursor = [der bytes];
  ECDSA_SIG *signature = d2i_ECDSA_SIG(NULL, &cursor, (long)[der length]);
  if (signature == NULL) {
    return nil;
  }
  const BIGNUM *r = NULL;
  const BIGNUM *s = NULL;
  ECDSA_SIG_get0(signature, &r, &s);
  uint8_t raw[64];
  BOOL ok = (BN_bn2binpad(r, raw, 32) == 32) && (BN_bn2binpad(s, raw + 32, 32) == 32);
  ECDSA_SIG_free(signature);
  return ok ? [NSData dataWithBytes:raw length:sizeof(raw)] : nil;
}

- (NSString *)signedTokenForAudience:(NSString *)audience
                             subject:(NSString *)subject
                          expiration:(NSDate *)expiration
                               error:(NSError **)error {
  if ([audience length] == 0 || [subject length] == 0 || expiration == nil) {
    ALNWebPushSetError(error, ALNWebPushErrorInvalidArgument, @"VAPID tokens need an audience, subject and expiration");
    return nil;
  }
  NSString *header = @"{\"typ\":\"JWT\",\"alg\":\"ES256\"}";
  NSString *claims = [NSString stringWithFormat:@"{\"aud\":%@,\"exp\":%lld,\"sub\":%@}",
                                                ALNWebPushJSONString(audience),
                                                (long long)floor([expiration timeIntervalSince1970]),
                                                ALNWebPushJSONString(subject)];
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@",
                                                      ALNBase64URLStringFromData([header dataUsingEncoding:NSUTF8StringEncoding]),
                                                      ALNBase64URLStringFromData([claims dataUsingEncoding:NSUTF8StringEncoding])];
  NSData *signature = [self rawSignatureForData:[signingInput dataUsingEncoding:NSUTF8StringEncoding]];
  if (signature == nil) {
    ALNWebPushSetError(error, ALNWebPushErrorCryptoFailed, @"VAPID token signing failed");
    return nil;
  }
  return [NSString stringWithFormat:@"%@.%@", signingInput, ALNBase64URLStringFromData(signature)];
}

- (NSString *)authorizationHeaderForAudience:(NSString *)audience
                                     subject:(NSString *)subject
                                  expiration:(NSDate *)expiration
                                       error:(NSError **)error {
  NSString *token = [self signedTokenForAudience:audience subject:subject expiration:expiration error:error];
  return (token != nil) ? [NSString stringWithFormat:@"vapid t=%@, k=%@", token, self.publicKey] : nil;
}

@end
