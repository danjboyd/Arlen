#ifndef ALN_RECOVERY_CODES_H
#define ALN_RECOVERY_CODES_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNRecoveryCodesErrorDomain;

typedef NS_ENUM(NSInteger, ALNRecoveryCodesErrorCode) {
  ALNRecoveryCodesErrorInvalidArgument = 1,
  ALNRecoveryCodesErrorRandomGenerationFailed = 2,
  ALNRecoveryCodesErrorHashingFailed = 3,
};

@interface ALNRecoveryCodes : NSObject

+ (nullable NSArray *)generateCodesWithCount:(NSUInteger)count
                                       error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray *)generateCodesWithCount:(NSUInteger)count
                               segmentLength:(NSUInteger)segmentLength
                                       error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray *)hashCodes:(NSArray *)codes
                          error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)verifyCode:(NSString *)code
 againstEncodedHash:(NSString *)encodedHash
             error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)consumeCode:(NSString *)code
againstEncodedHashes:(NSArray *)encodedHashes
remainingEncodedHashes:(NSArray *_Nullable *_Nullable)remainingEncodedHashes
             error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
