#ifndef ALN_CRYPTO_COMPAT_H
#define ALN_CRYPTO_COMPAT_H

#import <Foundation/Foundation.h>
#import <openssl/evp.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT EVP_PKEY *_Nullable ALNCryptoCreateRSAPublicKeyFromModulusExponent(NSData *modulusData,
                                                                                      NSData *exponentData);
FOUNDATION_EXPORT EVP_PKEY *_Nullable ALNCryptoCreateES256PublicKeyFromCoordinates(NSData *xData,
                                                                                    NSData *yData);
FOUNDATION_EXPORT EVP_PKEY *_Nullable ALNCryptoGenerateRSAKey(NSUInteger bits);
FOUNDATION_EXPORT EVP_PKEY *_Nullable ALNCryptoGenerateES256Key(void);
FOUNDATION_EXPORT NSString *_Nullable ALNCryptoCopyPEMStringForPrivateKey(EVP_PKEY *key);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *_Nullable ALNCryptoCopyRSAJWK(EVP_PKEY *key,
                                                                              NSString *kid);
FOUNDATION_EXPORT NSDictionary<NSString *, NSData *> *_Nullable ALNCryptoCopyES256PublicKeyCoordinates(EVP_PKEY *key);
FOUNDATION_EXPORT NSString *_Nullable ALNCryptoCopyPublicPEMString(EVP_PKEY *key);

NS_ASSUME_NONNULL_END

#endif
