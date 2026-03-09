#ifndef ALN_CONFIG_H
#define ALN_CONFIG_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNConfig : NSObject

+ (NSDictionary *)loadConfigAtRoot:(NSString *)rootPath
                       environment:(NSString *)environment
                             error:(NSError *_Nullable *_Nullable)error;
+ (NSDictionary *)loadConfigAtRoot:(NSString *)rootPath
                       environment:(NSString *)environment
                    includeModules:(BOOL)includeModules
                             error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
