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
// install), then the root GNUSTEP_MAKEFILES points into (a stock C:/msys64 only
// when it is the toolchain in use). Empty on other platforms.
FOUNDATION_EXPORT NSArray<NSString *> *ALNPlatformWindowsMSYSRoots(void);
// bash for `bash -lc` helpers: /bin/bash on POSIX. On Windows: ARLEN_BASH_PATH,
// then usr/bin/bash.exe under the first MSYS2 root that has one, else the
// managed root's path (which fails to launch: set ARLEN_BASH_PATH).
FOUNDATION_EXPORT NSString *ALNPlatformBashPath(void);
FOUNDATION_EXPORT NSArray<NSString *> *ALNDefaultLibpqCandidatePaths(void);
FOUNDATION_EXPORT NSArray<NSString *> *ALNDefaultODBCCandidatePaths(void);
NSCalendarUnit ALNPlatformCalendarDateTimeUnitMask(void);
double ALNPlatformNowMilliseconds(void);
NSString *ALNPlatformISO8601Now(void);
NSInteger ALNPlatformProcessIdentifier(void);
void ALNPlatformSleepMilliseconds(NSUInteger milliseconds);
BOOL ALNPlatformPathIsAbsolute(NSString *path);
#if defined(_WIN32)
// LoadLibraryW for a relative name; for an absolute path, LoadLibraryExW with
// backslashes and LOAD_WITH_ALTERED_SEARCH_PATH so the DLL's own imports
// resolve from its directory. Wide-character, so non-ASCII paths load.
void *_Nullable ALNPlatformLoadWindowsLibrary(NSString *path);
#endif
BOOL ALNPlatformFillRandomBytes(void *buffer, size_t count);
BOOL ALNPlatformGMTimeUTC(const time_t *seconds, struct tm *utc);
// fopen() for an NSString path. -fileSystemRepresentation is UTF-16 on
// Windows GNUstep, so this uses _wfopen there and fopen elsewhere.
FILE *_Nullable ALNPlatformOpenFile(NSString *path, const char *mode);
// Memory-mapped file contents. On Windows a read-only file mapping
// (CreateFileMappingW/MapViewOfFile): the MSYS2 gnustep-base has no
// +dataWithContentsOfFile:options:error:, and its +dataWithContentsOfMappedFile:
// reads the whole file into the heap (no HAVE_MMAP).
NSData *_Nullable ALNPlatformMappedFileData(NSString *path, NSError *_Nullable *_Nullable error);
// Removes a file or directory that ALNPlatformMappedFileData may still have
// mapped. POSIX unlink leaves existing mappings valid; Windows refuses to delete
// a mapped file, so whatever cannot go yet is removed when its last mapped view
// is released.
void ALNPlatformRemoveItemWhenUnmapped(NSString *path);
// Windows only: what struct stat lacks to tell file versions apart there
// (st_ino is 0, times are whole seconds, st_ctime is the creation time). Fills
// the NTFS file index and the 100 ns last-write and change times. NO on other
// platforms or when the file cannot be opened.
BOOL ALNPlatformFileVersion(NSString *path,
                            unsigned long long *fileIndex,
                            unsigned long long *writeTime,
                            unsigned long long *changeTime);
// Opens (creating, 0600) the lock file at path and blocks until this process
// holds an exclusive, cross-process lock on it: flock() on POSIX, LockFileEx
// on Windows. Returns the descriptor, or -1 with errno set.
int ALNPlatformOpenExclusiveLock(NSString *path);
// Releases a lock from ALNPlatformOpenExclusiveLock and closes its descriptor.
void ALNPlatformReleaseExclusiveLock(int descriptor);

NS_ASSUME_NONNULL_END

#endif
