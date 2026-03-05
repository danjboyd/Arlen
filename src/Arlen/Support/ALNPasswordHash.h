#ifndef ALN_PASSWORD_HASH_H
#define ALN_PASSWORD_HASH_H

#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNPasswordHashErrorDomain;
extern NSString *const ALNPasswordHashUnderlyingArgon2ErrorCodeKey;

typedef NS_ENUM(NSInteger, ALNPasswordHashErrorCode) {
  ALNPasswordHashErrorInvalidArgument = 1,
  ALNPasswordHashErrorUTF8EncodingFailed = 2,
  ALNPasswordHashErrorSaltGenerationFailed = 3,
  ALNPasswordHashErrorHashingFailed = 4,
  ALNPasswordHashErrorMalformedEncodedHash = 5,
  ALNPasswordHashErrorUnsupportedEncodedHash = 6,
  ALNPasswordHashErrorVerificationFailed = 7,
};

typedef struct {
  uint32_t memoryKiB;
  uint32_t iterations;
  uint32_t parallelism;
  uint32_t saltLength;
  uint32_t hashLength;
} ALNArgon2idOptions;

@interface ALNPasswordHash : NSObject

+ (ALNArgon2idOptions)defaultArgon2idOptions;

+ (nullable NSString *)hashPasswordString:(NSString *)password
                                  options:(ALNArgon2idOptions)options
                                    error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)hashPasswordData:(NSData *)passwordData
                                options:(ALNArgon2idOptions)options
                                  error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)verifyPasswordString:(NSString *)password
           againstEncodedHash:(NSString *)encodedHash
                        error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)verifyPasswordData:(NSData *)passwordData
         againstEncodedHash:(NSString *)encodedHash
                      error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)encodedHashNeedsRehash:(NSString *)encodedHash
                       options:(ALNArgon2idOptions)options
                         error:(NSError *_Nullable *_Nullable)error;

+ (NSString *)argon2Version;

@end

NS_ASSUME_NONNULL_END

#endif
