#import "ALNWebAuthn.h"

#import "ALNJSONSerialization.h"
#import "ALNSecurityPrimitives.h"

#import <openssl/bio.h>
#import <openssl/ec.h>
#import <openssl/ecdsa.h>
#import <openssl/evp.h>
#import <openssl/pem.h>

NSString *const ALNWebAuthnErrorDomain = @"Arlen.WebAuthn.Error";

static NSError *ALNWebAuthnError(ALNWebAuthnErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNWebAuthnErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"webauthn failed",
                         }];
}

static NSString *ALNWebAuthnTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

typedef struct {
  NSData *rpIDHash;
  uint8_t flags;
  uint32_t signCount;
  NSData *aaguid;
  NSData *credentialID;
  id credentialPublicKey;
} ALNWebAuthnParsedAuthenticatorData;

typedef struct {
  const uint8_t *bytes;
  NSUInteger length;
  NSUInteger offset;
  NSUInteger depth;
} ALNWebAuthnCBORCursor;

static BOOL ALNWebAuthnParseCBORValue(ALNWebAuthnCBORCursor *cursor, id *value, NSError **error);

static BOOL ALNWebAuthnReadCBORLength(ALNWebAuthnCBORCursor *cursor,
                                      uint8_t additionalInfo,
                                      uint64_t *lengthOut,
                                      NSError **error) {
  if (cursor == NULL || lengthOut == NULL) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"Malformed CBOR length state");
    }
    return NO;
  }
  if (additionalInfo < 24) {
    *lengthOut = additionalInfo;
    return YES;
  }

  NSUInteger byteCount = 0;
  switch (additionalInfo) {
    case 24:
      byteCount = 1;
      break;
    case 25:
      byteCount = 2;
      break;
    case 26:
      byteCount = 4;
      break;
    case 27:
      byteCount = 8;
      break;
    default:
      if (error != NULL) {
        *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR,
                                  @"Indefinite-length CBOR values are not supported");
      }
      return NO;
  }

  if (cursor->offset + byteCount > cursor->length) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"CBOR length exceeds input");
    }
    return NO;
  }

  uint64_t value = 0;
  for (NSUInteger idx = 0; idx < byteCount; idx++) {
    value = (value << 8) | cursor->bytes[cursor->offset + idx];
  }
  cursor->offset += byteCount;
  *lengthOut = value;
  return YES;
}

static BOOL ALNWebAuthnParseCBORMap(ALNWebAuthnCBORCursor *cursor,
                                    uint64_t count,
                                    id *value,
                                    NSError **error) {
  NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)count];
  for (uint64_t idx = 0; idx < count; idx++) {
    id key = nil;
    id item = nil;
    if (!ALNWebAuthnParseCBORValue(cursor, &key, error) ||
        !ALNWebAuthnParseCBORValue(cursor, &item, error)) {
      return NO;
    }
    if (![key conformsToProtocol:@protocol(NSCopying)]) {
      if (error != NULL) {
        *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"CBOR map key is not copyable");
      }
      return NO;
    }
    map[(id<NSCopying>)key] = item ?: [NSNull null];
  }
  *value = [NSDictionary dictionaryWithDictionary:map];
  return YES;
}

static BOOL ALNWebAuthnParseCBORArray(ALNWebAuthnCBORCursor *cursor,
                                      uint64_t count,
                                      id *value,
                                      NSError **error) {
  NSMutableArray *array = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (uint64_t idx = 0; idx < count; idx++) {
    id item = nil;
    if (!ALNWebAuthnParseCBORValue(cursor, &item, error)) {
      return NO;
    }
    [array addObject:item ?: [NSNull null]];
  }
  *value = [NSArray arrayWithArray:array];
  return YES;
}

static BOOL ALNWebAuthnParseCBORValue(ALNWebAuthnCBORCursor *cursor, id *value, NSError **error) {
  if (cursor == NULL || value == NULL || cursor->offset >= cursor->length || cursor->depth > 64) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"Malformed CBOR value");
    }
    return NO;
  }

  uint8_t initial = cursor->bytes[cursor->offset++];
  uint8_t majorType = initial >> 5;
  uint8_t additionalInfo = initial & 0x1F;
  uint64_t length = 0;
  cursor->depth += 1;

  BOOL ok = YES;
  switch (majorType) {
    case 0:
      ok = ALNWebAuthnReadCBORLength(cursor, additionalInfo, &length, error);
      *value = ok ? @(length) : nil;
      break;
    case 1:
      ok = ALNWebAuthnReadCBORLength(cursor, additionalInfo, &length, error);
      *value = ok ? @(-1 - (NSInteger)length) : nil;
      break;
    case 2:
      ok = ALNWebAuthnReadCBORLength(cursor, additionalInfo, &length, error);
      if (ok && cursor->offset + length <= cursor->length) {
        *value = [NSData dataWithBytes:(cursor->bytes + cursor->offset) length:(NSUInteger)length];
        cursor->offset += (NSUInteger)length;
      } else if (ok) {
        ok = NO;
        if (error != NULL) {
          *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"CBOR byte string exceeds input");
        }
      }
      break;
    case 3:
      ok = ALNWebAuthnReadCBORLength(cursor, additionalInfo, &length, error);
      if (ok && cursor->offset + length <= cursor->length) {
        NSData *data = [NSData dataWithBytes:(cursor->bytes + cursor->offset) length:(NSUInteger)length];
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([string length] == 0 && length > 0) {
          ok = NO;
          if (error != NULL) {
            *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"CBOR text string is not valid UTF-8");
          }
        } else {
          *value = string ?: @"";
          cursor->offset += (NSUInteger)length;
        }
      } else if (ok) {
        ok = NO;
        if (error != NULL) {
          *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"CBOR text string exceeds input");
        }
      }
      break;
    case 4:
      ok = ALNWebAuthnReadCBORLength(cursor, additionalInfo, &length, error);
      if (ok) {
        ok = ALNWebAuthnParseCBORArray(cursor, length, value, error);
      }
      break;
    case 5:
      ok = ALNWebAuthnReadCBORLength(cursor, additionalInfo, &length, error);
      if (ok) {
        ok = ALNWebAuthnParseCBORMap(cursor, length, value, error);
      }
      break;
    case 7:
      switch (additionalInfo) {
        case 20:
          *value = @(NO);
          break;
        case 21:
          *value = @(YES);
          break;
        case 22:
          *value = [NSNull null];
          break;
        default:
          ok = NO;
          if (error != NULL) {
            *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR,
                                      @"Unsupported CBOR simple value");
          }
          break;
      }
      break;
    default:
      ok = NO;
      if (error != NULL) {
        *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR,
                                  @"Unsupported CBOR major type");
      }
      break;
  }

  cursor->depth -= 1;
  return ok;
}

static id ALNWebAuthnParseCBOR(NSData *data, NSError **error) {
  if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR, @"CBOR payload is empty");
    }
    return nil;
  }
  ALNWebAuthnCBORCursor cursor;
  cursor.bytes = [data bytes];
  cursor.length = [data length];
  cursor.offset = 0;
  cursor.depth = 0;
  id value = nil;
  if (!ALNWebAuthnParseCBORValue(&cursor, &value, error)) {
    return nil;
  }
  if (cursor.offset != cursor.length) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR,
                                @"CBOR payload contains trailing bytes");
    }
    return nil;
  }
  return value;
}

static BOOL ALNWebAuthnParseAuthenticatorData(NSData *data,
                                              BOOL requireAttestedCredentialData,
                                              ALNWebAuthnParsedAuthenticatorData *parsed,
                                              NSError **error) {
  if (![data isKindOfClass:[NSData class]] || [data length] < 37 || parsed == NULL) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"Authenticator data is malformed");
    }
    return NO;
  }
  const uint8_t *bytes = [data bytes];
  parsed->rpIDHash = [NSData dataWithBytes:bytes length:32];
  parsed->flags = bytes[32];
  parsed->signCount = ((uint32_t)bytes[33] << 24) |
                      ((uint32_t)bytes[34] << 16) |
                      ((uint32_t)bytes[35] << 8) |
                      ((uint32_t)bytes[36]);
  parsed->aaguid = nil;
  parsed->credentialID = nil;
  parsed->credentialPublicKey = nil;

  BOOL hasAttestedCredentialData = (parsed->flags & 0x40) != 0;
  if (!requireAttestedCredentialData) {
    return YES;
  }
  if (!hasAttestedCredentialData || [data length] < 55) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"Registration authenticator data is missing attested credential data");
    }
    return NO;
  }

  NSUInteger offset = 37;
  parsed->aaguid = [NSData dataWithBytes:(bytes + offset) length:16];
  offset += 16;
  uint16_t credentialLength = ((uint16_t)bytes[offset] << 8) | ((uint16_t)bytes[offset + 1]);
  offset += 2;
  if (offset + credentialLength > [data length]) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"Registration credential ID exceeds authenticator data length");
    }
    return NO;
  }
  parsed->credentialID = [NSData dataWithBytes:(bytes + offset) length:credentialLength];
  offset += credentialLength;
  NSData *credentialPublicKeyData =
      [NSData dataWithBytes:(bytes + offset) length:([data length] - offset)];
  NSError *cborError = nil;
  id credentialPublicKey = ALNWebAuthnParseCBOR(credentialPublicKeyData, &cborError);
  if (credentialPublicKey == nil || cborError != nil) {
    if (error != NULL) {
      *error = cborError ?: ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR,
                                             @"Registration credential public key is invalid");
    }
    return NO;
  }
  parsed->credentialPublicKey = credentialPublicKey;
  return YES;
}

static NSString *ALNWebAuthnPublicKeyPEMFromCOSEKey(id keyObject, NSError **error) {
  NSDictionary *key = [keyObject isKindOfClass:[NSDictionary class]] ? keyObject : nil;
  NSNumber *kty = [key[@1] isKindOfClass:[NSNumber class]] ? key[@1] : nil;
  NSNumber *alg = [key[@3] isKindOfClass:[NSNumber class]] ? key[@3] : nil;
  NSNumber *crv = [key[@-1] isKindOfClass:[NSNumber class]] ? key[@-1] : nil;
  NSData *x = [key[@-2] isKindOfClass:[NSData class]] ? key[@-2] : nil;
  NSData *y = [key[@-3] isKindOfClass:[NSData class]] ? key[@-3] : nil;
  if ([kty integerValue] != 2 || [alg integerValue] != -7 || [crv integerValue] != 1 ||
      [x length] != 32 || [y length] != 32) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorUnsupportedCredentialKey,
                                @"Only ES256 P-256 WebAuthn credential keys are supported");
    }
    return nil;
  }

  EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  BIGNUM *xBN = BN_bin2bn([x bytes], (int)[x length], NULL);
  BIGNUM *yBN = BN_bin2bn([y bytes], (int)[y length], NULL);
  const EC_GROUP *group = (ecKey != NULL) ? EC_KEY_get0_group(ecKey) : NULL;
  EC_POINT *point = (group != NULL) ? EC_POINT_new(group) : NULL;
  NSString *pem = nil;

  if (ecKey != NULL && group != NULL && xBN != NULL && yBN != NULL && point != NULL &&
      EC_POINT_set_affine_coordinates_GFp(group, point, xBN, yBN, NULL) == 1 &&
      EC_KEY_set_public_key(ecKey, point) == 1) {
    EVP_PKEY *pkey = EVP_PKEY_new();
    if (pkey != NULL && EVP_PKEY_assign_EC_KEY(pkey, ecKey) == 1) {
      BIO *bio = BIO_new(BIO_s_mem());
      if (bio != NULL && PEM_write_bio_PUBKEY(bio, pkey) == 1) {
        char *buffer = NULL;
        long length = BIO_get_mem_data(bio, &buffer);
        if (buffer != NULL && length > 0) {
          pem = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSUTF8StringEncoding];
        }
      }
      BIO_free(bio);
      EVP_PKEY_free(pkey);
      ecKey = NULL;
    }
  }

  if (ecKey != NULL) {
    EC_KEY_free(ecKey);
  }
  EC_POINT_free(point);
  BN_free(xBN);
  BN_free(yBN);

  if ([pem length] == 0 && error != NULL) {
    *error = ALNWebAuthnError(ALNWebAuthnErrorUnsupportedCredentialKey,
                              @"Failed converting WebAuthn public key to PEM");
  }
  return pem;
}

static BOOL ALNWebAuthnVerifyECDSASignature(NSData *signedData,
                                            NSData *signature,
                                            NSString *publicKeyPEM,
                                            NSError **error) {
  if (![signedData isKindOfClass:[NSData class]] || ![signature isKindOfClass:[NSData class]] ||
      ![publicKeyPEM isKindOfClass:[NSString class]] || [publicKeyPEM length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorInvalidArgument,
                                @"Signature verification requires signed data, signature, and public key");
    }
    return NO;
  }

  BIO *bio = BIO_new_mem_buf((void *)[publicKeyPEM UTF8String], -1);
  EVP_PKEY *pkey = (bio != NULL) ? PEM_read_bio_PUBKEY(bio, NULL, NULL, NULL) : NULL;
  EVP_MD_CTX *ctx = (pkey != NULL) ? EVP_MD_CTX_new() : NULL;
  BOOL verified = NO;

  if (ctx != NULL &&
      EVP_DigestVerifyInit(ctx, NULL, EVP_sha256(), NULL, pkey) == 1 &&
      EVP_DigestVerifyUpdate(ctx, [signedData bytes], [signedData length]) == 1) {
    int status = EVP_DigestVerifyFinal(ctx, [signature bytes], [signature length]);
    verified = (status == 1);
  }

  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(pkey);
  BIO_free(bio);

  if (!verified && error != NULL) {
    *error = ALNWebAuthnError(ALNWebAuthnErrorSignatureVerificationFailed,
                              @"WebAuthn assertion signature verification failed");
  }
  return verified;
}

static NSDictionary *ALNWebAuthnDecodedClientData(NSString *encodedClientDataJSON,
                                                  NSString *expectedType,
                                                  NSString *expectedChallenge,
                                                  NSString *expectedOrigin,
                                                  NSNumber *expiresAt,
                                                  NSError **error) {
  NSData *clientDataJSON = ALNDataFromBase64URLString(encodedClientDataJSON);
  if ([clientDataJSON length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"WebAuthn clientDataJSON is missing or invalid");
    }
    return nil;
  }

  NSError *jsonError = nil;
  NSDictionary *clientData =
      [ALNJSONSerialization JSONObjectWithData:clientDataJSON options:0 error:&jsonError];
  if (![clientData isKindOfClass:[NSDictionary class]] || jsonError != nil) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"WebAuthn clientDataJSON is not valid JSON");
    }
    return nil;
  }

  NSString *type = ALNWebAuthnTrimmedString(clientData[@"type"]);
  NSString *challenge = ALNWebAuthnTrimmedString(clientData[@"challenge"]);
  NSString *origin = ALNWebAuthnTrimmedString(clientData[@"origin"]);
  if (![type isEqualToString:expectedType]) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"WebAuthn clientData type does not match expected ceremony");
    }
    return nil;
  }

  NSData *expectedChallengeData = ALNDataFromBase64URLString(expectedChallenge);
  NSData *actualChallengeData = ALNDataFromBase64URLString(challenge);
  if ([expectedChallengeData length] == 0 || [actualChallengeData length] == 0 ||
      !ALNConstantTimeDataEquals(expectedChallengeData, actualChallengeData)) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorChallengeMismatch,
                                @"WebAuthn challenge does not match expected value");
    }
    return nil;
  }

  if ([origin length] == 0 || ![origin isEqualToString:expectedOrigin]) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorOriginMismatch,
                                @"WebAuthn origin does not match expected origin");
    }
    return nil;
  }

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  if ([expiresAt respondsToSelector:@selector(doubleValue)] && [expiresAt doubleValue] < now) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorChallengeExpired,
                                @"WebAuthn challenge has expired");
    }
    return nil;
  }

  NSMutableDictionary *decoded = [NSMutableDictionary dictionaryWithDictionary:clientData];
  decoded[@"_clientDataJSONData"] = clientDataJSON;
  return decoded;
}

static BOOL ALNWebAuthnValidateFlags(ALNWebAuthnParsedAuthenticatorData parsed,
                                     BOOL requireUserVerification,
                                     NSError **error) {
  BOOL userPresent = (parsed.flags & 0x01) != 0;
  BOOL userVerified = (parsed.flags & 0x04) != 0;
  if (!userPresent) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorUserPresenceRequired,
                                @"WebAuthn user presence flag is required");
    }
    return NO;
  }
  if (requireUserVerification && !userVerified) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorUserVerificationRequired,
                                @"WebAuthn user verification flag is required");
    }
    return NO;
  }
  return YES;
}

static BOOL ALNWebAuthnValidateRPIDHash(ALNWebAuthnParsedAuthenticatorData parsed,
                                        NSString *relyingPartyID,
                                        NSError **error) {
  NSData *expectedHash = ALNSHA256([relyingPartyID dataUsingEncoding:NSUTF8StringEncoding]);
  if ([expectedHash length] == 0 || !ALNConstantTimeDataEquals(expectedHash, parsed.rpIDHash)) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorRPIDMismatch,
                                @"WebAuthn RP ID hash does not match expected RP ID");
    }
    return NO;
  }
  return YES;
}

static NSDictionary *ALNWebAuthnAssertionOrRegistrationOptions(NSString *type,
                                                               NSString *relyingPartyID,
                                                               NSString *origin,
                                                               BOOL requireUserVerification,
                                                               NSUInteger timeoutSeconds) {
  NSString *challenge = ALNBase64URLStringFromData(ALNSecureRandomData(32)) ?: @"";
  NSTimeInterval expiresAt = [[NSDate date] timeIntervalSince1970] +
                             (NSTimeInterval)((timeoutSeconds > 0) ? timeoutSeconds : 300);
  return @{
    @"challenge" : challenge,
    @"rpId" : relyingPartyID ?: @"",
    @"origin" : origin ?: @"",
    @"type" : type ?: @"",
    @"expiresAt" : @((NSInteger)expiresAt),
    @"requireUserVerification" : @(requireUserVerification),
    @"timeoutSeconds" : @((timeoutSeconds > 0) ? timeoutSeconds : 300),
  };
}

@implementation ALNWebAuthn

+ (NSDictionary *)registrationOptionsForRelyingPartyID:(NSString *)relyingPartyID
                                      relyingPartyName:(NSString *)relyingPartyName
                                                origin:(NSString *)origin
                                        userIdentifier:(NSString *)userIdentifier
                                              userName:(NSString *)userName
                                       userDisplayName:(NSString *)userDisplayName
                               requireUserVerification:(BOOL)requireUserVerification
                                        timeoutSeconds:(NSUInteger)timeoutSeconds
                                                 error:(NSError **)error {
  NSString *rpID = ALNWebAuthnTrimmedString(relyingPartyID);
  NSString *rpName = ALNWebAuthnTrimmedString(relyingPartyName);
  NSString *normalizedOrigin = ALNWebAuthnTrimmedString(origin);
  NSString *userID = ALNWebAuthnTrimmedString(userIdentifier);
  NSString *name = ALNWebAuthnTrimmedString(userName);
  NSString *displayName = ALNWebAuthnTrimmedString(userDisplayName) ?: name;
  if ([rpID length] == 0 || [rpName length] == 0 || [normalizedOrigin length] == 0 ||
      [userID length] == 0 || [name length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorInvalidArgument,
                                @"Registration options require RP ID, RP name, origin, user ID, and user name");
    }
    return nil;
  }

  NSDictionary *base = ALNWebAuthnAssertionOrRegistrationOptions(@"webauthn.create",
                                                                 rpID,
                                                                 normalizedOrigin,
                                                                 requireUserVerification,
                                                                 timeoutSeconds);
  NSString *challenge = base[@"challenge"];
  NSData *userIDData = [userID dataUsingEncoding:NSUTF8StringEncoding];
  if ([challenge length] == 0 || [userIDData length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorRandomGenerationFailed,
                                @"Failed generating WebAuthn registration options");
    }
    return nil;
  }
  NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:base];
  options[@"publicKey"] = @{
    @"challenge" : challenge,
    @"rp" : @{
      @"id" : rpID,
      @"name" : rpName,
    },
    @"user" : @{
      @"id" : ALNBase64URLStringFromData(userIDData) ?: @"",
      @"name" : name,
      @"displayName" : displayName ?: name,
    },
    @"pubKeyCredParams" : @[ @{ @"type" : @"public-key", @"alg" : @(-7) } ],
    @"timeout" : @([base[@"timeoutSeconds"] integerValue] * 1000),
    @"attestation" : @"none",
    @"authenticatorSelection" : @{
      @"userVerification" : requireUserVerification ? @"required" : @"preferred",
    },
  };
  return options;
}

+ (NSDictionary *)assertionOptionsForRelyingPartyID:(NSString *)relyingPartyID
                                             origin:(NSString *)origin
                               allowedCredentialIDs:(NSArray *)allowedCredentialIDs
                            requireUserVerification:(BOOL)requireUserVerification
                                     timeoutSeconds:(NSUInteger)timeoutSeconds
                                              error:(NSError **)error {
  NSString *rpID = ALNWebAuthnTrimmedString(relyingPartyID);
  NSString *normalizedOrigin = ALNWebAuthnTrimmedString(origin);
  if ([rpID length] == 0 || [normalizedOrigin length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorInvalidArgument,
                                @"Assertion options require RP ID and origin");
    }
    return nil;
  }

  NSDictionary *base = ALNWebAuthnAssertionOrRegistrationOptions(@"webauthn.get",
                                                                 rpID,
                                                                 normalizedOrigin,
                                                                 requireUserVerification,
                                                                 timeoutSeconds);
  NSString *challenge = base[@"challenge"];
  if ([challenge length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorRandomGenerationFailed,
                                @"Failed generating WebAuthn assertion options");
    }
    return nil;
  }

  NSMutableArray *allowCredentials = [NSMutableArray array];
  for (id value in allowedCredentialIDs ?: @[]) {
    NSString *credentialID = ALNWebAuthnTrimmedString(value);
    if ([credentialID length] == 0) {
      continue;
    }
    [allowCredentials addObject:@{
      @"id" : credentialID,
      @"type" : @"public-key",
    }];
  }

  NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:base];
  options[@"publicKey"] = @{
    @"challenge" : challenge,
    @"rpId" : rpID,
    @"allowCredentials" : allowCredentials,
    @"timeout" : @([base[@"timeoutSeconds"] integerValue] * 1000),
    @"userVerification" : requireUserVerification ? @"required" : @"preferred",
  };
  return options;
}

+ (NSDictionary *)verifyRegistrationResponse:(NSDictionary *)response
                             expectedOptions:(NSDictionary *)expectedOptions
                                       error:(NSError **)error {
  NSDictionary *payload = [response isKindOfClass:[NSDictionary class]] ? response : nil;
  NSDictionary *options = [expectedOptions isKindOfClass:[NSDictionary class]] ? expectedOptions : nil;
  NSString *challenge = ALNWebAuthnTrimmedString(options[@"challenge"]);
  NSString *origin = ALNWebAuthnTrimmedString(options[@"origin"]);
  NSString *relyingPartyID = ALNWebAuthnTrimmedString(options[@"rpId"]);
  BOOL requireUserVerification = [options[@"requireUserVerification"] boolValue];
  if (payload == nil || [challenge length] == 0 || [origin length] == 0 || [relyingPartyID length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorInvalidArgument,
                                @"Registration verification requires a response and expected options");
    }
    return nil;
  }

  NSString *rawID = ALNWebAuthnTrimmedString(payload[@"rawId"]) ?: ALNWebAuthnTrimmedString(payload[@"id"]);
  NSDictionary *responsePayload = [payload[@"response"] isKindOfClass:[NSDictionary class]]
                                      ? payload[@"response"]
                                      : nil;
  NSString *clientDataJSON = ALNWebAuthnTrimmedString(responsePayload[@"clientDataJSON"]);
  NSString *attestationObject = ALNWebAuthnTrimmedString(responsePayload[@"attestationObject"]);
  if ([rawID length] == 0 || responsePayload == nil || [clientDataJSON length] == 0 ||
      [attestationObject length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"Registration response is missing required fields");
    }
    return nil;
  }

  NSDictionary *clientData = ALNWebAuthnDecodedClientData(clientDataJSON,
                                                          @"webauthn.create",
                                                          challenge,
                                                          origin,
                                                          options[@"expiresAt"],
                                                          error);
  if (clientData == nil) {
    return nil;
  }

  NSData *attestationData = ALNDataFromBase64URLString(attestationObject);
  NSError *cborError = nil;
  id attestationValue = ALNWebAuthnParseCBOR(attestationData, &cborError);
  NSDictionary *attestation =
      [attestationValue isKindOfClass:[NSDictionary class]] ? attestationValue : nil;
  if (attestation == nil || cborError != nil) {
    if (error != NULL) {
      *error = cborError ?: ALNWebAuthnError(ALNWebAuthnErrorMalformedCBOR,
                                             @"Attestation object is invalid");
    }
    return nil;
  }

  NSString *format = ALNWebAuthnTrimmedString(attestation[@"fmt"]);
  NSData *authData = [attestation[@"authData"] isKindOfClass:[NSData class]] ? attestation[@"authData"] : nil;
  if (![format isEqualToString:@"none"] || [authData length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorUnsupportedAttestationFormat,
                                @"Only attestation format 'none' is supported");
    }
    return nil;
  }

  ALNWebAuthnParsedAuthenticatorData parsed;
  if (!ALNWebAuthnParseAuthenticatorData(authData, YES, &parsed, error) ||
      !ALNWebAuthnValidateRPIDHash(parsed, relyingPartyID, error) ||
      !ALNWebAuthnValidateFlags(parsed, requireUserVerification, error)) {
    return nil;
  }

  NSString *derivedCredentialID = ALNBase64URLStringFromData(parsed.credentialID);
  if ([derivedCredentialID length] == 0 || ![derivedCredentialID isEqualToString:rawID]) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorCredentialNotAllowed,
                                @"Registration credential ID does not match rawId");
    }
    return nil;
  }

  NSString *publicKeyPEM = ALNWebAuthnPublicKeyPEMFromCOSEKey(parsed.credentialPublicKey, error);
  if ([publicKeyPEM length] == 0) {
    return nil;
  }

  return @{
    @"credentialID" : derivedCredentialID,
    @"publicKeyPEM" : publicKeyPEM,
    @"signCount" : @(parsed.signCount),
    @"aaguid" : ALNLowercaseHexStringFromData(parsed.aaguid) ?: @"",
    @"userPresent" : @((parsed.flags & 0x01) != 0),
    @"userVerified" : @((parsed.flags & 0x04) != 0),
    @"authenticationMethod" : @"webauthn",
    @"assuranceLevel" : @(2),
  };
}

+ (NSDictionary *)verifyAssertionResponse:(NSDictionary *)response
                          expectedOptions:(NSDictionary *)expectedOptions
                        storedCredentialID:(NSString *)storedCredentialID
                         storedPublicKeyPEM:(NSString *)storedPublicKeyPEM
                         previousSignCount:(NSUInteger)previousSignCount
                                     error:(NSError **)error {
  NSDictionary *payload = [response isKindOfClass:[NSDictionary class]] ? response : nil;
  NSDictionary *options = [expectedOptions isKindOfClass:[NSDictionary class]] ? expectedOptions : nil;
  NSString *challenge = ALNWebAuthnTrimmedString(options[@"challenge"]);
  NSString *origin = ALNWebAuthnTrimmedString(options[@"origin"]);
  NSString *relyingPartyID = ALNWebAuthnTrimmedString(options[@"rpId"]);
  BOOL requireUserVerification = [options[@"requireUserVerification"] boolValue];
  NSString *normalizedPublicKeyPEM = ALNWebAuthnTrimmedString(storedPublicKeyPEM);
  if (payload == nil || [challenge length] == 0 || [origin length] == 0 ||
      [relyingPartyID length] == 0 || [normalizedPublicKeyPEM length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorInvalidArgument,
                                @"Assertion verification requires a response, expected options, and stored public key");
    }
    return nil;
  }

  NSString *responseCredentialID =
      ALNWebAuthnTrimmedString(payload[@"rawId"]) ?: ALNWebAuthnTrimmedString(payload[@"id"]);
  NSDictionary *responsePayload = [payload[@"response"] isKindOfClass:[NSDictionary class]]
                                      ? payload[@"response"]
                                      : nil;
  NSString *clientDataJSON = ALNWebAuthnTrimmedString(responsePayload[@"clientDataJSON"]);
  NSString *authenticatorData = ALNWebAuthnTrimmedString(responsePayload[@"authenticatorData"]);
  NSString *signature = ALNWebAuthnTrimmedString(responsePayload[@"signature"]);
  if ([responseCredentialID length] == 0 || responsePayload == nil || [clientDataJSON length] == 0 ||
      [authenticatorData length] == 0 || [signature length] == 0) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorMalformedResponse,
                                @"Assertion response is missing required fields");
    }
    return nil;
  }

  if ([storedCredentialID length] > 0 && ![responseCredentialID isEqualToString:storedCredentialID]) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorCredentialNotAllowed,
                                @"Assertion credential ID does not match the stored credential");
    }
    return nil;
  }

  NSArray *allowedCredentials =
      [options[@"publicKey"][@"allowCredentials"] isKindOfClass:[NSArray class]]
          ? options[@"publicKey"][@"allowCredentials"]
          : @[];
  if ([allowedCredentials count] > 0) {
    BOOL allowed = NO;
    for (id value in allowedCredentials) {
      NSString *credentialID = ALNWebAuthnTrimmedString([value isKindOfClass:[NSDictionary class]] ? value[@"id"] : nil);
      if ([credentialID isEqualToString:responseCredentialID]) {
        allowed = YES;
        break;
      }
    }
    if (!allowed) {
      if (error != NULL) {
        *error = ALNWebAuthnError(ALNWebAuthnErrorCredentialNotAllowed,
                                  @"Assertion credential is not in the allowCredentials set");
      }
      return nil;
    }
  }

  NSDictionary *clientData = ALNWebAuthnDecodedClientData(clientDataJSON,
                                                          @"webauthn.get",
                                                          challenge,
                                                          origin,
                                                          options[@"expiresAt"],
                                                          error);
  if (clientData == nil) {
    return nil;
  }

  NSData *authData = ALNDataFromBase64URLString(authenticatorData);
  ALNWebAuthnParsedAuthenticatorData parsed;
  if (!ALNWebAuthnParseAuthenticatorData(authData, NO, &parsed, error) ||
      !ALNWebAuthnValidateRPIDHash(parsed, relyingPartyID, error) ||
      !ALNWebAuthnValidateFlags(parsed, requireUserVerification, error)) {
    return nil;
  }

  if (previousSignCount > 0 && parsed.signCount <= previousSignCount) {
    if (error != NULL) {
      *error = ALNWebAuthnError(ALNWebAuthnErrorSignCountReplay,
                                @"Assertion sign count did not advance");
    }
    return nil;
  }

  NSData *clientDataJSONData = [clientData[@"_clientDataJSONData"] isKindOfClass:[NSData class]]
                                   ? clientData[@"_clientDataJSONData"]
                                   : nil;
  NSData *clientDataHash = ALNSHA256(clientDataJSONData);
  NSMutableData *signedData = [NSMutableData dataWithData:authData ?: [NSData data]];
  [signedData appendData:clientDataHash ?: [NSData data]];
  NSData *signatureData = ALNDataFromBase64URLString(signature);
  if ([signatureData length] == 0 ||
      !ALNWebAuthnVerifyECDSASignature(signedData, signatureData, normalizedPublicKeyPEM, error)) {
    return nil;
  }

  return @{
    @"credentialID" : responseCredentialID,
    @"signCount" : @(parsed.signCount),
    @"userPresent" : @((parsed.flags & 0x01) != 0),
    @"userVerified" : @((parsed.flags & 0x04) != 0),
    @"authenticationMethod" : @"webauthn",
    @"assuranceLevel" : @(2),
  };
}

@end
