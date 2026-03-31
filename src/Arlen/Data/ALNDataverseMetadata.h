#ifndef ALN_DATAVERSE_METADATA_H
#define ALN_DATAVERSE_METADATA_H

#import <Foundation/Foundation.h>

#import "ALNDataverseClient.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDataverseMetadataErrorDomain;

typedef NS_ENUM(NSInteger, ALNDataverseMetadataErrorCode) {
  ALNDataverseMetadataErrorInvalidArgument = 1,
  ALNDataverseMetadataErrorInvalidResponse = 2,
  ALNDataverseMetadataErrorFetchFailed = 3,
};

@interface ALNDataverseMetadata : NSObject

+ (nullable NSDictionary<NSString *, id> *)normalizedMetadataFromPayload:(id)payload
                                                                   error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary<NSString *, id> *)fetchNormalizedMetadataWithClient:(ALNDataverseClient *)client
                                                                logicalNames:(nullable NSArray<NSString *> *)logicalNames
                                                                       error:(NSError *_Nullable *_Nullable)error;

@end

FOUNDATION_EXPORT NSError *ALNDataverseMetadataMakeError(ALNDataverseMetadataErrorCode code,
                                                         NSString *message,
                                                         NSDictionary *_Nullable userInfo);

NS_ASSUME_NONNULL_END

#endif
