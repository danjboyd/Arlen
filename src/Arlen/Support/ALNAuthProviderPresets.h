#ifndef ALN_AUTH_PROVIDER_PRESETS_H
#define ALN_AUTH_PROVIDER_PRESETS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAuthProviderPresetsErrorDomain;

typedef NS_ENUM(NSInteger, ALNAuthProviderPresetsErrorCode) {
  ALNAuthProviderPresetsErrorInvalidPreset = 1,
  ALNAuthProviderPresetsErrorInvalidConfiguration = 2,
};

@interface ALNAuthProviderPresets : NSObject

+ (NSDictionary *)availablePresets;
+ (nullable NSDictionary *)presetNamed:(NSString *)presetName
                                 error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary *)providerConfigurationFromPresetNamed:(NSString *)presetName
                                                      overrides:(nullable NSDictionary *)overrides
                                                          error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary *)normalizedProvidersFromConfiguration:(NSDictionary *)providersConfiguration
                                                          error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
