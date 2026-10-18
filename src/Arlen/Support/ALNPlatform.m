#import "ALNPlatform.h"

#import <dispatch/dispatch.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(_WIN32)
#include <bcrypt.h>
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <sys/stat.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <sys/time.h>
#include <unistd.h>
#endif
#include <errno.h>

NSString *ALNPlatformName(void) {
#if defined(__APPLE__)
  return @"apple";
#elif defined(_WIN32)
  return @"windows";
#elif defined(__linux__)
  return @"linux";
#else
  return @"unknown";
#endif
}

BOOL ALNPlatformUsesAppleFoundation(void) {
#if defined(__APPLE__)
  return YES;
#else
  return NO;
#endif
}

BOOL ALNPlatformUsesGNUstepFoundation(void) {
#if defined(GNUSTEP)
  return YES;
#else
  return NO;
#endif
}

BOOL ALNNumberIsBoolean(id value) {
  if (![value isKindOfClass:[NSNumber class]]) {
    return NO;
  }
#if defined(__APPLE__)
  return (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID());
#else
  static Class boolNumberClass = Nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    boolNumberClass = [[NSNumber numberWithBool:YES] class];
    if (boolNumberClass == [[NSNumber numberWithInt:1] class]) {
      boolNumberClass = Nil;
    }
  });
  if (boolNumberClass != Nil) {
    return [value isKindOfClass:boolNumberClass];
  }
  const char *type = [value objCType];
  return (type != NULL && strcmp(type, @encode(BOOL)) == 0);
#endif
}

BOOL ALNUnsignedIntegerFromValue(id value, NSUInteger *outValue) {
  if ([value isKindOfClass:[NSNumber class]]) {
    if (outValue != NULL) {
      *outValue = [value unsignedIntegerValue];
    }
    return YES;
  }
  if (![value isKindOfClass:[NSString class]]) {
    return NO;
  }
  NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSUInteger length = [text length];
  if (length == 0) {
    return NO;
  }
  NSUInteger parsed = 0;
  for (NSUInteger index = 0; index < length; index++) {
    unichar character = [text characterAtIndex:index];
    if (character < '0' || character > '9') {
      return NO;
    }
    NSUInteger digit = (NSUInteger)(character - '0');
    if (parsed > (NSUIntegerMax - digit) / 10) {
      return NO;
    }
    parsed = (parsed * 10) + digit;
  }
  if (outValue != NULL) {
    *outValue = parsed;
  }
  return YES;
}

NSUInteger ALNUnsignedIntegerValueOrDefault(id value, NSUInteger fallback) {
  NSUInteger parsed = 0;
  return ALNUnsignedIntegerFromValue(value, &parsed) ? parsed : fallback;
}

static void ALNAppendPrefixLibraryCandidates(NSMutableArray<NSString *> *candidates,
                                             const char *envName,
                                             NSArray<NSString *> *relativePaths) {
  if (candidates == nil || relativePaths == nil) {
    return;
  }

  const char *prefixValue = (envName != NULL) ? getenv(envName) : NULL;
  if (prefixValue == NULL || prefixValue[0] == '\0') {
    return;
  }

  NSString *prefix = [NSString stringWithUTF8String:prefixValue];
  if ([prefix length] == 0) {
    return;
  }

  for (NSString *relativePath in relativePaths) {
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) {
      continue;
    }
    [candidates addObject:[prefix stringByAppendingPathComponent:relativePath]];
  }
}

NSArray<NSString *> *ALNPlatformWindowsMSYSRoots(void) {
#if defined(_WIN32)
  NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];
  NSMutableArray<NSString *> *roots = [NSMutableArray array];
  NSString *override = environment[@"ARLEN_MSYS_ROOT"];
  if ([override length] > 0) {
    [roots addObject:override];
  }
  NSString *localAppData = environment[@"LOCALAPPDATA"];
  if ([localAppData length] > 0) {
    [roots addObject:[localAppData stringByAppendingPathComponent:@"gnustep-cli"]];
  }
  NSString *programFiles = environment[@"ProgramFiles"];
  if ([programFiles length] > 0) {
    [roots addObject:[programFiles stringByAppendingPathComponent:@"gnustep-cli"]];
  }
  // Any other root (a stock C:\msys64) only when it is the toolchain in use,
  // i.e. GNUSTEP_MAKEFILES points into it. An unprivileged user can create
  // C:\msys64 on a host without MSYS2 and plant DLLs there, so it is never a
  // default.
  NSString *makefiles = [environment[@"GNUSTEP_MAKEFILES"] stringByReplacingOccurrencesOfString:@"\\"
                                                                                       withString:@"/"];
  NSRange clang64 = [makefiles rangeOfString:@"/clang64/share/GNUstep/Makefiles" options:NSCaseInsensitiveSearch];
  if (clang64.location != NSNotFound && clang64.location > 0) {
    NSString *activeRoot = [makefiles substringToIndex:clang64.location];
    if (ALNPlatformPathIsAbsolute(activeRoot) && ![roots containsObject:activeRoot]) {
      [roots addObject:activeRoot];
    }
  }
  return roots;
#else
  return @[];
#endif
}

NSString *ALNPlatformBashPath(void) {
#if defined(_WIN32)
  NSString *override = [[NSProcessInfo processInfo] environment][@"ARLEN_BASH_PATH"];
  if ([override length] > 0) {
    return override;
  }
  for (NSString *root in ALNPlatformWindowsMSYSRoots()) {
    NSString *candidate = [root stringByAppendingPathComponent:@"usr/bin/bash.exe"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }
  // Not a bare "bash.exe": that could resolve to System32's bash.exe (WSL). Name
  // the managed toolchain's path so the launch error says where bash belongs
  // (or set ARLEN_BASH_PATH).
  NSString *managedRoot = [ALNPlatformWindowsMSYSRoots() firstObject] ?: @"C:/gnustep-cli";
  return [managedRoot stringByAppendingPathComponent:@"usr/bin/bash.exe"];
#else
  return @"/bin/bash";
#endif
}

static void ALNAppendMSYSClang64BinCandidates(NSMutableArray<NSString *> *candidates,
                                              NSArray<NSString *> *libraryNames) {
  for (NSString *root in ALNPlatformWindowsMSYSRoots()) {
    for (NSString *name in libraryNames) {
      [candidates addObject:[[root stringByAppendingPathComponent:@"clang64/bin"] stringByAppendingPathComponent:name]];
    }
  }
}

NSArray<NSString *> *ALNDefaultLibpqCandidatePaths(void) {
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];
  const char *envCandidate = getenv("ARLEN_LIBPQ_LIBRARY");
  if (envCandidate != NULL && envCandidate[0] != '\0') {
    NSString *envPath = [NSString stringWithUTF8String:envCandidate];
    if ([envPath length] > 0) {
      [candidates addObject:envPath];
    }
  }
  ALNAppendPrefixLibraryCandidates(candidates,
                                   "ARLEN_LIBPQ_PREFIX",
                                   @[ @"lib/libpq.5.dylib", @"lib/libpq.dylib", @"lib/libpq.5.so",
                                      @"lib/libpq.so", @"bin/libpq-5.dll", @"bin/libpq.dll" ]);

#if defined(__APPLE__)
  [candidates addObject:@"/opt/homebrew/opt/libpq/lib/libpq.5.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/libpq/lib/libpq.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/postgresql/lib/libpq.5.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/postgresql/lib/libpq.dylib"];
  [candidates addObject:@"/usr/local/opt/libpq/lib/libpq.5.dylib"];
  [candidates addObject:@"/usr/local/opt/libpq/lib/libpq.dylib"];
  [candidates addObject:@"/usr/local/opt/postgresql/lib/libpq.5.dylib"];
  [candidates addObject:@"/usr/local/opt/postgresql/lib/libpq.dylib"];
  [candidates addObject:@"libpq.5.dylib"];
  [candidates addObject:@"libpq.dylib"];
#elif defined(_WIN32)
  // The Windows release bundles libpq and its DLL closure under
  // <framework>/build/dll, so nothing is installed into the toolchain root.
  NSString *frameworkRoot = [[NSProcessInfo processInfo] environment][@"ARLEN_FRAMEWORK_ROOT"];
  if ([frameworkRoot length] > 0) {
    [candidates addObject:[frameworkRoot stringByAppendingPathComponent:@"build/dll/libpq-5.dll"]];
    [candidates addObject:[frameworkRoot stringByAppendingPathComponent:@"build/dll/libpq.dll"]];
  }
  ALNAppendMSYSClang64BinCandidates(candidates, @[ @"libpq-5.dll", @"libpq.dll" ]);
  [candidates addObject:@"libpq-5.dll"];
  [candidates addObject:@"libpq.dll"];
#else
  [candidates addObject:@"/usr/lib/x86_64-linux-gnu/libpq.so.5"];
  [candidates addObject:@"libpq.so.5"];
  [candidates addObject:@"libpq.so"];
#endif

  return candidates;
}

NSArray<NSString *> *ALNDefaultODBCCandidatePaths(void) {
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];
  const char *envCandidate = getenv("ARLEN_ODBC_LIBRARY");
  if (envCandidate != NULL && envCandidate[0] != '\0') {
    NSString *envPath = [NSString stringWithUTF8String:envCandidate];
    if ([envPath length] > 0) {
      [candidates addObject:envPath];
    }
  }
  ALNAppendPrefixLibraryCandidates(candidates,
                                   "ARLEN_ODBC_PREFIX",
                                   @[ @"lib/libodbc.2.dylib", @"lib/libodbc.dylib",
                                      @"lib/libodbc.so.2", @"lib/libodbc.so",
                                      @"bin/libodbc-2.dll", @"bin/libodbc.dll" ]);

#if defined(__APPLE__)
  [candidates addObject:@"/opt/homebrew/opt/unixodbc/lib/libodbc.2.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/unixodbc/lib/libodbc.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/libiodbc/lib/libiodbc.2.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/libiodbc/lib/libiodbc.dylib"];
  [candidates addObject:@"/usr/local/opt/unixodbc/lib/libodbc.2.dylib"];
  [candidates addObject:@"/usr/local/opt/unixodbc/lib/libodbc.dylib"];
  [candidates addObject:@"/usr/local/opt/libiodbc/lib/libiodbc.2.dylib"];
  [candidates addObject:@"/usr/local/opt/libiodbc/lib/libiodbc.dylib"];
  [candidates addObject:@"libodbc.2.dylib"];
  [candidates addObject:@"libodbc.dylib"];
  [candidates addObject:@"libiodbc.2.dylib"];
  [candidates addObject:@"libiodbc.dylib"];
#elif defined(_WIN32)
  // The system ODBC driver manager first, then the toolchain's unixODBC.
  [candidates addObject:@"odbc32.dll"];
  ALNAppendMSYSClang64BinCandidates(candidates, @[ @"libodbc-2.dll", @"libodbc.dll" ]);
  [candidates addObject:@"libodbc-2.dll"];
  [candidates addObject:@"libodbc.dll"];
#else
  [candidates addObject:@"/usr/lib/x86_64-linux-gnu/libodbc.so.2"];
  [candidates addObject:@"libodbc.so.2"];
  [candidates addObject:@"libodbc.so"];
#endif

  return candidates;
}

NSCalendarUnit ALNPlatformCalendarDateTimeUnitMask(void) {
#if defined(GNUSTEP)
  return (NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit |
          NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit);
#else
  return (NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
          NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond);
#endif
}

BOOL ALNPlatformFillRandomBytes(void *buffer, size_t count) {
  if (buffer == NULL) {
    return NO;
  }
#if defined(_WIN32)
  return BCryptGenRandom(NULL, (PUCHAR)buffer, (ULONG)count, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
#else
  arc4random_buf(buffer, count);
  return YES;
#endif
}

BOOL ALNPlatformGMTimeUTC(const time_t *seconds, struct tm *utc) {
  if (seconds == NULL || utc == NULL) {
    return NO;
  }
#if defined(_WIN32)
  return gmtime_s(utc, seconds) == 0;
#else
  return gmtime_r(seconds, utc) != NULL;
#endif
}

double ALNPlatformNowMilliseconds(void) {
#if defined(_WIN32)
  FILETIME fileTime;
  ULARGE_INTEGER rawTime;
  GetSystemTimeAsFileTime(&fileTime);
  rawTime.LowPart = fileTime.dwLowDateTime;
  rawTime.HighPart = fileTime.dwHighDateTime;
  return (double)((rawTime.QuadPart - 116444736000000000ULL) / 10000ULL);
#else
  struct timeval tv;
  if (gettimeofday(&tv, NULL) != 0) {
    return 0.0;
  }
  return ((double)tv.tv_sec * 1000.0) + ((double)tv.tv_usec / 1000.0);
#endif
}

NSString *ALNPlatformISO8601Now(void) {
#if defined(_WIN32)
  SYSTEMTIME utc;
  GetSystemTime(&utc);
  char buffer[32];
  int written = snprintf(buffer,
                         sizeof(buffer),
                         "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                         (int)utc.wYear,
                         (int)utc.wMonth,
                         (int)utc.wDay,
                         (int)utc.wHour,
                         (int)utc.wMinute,
                         (int)utc.wSecond,
                         (int)utc.wMilliseconds);
  if (written <= 0 || written >= (int)sizeof(buffer)) {
    return @"1970-01-01T00:00:00.000Z";
  }
  return [NSString stringWithUTF8String:buffer] ?: @"1970-01-01T00:00:00.000Z";
#else
  struct timeval tv;
  if (gettimeofday(&tv, NULL) != 0) {
    return @"1970-01-01T00:00:00.000Z";
  }

  time_t seconds = tv.tv_sec;
  struct tm utc;
  if (!ALNPlatformGMTimeUTC(&seconds, &utc)) {
    return @"1970-01-01T00:00:00.000Z";
  }

  char buffer[32];
  int written = snprintf(buffer,
                         sizeof(buffer),
                         "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                         utc.tm_year + 1900,
                         utc.tm_mon + 1,
                         utc.tm_mday,
                         utc.tm_hour,
                         utc.tm_min,
                         utc.tm_sec,
                         (int)(tv.tv_usec / 1000));
  if (written <= 0 || written >= (int)sizeof(buffer)) {
    return @"1970-01-01T00:00:00.000Z";
  }
  return [NSString stringWithUTF8String:buffer] ?: @"1970-01-01T00:00:00.000Z";
#endif
}

NSInteger ALNPlatformProcessIdentifier(void) {
#if defined(_WIN32)
  return (NSInteger)_getpid();
#else
  return (NSInteger)getpid();
#endif
}

void ALNPlatformSleepMilliseconds(NSUInteger milliseconds) {
#if defined(_WIN32)
  Sleep((DWORD)milliseconds);
#else
  usleep((useconds_t)(milliseconds * 1000U));
#endif
}

BOOL ALNPlatformPathIsAbsolute(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return NO;
  }
  if ([path hasPrefix:@"/"] || [path hasPrefix:@"\\\\"]) {
    return YES;
  }
  if ([path length] >= 3) {
    unichar drive = [path characterAtIndex:0];
    unichar colon = [path characterAtIndex:1];
    unichar separator = [path characterAtIndex:2];
    if (((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) &&
        colon == ':' &&
        (separator == '\\' || separator == '/')) {
      return YES;
    }
  }
  return NO;
}

#if defined(_WIN32)
void *ALNPlatformLoadWindowsLibrary(NSString *path) {
  if ([path length] == 0) {
    return NULL;
  }
  BOOL absolute = ALNPlatformPathIsAbsolute(path);
  // LOAD_WITH_ALTERED_SEARCH_PATH wants backslashes, and paths built with
  // -stringByAppendingPathComponent: mix them.
  NSString *native = absolute ? [path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"] : path;
  NSMutableData *wide = [[native dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  if (wide == nil) {
    return NULL;
  }
  [wide appendBytes:"\0\0" length:2];
  const wchar_t *widePath = (const wchar_t *)[wide bytes];
  // An absolute path resolves the DLL's own imports from its directory (a
  // bundled build/dll next to its OpenSSL), not only the exe's and PATH.
  return (void *)(absolute ? LoadLibraryExW(widePath, NULL, LOAD_WITH_ALTERED_SEARCH_PATH)
                           : LoadLibraryW(widePath));
}
#endif

#if defined(_WIN32)
// A read-only file mapping behind NSData. The MSYS2 gnustep-base is built
// without HAVE_MMAP, so +dataWithContentsOfMappedFile: there reads the whole
// file into the heap (a 256 MiB spool file grew private memory by 257 MiB),
// which broke the spool-to-disk memory bound for request bodies and uploads.
@interface ALNWindowsMappedFileData : NSData {
  const void *_view;
  NSUInteger _length;
  NSString *_path;
}
- (instancetype)initWithView:(const void *)view length:(NSUInteger)length path:(NSString *)path;
@end

// Windows refuses to delete a file that still has a mapped view, where POSIX
// unlink just drops the name. Paths whose removal had to wait for their views
// (files, and the spool directories holding them) are finished off by the last
// ALNWindowsMappedFileData of each file as it is released.
static NSMutableSet<NSString *> *ALNPendingRemovalPaths(void) {
  static NSMutableSet<NSString *> *paths = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    paths = [NSMutableSet set];
  });
  return paths;
}

// Guards ALNPendingRemovalPaths. A lock created up front, not @synchronized on
// the set (BuildPolicyTests bans @synchronized on instance receivers).
static NSLock *ALNPendingRemovalLock(void) {
  static NSLock *lock = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static NSString *ALNRemovalKey(NSString *path) {
  return [[[path stringByStandardizingPath] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]
      lowercaseString];
}

static void ALNFinishPendingRemoval(NSString *path) {
  NSString *key = ALNRemovalKey(path);
  NSString *parent = [path stringByDeletingLastPathComponent];
  NSString *parentKey = ALNRemovalKey(parent);
  NSMutableSet<NSString *> *pending = ALNPendingRemovalPaths();
  [ALNPendingRemovalLock() lock];
  @try {
    if (![pending containsObject:key] && ![pending containsObject:parentKey]) {
      return;
    }
    if ([[NSFileManager defaultManager] removeItemAtPath:path error:NULL] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
      [pending removeObject:key];
    }
    if ([pending containsObject:parentKey] &&
        [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:parent error:NULL] count] == 0 &&
        [[NSFileManager defaultManager] removeItemAtPath:parent error:NULL]) {
      [pending removeObject:parentKey];
    }
  } @finally {
    [ALNPendingRemovalLock() unlock];
  }
}

@implementation ALNWindowsMappedFileData
- (instancetype)initWithView:(const void *)view length:(NSUInteger)length path:(NSString *)path {
  self = [self initWithBytesNoCopy:(void *)view length:length freeWhenDone:NO];
  _path = [path copy];
  return self;
}
// NSData's designated initializer, which GNUstep's -init forwards to and an
// NSData subclass must implement. The view is unmapped in -dealloc, never freed.
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)shouldFree {
  (void)shouldFree;
  _view = bytes;
  _length = length;
  return self;
}
- (const void *)bytes {
  return _view;
}
- (NSUInteger)length {
  return _length;
}
- (void)dealloc {
  if (_view != NULL) {
    UnmapViewOfFile(_view);
  }
  if (_path != nil) {
    ALNFinishPendingRemoval(_path);
  }
}
@end

// lastError is captured by the caller before anything (CloseHandle) can reset it.
static NSError *ALNPlatformMappedFileError(NSString *path, DWORD lastError) {
  return [NSError errorWithDomain:NSCocoaErrorDomain
                             code:NSFileReadUnknownError
                         userInfo:@{
                           NSFilePathErrorKey : path ?: @"",
                           @"ALNWindowsLastError" : @((unsigned long)lastError),
                         }];
}
#endif

NSData *ALNPlatformMappedFileData(NSString *path, NSError **error) {
#if defined(_WIN32)
  NSMutableData *wide = [[[path ?: @"" stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
      dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  // Share everything, delete included: spool files are moved (an upload's
  // -writeToFile:) or removed while their bytes are still mapped.
  HANDLE file = CreateFileW((const wchar_t *)[wide bytes], GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    if (error != NULL) {
      *error = ALNPlatformMappedFileError(path, GetLastError());
    }
    return nil;
  }
  LARGE_INTEGER size;
  if (!GetFileSizeEx(file, &size) || (unsigned long long)size.QuadPart > (unsigned long long)NSUIntegerMax) {
    if (error != NULL) {
      *error = ALNPlatformMappedFileError(path, GetLastError());
    }
    CloseHandle(file);
    return nil;
  }
  if (size.QuadPart == 0) {
    CloseHandle(file);
    return [NSData data];  // a zero-length file cannot be mapped
  }
  HANDLE mapping = CreateFileMappingW(file, NULL, PAGE_READONLY, 0, 0, NULL);
  DWORD mappingError = (mapping == NULL) ? GetLastError() : 0;
  CloseHandle(file);  // the mapping keeps the file referenced
  if (mapping == NULL) {
    if (error != NULL) {
      *error = ALNPlatformMappedFileError(path, mappingError);
    }
    return nil;
  }
  const void *view = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
  DWORD viewError = (view == NULL) ? GetLastError() : 0;
  CloseHandle(mapping);  // the view keeps the mapping alive
  if (view == NULL) {
    if (error != NULL) {
      *error = ALNPlatformMappedFileError(path, viewError);
    }
    return nil;
  }
  return [[ALNWindowsMappedFileData alloc] initWithView:view length:(NSUInteger)size.QuadPart path:path];
#else
  return [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:error];
#endif
}

BOOL ALNPlatformFileVersion(NSString *path,
                            unsigned long long *fileIndex,
                            unsigned long long *writeTime,
                            unsigned long long *changeTime) {
#if defined(_WIN32)
  if ([path length] == 0) {
    return NO;
  }
  NSMutableData *wide = [[[path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
      dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  HANDLE file = CreateFileW((const wchar_t *)[wide bytes], FILE_READ_ATTRIBUTES,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                            OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return NO;
  }
  BY_HANDLE_FILE_INFORMATION info;
  FILE_BASIC_INFO basic;
  BOOL ok = GetFileInformationByHandle(file, &info) &&
            GetFileInformationByHandleEx(file, FileBasicInfo, &basic, sizeof(basic));
  CloseHandle(file);
  if (!ok) {
    return NO;
  }
  if (fileIndex != NULL) {
    *fileIndex = ((unsigned long long)info.nFileIndexHigh << 32) | info.nFileIndexLow;
  }
  if (writeTime != NULL) {
    *writeTime = (unsigned long long)basic.LastWriteTime.QuadPart;
  }
  if (changeTime != NULL) {
    *changeTime = (unsigned long long)basic.ChangeTime.QuadPart;
  }
  return YES;
#else
  (void)path;
  (void)fileIndex;
  (void)writeTime;
  (void)changeTime;
  return NO;
#endif
}

void ALNPlatformRemoveItemWhenUnmapped(NSString *path) {
  if ([path length] == 0) {
    return;
  }
  NSFileManager *fileManager = [NSFileManager defaultManager];
#if defined(_WIN32)
  NSMutableSet<NSString *> *pending = ALNPendingRemovalPaths();
  [ALNPendingRemovalLock() lock];
  @try {
    // Retry earlier removals too. A pending path is otherwise finished only
    // when one of its mapped views is released, so a delete blocked for another
    // reason (an antivirus or indexer handle without share-delete) would stay
    // on disk for the life of the process.
    for (NSString *pendingKey in [pending allObjects]) {
      if (![fileManager fileExistsAtPath:pendingKey] || [fileManager removeItemAtPath:pendingKey error:NULL]) {
        [pending removeObject:pendingKey];
      }
    }
    if ([fileManager removeItemAtPath:path error:NULL] || ![fileManager fileExistsAtPath:path]) {
      return;
    }
    // Something under `path` is still mapped. Remove what can go now and leave
    // the rest, and the directory, to the mapped data's release.
    BOOL isDirectory = NO;
    if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
      for (NSString *name in [fileManager contentsOfDirectoryAtPath:path error:NULL]) {
        NSString *child = [path stringByAppendingPathComponent:name];
        if (![fileManager removeItemAtPath:child error:NULL]) {
          [pending addObject:ALNRemovalKey(child)];
        }
      }
      if ([[fileManager contentsOfDirectoryAtPath:path error:NULL] count] == 0 &&
          [fileManager removeItemAtPath:path error:NULL]) {
        return;
      }
    }
    [pending addObject:ALNRemovalKey(path)];
  } @finally {
    [ALNPendingRemovalLock() unlock];
  }
#else
  // POSIX unlink drops the name; existing mappings stay valid.
  (void)[fileManager removeItemAtPath:path error:NULL];
#endif
}

FILE *ALNPlatformOpenFile(NSString *path, const char *mode) {
  if ([path length] == 0 || mode == NULL) {
    return NULL;
  }
#if defined(_WIN32)
  wchar_t wideMode[8];
  size_t idx = 0;
  for (; mode[idx] != '\0' && idx < 7; idx++) {
    wideMode[idx] = (wchar_t)(unsigned char)mode[idx];
  }
  wideMode[idx] = L'\0';
  return _wfopen((const wchar_t *)[path fileSystemRepresentation], wideMode);
#else
  return fopen([path fileSystemRepresentation], mode);
#endif
}

int ALNPlatformOpenExclusiveLock(NSString *path) {
  return ALNPlatformOpenExclusiveLockWithTimeout(path, -1.0);
}

int ALNPlatformOpenExclusiveLockWithTimeout(NSString *path, NSTimeInterval timeoutSeconds) {
  if ([path length] == 0) {
    errno = EINVAL;
    return -1;
  }
  NSDate *deadline = (timeoutSeconds >= 0.0) ? [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds] : nil;
  unsigned int pause = 1000;  // microseconds, doubling to 50 ms
#if defined(_WIN32)
  int descriptor = _wopen((const wchar_t *)[path fileSystemRepresentation],
                          _O_RDWR | _O_CREAT | _O_BINARY | _O_NOINHERIT, _S_IREAD | _S_IWRITE);
  if (descriptor < 0) {
    return -1;
  }
  HANDLE handle = (HANDLE)_get_osfhandle(descriptor);
  if (handle == INVALID_HANDLE_VALUE) {
    _close(descriptor);
    errno = EIO;
    return -1;
  }
  DWORD flags = LOCKFILE_EXCLUSIVE_LOCK | ((deadline != nil) ? LOCKFILE_FAIL_IMMEDIATELY : 0);
  for (;;) {
    OVERLAPPED overlapped;
    memset(&overlapped, 0, sizeof(overlapped));
    if (LockFileEx(handle, flags, 0, MAXDWORD, MAXDWORD, &overlapped)) {
      return descriptor;
    }
    DWORD lastError = GetLastError();
    if (deadline == nil || lastError != ERROR_LOCK_VIOLATION) {
      _close(descriptor);
      errno = EIO;
      return -1;
    }
    if ([deadline timeIntervalSinceNow] <= 0.0) {
      _close(descriptor);
      errno = ETIMEDOUT;
      return -1;
    }
    Sleep((DWORD)(pause / 1000));
    pause = (pause < 50000) ? pause * 2 : 50000;
  }
#else
  int descriptor = -1;
  do {
    descriptor = open([path fileSystemRepresentation], O_RDWR | O_CREAT | O_CLOEXEC, 0600);
  } while (descriptor < 0 && errno == EINTR);
  if (descriptor < 0) {
    return -1;
  }
  int operation = LOCK_EX | ((deadline != nil) ? LOCK_NB : 0);
  for (;;) {
    if (flock(descriptor, operation) == 0) {
      return descriptor;
    }
    int savedErrno = errno;
    if (savedErrno == EINTR) {
      continue;
    }
    if (deadline == nil || savedErrno != EWOULDBLOCK) {
      close(descriptor);
      errno = savedErrno;
      return -1;
    }
    if ([deadline timeIntervalSinceNow] <= 0.0) {
      close(descriptor);
      errno = ETIMEDOUT;
      return -1;
    }
    usleep((useconds_t)pause);
    pause = (pause < 50000) ? pause * 2 : 50000;
  }
#endif
}

void ALNPlatformReleaseExclusiveLock(int descriptor) {
  if (descriptor < 0) {
    return;
  }
#if defined(_WIN32)
  HANDLE handle = (HANDLE)_get_osfhandle(descriptor);
  if (handle != INVALID_HANDLE_VALUE) {
    OVERLAPPED overlapped;
    memset(&overlapped, 0, sizeof(overlapped));
    (void)UnlockFileEx(handle, 0, MAXDWORD, MAXDWORD, &overlapped);
  }
  _close(descriptor);
#else
  (void)flock(descriptor, LOCK_UN);
  close(descriptor);
#endif
}
