#ifndef ALN_PLATFORM_H
#define ALN_PLATFORM_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT double ALNPlatformNowMilliseconds(void);
FOUNDATION_EXPORT NSString *ALNPlatformISO8601Now(void);
FOUNDATION_EXPORT NSInteger ALNPlatformProcessIdentifier(void);
FOUNDATION_EXPORT void ALNPlatformSleepMilliseconds(NSUInteger milliseconds);
FOUNDATION_EXPORT BOOL ALNPlatformPathIsAbsolute(NSString *path);

NS_ASSUME_NONNULL_END

#endif
