#ifndef ALN_DATAVERSE_CODEGEN_H
#define ALN_DATAVERSE_CODEGEN_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDataverseCodegenErrorDomain;

typedef NS_ENUM(NSInteger, ALNDataverseCodegenErrorCode) {
  ALNDataverseCodegenErrorInvalidArgument = 1,
  ALNDataverseCodegenErrorInvalidMetadata = 2,
  ALNDataverseCodegenErrorIdentifierCollision = 3,
};

@interface ALNDataverseCodegen : NSObject

+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromMetadata:(NSDictionary<NSString *, id> *)metadata
                                                           classPrefix:(NSString *)classPrefix
                                                       dataverseTarget:(nullable NSString *)dataverseTarget
                                                                 error:(NSError *_Nullable *_Nullable)error;

@end

FOUNDATION_EXPORT NSError *ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorCode code,
                                                        NSString *message,
                                                        NSDictionary *_Nullable userInfo);

NS_ASSUME_NONNULL_END

#endif
