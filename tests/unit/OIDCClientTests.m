#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <openssl/bn.h>
#import <openssl/evp.h>
#import <openssl/pem.h>
#import <openssl/rsa.h>

#import "ALNAuthProviderPresets.h"
#import "ALNOIDCClient.h"
#import "ALNSecurityPrimitives.h"

static NSDictionary *OIDCTestRSAKeyMaterial(NSString *kid) {
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

  NSData *modulus = [NSMutableData dataWithLength:(NSUInteger)BN_num_bytes(nValue)];
  NSData *exponentData = [NSMutableData dataWithLength:(NSUInteger)BN_num_bytes(eValue)];
  BN_bn2bin(nValue, (unsigned char *)[(NSMutableData *)modulus mutableBytes]);
  BN_bn2bin(eValue, (unsigned char *)[(NSMutableData *)exponentData mutableBytes]);

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

static NSString *OIDCTestRS256JWT(NSDictionary *claims, NSString *privateKeyPEM, NSString *kid) {
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

@interface OIDCClientTests : XCTestCase
@end

@implementation OIDCClientTests

- (NSDictionary *)providerConfiguration {
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

- (NSDictionary *)fixturePayload {
  NSString *path = @"tests/fixtures/auth/phase12_oidc_cases.json";
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data);
  NSError *error = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([payload isKindOfClass:[NSDictionary class]]);
  return payload ?: @{};
}

- (NSDictionary *)validClaimsWithNonce:(NSString *)nonce {
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

- (void)testAuthorizationRequestIncludesPKCEStateNonceAndChallenge {
  NSError *error = nil;
  NSDictionary *request = [ALNOIDCClient authorizationRequestForProviderConfiguration:[self providerConfiguration]
                                                                          redirectURI:@"https://app.example.test/callback"
                                                                               scopes:nil
                                                                        referenceDate:[NSDate dateWithTimeIntervalSince1970:1700000000]
                                                                                error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([request[@"authorizationURL"] containsString:@"response_type=code"]);
  XCTAssertTrue([request[@"authorizationURL"] containsString:@"code_challenge_method=S256"]);
  XCTAssertTrue([request[@"authorizationURL"] containsString:@"scope=openid%20email%20profile"]);
  XCTAssertTrue([request[@"state"] length] >= 20);
  XCTAssertTrue([request[@"nonce"] length] >= 20);
  XCTAssertTrue([request[@"codeVerifier"] length] >= 30);
  XCTAssertTrue([request[@"codeChallenge"] length] >= 30);

  NSDictionary *callback = @{
    @"code" : @"stub-code",
    @"state" : request[@"state"] ?: @"",
  };
  NSDictionary *validated = [ALNOIDCClient validateAuthorizationCallbackParameters:callback
                                                                      expectedState:request[@"state"]
                                                                       issuedAtDate:[NSDate date]
                                                                      maxAgeSeconds:300
                                                                              error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"stub-code", validated[@"code"]);
}

- (void)testCallbackRejectsTamperedStateAndFixtureListsScenario {
  NSDictionary *payload = [self fixturePayload];
  NSArray *scenarios = [payload[@"scenarios"] isKindOfClass:[NSArray class]] ? payload[@"scenarios"] : @[];
  NSMutableSet *scenarioIDs = [NSMutableSet set];
  for (NSDictionary *entry in scenarios) {
    if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"id"] isKindOfClass:[NSString class]]) {
      [scenarioIDs addObject:entry[@"id"]];
    }
  }
  XCTAssertTrue([scenarioIDs containsObject:@"callback_tampered_state"]);

  NSError *error = nil;
  NSDictionary *request = [ALNOIDCClient authorizationRequestForProviderConfiguration:[self providerConfiguration]
                                                                          redirectURI:@"https://app.example.test/callback"
                                                                               scopes:nil
                                                                        referenceDate:[NSDate date]
                                                                                error:&error];
  XCTAssertNil(error);

  NSDictionary *callback = @{
    @"code" : @"stub-code",
    @"state" : @"tampered-state",
  };
  NSDictionary *validated = [ALNOIDCClient validateAuthorizationCallbackParameters:callback
                                                                      expectedState:request[@"state"]
                                                                       issuedAtDate:[NSDate date]
                                                                      maxAgeSeconds:300
                                                                              error:&error];
  XCTAssertNil(validated);
  XCTAssertEqual(ALNOIDCClientErrorCallbackStateMismatch, error.code);
}

- (void)testTokenExchangeRequestRedactsClientSecretDeterministically {
  NSError *error = nil;
  NSDictionary *request =
      [ALNOIDCClient tokenExchangeRequestForProviderConfiguration:[self providerConfiguration]
                                               authorizationCode:@"stub-code"
                                                     redirectURI:@"https://app.example.test/callback"
                                                    codeVerifier:@"verifier"
                                                           error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"POST", request[@"method"]);
  XCTAssertTrue([request[@"bodyString"] containsString:@"grant_type=authorization_code"]);
  XCTAssertTrue([request[@"redactedDescription"] containsString:@"client_secret=[REDACTED]"]);
  XCTAssertFalse([request[@"redactedDescription"] containsString:@"client-secret-0123456789abcdef"]);
}

- (void)testVerifyRS256IDTokenAcceptsMatchingJWKAndNonce {
  NSDictionary *keyMaterial = OIDCTestRSAKeyMaterial(@"key-a");
  NSDictionary *jwks = @{
    @"keys" : @[ keyMaterial[@"jwk"] ?: @{} ],
    @"fetched_at" : @([[NSDate date] timeIntervalSince1970]),
  };
  NSDictionary *claims = [self validClaimsWithNonce:@"nonce-123"];
  NSString *token = OIDCTestRS256JWT(claims, keyMaterial[@"privateKeyPEM"], @"key-a");

  NSError *error = nil;
  NSDictionary *verified = [ALNOIDCClient verifyIDToken:token
                                  providerConfiguration:[self providerConfiguration]
                                          expectedNonce:@"nonce-123"
                                           jwksDocument:jwks
                                          referenceDate:[NSDate date]
                                                  error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"provider-user-123", verified[@"sub"]);
  XCTAssertEqualObjects(@"oidc-user@example.com", verified[@"email"]);
}

- (void)testVerifyRS256IDTokenRejectsNonceMismatch {
  NSDictionary *payload = [self fixturePayload];
  NSArray *scenarios = [payload[@"scenarios"] isKindOfClass:[NSArray class]] ? payload[@"scenarios"] : @[];
  NSMutableSet *scenarioIDs = [NSMutableSet set];
  for (NSDictionary *entry in scenarios) {
    if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"id"] isKindOfClass:[NSString class]]) {
      [scenarioIDs addObject:entry[@"id"]];
    }
  }
  XCTAssertTrue([scenarioIDs containsObject:@"nonce_mismatch"]);

  NSDictionary *keyMaterial = OIDCTestRSAKeyMaterial(@"key-a");
  NSDictionary *jwks = @{
    @"keys" : @[ keyMaterial[@"jwk"] ?: @{} ],
    @"fetched_at" : @([[NSDate date] timeIntervalSince1970]),
  };
  NSDictionary *claims = [self validClaimsWithNonce:@"nonce-from-provider"];
  NSString *token = OIDCTestRS256JWT(claims, keyMaterial[@"privateKeyPEM"], @"key-a");

  NSError *error = nil;
  NSDictionary *verified = [ALNOIDCClient verifyIDToken:token
                                  providerConfiguration:[self providerConfiguration]
                                          expectedNonce:@"different-nonce"
                                           jwksDocument:jwks
                                          referenceDate:[NSDate date]
                                                  error:&error];
  XCTAssertNil(verified);
  XCTAssertEqual(ALNOIDCClientErrorNonceMismatch, error.code);
}

- (void)testVerifyRS256IDTokenRejectsMissingRotatedKeyDeterministically {
  NSDictionary *payload = [self fixturePayload];
  NSArray *scenarios = [payload[@"scenarios"] isKindOfClass:[NSArray class]] ? payload[@"scenarios"] : @[];
  NSMutableSet *scenarioIDs = [NSMutableSet set];
  for (NSDictionary *entry in scenarios) {
    if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"id"] isKindOfClass:[NSString class]]) {
      [scenarioIDs addObject:entry[@"id"]];
    }
  }
  XCTAssertTrue([scenarioIDs containsObject:@"jwks_rotation_miss"]);

  NSDictionary *signingKey = OIDCTestRSAKeyMaterial(@"signing-key");
  NSDictionary *differentKey = OIDCTestRSAKeyMaterial(@"different-key");
  NSDictionary *jwks = @{
    @"keys" : @[ differentKey[@"jwk"] ?: @{} ],
    @"fetched_at" : @([[NSDate date] timeIntervalSince1970]),
  };
  NSString *token = OIDCTestRS256JWT([self validClaimsWithNonce:@"nonce-123"],
                                     signingKey[@"privateKeyPEM"],
                                     @"signing-key");

  NSError *error = nil;
  NSDictionary *verified = [ALNOIDCClient verifyIDToken:token
                                  providerConfiguration:[self providerConfiguration]
                                          expectedNonce:@"nonce-123"
                                           jwksDocument:jwks
                                          referenceDate:[NSDate date]
                                                  error:&error];
  XCTAssertNil(verified);
  XCTAssertEqual(ALNOIDCClientErrorJWKNotFound, error.code);
}

- (void)testVerifyRS256IDTokenRejectsExpiredJWKSDocument {
  NSDictionary *payload = [self fixturePayload];
  NSArray *scenarios = [payload[@"scenarios"] isKindOfClass:[NSArray class]] ? payload[@"scenarios"] : @[];
  NSMutableSet *scenarioIDs = [NSMutableSet set];
  for (NSDictionary *entry in scenarios) {
    if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"id"] isKindOfClass:[NSString class]]) {
      [scenarioIDs addObject:entry[@"id"]];
    }
  }
  XCTAssertTrue([scenarioIDs containsObject:@"jwks_expired"]);

  NSDictionary *keyMaterial = OIDCTestRSAKeyMaterial(@"key-a");
  NSDictionary *jwks = @{
    @"keys" : @[ keyMaterial[@"jwk"] ?: @{} ],
    @"fetched_at" : @([[NSDate dateWithTimeIntervalSinceNow:-600] timeIntervalSince1970]),
  };
  NSString *token = OIDCTestRS256JWT([self validClaimsWithNonce:@"nonce-123"],
                                     keyMaterial[@"privateKeyPEM"],
                                     @"key-a");

  NSError *error = nil;
  NSDictionary *verified = [ALNOIDCClient verifyIDToken:token
                                  providerConfiguration:[self providerConfiguration]
                                          expectedNonce:@"nonce-123"
                                           jwksDocument:jwks
                                          referenceDate:[NSDate date]
                                                  error:&error];
  XCTAssertNil(verified);
  XCTAssertEqual(ALNOIDCClientErrorJWKSExpired, error.code);
}

- (void)testProviderPresetsMergeDeterministicallyAndNormalizeIdentifiers {
  NSError *error = nil;
  NSDictionary *providers = [ALNAuthProviderPresets normalizedProvidersFromConfiguration:@{
    @"google" : @{
      @"clientID" : @"google-client",
      @"clientSecret" : @"google-secret",
      @"defaultScopes" : @[ @"openid", @"email" ],
      @"extraAuthorizationParameters" : @{
        @"prompt" : @"consent",
      },
    },
    @"backoffice" : @{
      @"preset" : @"okta",
      @"identifier" : @"backoffice_okta",
      @"issuer" : @"https://acme.okta.com/oauth2/default",
    },
  }
                                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"https://accounts.google.com/o/oauth2/v2/auth",
                        providers[@"google"][@"authorizationEndpoint"]);
  NSArray *expectedScopes = @[ @"openid", @"email" ];
  XCTAssertEqualObjects(expectedScopes, providers[@"google"][@"defaultScopes"]);
  XCTAssertEqualObjects(@"consent",
                        providers[@"google"][@"extraAuthorizationParameters"][@"prompt"]);
  XCTAssertEqualObjects(@"backoffice_okta", providers[@"backoffice"][@"identifier"]);
  XCTAssertEqualObjects(@"https://acme.okta.com/oauth2/default", providers[@"backoffice"][@"issuer"]);
}

@end
