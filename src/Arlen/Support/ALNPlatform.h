#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNPlatformName(void);
FOUNDATION_EXPORT BOOL ALNPlatformUsesAppleFoundation(void);
FOUNDATION_EXPORT BOOL ALNPlatformUsesGNUstepFoundation(void);
FOUNDATION_EXPORT NSArray<NSString *> *ALNDefaultLibpqCandidatePaths(void);

NS_ASSUME_NONNULL_END
