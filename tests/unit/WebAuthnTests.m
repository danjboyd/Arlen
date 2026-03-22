#import <Foundation/Foundation.h>
#import <Foundation/NSByteOrder.h>
#import <XCTest/XCTest.h>

#import <openssl/bio.h>
#import <openssl/ec.h>
#import <openssl/evp.h>
#import <openssl/pem.h>

#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"
#import "ALNWebAuthn.h"

static NSData *WACBOREncodedLength(uint8_t majorType, uint64_t value) {
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

static NSData *WACBORUnsigned(uint64_t value) {
  return WACBOREncodedLength(0, value);
}

static NSData *WACBORNegative(NSInteger value) {
  return WACBOREncodedLength(1, (uint64_t)(-1 - value));
}

static NSData *WACBORBytes(NSData *bytes) {
  NSMutableData *data = [NSMutableData dataWithData:WACBOREncodedLength(2, [bytes length])];
  [data appendData:bytes ?: [NSData data]];
  return data;
}

static NSData *WACBORString(NSString *string) {
  NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSMutableData *data = [NSMutableData dataWithData:WACBOREncodedLength(3, [utf8 length])];
  [data appendData:utf8];
  return data;
}

static NSData *WACBORMap(NSArray *encodedPairs) {
  NSUInteger pairCount = [encodedPairs count] / 2;
  NSMutableData *data = [NSMutableData dataWithData:WACBOREncodedLength(5, pairCount)];
  for (NSData *entry in encodedPairs) {
    [data appendData:entry ?: [NSData data]];
  }
  return data;
}

static NSData *WASHA256String(NSString *value) {
  return ALNSHA256([value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
}

static NSDictionary *WAGeneratedKeyMaterial(void) {
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

static NSData *WACOSEKeyFromMaterial(NSDictionary *keyMaterial) {
  return WACBORMap(@[
    WACBORUnsigned(1), WACBORUnsigned(2),
    WACBORUnsigned(3), WACBORNegative(-7),
    WACBORNegative(-1), WACBORUnsigned(1),
    WACBORNegative(-2), WACBORBytes(keyMaterial[@"x"] ?: [NSData data]),
    WACBORNegative(-3), WACBORBytes(keyMaterial[@"y"] ?: [NSData data]),
  ]);
}

static NSData *WAAttestationObjectForRPID(NSString *rpID,
                                          NSData *credentialID,
                                          NSDictionary *keyMaterial,
                                          BOOL userVerified,
                                          uint32_t signCount) {
  NSMutableData *authData = [NSMutableData data];
  [authData appendData:WASHA256String(rpID) ?: [NSData data]];
  uint8_t flags = (uint8_t)(0x01 | 0x40 | (userVerified ? 0x04 : 0x00));
  [authData appendBytes:&flags length:1];
  uint32_t encodedSignCount = NSSwapHostIntToBig(signCount);
  [authData appendBytes:&encodedSignCount length:4];
  unsigned char aaguid[16] = { 0 };
  [authData appendBytes:aaguid length:sizeof(aaguid)];
  uint16_t credentialLength = NSSwapHostShortToBig((uint16_t)[credentialID length]);
  [authData appendBytes:&credentialLength length:2];
  [authData appendData:credentialID ?: [NSData data]];
  [authData appendData:WACOSEKeyFromMaterial(keyMaterial)];

  return WACBORMap(@[
    WACBORString(@"fmt"), WACBORString(@"none"),
    WACBORString(@"authData"), WACBORBytes(authData),
    WACBORString(@"attStmt"), WACBORMap(@[]),
  ]);
}

static NSData *WAAuthenticatorDataForRPID(NSString *rpID, BOOL userVerified, uint32_t signCount) {
  NSMutableData *authData = [NSMutableData data];
  [authData appendData:WASHA256String(rpID) ?: [NSData data]];
  uint8_t flags = (uint8_t)(0x01 | (userVerified ? 0x04 : 0x00));
  [authData appendBytes:&flags length:1];
  uint32_t encodedSignCount = NSSwapHostIntToBig(signCount);
  [authData appendBytes:&encodedSignCount length:4];
  return authData;
}

static NSData *WASignAssertion(NSString *privateKeyPEM, NSData *signedData) {
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

@interface WebAuthnTests : XCTestCase
@end

@implementation WebAuthnTests

- (NSDictionary *)registrationOptionsWithOrigin:(NSString *)origin {
  NSError *error = nil;
  NSDictionary *options = [ALNWebAuthn registrationOptionsForRelyingPartyID:@"example.com"
                                                           relyingPartyName:@"Example"
                                                                     origin:origin
                                                             userIdentifier:@"user-123"
                                                                   userName:@"user@example.com"
                                                            userDisplayName:@"User Example"
                                                    requireUserVerification:YES
                                                             timeoutSeconds:300
                                                                      error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([options isKindOfClass:[NSDictionary class]]);
  return options ?: @{};
}

- (NSDictionary *)assertionOptionsForCredentialID:(NSString *)credentialID origin:(NSString *)origin {
  NSError *error = nil;
  NSDictionary *options = [ALNWebAuthn assertionOptionsForRelyingPartyID:@"example.com"
                                                                  origin:origin
                                                    allowedCredentialIDs:@[ credentialID ?: @"" ]
                                                 requireUserVerification:YES
                                                          timeoutSeconds:300
                                                                   error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([options isKindOfClass:[NSDictionary class]]);
  return options ?: @{};
}

- (NSDictionary *)registrationResponseForOptions:(NSDictionary *)options
                                     credentialID:(NSData *)credentialID
                                      keyMaterial:(NSDictionary *)keyMaterial
                                           origin:(NSString *)origin {
  NSDictionary *clientDataObject = @{
    @"type" : @"webauthn.create",
    @"challenge" : options[@"challenge"] ?: @"",
    @"origin" : origin ?: @"",
  };
  NSData *clientDataJSON =
      [NSJSONSerialization dataWithJSONObject:clientDataObject options:0 error:NULL];
  NSData *attestationObject = WAAttestationObjectForRPID(@"example.com",
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

- (NSDictionary *)assertionResponseForOptions:(NSDictionary *)options
                                  credentialID:(NSString *)credentialID
                                privateKeyPEM:(NSString *)privateKeyPEM
                                        origin:(NSString *)origin
                                     signCount:(uint32_t)signCount {
  NSDictionary *clientDataObject = @{
    @"type" : @"webauthn.get",
    @"challenge" : options[@"challenge"] ?: @"",
    @"origin" : origin ?: @"",
  };
  NSData *clientDataJSON =
      [NSJSONSerialization dataWithJSONObject:clientDataObject options:0 error:NULL];
  NSData *authenticatorData = WAAuthenticatorDataForRPID(@"example.com", YES, signCount);
  NSMutableData *signedPayload = [NSMutableData dataWithData:authenticatorData ?: [NSData data]];
  [signedPayload appendData:ALNSHA256(clientDataJSON) ?: [NSData data]];
  NSData *signature = WASignAssertion(privateKeyPEM, signedPayload);

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

- (ALNContext *)freshContext {
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

- (void)testRegistrationVerificationExtractsCredentialAndPublicKey {
  NSDictionary *keyMaterial = WAGeneratedKeyMaterial();
  NSData *credentialID = ALNSecureRandomData(32);
  NSDictionary *options = [self registrationOptionsWithOrigin:@"https://example.com"];
  NSDictionary *response =
      [self registrationResponseForOptions:options
                               credentialID:credentialID
                                keyMaterial:keyMaterial
                                     origin:@"https://example.com"];

  NSError *error = nil;
  NSDictionary *verified = [ALNWebAuthn verifyRegistrationResponse:response
                                                   expectedOptions:options
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(ALNBase64URLStringFromData(credentialID), verified[@"credentialID"]);
  XCTAssertTrue([verified[@"publicKeyPEM"] hasPrefix:@"-----BEGIN PUBLIC KEY-----"]);
  XCTAssertEqualObjects(@2, verified[@"assuranceLevel"]);
}

- (void)testRegistrationVerificationRejectsOriginMismatch {
  NSDictionary *keyMaterial = WAGeneratedKeyMaterial();
  NSData *credentialID = ALNSecureRandomData(32);
  NSDictionary *options = [self registrationOptionsWithOrigin:@"https://example.com"];
  NSDictionary *response =
      [self registrationResponseForOptions:options
                               credentialID:credentialID
                                keyMaterial:keyMaterial
                                     origin:@"https://evil.example"];

  NSError *error = nil;
  NSDictionary *verified = [ALNWebAuthn verifyRegistrationResponse:response
                                                   expectedOptions:options
                                                             error:&error];
  XCTAssertNil(verified);
  XCTAssertEqual(ALNWebAuthnErrorOriginMismatch, error.code);
}

- (void)testAssertionVerificationRejectsExpiredChallenge {
  NSDictionary *keyMaterial = WAGeneratedKeyMaterial();
  NSData *credentialIDData = ALNSecureRandomData(32);
  NSDictionary *registrationOptions = [self registrationOptionsWithOrigin:@"https://example.com"];
  NSDictionary *registrationResponse =
      [self registrationResponseForOptions:registrationOptions
                               credentialID:credentialIDData
                                keyMaterial:keyMaterial
                                     origin:@"https://example.com"];
  NSDictionary *credential = [ALNWebAuthn verifyRegistrationResponse:registrationResponse
                                                     expectedOptions:registrationOptions
                                                               error:NULL];
  NSString *credentialID = credential[@"credentialID"];

  NSMutableDictionary *assertionOptions =
      [[self assertionOptionsForCredentialID:credentialID origin:@"https://example.com"] mutableCopy];
  assertionOptions[@"expiresAt"] = @((NSInteger)[[NSDate date] timeIntervalSince1970] - 1);
  NSDictionary *assertionResponse =
      [self assertionResponseForOptions:assertionOptions
                            credentialID:credentialID
                          privateKeyPEM:keyMaterial[@"privateKeyPEM"]
                                  origin:@"https://example.com"
                               signCount:2];

  NSError *error = nil;
  NSDictionary *verified = [ALNWebAuthn verifyAssertionResponse:assertionResponse
                                                expectedOptions:assertionOptions
                                              storedCredentialID:credentialID
                                               storedPublicKeyPEM:credential[@"publicKeyPEM"]
                                               previousSignCount:1
                                                           error:&error];
  XCTAssertNil(verified);
  XCTAssertEqual(ALNWebAuthnErrorChallengeExpired, error.code);
}

- (void)testAssertionVerificationRejectsSignCountReplay {
  NSDictionary *keyMaterial = WAGeneratedKeyMaterial();
  NSData *credentialIDData = ALNSecureRandomData(32);
  NSDictionary *registrationOptions = [self registrationOptionsWithOrigin:@"https://example.com"];
  NSDictionary *registrationResponse =
      [self registrationResponseForOptions:registrationOptions
                               credentialID:credentialIDData
                                keyMaterial:keyMaterial
                                     origin:@"https://example.com"];
  NSDictionary *credential = [ALNWebAuthn verifyRegistrationResponse:registrationResponse
                                                     expectedOptions:registrationOptions
                                                               error:NULL];
  NSString *credentialID = credential[@"credentialID"];
  NSDictionary *assertionOptions =
      [self assertionOptionsForCredentialID:credentialID origin:@"https://example.com"];
  NSDictionary *assertionResponse =
      [self assertionResponseForOptions:assertionOptions
                            credentialID:credentialID
                          privateKeyPEM:keyMaterial[@"privateKeyPEM"]
                                  origin:@"https://example.com"
                               signCount:2];

  NSError *error = nil;
  NSDictionary *verified = [ALNWebAuthn verifyAssertionResponse:assertionResponse
                                                expectedOptions:assertionOptions
                                              storedCredentialID:credentialID
                                               storedPublicKeyPEM:credential[@"publicKeyPEM"]
                                               previousSignCount:2
                                                           error:&error];
  XCTAssertNil(verified);
  XCTAssertEqual(ALNWebAuthnErrorSignCountReplay, error.code);
}

- (void)testSuccessfulAssertionCanElevateAuthenticatedSession {
  NSDictionary *keyMaterial = WAGeneratedKeyMaterial();
  NSData *credentialIDData = ALNSecureRandomData(32);
  NSDictionary *registrationOptions = [self registrationOptionsWithOrigin:@"https://example.com"];
  NSDictionary *registrationResponse =
      [self registrationResponseForOptions:registrationOptions
                               credentialID:credentialIDData
                                keyMaterial:keyMaterial
                                     origin:@"https://example.com"];
  NSDictionary *credential = [ALNWebAuthn verifyRegistrationResponse:registrationResponse
                                                     expectedOptions:registrationOptions
                                                               error:NULL];
  NSString *credentialID = credential[@"credentialID"];
  NSDictionary *assertionOptions =
      [self assertionOptionsForCredentialID:credentialID origin:@"https://example.com"];
  NSDictionary *assertionResponse =
      [self assertionResponseForOptions:assertionOptions
                            credentialID:credentialID
                          privateKeyPEM:keyMaterial[@"privateKeyPEM"]
                                  origin:@"https://example.com"
                               signCount:3];

  NSError *error = nil;
  NSDictionary *verified = [ALNWebAuthn verifyAssertionResponse:assertionResponse
                                                expectedOptions:assertionOptions
                                              storedCredentialID:credentialID
                                               storedPublicKeyPEM:credential[@"publicKeyPEM"]
                                               previousSignCount:2
                                                           error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"webauthn", verified[@"authenticationMethod"]);
  XCTAssertEqualObjects(@2, verified[@"assuranceLevel"]);

  ALNContext *context = [self freshContext];
  XCTAssertTrue([ALNAuthSession establishAuthenticatedSessionForSubject:@"user-123"
                                                               provider:@"local"
                                                                methods:@[ @"pwd" ]
                                                         assuranceLevel:1
                                                        authenticatedAt:nil
                                                                context:context
                                                                  error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [ALNAuthSession assuranceLevelFromContext:context]);

  XCTAssertTrue([ALNAuthSession elevateAuthenticatedSessionForMethod:verified[@"authenticationMethod"]
                                                      assuranceLevel:[verified[@"assuranceLevel"] integerValue]
                                                     authenticatedAt:nil
                                                             context:context
                                                               error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [ALNAuthSession assuranceLevelFromContext:context]);
  XCTAssertTrue([[ALNAuthSession authenticationMethodsFromContext:context] containsObject:@"webauthn"]);
  XCTAssertTrue([ALNAuthSession isMFAAuthenticatedForContext:context]);
}

@end
