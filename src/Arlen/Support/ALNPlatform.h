#ifndef ALN_PLATFORM_H
#define ALN_PLATFORM_H

#import <Foundation/Foundation.h>
#import "../ALNExports.h"

NS_ASSUME_NONNULL_BEGIN

ALN_EXPORT double ALNPlatformNowMilliseconds(void);
ALN_EXPORT NSString *ALNPlatformISO8601Now(void);
ALN_EXPORT NSInteger ALNPlatformProcessIdentifier(void);
ALN_EXPORT void ALNPlatformSleepMilliseconds(NSUInteger milliseconds);
ALN_EXPORT BOOL ALNPlatformPathIsAbsolute(NSString *path);

NS_ASSUME_NONNULL_END

#endif
