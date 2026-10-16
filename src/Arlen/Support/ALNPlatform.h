#ifndef ALN_PLATFORM_H
#define ALN_PLATFORM_H
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNPlatformName(void);
FOUNDATION_EXPORT BOOL ALNPlatformUsesAppleFoundation(void);
FOUNDATION_EXPORT BOOL ALNPlatformUsesGNUstepFoundation(void);
// YES only for NSNumber booleans (@YES, @NO, numberWithBool:, decoded JSON
// true/false). Char-typed numbers are not booleans. Never use objCType for this:
// @encode(BOOL) is "B" on Apple arm64 while @YES reports "c".
FOUNDATION_EXPORT BOOL ALNNumberIsBoolean(id _Nullable value);
// MSYS2 roots that may hold the CLANG64 toolchain on Windows, in search order:
// ARLEN_MSYS_ROOT, the gnustep-cli managed toolchain (user, then system
// install), then a stock MSYS2 at C:/msys64. Empty on other platforms.
FOUNDATION_EXPORT NSArray<NSString *> *ALNPlatformWindowsMSYSRoots(void);
// bash for `bash -lc` helpers: /bin/bash on POSIX. On Windows: ARLEN_BASH_PATH,
// then usr/bin/bash.exe under the first MSYS2 root that has one, then bash.exe.
FOUNDATION_EXPORT NSString *ALNPlatformBashPath(void);
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
// fopen() for an NSString path. -fileSystemRepresentation is UTF-16 on
// Windows GNUstep, so this uses _wfopen there and fopen elsewhere.
FILE *_Nullable ALNPlatformOpenFile(NSString *path, const char *mode);
// Memory-mapped file contents. The MSYS2 gnustep-base package on Windows has
// no +dataWithContentsOfFile:options:error:, only +dataWithContentsOfMappedFile:.
NSData *_Nullable ALNPlatformMappedFileData(NSString *path, NSError *_Nullable *_Nullable error);
// Opens (creating, 0600) the lock file at path and blocks until this process
// holds an exclusive, cross-process lock on it: flock() on POSIX, LockFileEx
// on Windows. Returns the descriptor, or -1 with errno set.
int ALNPlatformOpenExclusiveLock(NSString *path);
// Releases a lock from ALNPlatformOpenExclusiveLock and closes its descriptor.
void ALNPlatformReleaseExclusiveLock(int descriptor);

NS_ASSUME_NONNULL_END

#endif
