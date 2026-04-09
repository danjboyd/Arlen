#import "ALNCryptoCompat.h"

#import <openssl/bn.h>
#import <openssl/bio.h>
#include <openssl/crypto.h>
#import <openssl/ec.h>
#import <openssl/pem.h>
#import <openssl/rsa.h>

#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
#include <openssl/core_names.h>
#include <openssl/params.h>
#include <openssl/param_build.h>
#endif

#import "ALNSecurityPrimitives.h"

static NSString *ALNCryptoStringFromBIO(BIO *bio) {
  if (bio == NULL) {
    return nil;
  }
  char *buffer = NULL;
  long length = BIO_get_mem_data(bio, &buffer);
  if (buffer == NULL || length <= 0) {
    return nil;
  }
  return [[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSUTF8StringEncoding];
}

static NSData *ALNCryptoDataFromBIGNUM(const BIGNUM *value) {
  if (value == NULL) {
    return nil;
  }
  int length = BN_num_bytes(value);
  if (length <= 0) {
    return nil;
  }
  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
  BN_bn2bin(value, (unsigned char *)[data mutableBytes]);
  return data;
}

EVP_PKEY *ALNCryptoCreateRSAPublicKeyFromModulusExponent(NSData *modulusData, NSData *exponentData) {
  if ([modulusData length] == 0 || [exponentData length] == 0) {
    return NULL;
  }

#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  BIGNUM *modulus = BN_bin2bn([modulusData bytes], (int)[modulusData length], NULL);
  BIGNUM *exponent = BN_bin2bn([exponentData bytes], (int)[exponentData length], NULL);
  EVP_PKEY *key = NULL;
  OSSL_PARAM_BLD *builder = NULL;
  OSSL_PARAM *params = NULL;
  EVP_PKEY_CTX *ctx = NULL;

  if (modulus == NULL || exponent == NULL) {
    BN_free(modulus);
    BN_free(exponent);
    return NULL;
  }

  builder = OSSL_PARAM_BLD_new();
  if (builder == NULL ||
      OSSL_PARAM_BLD_push_BN(builder, OSSL_PKEY_PARAM_RSA_N, modulus) != 1 ||
      OSSL_PARAM_BLD_push_BN(builder, OSSL_PKEY_PARAM_RSA_E, exponent) != 1) {
    OSSL_PARAM_BLD_free(builder);
    BN_free(modulus);
    BN_free(exponent);
    return NULL;
  }

  params = OSSL_PARAM_BLD_to_param(builder);
  ctx = EVP_PKEY_CTX_new_from_name(NULL, "RSA", NULL);
  if (params == NULL || ctx == NULL || EVP_PKEY_fromdata_init(ctx) != 1 ||
      EVP_PKEY_fromdata(ctx, &key, EVP_PKEY_PUBLIC_KEY, params) != 1) {
    key = NULL;
  }

  EVP_PKEY_CTX_free(ctx);
  OSSL_PARAM_free(params);
  OSSL_PARAM_BLD_free(builder);
  BN_free(modulus);
  BN_free(exponent);
  return key;
#else
  BIGNUM *modulus = BN_bin2bn([modulusData bytes], (int)[modulusData length], NULL);
  BIGNUM *exponent = BN_bin2bn([exponentData bytes], (int)[exponentData length], NULL);
  RSA *rsa = RSA_new();
  EVP_PKEY *key = NULL;

  if (modulus == NULL || exponent == NULL || rsa == NULL ||
      RSA_set0_key(rsa, modulus, exponent, NULL) != 1) {
    BN_free(modulus);
    BN_free(exponent);
    RSA_free(rsa);
    return NULL;
  }

  key = EVP_PKEY_new();
  if (key == NULL || EVP_PKEY_assign_RSA(key, rsa) != 1) {
    EVP_PKEY_free(key);
    RSA_free(rsa);
    return NULL;
  }
  return key;
#endif
}

EVP_PKEY *ALNCryptoCreateES256PublicKeyFromCoordinates(NSData *xData, NSData *yData) {
  if ([xData length] != 32 || [yData length] != 32) {
    return NULL;
  }

#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  uint8_t publicKeyBytes[65];
  publicKeyBytes[0] = 0x04;
  memcpy(publicKeyBytes + 1, [xData bytes], 32);
  memcpy(publicKeyBytes + 33, [yData bytes], 32);

  EVP_PKEY *key = NULL;
  OSSL_PARAM params[] = {
    OSSL_PARAM_construct_utf8_string(OSSL_PKEY_PARAM_GROUP_NAME, "prime256v1", 0),
    OSSL_PARAM_construct_octet_string(OSSL_PKEY_PARAM_PUB_KEY, publicKeyBytes, sizeof(publicKeyBytes)),
    OSSL_PARAM_construct_end()
  };
  EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL);
  if (ctx == NULL || EVP_PKEY_fromdata_init(ctx) != 1 ||
      EVP_PKEY_fromdata(ctx, &key, EVP_PKEY_PUBLIC_KEY, params) != 1) {
    key = NULL;
  }
  EVP_PKEY_CTX_free(ctx);
  return key;
#else
  EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  BIGNUM *xBN = BN_bin2bn([xData bytes], (int)[xData length], NULL);
  BIGNUM *yBN = BN_bin2bn([yData bytes], (int)[yData length], NULL);
  const EC_GROUP *group = (ecKey != NULL) ? EC_KEY_get0_group(ecKey) : NULL;
  EC_POINT *point = (group != NULL) ? EC_POINT_new(group) : NULL;
  EVP_PKEY *key = NULL;

  if (ecKey != NULL && group != NULL && point != NULL && xBN != NULL && yBN != NULL &&
      EC_POINT_set_affine_coordinates_GFp(group, point, xBN, yBN, NULL) == 1 &&
      EC_KEY_set_public_key(ecKey, point) == 1) {
    key = EVP_PKEY_new();
    if (key == NULL || EVP_PKEY_assign_EC_KEY(key, ecKey) != 1) {
      EVP_PKEY_free(key);
      key = NULL;
    } else {
      ecKey = NULL;
    }
  }

  EC_KEY_free(ecKey);
  EC_POINT_free(point);
  BN_free(xBN);
  BN_free(yBN);
  return key;
#endif
}

EVP_PKEY *ALNCryptoGenerateRSAKey(NSUInteger bits) {
#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_name(NULL, "RSA", NULL);
  EVP_PKEY *key = NULL;
  if (ctx == NULL || EVP_PKEY_keygen_init(ctx) != 1 ||
      EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, (int)((bits > 0) ? bits : 2048)) != 1 ||
      EVP_PKEY_keygen(ctx, &key) != 1) {
    key = NULL;
  }
  EVP_PKEY_CTX_free(ctx);
  return key;
#else
  BIGNUM *exponent = BN_new();
  RSA *rsa = RSA_new();
  EVP_PKEY *key = NULL;
  if (exponent == NULL || rsa == NULL || BN_set_word(exponent, RSA_F4) != 1 ||
      RSA_generate_key_ex(rsa, (int)((bits > 0) ? bits : 2048), exponent, NULL) != 1) {
    BN_free(exponent);
    RSA_free(rsa);
    return NULL;
  }
  key = EVP_PKEY_new();
  if (key == NULL || EVP_PKEY_assign_RSA(key, rsa) != 1) {
    EVP_PKEY_free(key);
    RSA_free(rsa);
    key = NULL;
  }
  BN_free(exponent);
  return key;
#endif
}

EVP_PKEY *ALNCryptoGenerateES256Key(void) {
#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL);
  EVP_PKEY *key = NULL;
  OSSL_PARAM params[] = {
    OSSL_PARAM_construct_utf8_string(OSSL_PKEY_PARAM_GROUP_NAME, "prime256v1", 0),
    OSSL_PARAM_construct_end()
  };
  if (ctx == NULL || EVP_PKEY_keygen_init(ctx) != 1 ||
      EVP_PKEY_CTX_set_params(ctx, params) != 1 ||
      EVP_PKEY_keygen(ctx, &key) != 1) {
    key = NULL;
  }
  EVP_PKEY_CTX_free(ctx);
  return key;
#else
  EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  EVP_PKEY *key = NULL;
  if (ecKey == NULL || EC_KEY_generate_key(ecKey) != 1) {
    EC_KEY_free(ecKey);
    return NULL;
  }
  key = EVP_PKEY_new();
  if (key == NULL || EVP_PKEY_assign_EC_KEY(key, ecKey) != 1) {
    EVP_PKEY_free(key);
    EC_KEY_free(ecKey);
    return NULL;
  }
  return key;
#endif
}

NSString *ALNCryptoCopyPEMStringForPrivateKey(EVP_PKEY *key) {
  BIO *bio = BIO_new(BIO_s_mem());
  NSString *pem = nil;
  if (bio != NULL && key != NULL &&
      PEM_write_bio_PrivateKey(bio, key, NULL, NULL, 0, NULL, NULL) == 1) {
    pem = ALNCryptoStringFromBIO(bio);
  }
  BIO_free(bio);
  return pem;
}

NSDictionary<NSString *, id> *ALNCryptoCopyRSAJWK(EVP_PKEY *key, NSString *kid) {
  if (key == NULL) {
    return nil;
  }

  NSData *modulusData = nil;
  NSData *exponentData = nil;

#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  BIGNUM *modulus = NULL;
  BIGNUM *exponent = NULL;
  if (EVP_PKEY_get_bn_param(key, OSSL_PKEY_PARAM_RSA_N, &modulus) != 1 ||
      EVP_PKEY_get_bn_param(key, OSSL_PKEY_PARAM_RSA_E, &exponent) != 1) {
    BN_free(modulus);
    BN_free(exponent);
    return nil;
  }
  modulusData = ALNCryptoDataFromBIGNUM(modulus);
  exponentData = ALNCryptoDataFromBIGNUM(exponent);
  BN_free(modulus);
  BN_free(exponent);
#else
  RSA *rsa = EVP_PKEY_get1_RSA(key);
  const BIGNUM *modulus = NULL;
  const BIGNUM *exponent = NULL;
  if (rsa == NULL) {
    return nil;
  }
  RSA_get0_key(rsa, &modulus, &exponent, NULL);
  modulusData = ALNCryptoDataFromBIGNUM(modulus);
  exponentData = ALNCryptoDataFromBIGNUM(exponent);
  RSA_free(rsa);
#endif

  if ([modulusData length] == 0 || [exponentData length] == 0) {
    return nil;
  }

  return @{
    @"kty" : @"RSA",
    @"alg" : @"RS256",
    @"use" : @"sig",
    @"kid" : kid ?: @"test-key",
    @"n" : ALNBase64URLStringFromData(modulusData) ?: @"",
    @"e" : ALNBase64URLStringFromData(exponentData) ?: @"",
  };
}

NSDictionary<NSString *, NSData *> *ALNCryptoCopyES256PublicKeyCoordinates(EVP_PKEY *key) {
  if (key == NULL) {
    return nil;
  }

#if defined(OPENSSL_VERSION_MAJOR) && OPENSSL_VERSION_MAJOR >= 3
  uint8_t publicKeyBytes[65];
  size_t length = sizeof(publicKeyBytes);
  if (EVP_PKEY_get_octet_string_param(key, OSSL_PKEY_PARAM_PUB_KEY, publicKeyBytes, sizeof(publicKeyBytes),
                                      &length) != 1 ||
      length != sizeof(publicKeyBytes) || publicKeyBytes[0] != 0x04) {
    return nil;
  }
  return @{
    @"x" : [NSData dataWithBytes:publicKeyBytes + 1 length:32],
    @"y" : [NSData dataWithBytes:publicKeyBytes + 33 length:32],
  };
#else
  EC_KEY *ecKey = EVP_PKEY_get1_EC_KEY(key);
  const EC_GROUP *group = (ecKey != NULL) ? EC_KEY_get0_group(ecKey) : NULL;
  const EC_POINT *point = (ecKey != NULL) ? EC_KEY_get0_public_key(ecKey) : NULL;
  BIGNUM *xBN = BN_new();
  BIGNUM *yBN = BN_new();
  NSDictionary<NSString *, NSData *> *coordinates = nil;
  if (group != NULL && point != NULL && xBN != NULL && yBN != NULL &&
      EC_POINT_get_affine_coordinates_GFp(group, point, xBN, yBN, NULL) == 1) {
    unsigned char xBytes[32];
    unsigned char yBytes[32];
    if (BN_bn2binpad(xBN, xBytes, sizeof(xBytes)) == sizeof(xBytes) &&
        BN_bn2binpad(yBN, yBytes, sizeof(yBytes)) == sizeof(yBytes)) {
      coordinates = @{
        @"x" : [NSData dataWithBytes:xBytes length:sizeof(xBytes)],
        @"y" : [NSData dataWithBytes:yBytes length:sizeof(yBytes)],
      };
    }
  }
  BN_free(xBN);
  BN_free(yBN);
  EC_KEY_free(ecKey);
  return coordinates;
#endif
}

NSString *ALNCryptoCopyPublicPEMString(EVP_PKEY *key) {
  BIO *bio = BIO_new(BIO_s_mem());
  NSString *pem = nil;
  if (bio != NULL && key != NULL && PEM_write_bio_PUBKEY(bio, key) == 1) {
    pem = ALNCryptoStringFromBIO(bio);
  }
  BIO_free(bio);
  return pem;
}
