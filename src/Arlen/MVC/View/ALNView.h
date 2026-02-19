#ifndef ALN_VIEW_H
#define ALN_VIEW_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNView : NSObject

+ (NSString *)normalizeTemplateLogicalPath:(NSString *)templateName;
+ (nullable NSString *)renderTemplate:(NSString *)templateName
                              context:(nullable NSDictionary *)context
                               layout:(nullable NSString *)layoutName
                                error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)renderTemplate:(NSString *)templateName
                              context:(nullable NSDictionary *)context
                               layout:(nullable NSString *)layoutName
                         strictLocals:(BOOL)strictLocals
                      strictStringify:(BOOL)strictStringify
                                error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
