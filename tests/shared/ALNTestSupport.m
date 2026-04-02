#import "ALNTestSupport.h"

#import <dispatch/dispatch.h>
#import <ctype.h>
#import <string.h>
#import <unistd.h>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#endif

static NSString *const ALNTestSupportErrorDomain = @"Arlen.TestSupport.Error";

static NSString *ALNTestSupportSanitizedPrefix(NSString *prefix) {
  NSString *input = [prefix isKindOfClass:[NSString class]] ? prefix : @"arlen_test";
  NSMutableString *sanitized = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [input length]; idx++) {
    unichar character = [input characterAtIndex:idx];
    if ((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
        (character >= '0' && character <= '9')) {
      [sanitized appendFormat:@"%c", (char)tolower((int)character)];
    } else {
      [sanitized appendString:@"_"];
    }
  }

  while ([sanitized containsString:@"__"]) {
    [sanitized replaceOccurrencesOfString:@"__"
                               withString:@"_"
                                  options:0
                                    range:NSMakeRange(0, [sanitized length])];
  }
  NSString *trimmed =
      [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_"]];
  return [trimmed length] > 0 ? trimmed : @"arlen_test";
}

static NSString *ALNTestSupportPortablePath(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return path;
  }
  NSString *normalized = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
#if defined(_WIN32)
  return normalized;
#else
  return [normalized stringByStandardizingPath];
#endif
}

static NSError *ALNTestSupportMakeError(NSString *message, NSDictionary *userInfo) {
  return [NSError errorWithDomain:ALNTestSupportErrorDomain
                             code:1
                         userInfo:userInfo != nil
                                      ? userInfo
                                      : @{
                                          NSLocalizedDescriptionKey : message ?: @"test support error",
                                        }];
}

static int ALNTestSupportFallbackPort(void) {
  return 32000 + (int)arc4random_uniform(20000);
}

#if defined(_WIN32)
static BOOL ALNTestSupportEnsureWinsockInitialized(void) {
  static BOOL attempted = NO;
  static BOOL initialized = NO;
  if (!attempted) {
    WSADATA socketData;
    attempted = YES;
    initialized = (WSAStartup(MAKEWORD(2, 2), &socketData) == 0);
  }
  return initialized;
}
#endif

NSString *ALNTestRepoRoot(void) {
  return ALNTestSupportPortablePath([[NSFileManager defaultManager] currentDirectoryPath]);
}

NSString *ALNTestPathFromRepoRoot(NSString *relativePath) {
  NSString *path = [ALNTestRepoRoot() stringByAppendingPathComponent:relativePath ?: @""];
  return ALNTestSupportPortablePath(path);
}

NSData *ALNTestDataAtRelativePath(NSString *relativePath, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *path = ALNTestPathFromRepoRoot(relativePath ?: @"");
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil && error != NULL) {
    *error = ALNTestSupportMakeError(
        @"fixture file is missing",
        @{
          NSLocalizedDescriptionKey : @"fixture file is missing",
          @"relative_path" : relativePath ?: @"",
          @"path" : path ?: @"",
        });
  }
  return data;
}

id ALNTestJSONObjectAtRelativePath(NSString *relativePath, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSData *data = ALNTestDataAtRelativePath(relativePath, error);
  if (data == nil) {
    return nil;
  }

  NSError *jsonError = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (object == nil && error != NULL) {
    *error = jsonError;
  }
  return object;
}

id ALNTestJSONObjectFromString(NSString *string, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *payload = [string isKindOfClass:[NSString class]] ? string : @"";
  NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    if (error != NULL) {
      *error = ALNTestSupportMakeError(
          @"fixture string could not be encoded as UTF-8",
          @{
            NSLocalizedDescriptionKey : @"fixture string could not be encoded as UTF-8",
          });
    }
    return nil;
  }

  NSError *jsonError = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (object == nil && error != NULL) {
    *error = jsonError;
  }
  return object;
}

NSDictionary *ALNTestJSONDictionaryAtRelativePath(NSString *relativePath, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  id object = ALNTestJSONObjectAtRelativePath(relativePath, error);
  if (![object isKindOfClass:[NSDictionary class]]) {
    if (object != nil && error != NULL) {
      *error = ALNTestSupportMakeError(
          @"fixture JSON payload must be a dictionary",
          @{
            NSLocalizedDescriptionKey : @"fixture JSON payload must be a dictionary",
            @"relative_path" : relativePath ?: @"",
          });
    }
    return nil;
  }
  return object;
}

NSDictionary *ALNTestJSONDictionaryFromString(NSString *string, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  id object = ALNTestJSONObjectFromString(string, error);
  if (![object isKindOfClass:[NSDictionary class]]) {
    if (object != nil && error != NULL) {
      *error = ALNTestSupportMakeError(
          @"fixture JSON payload must be a dictionary",
          @{
            NSLocalizedDescriptionKey : @"fixture JSON payload must be a dictionary",
          });
    }
    return nil;
  }
  return object;
}

NSString *ALNTestEnvironmentString(NSString *name) {
  if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return nil;
  }
  const char *value = getenv([name UTF8String]);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  NSString *string = [NSString stringWithUTF8String:value];
  return [string length] > 0 ? string : nil;
}

NSString *ALNTestResolvedBashLaunchPath(void) {
  NSString *override = ALNTestEnvironmentString(@"ARLEN_BASH_PATH");
  NSArray<NSString *> *candidates = @[
    [override isKindOfClass:[NSString class]] ? override : @"",
    @"C:/msys64/usr/bin/bash.exe",
    @"C:/msys64/usr/bin/bash",
    @"/usr/bin/bash",
    @"/bin/bash",
  ];
  for (NSString *candidate in candidates) {
    if ([candidate length] == 0) {
      continue;
    }
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }
  return @"C:/msys64/usr/bin/bash.exe";
}

int ALNTestAvailableTCPPort(void) {
#if defined(_WIN32)
  if (!ALNTestSupportEnsureWinsockInitialized()) {
    return ALNTestSupportFallbackPort();
  }

  SOCKET fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (fd != INVALID_SOCKET) {
    int port = 0;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
      int length = (int)sizeof(address);
      if (getsockname(fd, (struct sockaddr *)&address, &length) == 0) {
        port = (int)ntohs(address.sin_port);
      }
    }

    (void)closesocket(fd);
    if (port > 0) {
      return port;
    }
  }
#else
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd >= 0) {
    int port = 0;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
      socklen_t length = sizeof(address);
      if (getsockname(fd, (struct sockaddr *)&address, &length) == 0) {
        port = (int)ntohs(address.sin_port);
      }
    }

    close(fd);
    if (port > 0) {
      return port;
    }
  }
#endif

  return ALNTestSupportFallbackPort();
}

NSString *ALNTestShellPath(NSString *path) {
  NSString *normalized =
      ALNTestSupportPortablePath([path isKindOfClass:[NSString class]] ? path : @"");
  if (![normalized length]) {
    return normalized;
  }
#if defined(_WIN32)
  if ([normalized hasPrefix:@"/"]) {
    return normalized;
  }
  if ([normalized length] >= 3) {
    unichar drive = [normalized characterAtIndex:0];
    unichar colon = [normalized characterAtIndex:1];
    unichar slash = [normalized characterAtIndex:2];
    if (((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) && colon == ':' &&
        slash == '/') {
      NSString *suffix = [normalized substringFromIndex:3];
      return [NSString stringWithFormat:@"/%c/%@",
                                        (char)tolower((int)drive),
                                        suffix ?: @""];
    }
  }
#endif
  return normalized;
}

NSString *ALNTestResolvedExecutablePath(NSString *path) {
  NSString *resolved =
      ALNTestSupportPortablePath([path isKindOfClass:[NSString class]] ? path : @"");
#if defined(_WIN32)
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:resolved]) {
    return resolved;
  }
  if ([resolved length] > 0 && ![[resolved lowercaseString] hasSuffix:@".exe"]) {
    NSString *candidate = [resolved stringByAppendingString:@".exe"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }
#endif
  return resolved;
}

NSString *ALNTestPlatformLinkFlags(void) {
#if defined(_WIN32)
  return @"-lws2_32";
#else
  return @"-ldl";
#endif
}

NSString *ALNTestUniqueIdentifier(NSString *prefix) {
  NSString *sanitizedPrefix = ALNTestSupportSanitizedPrefix(prefix);
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"%@_%@", sanitizedPrefix, uuid];
}

NSString *ALNTestTemporaryDirectory(NSString *prefix) {
  NSString *sanitizedPrefix = ALNTestSupportSanitizedPrefix(prefix);
  NSString *base = [ALNTestRepoRoot() stringByAppendingPathComponent:@"build/test-tmp"];
  if (![base length]) {
    base = NSTemporaryDirectory();
    if (![base length]) {
      base = [@"." stringByStandardizingPath];
    }
  }
  base = ALNTestSupportPortablePath(base);
  NSString *directoryName =
      [NSString stringWithFormat:@"%@-%@", sanitizedPrefix, [[[NSUUID UUID] UUIDString] lowercaseString]];
  NSString *candidate = ALNTestSupportPortablePath([base stringByAppendingPathComponent:directoryName]);
  NSError *createError = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:candidate
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&createError];
  if (!created || createError != nil) {
    return nil;
  }
  return candidate;
}

BOOL ALNTestWriteUTF8File(NSString *path, NSString *content, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *resolvedPath =
      ALNTestSupportPortablePath([path isKindOfClass:[NSString class]] ? path : @"");
  NSString *directory = [resolvedPath stringByDeletingLastPathComponent];
  NSError *directoryError = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&directoryError];
  if (!created || directoryError != nil) {
    if (error != NULL) {
      *error = directoryError ?: ALNTestSupportMakeError(
                                     @"failed creating parent directory for test file",
                                     @{
                                       NSLocalizedDescriptionKey :
                                           @"failed creating parent directory for test file",
                                       @"path" : resolvedPath ?: @"",
                                     });
    }
    return NO;
  }

  NSError *writeError = nil;
  BOOL wrote = [[content isKindOfClass:[NSString class]] ? content : @""
      writeToFile:resolvedPath
       atomically:YES
         encoding:NSUTF8StringEncoding
            error:&writeError];
  if (!wrote || writeError != nil) {
    if (error != NULL) {
      *error = writeError;
    }
    return NO;
  }
  return YES;
}

NSString *ALNTestRunShellCapture(NSString *command, int *exitCode) {
  @try {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = ALNTestResolvedBashLaunchPath();
    task.arguments = @[ @"-lc", [command isKindOfClass:[NSString class]] ? command : @"" ];

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    NSFileHandle *stdoutHandle = [stdoutPipe fileHandleForReading];
    NSFileHandle *stderrHandle = [stderrPipe fileHandleForReading];
    __block NSData *stdoutData = nil;
    __block NSData *stderrData = nil;
    dispatch_group_t readGroup = dispatch_group_create();
    dispatch_queue_t readQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    [task launch];
    dispatch_group_async(readGroup, readQueue, ^{
      stdoutData = [stdoutHandle readDataToEndOfFile];
    });
    dispatch_group_async(readGroup, readQueue, ^{
      stderrData = [stderrHandle readDataToEndOfFile];
    });
    [task waitUntilExit];
    dispatch_group_wait(readGroup, DISPATCH_TIME_FOREVER);

    if (exitCode != NULL) {
      *exitCode = task.terminationStatus;
    }

    NSMutableData *combined = [NSMutableData dataWithData:stdoutData ?: [NSData data]];
    if ([stderrData length] > 0) {
      [combined appendData:stderrData];
    }
    NSString *output = [[NSString alloc] initWithData:combined encoding:NSUTF8StringEncoding];
    return output ?: @"";
  } @catch (NSException *exception) {
    if (exitCode != NULL) {
      *exitCode = 127;
    }
    return exception.reason ?: @"shell command failed";
  }
}
