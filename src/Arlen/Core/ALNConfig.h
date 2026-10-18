#ifndef ALN_CONFIG_H
#define ALN_CONFIG_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ALNEnvironmentKind) {
  ALNEnvironmentKindDevelopment = 0,
  ALNEnvironmentKindTest = 1,
  // Every other name (production, staging, preview, ...) is production-like.
  ALNEnvironmentKindProduction = 2,
};

// Classifies an environment name, ignoring case and surrounding whitespace, so
// "Development" and "development" mean the same thing everywhere.
FOUNDATION_EXPORT ALNEnvironmentKind ALNEnvironmentKindForName(NSString *_Nullable name);
// YES for development and test, the environments that get developer-facing
// behaviour (detailed error pages, tolerating a module that fails to load).
FOUNDATION_EXPORT BOOL ALNEnvironmentIsDevelopmentLike(NSString *_Nullable name);
// The canonical spelling of an environment name: trimmed and lowercased, with
// an empty name meaning "development". Config loading uses it to pick
// config/environments/<name>.plist, and it is what application.environment
// and config[@"environment"] hold.
FOUNDATION_EXPORT NSString *ALNNormalizedEnvironmentName(NSString *_Nullable name);

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
