#ifndef ALN_MIME_TYPES_H
#define ALN_MIME_TYPES_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Extension -> Content-Type table shared by static mounts and controller file
// responses. Extensions are matched case-insensitively without the leading dot.
// Overrides map extensions to Content-Type values and win over the defaults;
// apps supply them through the `mimeTypes` config dictionary.
@interface ALNMIMETypes : NSObject

+ (NSDictionary<NSString *, NSString *> *)defaultTypes;
+ (nullable NSString *)typeForExtension:(NSString *)extension;
+ (nullable NSString *)typeForExtension:(NSString *)extension
                              overrides:(nullable NSDictionary *)overrides;
+ (NSString *)contentTypeForFilePath:(NSString *)filePath;
+ (NSString *)contentTypeForFilePath:(NSString *)filePath
                           overrides:(nullable NSDictionary *)overrides;

@end

NS_ASSUME_NONNULL_END

#endif
