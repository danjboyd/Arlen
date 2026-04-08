#import "ALNPlatform.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#if defined(_WIN32)
#include <bcrypt.h>
#include <process.h>
#include <windows.h>
#else
#include <sys/time.h>
#include <unistd.h>
#endif

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

NSArray<NSString *> *ALNDefaultLibpqCandidatePaths(void) {
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];
  const char *envCandidate = getenv("ARLEN_LIBPQ_LIBRARY");
  if (envCandidate != NULL && envCandidate[0] != '\0') {
    NSString *envPath = [NSString stringWithUTF8String:envCandidate];
    if ([envPath length] > 0) {
      [candidates addObject:envPath];
    }
  }

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
  [candidates addObject:@"C:/msys64/clang64/bin/libpq-5.dll"];
  [candidates addObject:@"C:/msys64/clang64/bin/libpq.dll"];
  [candidates addObject:@"libpq-5.dll"];
  [candidates addObject:@"libpq.dll"];
#else
  [candidates addObject:@"/usr/lib/x86_64-linux-gnu/libpq.so.5"];
  [candidates addObject:@"libpq.so.5"];
  [candidates addObject:@"libpq.so"];
#endif

  return candidates;
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
