#import <Foundation/Foundation.h>
#import <Foundation/NSByteOrder.h>

#import <openssl/bn.h>
#import <openssl/bio.h>
#import <openssl/ec.h>
#import <openssl/evp.h>
#import <openssl/pem.h>
#import <openssl/rsa.h>

#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNLogger.h"
#import "ALNOIDCClient.h"
#import "ALNPasswordHash.h"
#import "ALNPerf.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"
#import "ALNWebAuthn.h"

static void AuditFail(NSString *message) {
  fprintf(stderr, "apple-auth-audit: %s\n", [message UTF8String]);
  exit(1);
}

static void AuditRequire(BOOL condition, NSString *message) {
  if (!condition) {
    AuditFail(message);
  }
}

static NSDictionary *AuditProviderConfiguration(void) {
  return @{
    @"identifier" : @"stub_oidc",
    @"protocol" : @"oidc",
    @"issuer" : @"https://issuer.example.test",
    @"authorizationEndpoint" : @"https://issuer.example.test/authorize",
    @"tokenEndpoint" : @"https://issuer.example.test/token",
    @"clientID" : @"client-123",
    @"clientSecret" : @"client-secret-0123456789abcdef",
    @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
    @"jwksMaxAgeSeconds" : @300,
  };
}

static NSDictionary *AuditValidClaims(NSString *nonce) {
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  return @{
    @"iss" : @"https://issuer.example.test",
    @"sub" : @"provider-user-123",
    @"aud" : @"client-123",
    @"exp" : @((NSInteger)(now + 300)),
    @"iat" : @((NSInteger)now),
    @"nonce" : nonce ?: @"",
    @"email" : @"oidc-user@example.com",
  };
}

static NSDictionary *AuditRSAKeyMaterial(NSString *kid) {
  NSMutableDictionary *material = [NSMutableDictionary dictionary];
  BIGNUM *exponent = BN_new();
  RSA *rsa = RSA_new();
  EVP_PKEY *privateKey = NULL;
  BIO *privateBIO = NULL;
  const BIGNUM *nValue = NULL;
  const BIGNUM *eValue = NULL;
  char *privateBuffer = NULL;

  if (exponent == NULL || rsa == NULL || BN_set_word(exponent, RSA_F4) != 1 ||
      RSA_generate_key_ex(rsa, 2048, exponent, NULL) != 1) {
    BN_free(exponent);
    RSA_free(rsa);
    return material;
  }

  RSA_get0_key(rsa, &nValue, &eValue, NULL);
  if (nValue == NULL || eValue == NULL) {
    BN_free(exponent);
    RSA_free(rsa);
    return material;
  }

  NSMutableData *modulus = [NSMutableData dataWithLength:(NSUInteger)BN_num_bytes(nValue)];
  NSMutableData *exponentData = [NSMutableData dataWithLength:(NSUInteger)BN_num_bytes(eValue)];
  BN_bn2bin(nValue, (unsigned char *)[modulus mutableBytes]);
  BN_bn2bin(eValue, (unsigned char *)[exponentData mutableBytes]);

  privateKey = EVP_PKEY_new();
  if (privateKey == NULL || EVP_PKEY_assign_RSA(privateKey, rsa) != 1) {
    EVP_PKEY_free(privateKey);
    BN_free(exponent);
    RSA_free(rsa);
    return material;
  }
  rsa = NULL;

  privateBIO = BIO_new(BIO_s_mem());
  if (privateBIO == NULL ||
      PEM_write_bio_PrivateKey(privateBIO, privateKey, NULL, NULL, 0, NULL, NULL) != 1) {
    BIO_free(privateBIO);
    EVP_PKEY_free(privateKey);
    BN_free(exponent);
    return material;
  }

  long privateLength = BIO_get_mem_data(privateBIO, &privateBuffer);
  NSString *privateKeyPEM =
      (privateBuffer != NULL && privateLength > 0)
          ? [[NSString alloc] initWithBytes:privateBuffer
                                     length:(NSUInteger)privateLength
                                   encoding:NSUTF8StringEncoding]
          : nil;
  if ([privateKeyPEM length] == 0) {
    BIO_free(privateBIO);
    EVP_PKEY_free(privateKey);
    BN_free(exponent);
    return material;
  }

  material[@"kid"] = kid ?: @"test-key";
  material[@"privateKeyPEM"] = privateKeyPEM;
  material[@"jwk"] = @{
    @"kty" : @"RSA",
    @"alg" : @"RS256",
    @"use" : @"sig",
    @"kid" : kid ?: @"test-key",
    @"n" : ALNBase64URLStringFromData(modulus) ?: @"",
    @"e" : ALNBase64URLStringFromData(exponentData) ?: @"",
  };

  BIO_free(privateBIO);
  EVP_PKEY_free(privateKey);
  BN_free(exponent);
  return material;
}

static NSString *AuditRS256JWT(NSDictionary *claims, NSString *privateKeyPEM, NSString *kid) {
  NSDictionary *header = @{
    @"alg" : @"RS256",
    @"typ" : @"JWT",
    @"kid" : kid ?: @"test-key",
  };
  NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:NULL];
  NSData *claimsData = [NSJSONSerialization dataWithJSONObject:claims options:0 error:NULL];
  NSString *headerPart = ALNBase64URLStringFromData(headerData) ?: @"";
  NSString *claimsPart = ALNBase64URLStringFromData(claimsData) ?: @"";
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, claimsPart];

  BIO *privateBIO = BIO_new_mem_buf((void *)[privateKeyPEM UTF8String], -1);
  EVP_PKEY *privateKey =
      (privateBIO != NULL) ? PEM_read_bio_PrivateKey(privateBIO, NULL, NULL, NULL) : NULL;
  EVP_MD_CTX *ctx = (privateKey != NULL) ? EVP_MD_CTX_new() : NULL;
  NSMutableData *signature = nil;

  if (ctx != NULL &&
      EVP_DigestSignInit(ctx, NULL, EVP_sha256(), NULL, privateKey) == 1 &&
      EVP_DigestSignUpdate(ctx, [signingInput UTF8String], strlen([signingInput UTF8String])) == 1) {
    size_t signatureLength = 0;
    if (EVP_DigestSignFinal(ctx, NULL, &signatureLength) == 1 && signatureLength > 0) {
      signature = [NSMutableData dataWithLength:signatureLength];
      if (EVP_DigestSignFinal(ctx, [signature mutableBytes], &signatureLength) == 1) {
        [signature setLength:signatureLength];
      } else {
        signature = nil;
      }
    }
  }

  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(privateKey);
  BIO_free(privateBIO);

  NSString *signaturePart = ALNBase64URLStringFromData(signature) ?: @"";
  return [NSString stringWithFormat:@"%@.%@.%@", headerPart, claimsPart, signaturePart];
}

static NSData *AuditCBOREncodedLength(uint8_t majorType, uint64_t value) {
  NSMutableData *data = [NSMutableData data];
  if (value < 24) {
    uint8_t byte = (uint8_t)((majorType << 5) | value);
    [data appendBytes:&byte length:1];
    return data;
  }
  if (value <= UINT8_MAX) {
    uint8_t prefix = (uint8_t)((majorType << 5) | 24);
    uint8_t encoded = (uint8_t)value;
    [data appendBytes:&prefix length:1];
    [data appendBytes:&encoded length:1];
    return data;
  }
  if (value <= UINT16_MAX) {
    uint8_t prefix = (uint8_t)((majorType << 5) | 25);
    uint16_t encoded = NSSwapHostShortToBig((uint16_t)value);
    [data appendBytes:&prefix length:1];
    [data appendBytes:&encoded length:2];
    return data;
  }
  if (value <= UINT32_MAX) {
    uint8_t prefix = (uint8_t)((majorType << 5) | 26);
    uint32_t encoded = NSSwapHostIntToBig((uint32_t)value);
    [data appendBytes:&prefix length:1];
    [data appendBytes:&encoded length:4];
    return data;
  }
  uint8_t prefix = (uint8_t)((majorType << 5) | 27);
  uint64_t encoded = NSSwapHostLongLongToBig(value);
  [data appendBytes:&prefix length:1];
  [data appendBytes:&encoded length:8];
  return data;
}

static NSData *AuditCBORUnsigned(uint64_t value) {
  return AuditCBOREncodedLength(0, value);
}

static NSData *AuditCBORNegative(NSInteger value) {
  return AuditCBOREncodedLength(1, (uint64_t)(-1 - value));
}

static NSData *AuditCBORBytes(NSData *bytes) {
  NSMutableData *data = [NSMutableData dataWithData:AuditCBOREncodedLength(2, [bytes length])];
  [data appendData:bytes ?: [NSData data]];
  return data;
}

static NSData *AuditCBORString(NSString *string) {
  NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSMutableData *data = [NSMutableData dataWithData:AuditCBOREncodedLength(3, [utf8 length])];
  [data appendData:utf8];
  return data;
}

static NSData *AuditCBORMap(NSArray *encodedPairs) {
  NSUInteger pairCount = [encodedPairs count] / 2;
  NSMutableData *data = [NSMutableData dataWithData:AuditCBOREncodedLength(5, pairCount)];
  for (NSData *entry in encodedPairs) {
    [data appendData:entry ?: [NSData data]];
  }
  return data;
}

static NSData *AuditSHA256String(NSString *value) {
  return ALNSHA256([value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
}

static NSDictionary *AuditGeneratedKeyMaterial(void) {
  EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  NSMutableDictionary *material = [NSMutableDictionary dictionary];
  if (ecKey == NULL || EC_KEY_generate_key(ecKey) != 1) {
    EC_KEY_free(ecKey);
    return material;
  }

  const EC_GROUP *group = EC_KEY_get0_group(ecKey);
  const EC_POINT *point = EC_KEY_get0_public_key(ecKey);
  BIGNUM *xBN = BN_new();
  BIGNUM *yBN = BN_new();
  if (group != NULL && point != NULL && xBN != NULL && yBN != NULL &&
      EC_POINT_get_affine_coordinates_GFp(group, point, xBN, yBN, NULL) == 1) {
    unsigned char xBytes[32];
    unsigned char yBytes[32];
    BN_bn2binpad(xBN, xBytes, sizeof(xBytes));
    BN_bn2binpad(yBN, yBytes, sizeof(yBytes));
    material[@"x"] = [NSData dataWithBytes:xBytes length:sizeof(xBytes)];
    material[@"y"] = [NSData dataWithBytes:yBytes length:sizeof(yBytes)];
  }

  EVP_PKEY *privateKey = EVP_PKEY_new();
  if (privateKey != NULL && EVP_PKEY_assign_EC_KEY(privateKey, ecKey) == 1) {
    BIO *privateBIO = BIO_new(BIO_s_mem());
    BIO *publicBIO = BIO_new(BIO_s_mem());
    if (privateBIO != NULL && publicBIO != NULL &&
        PEM_write_bio_PrivateKey(privateBIO, privateKey, NULL, NULL, 0, NULL, NULL) == 1 &&
        PEM_write_bio_PUBKEY(publicBIO, privateKey) == 1) {
      char *privateBuffer = NULL;
      char *publicBuffer = NULL;
      long privateLength = BIO_get_mem_data(privateBIO, &privateBuffer);
      long publicLength = BIO_get_mem_data(publicBIO, &publicBuffer);
      if (privateBuffer != NULL && privateLength > 0) {
        material[@"privateKeyPEM"] =
            [[NSString alloc] initWithBytes:privateBuffer
                                     length:(NSUInteger)privateLength
                                   encoding:NSUTF8StringEncoding];
      }
      if (publicBuffer != NULL && publicLength > 0) {
        material[@"publicKeyPEM"] =
            [[NSString alloc] initWithBytes:publicBuffer
                                     length:(NSUInteger)publicLength
                                   encoding:NSUTF8StringEncoding];
      }
    }
    BIO_free(privateBIO);
    BIO_free(publicBIO);
    EVP_PKEY_free(privateKey);
    ecKey = NULL;
  }

  EC_KEY_free(ecKey);
  BN_free(xBN);
  BN_free(yBN);
  return material;
}

static NSData *AuditCOSEKeyFromMaterial(NSDictionary *keyMaterial) {
  return AuditCBORMap(@[
    AuditCBORUnsigned(1), AuditCBORUnsigned(2),
    AuditCBORUnsigned(3), AuditCBORNegative(-7),
    AuditCBORNegative(-1), AuditCBORUnsigned(1),
    AuditCBORNegative(-2), AuditCBORBytes(keyMaterial[@"x"] ?: [NSData data]),
    AuditCBORNegative(-3), AuditCBORBytes(keyMaterial[@"y"] ?: [NSData data]),
  ]);
}

static NSData *AuditAttestationObjectForRPID(NSString *rpID,
                                             NSData *credentialID,
                                             NSDictionary *keyMaterial,
                                             BOOL userVerified,
                                             uint32_t signCount) {
  NSMutableData *authData = [NSMutableData data];
  [authData appendData:AuditSHA256String(rpID) ?: [NSData data]];
  uint8_t flags = (uint8_t)(0x01 | 0x40 | (userVerified ? 0x04 : 0x00));
  [authData appendBytes:&flags length:1];
  uint32_t encodedSignCount = NSSwapHostIntToBig(signCount);
  [authData appendBytes:&encodedSignCount length:4];
  unsigned char aaguid[16] = { 0 };
  [authData appendBytes:aaguid length:sizeof(aaguid)];
  uint16_t credentialLength = NSSwapHostShortToBig((uint16_t)[credentialID length]);
  [authData appendBytes:&credentialLength length:2];
  [authData appendData:credentialID ?: [NSData data]];
  [authData appendData:AuditCOSEKeyFromMaterial(keyMaterial)];

  return AuditCBORMap(@[
    AuditCBORString(@"fmt"), AuditCBORString(@"none"),
    AuditCBORString(@"authData"), AuditCBORBytes(authData),
    AuditCBORString(@"attStmt"), AuditCBORMap(@[]),
  ]);
}

static NSData *AuditAuthenticatorDataForRPID(NSString *rpID, BOOL userVerified, uint32_t signCount) {
  NSMutableData *authData = [NSMutableData data];
  [authData appendData:AuditSHA256String(rpID) ?: [NSData data]];
  uint8_t flags = (uint8_t)(0x01 | (userVerified ? 0x04 : 0x00));
  [authData appendBytes:&flags length:1];
  uint32_t encodedSignCount = NSSwapHostIntToBig(signCount);
  [authData appendBytes:&encodedSignCount length:4];
  return authData;
}

static NSData *AuditSignAssertion(NSString *privateKeyPEM, NSData *signedData) {
  BIO *bio = BIO_new_mem_buf((void *)[privateKeyPEM UTF8String], -1);
  EVP_PKEY *privateKey = (bio != NULL) ? PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL) : NULL;
  EVP_MD_CTX *ctx = (privateKey != NULL) ? EVP_MD_CTX_new() : NULL;
  NSMutableData *signature = nil;

  if (ctx != NULL &&
      EVP_DigestSignInit(ctx, NULL, EVP_sha256(), NULL, privateKey) == 1 &&
      EVP_DigestSignUpdate(ctx, [signedData bytes], [signedData length]) == 1) {
    size_t signatureLength = 0;
    if (EVP_DigestSignFinal(ctx, NULL, &signatureLength) == 1 && signatureLength > 0) {
      signature = [NSMutableData dataWithLength:signatureLength];
      if (EVP_DigestSignFinal(ctx, [signature mutableBytes], &signatureLength) == 1) {
        [signature setLength:signatureLength];
      } else {
        signature = nil;
      }
    }
  }

  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(privateKey);
  BIO_free(bio);
  return signature;
}

static NSDictionary *AuditRegistrationResponse(NSDictionary *options,
                                               NSData *credentialID,
                                               NSDictionary *keyMaterial,
                                               NSString *origin) {
  NSDictionary *clientDataObject = @{
    @"type" : @"webauthn.create",
    @"challenge" : options[@"challenge"] ?: @"",
    @"origin" : origin ?: @"",
  };
  NSData *clientDataJSON =
      [NSJSONSerialization dataWithJSONObject:clientDataObject options:0 error:NULL];
  NSData *attestationObject = AuditAttestationObjectForRPID(@"example.com",
                                                            credentialID,
                                                            keyMaterial,
                                                            YES,
                                                            1);
  NSString *credentialIDString = ALNBase64URLStringFromData(credentialID) ?: @"";
  return @{
    @"id" : credentialIDString,
    @"rawId" : credentialIDString,
    @"type" : @"public-key",
    @"response" : @{
      @"clientDataJSON" : ALNBase64URLStringFromData(clientDataJSON) ?: @"",
      @"attestationObject" : ALNBase64URLStringFromData(attestationObject) ?: @"",
    },
  };
}

static NSDictionary *AuditAssertionResponse(NSDictionary *options,
                                            NSString *credentialID,
                                            NSString *privateKeyPEM,
                                            NSString *origin,
                                            uint32_t signCount) {
  NSDictionary *clientDataObject = @{
    @"type" : @"webauthn.get",
    @"challenge" : options[@"challenge"] ?: @"",
    @"origin" : origin ?: @"",
  };
  NSData *clientDataJSON =
      [NSJSONSerialization dataWithJSONObject:clientDataObject options:0 error:NULL];
  NSData *authenticatorData = AuditAuthenticatorDataForRPID(@"example.com", YES, signCount);
  NSMutableData *signedPayload = [NSMutableData dataWithData:authenticatorData ?: [NSData data]];
  [signedPayload appendData:ALNSHA256(clientDataJSON) ?: [NSData data]];
  NSData *signature = AuditSignAssertion(privateKeyPEM, signedPayload);

  return @{
    @"id" : credentialID ?: @"",
    @"rawId" : credentialID ?: @"",
    @"type" : @"public-key",
    @"response" : @{
      @"clientDataJSON" : ALNBase64URLStringFromData(clientDataJSON) ?: @"",
      @"authenticatorData" : ALNBase64URLStringFromData(authenticatorData) ?: @"",
      @"signature" : ALNBase64URLStringFromData(signature) ?: @"",
    },
  };
}

static ALNContext *AuditFreshContext(void) {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:@"/"
                                               queryString:@""
                                                   headers:@{}
                                                      body:[NSData data]];
  ALNResponse *response = [[ALNResponse alloc] init];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
  return [[ALNContext alloc] initWithRequest:request
                                    response:response
                                      params:@{}
                                       stash:[NSMutableDictionary dictionary]
                                      logger:logger
                                   perfTrace:trace
                                   routeName:@""
                              controllerName:@""
                                  actionName:@""];
}

static void AuditPasswordHash(void) {
  NSError *error = nil;
  ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"s3cr3t-passphrase"
                                                     options:options
                                                       error:&error];
  AuditRequire(encodedHash != nil, @"password hashing returned nil");
  AuditRequire(error == nil, [NSString stringWithFormat:@"password hashing failed: %@", error]);
  AuditRequire([encodedHash hasPrefix:@"$argon2id$v=19$m=19456,t=2,p=1$"],
               @"password hash prefix did not match framework policy");

  error = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordString:@"s3cr3t-passphrase"
                                      againstEncodedHash:encodedHash
                                                   error:&error];
  AuditRequire(verified, @"password verification failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"password verify error: %@", error]);

  error = nil;
  BOOL wrongPassword = [ALNPasswordHash verifyPasswordString:@"wrong-battery"
                                          againstEncodedHash:encodedHash
                                                       error:&error];
  AuditRequire(!wrongPassword, @"wrong password unexpectedly verified");
  AuditRequire(error == nil, @"wrong password produced an unexpected framework error");
}

static void AuditOIDC(void) {
  NSError *error = nil;
  NSDictionary *request = [ALNOIDCClient authorizationRequestForProviderConfiguration:AuditProviderConfiguration()
                                                                          redirectURI:@"https://app.example.test/callback"
                                                                               scopes:nil
                                                                        referenceDate:[NSDate date]
                                                                                error:&error];
  AuditRequire(request != nil, @"OIDC authorization request failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"OIDC authorization error: %@", error]);
  AuditRequire([request[@"state"] length] >= 20, @"OIDC state length was too short");
  AuditRequire([request[@"nonce"] length] >= 20, @"OIDC nonce length was too short");

  NSDictionary *callback = @{
    @"code" : @"stub-code",
    @"state" : request[@"state"] ?: @"",
  };
  NSDictionary *validated = [ALNOIDCClient validateAuthorizationCallbackParameters:callback
                                                                      expectedState:request[@"state"]
                                                                       issuedAtDate:[NSDate date]
                                                                      maxAgeSeconds:300
                                                                              error:&error];
  AuditRequire(validated != nil, @"OIDC callback validation failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"OIDC callback error: %@", error]);

  NSDictionary *keyMaterial = AuditRSAKeyMaterial(@"key-a");
  AuditRequire([keyMaterial[@"privateKeyPEM"] length] > 0, @"failed generating RSA key material for OIDC audit");
  NSDictionary *jwks = @{
    @"keys" : @[ keyMaterial[@"jwk"] ?: @{} ],
    @"fetched_at" : @([[NSDate date] timeIntervalSince1970]),
  };
  NSString *token = AuditRS256JWT(AuditValidClaims(@"nonce-123"), keyMaterial[@"privateKeyPEM"], @"key-a");
  NSDictionary *verifiedToken = [ALNOIDCClient verifyIDToken:token
                                       providerConfiguration:AuditProviderConfiguration()
                                               expectedNonce:@"nonce-123"
                                                jwksDocument:jwks
                                               referenceDate:[NSDate date]
                                                       error:&error];
  AuditRequire(verifiedToken != nil, @"OIDC ID token verification failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"OIDC token verify error: %@", error]);
  AuditRequire([verifiedToken[@"sub"] isEqual:@"provider-user-123"], @"OIDC subject mismatch");
  AuditRequire([verifiedToken[@"email"] isEqual:@"oidc-user@example.com"], @"OIDC email mismatch");
}

static void AuditWebAuthn(void) {
  NSError *error = nil;
  NSDictionary *registrationOptions = [ALNWebAuthn registrationOptionsForRelyingPartyID:@"example.com"
                                                                        relyingPartyName:@"Example"
                                                                                  origin:@"https://example.com"
                                                                          userIdentifier:@"user-123"
                                                                                userName:@"user@example.com"
                                                                         userDisplayName:@"User Example"
                                                                 requireUserVerification:YES
                                                                          timeoutSeconds:300
                                                                                   error:&error];
  AuditRequire(registrationOptions != nil, @"WebAuthn registration options failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"WebAuthn registration options error: %@", error]);

  NSDictionary *keyMaterial = AuditGeneratedKeyMaterial();
  AuditRequire([keyMaterial[@"privateKeyPEM"] length] > 0, @"failed generating EC key material for WebAuthn audit");
  NSData *credentialID = ALNSecureRandomData(32);
  NSDictionary *registrationResponse =
      AuditRegistrationResponse(registrationOptions, credentialID, keyMaterial, @"https://example.com");
  NSDictionary *credential = [ALNWebAuthn verifyRegistrationResponse:registrationResponse
                                                     expectedOptions:registrationOptions
                                                               error:&error];
  AuditRequire(credential != nil, @"WebAuthn registration verification failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"WebAuthn registration verify error: %@", error]);
  AuditRequire([credential[@"publicKeyPEM"] hasPrefix:@"-----BEGIN PUBLIC KEY-----"],
               @"WebAuthn credential did not return a PEM public key");

  NSString *credentialIDString = credential[@"credentialID"];
  NSDictionary *assertionOptions = [ALNWebAuthn assertionOptionsForRelyingPartyID:@"example.com"
                                                                            origin:@"https://example.com"
                                                              allowedCredentialIDs:@[ credentialIDString ?: @"" ]
                                                           requireUserVerification:YES
                                                                    timeoutSeconds:300
                                                                             error:&error];
  AuditRequire(assertionOptions != nil, @"WebAuthn assertion options failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"WebAuthn assertion options error: %@", error]);

  NSDictionary *assertionResponse =
      AuditAssertionResponse(assertionOptions,
                             credentialIDString,
                             keyMaterial[@"privateKeyPEM"],
                             @"https://example.com",
                             3);
  NSDictionary *verifiedAssertion = [ALNWebAuthn verifyAssertionResponse:assertionResponse
                                                         expectedOptions:assertionOptions
                                                       storedCredentialID:credentialIDString
                                                        storedPublicKeyPEM:credential[@"publicKeyPEM"]
                                                        previousSignCount:2
                                                                    error:&error];
  AuditRequire(verifiedAssertion != nil, @"WebAuthn assertion verification failed");
  AuditRequire(error == nil, [NSString stringWithFormat:@"WebAuthn assertion verify error: %@", error]);
  AuditRequire([verifiedAssertion[@"authenticationMethod"] isEqual:@"webauthn"],
               @"WebAuthn authentication method mismatch");

  ALNContext *context = AuditFreshContext();
  BOOL established = [ALNAuthSession establishAuthenticatedSessionForSubject:@"user-123"
                                                                    provider:@"local"
                                                                     methods:@[ @"pwd" ]
                                                              assuranceLevel:1
                                                             authenticatedAt:nil
                                                                     context:context
                                                                       error:&error];
  AuditRequire(established, @"failed establishing auth session for WebAuthn audit");
  AuditRequire(error == nil, [NSString stringWithFormat:@"auth session establish error: %@", error]);

  BOOL elevated = [ALNAuthSession elevateAuthenticatedSessionForMethod:verifiedAssertion[@"authenticationMethod"]
                                                        assuranceLevel:[verifiedAssertion[@"assuranceLevel"] integerValue]
                                                       authenticatedAt:nil
                                                               context:context
                                                                 error:&error];
  AuditRequire(elevated, @"failed elevating auth session with WebAuthn");
  AuditRequire(error == nil, [NSString stringWithFormat:@"auth session elevate error: %@", error]);
  AuditRequire([ALNAuthSession assuranceLevelFromContext:context] == 2,
               @"WebAuthn elevation did not reach assurance level 2");
  AuditRequire([ALNAuthSession isMFAAuthenticatedForContext:context],
               @"WebAuthn elevation did not mark the session as MFA authenticated");
}

int main(void) {
  @autoreleasepool {
    AuditPasswordHash();
    AuditOIDC();
    AuditWebAuthn();
    fprintf(stdout, "apple-auth-audit: passed\n");
  }
  return 0;
}
