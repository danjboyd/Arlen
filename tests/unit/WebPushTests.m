#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <openssl/bn.h>
#import <openssl/ecdsa.h>
#import <openssl/evp.h>

#import "ALNCryptoCompat.h"
#import "ALNSecurityPrimitives.h"
#import "ALNWebPush.h"

// RFC 8291 Appendix A. The RFC wraps these values with whitespace; it is removed here.
static NSString *const WPPlaintext = @"V2hlbiBJIGdyb3cgdXAsIEkgd2FudCB0byBiZSBhIHdhdGVybWVsb24";
static NSString *const WPSenderPrivate = @"yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw";
static NSString *const WPUserAgentPublic =
    @"BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4";
static NSString *const WPUserAgentPrivate = @"q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94";
static NSString *const WPSalt = @"DGv6ra1nlYgDCS1FRnbzlw";
static NSString *const WPAuthSecret = @"BTBZMqHH6r4Tts7J_aSIgg";
static NSString *const WPHeader =
    @"DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8";
static NSString *const WPCiphertext = @"8pfeW0KbunFT06SuDKoJH9Ql87S1QUrdirN6GcG7sFz1y1sqLgVi1VhjVkHsUoEsbI_0LpXMuGvnzQ";

static NSData *WPData(NSString *base64URL) {
  return ALNDataFromBase64URLString(base64URL);
}

@interface WebPushTests : XCTestCase
@end

@implementation WebPushTests

- (NSData *)vectorBody {
  NSMutableData *body = [NSMutableData dataWithData:WPData(WPHeader)];
  [body appendData:WPData(WPCiphertext)];
  return body;
}

- (void)testRFC8291ExampleEncryptionMatchesPublishedBody {
  NSError *error = nil;
  NSData *body = ALNWebPushEncryptPayload(WPData(WPPlaintext), WPData(WPUserAgentPublic), WPData(WPAuthSecret),
                                          WPData(WPSenderPrivate), WPData(WPSalt), &error);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)86, [WPData(WPHeader) length]);
  XCTAssertEqualObjects([self vectorBody], body);
}

- (void)testRFC8291ExampleDecryptsWithUserAgentKey {
  NSError *error = nil;
  NSData *plaintext = ALNWebPushDecryptPayload([self vectorBody], WPData(WPUserAgentPrivate), WPData(WPAuthSecret), &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"When I grow up, I want to be a watermelon",
                        [[NSString alloc] initWithData:plaintext encoding:NSUTF8StringEncoding]);
}

- (void)testFreshKeysAndSaltRoundTripAndDifferEachTime {
  NSDictionary *receiver = ALNWebPushGenerateVAPIDKeyPair(NULL);
  NSData *receiverPublic = WPData(receiver[@"publicKey"]);
  NSData *receiverPrivate = WPData(receiver[@"privateKey"]);
  NSData *auth = ALNSecureRandomData(16);
  NSData *message = [@"{\"title\":\"Your turn\"}" dataUsingEncoding:NSUTF8StringEncoding];

  NSError *error = nil;
  NSData *first = ALNWebPushEncryptPayload(message, receiverPublic, auth, nil, nil, &error);
  NSData *second = ALNWebPushEncryptPayload(message, receiverPublic, auth, nil, nil, &error);
  XCTAssertNil(error);
  XCTAssertNotEqualObjects(first, second);
  XCTAssertEqualObjects(message, ALNWebPushDecryptPayload(first, receiverPrivate, auth, &error));
  XCTAssertEqualObjects(message, ALNWebPushDecryptPayload(second, receiverPrivate, auth, &error));

  NSMutableData *tampered = [first mutableCopy];
  ((uint8_t *)[tampered mutableBytes])[[tampered length] - 1] ^= 0x01;
  XCTAssertNil(ALNWebPushDecryptPayload(tampered, receiverPrivate, auth, &error));
  XCTAssertEqual(ALNWebPushErrorCryptoFailed, error.code);
}

- (void)testPayloadLimitKeepsBodyWithinFourKilobytes {
  NSDictionary *receiver = ALNWebPushGenerateVAPIDKeyPair(NULL);
  NSData *receiverPublic = WPData(receiver[@"publicKey"]);
  NSData *auth = ALNSecureRandomData(16);

  NSError *error = nil;
  NSData *largest = ALNWebPushEncryptPayload([NSMutableData dataWithLength:ALNWebPushMaxPlaintextLength],
                                             receiverPublic, auth, nil, nil, &error);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)4096, [largest length]);

  XCTAssertNil(ALNWebPushEncryptPayload([NSMutableData dataWithLength:ALNWebPushMaxPlaintextLength + 1],
                                        receiverPublic, auth, nil, nil, &error));
  XCTAssertEqualObjects(ALNWebPushErrorDomain, error.domain);
  XCTAssertEqual(ALNWebPushErrorPayloadTooLarge, error.code);
}

- (void)testMalformedSubscriptionKeysAreRejected {
  NSData *message = [@"hi" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *point = WPData(WPUserAgentPublic);
  NSData *auth = WPData(WPAuthSecret);
  NSError *error = nil;

  XCTAssertNil(ALNWebPushEncryptPayload(message, [point subdataWithRange:NSMakeRange(0, 33)], auth, nil, nil, &error));
  XCTAssertEqual(ALNWebPushErrorInvalidSubscription, error.code);

  NSMutableData *offCurve = [point mutableCopy];
  ((uint8_t *)[offCurve mutableBytes])[64] ^= 0x01;
  error = nil;
  XCTAssertNil(ALNWebPushEncryptPayload(message, offCurve, auth, nil, nil, &error));
  XCTAssertEqual(ALNWebPushErrorInvalidSubscription, error.code);

  error = nil;
  XCTAssertNil(ALNWebPushEncryptPayload(message, point, [auth subdataWithRange:NSMakeRange(0, 8)], nil, nil, &error));
  XCTAssertEqual(ALNWebPushErrorInvalidSubscription, error.code);
}

- (void)testVAPIDKeyPairMustMatch {
  NSDictionary *first = ALNWebPushGenerateVAPIDKeyPair(NULL);
  NSDictionary *second = ALNWebPushGenerateVAPIDKeyPair(NULL);
  XCTAssertEqual((NSUInteger)65, [WPData(first[@"publicKey"]) length]);
  XCTAssertEqual((NSUInteger)32, [WPData(first[@"privateKey"]) length]);

  NSError *error = nil;
  XCTAssertNotNil([ALNWebPushVAPIDKey keyWithPublicKey:first[@"publicKey"] privateKey:first[@"privateKey"] error:&error]);
  XCTAssertNil(error);
  XCTAssertNil([ALNWebPushVAPIDKey keyWithPublicKey:second[@"publicKey"] privateKey:first[@"privateKey"] error:&error]);
  XCTAssertEqual(ALNWebPushErrorInvalidKey, error.code);
  XCTAssertNil([ALNWebPushVAPIDKey keyWithPublicKey:@"not-a-key" privateKey:first[@"privateKey"] error:&error]);
  XCTAssertEqual(ALNWebPushErrorInvalidKey, error.code);

  XCTAssertEqualObjects(first[@"publicKey"], ALNWebPushVAPIDPublicKeyForPrivateKey(first[@"privateKey"], NULL));
  XCTAssertEqualObjects(@"BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8",
                        ALNWebPushVAPIDPublicKeyForPrivateKey(WPSenderPrivate, NULL));
  XCTAssertNil(ALNWebPushVAPIDPublicKeyForPrivateKey(@"AAAA", &error));
  XCTAssertEqual(ALNWebPushErrorInvalidKey, error.code);
}

- (void)testVAPIDTokenCarriesClaimsAndVerifiesAgainstPublicKey {
  NSDictionary *pair = ALNWebPushGenerateVAPIDKeyPair(NULL);
  ALNWebPushVAPIDKey *key = [ALNWebPushVAPIDKey keyWithPublicKey:pair[@"publicKey"] privateKey:pair[@"privateKey"] error:NULL];
  NSDate *expiration = [NSDate dateWithTimeIntervalSince1970:1800000000];
  NSError *error = nil;
  NSString *header = [key authorizationHeaderForAudience:@"https://web.push.apple.com"
                                                 subject:@"mailto:ops@example.test"
                                              expiration:expiration
                                                   error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([header hasPrefix:@"vapid t="]);
  NSString *suffix = [NSString stringWithFormat:@", k=%@", pair[@"publicKey"]];
  XCTAssertTrue([header hasSuffix:suffix]);

  NSString *token = [header substringWithRange:NSMakeRange(8, [header length] - 8 - [suffix length])];
  NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
  XCTAssertEqual((NSUInteger)3, [parts count]);
  NSDictionary *jose = [NSJSONSerialization JSONObjectWithData:WPData(parts[0]) options:0 error:NULL];
  NSDictionary *claims = [NSJSONSerialization JSONObjectWithData:WPData(parts[1]) options:0 error:NULL];
  XCTAssertEqualObjects(@"ES256", jose[@"alg"]);
  XCTAssertEqualObjects(@"https://web.push.apple.com", claims[@"aud"]);
  XCTAssertEqualObjects(@"mailto:ops@example.test", claims[@"sub"]);
  XCTAssertEqualObjects(@1800000000, claims[@"exp"]);

  NSData *rawSignature = WPData(parts[2]);
  XCTAssertEqual((NSUInteger)64, [rawSignature length]);
  ECDSA_SIG *signature = ECDSA_SIG_new();
  BIGNUM *r = BN_bin2bn([rawSignature bytes], 32, NULL);
  BIGNUM *s = BN_bin2bn((const unsigned char *)[rawSignature bytes] + 32, 32, NULL);
  ECDSA_SIG_set0(signature, r, s);
  unsigned char *der = NULL;
  int derLength = i2d_ECDSA_SIG(signature, &der);
  ECDSA_SIG_free(signature);

  NSData *point = WPData(pair[@"publicKey"]);
  EVP_PKEY *publicKey = ALNCryptoCreateES256PublicKeyFromCoordinates([point subdataWithRange:NSMakeRange(1, 32)],
                                                                     [point subdataWithRange:NSMakeRange(33, 32)]);
  NSData *signingInput = [[NSString stringWithFormat:@"%@.%@", parts[0], parts[1]] dataUsingEncoding:NSUTF8StringEncoding];
  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  int verified = EVP_DigestVerifyInit(ctx, NULL, EVP_sha256(), NULL, publicKey) == 1 &&
                 EVP_DigestVerify(ctx, der, (size_t)derLength, [signingInput bytes], [signingInput length]) == 1;
  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(publicKey);
  OPENSSL_free(der);
  XCTAssertTrue(verified);
}

- (void)testAudienceIsEndpointOrigin {
  XCTAssertEqualObjects(@"https://web.push.apple.com",
                        ALNWebPushAudienceForEndpoint([NSURL URLWithString:@"https://web.push.apple.com/QGuQ?x=1"]));
  XCTAssertEqualObjects(@"https://fcm.googleapis.com",
                        ALNWebPushAudienceForEndpoint([NSURL URLWithString:@"https://FCM.googleapis.com:443/fcm/send/a"]));
  XCTAssertEqualObjects(@"https://push.example.test:8443",
                        ALNWebPushAudienceForEndpoint([NSURL URLWithString:@"https://push.example.test:8443/a"]));
}

- (void)testTopicValidation {
  XCTAssertTrue(ALNWebPushTopicIsValid(@"ticket-42_confirm"));
  XCTAssertTrue(ALNWebPushTopicIsValid([@"" stringByPaddingToLength:32 withString:@"a" startingAtIndex:0]));
  XCTAssertFalse(ALNWebPushTopicIsValid([@"" stringByPaddingToLength:33 withString:@"a" startingAtIndex:0]));
  XCTAssertFalse(ALNWebPushTopicIsValid(@"has space"));
  XCTAssertFalse(ALNWebPushTopicIsValid(@"slash/"));
  XCTAssertFalse(ALNWebPushTopicIsValid(@""));
}

@end
