#ifndef ALN_MULTIPART_H
#define ALN_MULTIPART_H
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
extern NSString *const ALNMultipartErrorDomain;
typedef NS_ENUM(NSInteger, ALNMultipartErrorCode) {
  ALNMultipartErrorMalformed = 1,
  ALNMultipartErrorTruncated = 2,
  ALNMultipartErrorLimitExceeded = 3,
  ALNMultipartErrorSpoolFailed = 4,
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
// Set when the file part was larger than `requestLimits.spoolThresholdBytes` and
// was written to a private temporary file instead of memory; nil otherwise. The
// file is removed when the request ends, so move or copy it before then. `data`
// maps the file on each access rather than holding the bytes in memory.
@property(nonatomic, copy, readonly, nullable) NSString *temporaryFilePath;
// The caller chooses the destination. originalFilename is never used as a path.
// A spooled upload is moved (renamed, or copied across filesystems) the first
// time; afterwards `data` reads from `path` and later writes copy it.
- (BOOL)writeToFile:(NSString *)path error:(NSError *_Nullable *_Nullable)error;
@end

// Internal parsing entrypoint; request clients normally use ALNRequest accessors.
@interface ALNMultipart : NSObject
+ (NSDictionary *)defaultLimits;
+ (nullable NSArray<ALNMultipartPart *> *)parseBody:(NSData *)body
                                     contentType:(NSString *)contentType
                                          limits:(NSDictionary *)limits
                                           error:(NSError *_Nullable *_Nullable)error;
// Spools file parts larger than `limits[spoolThresholdBytes]` (default 1 MiB) into
// a new private directory under `limits[spoolDirectory]` (default the system temp
// directory), returned through `spoolDirectory`. The caller owns and must remove
// it; nothing is left behind when parsing fails. The method above never spools.
+ (nullable NSArray<ALNMultipartPart *> *)parseBody:(NSData *)body
                                     contentType:(NSString *)contentType
                                          limits:(NSDictionary *)limits
                                  spoolDirectory:(NSString *_Nullable *_Nullable)spoolDirectory
                                           error:(NSError *_Nullable *_Nullable)error;
@end
NS_ASSUME_NONNULL_END
#endif
