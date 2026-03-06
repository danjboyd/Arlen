#ifndef ALN_TOTP_H
#define ALN_TOTP_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNTOTPErrorDomain;

typedef NS_ENUM(NSInteger, ALNTOTPErrorCode) {
  ALNTOTPErrorInvalidArgument = 1,
  ALNTOTPErrorRandomGenerationFailed = 2,
  ALNTOTPErrorInvalidSecret = 3,
  ALNTOTPErrorInvalidCode = 4,
};

@interface ALNTOTP : NSObject

+ (nullable NSString *)generateSecretWithError:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)generateSecretWithLength:(NSUInteger)length
                                          error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSString *)provisioningURIForSecret:(NSString *)secret
                                    accountName:(NSString *)accountName
                                         issuer:(nullable NSString *)issuer
                                          error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSString *)codeForSecret:(NSString *)secret
                              atDate:(NSDate *)date
                               error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSString *)codeForSecret:(NSString *)secret
                              atDate:(NSDate *)date
                              digits:(NSUInteger)digits
                              period:(NSUInteger)period
                               error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)verifyCode:(NSString *)code
            secret:(NSString *)secret
            atDate:(NSDate *)date
             error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)verifyCode:(NSString *)code
            secret:(NSString *)secret
            atDate:(NSDate *)date
            digits:(NSUInteger)digits
            period:(NSUInteger)period
allowedPastIntervals:(NSUInteger)allowedPastIntervals
allowedFutureIntervals:(NSUInteger)allowedFutureIntervals
             error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
