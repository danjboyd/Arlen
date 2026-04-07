#ifndef ALN_PLATFORM_H
#define ALN_PLATFORM_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

double ALNPlatformNowMilliseconds(void);
NSString *ALNPlatformISO8601Now(void);
NSInteger ALNPlatformProcessIdentifier(void);
void ALNPlatformSleepMilliseconds(NSUInteger milliseconds);
BOOL ALNPlatformPathIsAbsolute(NSString *path);

NS_ASSUME_NONNULL_END

#endif
