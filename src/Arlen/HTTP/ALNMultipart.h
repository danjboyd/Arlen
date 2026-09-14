#ifndef ALN_MULTIPART_H
#define ALN_MULTIPART_H
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
extern NSString *const ALNMultipartErrorDomain;
typedef NS_ENUM(NSInteger, ALNMultipartErrorCode) {
  ALNMultipartErrorMalformed = 1,
  ALNMultipartErrorTruncated = 2,
  ALNMultipartErrorLimitExceeded = 3,
};

// Parts and their data are immutable and ordered as received.
@interface ALNMultipartPart : NSObject
@property(nonatomic, copy, readonly) NSString *fieldName;
@property(nonatomic, copy, readonly, nullable) NSString *originalFilename;
@property(nonatomic, copy, readonly) NSString *contentType;
@property(nonatomic, copy, readonly) NSData *data;
@property(nonatomic, assign, readonly) NSUInteger size;
@property(nonatomic, copy, readonly, nullable) NSString *text;
@end

@interface ALNUpload : ALNMultipartPart
// The caller chooses the destination. originalFilename is never used as a path.
- (BOOL)writeToFile:(NSString *)path error:(NSError *_Nullable *_Nullable)error;
@end

// Internal parsing entrypoint; request clients normally use ALNRequest accessors.
@interface ALNMultipart : NSObject
+ (NSDictionary *)defaultLimits;
+ (nullable NSArray<ALNMultipartPart *> *)parseBody:(NSData *)body
                                     contentType:(NSString *)contentType
                                          limits:(NSDictionary *)limits
                                           error:(NSError *_Nullable *_Nullable)error;
@end
NS_ASSUME_NONNULL_END
#endif
