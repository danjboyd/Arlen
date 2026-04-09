#ifndef ALN_PLATFORM_H
#define ALN_PLATFORM_H
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNPlatformName(void);
FOUNDATION_EXPORT BOOL ALNPlatformUsesAppleFoundation(void);
FOUNDATION_EXPORT BOOL ALNPlatformUsesGNUstepFoundation(void);
FOUNDATION_EXPORT NSArray<NSString *> *ALNDefaultLibpqCandidatePaths(void);
FOUNDATION_EXPORT NSArray<NSString *> *ALNDefaultODBCCandidatePaths(void);
NSCalendarUnit ALNPlatformCalendarDateTimeUnitMask(void);
double ALNPlatformNowMilliseconds(void);
NSString *ALNPlatformISO8601Now(void);
NSInteger ALNPlatformProcessIdentifier(void);
void ALNPlatformSleepMilliseconds(NSUInteger milliseconds);
BOOL ALNPlatformPathIsAbsolute(NSString *path);
BOOL ALNPlatformFillRandomBytes(void *buffer, size_t count);
BOOL ALNPlatformGMTimeUTC(const time_t *seconds, struct tm *utc);

NS_ASSUME_NONNULL_END

#endif
