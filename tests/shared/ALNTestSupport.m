#import "ALNTestSupport.h"
#import "ALNTestWait.h"
#import <dispatch/dispatch.h>
#import <signal.h>

#import <ctype.h>
#import <string.h>
#import <unistd.h>
#import <fcntl.h>
#if defined(_WIN32)
#import <io.h>
#import <windows.h>
#endif
#import <errno.h>

#import "ALNPlatform.h"

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

static NSError *ALNTestSupportMakeError(NSString *message, NSDictionary *userInfo) {
  return [NSError errorWithDomain:ALNTestSupportErrorDomain
                             code:1
                         userInfo:userInfo != nil
                                      ? userInfo
                                      : @{
                                          NSLocalizedDescriptionKey : message ?: @"test support error",
                                        }];
}

NSString *ALNTestRepoRoot(void) {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

NSString *ALNTestPathFromRepoRoot(NSString *relativePath) {
  return [ALNTestRepoRoot() stringByAppendingPathComponent:relativePath ?: @""];
}

NSString *ALNTestShellQuote(NSString *value) {
  NSString *safeValue = [value isKindOfClass:[NSString class]] ? value : @"";
  return [NSString stringWithFormat:@"'%@'",
                                    [safeValue stringByReplacingOccurrencesOfString:@"'"
                                                                            withString:@"'\"'\"'"]];
}

NSString *ALNTestGNUstepSourceCommandForRepoRoot(NSString *repoRoot) {
#if defined(__APPLE__)
  (void)repoRoot;
  return @":";
#else
  NSString *resolvedRepoRoot =
      ([repoRoot isKindOfClass:[NSString class]] && [repoRoot length] > 0) ? repoRoot : ALNTestRepoRoot();
  NSString *helperPath = [resolvedRepoRoot stringByAppendingPathComponent:@"tools/source_gnustep_env.sh"];
  return [NSString stringWithFormat:@"source %@", ALNTestShellQuote(helperPath)];
#endif
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

NSString *ALNTestUniqueIdentifier(NSString *prefix) {
  NSString *sanitizedPrefix = ALNTestSupportSanitizedPrefix(prefix);
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"%@_%@", sanitizedPrefix, uuid];
}

NSString *ALNTestTemporaryDirectory(NSString *prefix) {
  NSString *sanitizedPrefix = ALNTestSupportSanitizedPrefix(prefix);
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-XXXXXX",
                                                                                         sanitizedPrefix]];
#if defined(_WIN32)
  // No mkdtemp on MinGW, and -fileSystemRepresentation is UTF-16 there; a
  // UUID-named directory created exclusively is just as unique.
  NSString *uniquePath = [templatePath stringByReplacingOccurrencesOfString:@"XXXXXX"
                                                                 withString:[[NSUUID UUID] UUIDString]];
  return [[NSFileManager defaultManager] createDirectoryAtPath:uniquePath
                                   withIntermediateDirectories:NO
                                                    attributes:nil
                                                         error:NULL]
             ? uniquePath
             : nil;
#else
  const char *templateCString = [templatePath fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  char *created = (buffer != NULL) ? mkdtemp(buffer) : NULL;
  NSString *result = created != NULL
                         ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                         length:strlen(created)]
                         : nil;
  free(buffer);
  return result;
#endif
}

BOOL ALNTestWriteUTF8File(NSString *path, NSString *content, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *resolvedPath = [path isKindOfClass:[NSString class]] ? path : @"";
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

static BOOL ALNTestShellHasGNUTimeout(void) {
  static BOOL available = NO;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"] ?: @"/usr/bin:/bin";
    for (NSString *directory in [path componentsSeparatedByString:@":"]) {
      if ([directory length] > 0 &&
          [[NSFileManager defaultManager]
              isExecutableFileAtPath:[directory stringByAppendingPathComponent:@"timeout"]]) {
        available = YES;
        break;
      }
    }
  });
  return available;
}

NSString *ALNTestShellTimeoutPrefix(NSUInteger seconds) {
  if (ALNTestShellHasGNUTimeout()) {
    return [NSString stringWithFormat:@"timeout %lus", (unsigned long)seconds];
  }
  return [NSString stringWithFormat:@"perl -e 'alarm shift; exec @ARGV or die \"exec: $!\\n\"' %lu",
                                    (unsigned long)seconds];
}

BOOL ALNTestShellTimeoutExitedByTimeout(int exitCode) {
  // GNU timeout exits 124; a process killed by SIGALRM reports 128 + 14.
#if defined(SIGALRM)
  return ALNTestShellHasGNUTimeout() ? (exitCode == 124) : (exitCode == 128 + SIGALRM);
#else
  // Windows has no SIGALRM; MSYS2 ships GNU coreutils timeout.
  return exitCode == 124;
#endif
}

NSString *ALNTestRunShellCapture(NSString *command, int *exitCode) {
  NSString *capturePath = nil;
  @try {
    capturePath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-shell-capture-%@.log",
                                                                  [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createFileAtPath:capturePath contents:nil attributes:nil];
    NSFileHandle *captureHandle = [NSFileHandle fileHandleForWritingAtPath:capturePath];
    if (captureHandle == nil) {
      if (exitCode != NULL) {
        *exitCode = 127;
      }
      return @"failed to create shell capture file";
    }

    NSTask *task = [[NSTask alloc] init];
    task.environment = ALNTestShellEnvironment([[NSProcessInfo processInfo] environment]);
    task.launchPath = ALNTestBashPath();
    task.arguments = @[ @"-lc", [command isKindOfClass:[NSString class]] ? command : @"" ];

    task.standardOutput = captureHandle;
    task.standardError = captureHandle;

    [task launch];
    [task waitUntilExit];
    [captureHandle closeFile];

    if (exitCode != NULL) {
      *exitCode = task.terminationStatus;
    }

    NSData *capturedData = [NSData dataWithContentsOfFile:capturePath] ?: [NSData data];
    [[NSFileManager defaultManager] removeItemAtPath:capturePath error:NULL];
    NSString *output = [[NSString alloc] initWithData:capturedData encoding:NSUTF8StringEncoding];
    return output ?: @"";
  } @catch (NSException *exception) {
    if (capturePath != nil) {
      [[NSFileManager defaultManager] removeItemAtPath:capturePath error:NULL];
    }
    if (exitCode != NULL) {
      *exitCode = 127;
    }
    return exception.reason ?: @"shell command failed";
  }
}

NSDictionary<NSString *, NSString *> *ALNTestShellEnvironment(
    NSDictionary<NSString *, NSString *> *environment) {
  // Strip only TSAN preloads before exec: clearing them inside bash is too late.
  // Instrumented executables load their linked sanitizer runtime themselves.
  // Keep TSAN_OPTIONS so those children retain the lane's diagnostic policy.
  NSMutableDictionary *child = [environment mutableCopy];
  NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" :\t\n"];
  for (NSString *name in @[ @"LD_PRELOAD", @"XCTEST_LD_PRELOAD" ]) {
    NSString *value = child[name];
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSMutableArray *retained = [NSMutableArray array];
    for (NSString *library in [value componentsSeparatedByCharactersInSet:separators]) {
      NSString *filename = [library lastPathComponent];
      BOOL isTSAN = [filename hasPrefix:@"libtsan.so"] || [filename hasPrefix:@"libclang_rt.tsan"];
      if ([library length] > 0 && !isTSAN) {
        [retained addObject:library];
      }
    }
    if ([retained count] > 0) {
      child[name] = [retained componentsJoinedByString:@" "];
    } else {
      [child removeObjectForKey:name];
    }
  }
  return child;
}

NSString *ALNTestFrameworkBuildCommand(NSString *targets) {
#if defined(__APPLE__)
  (void)targets;
  return @"./bin/build-apple --with-boomhauer";
#else
  return [NSString stringWithFormat:@"make %@", targets ?: @""];
#endif
}

NSString *ALNTestAppBinaryRelativePath(void) {
#if defined(__APPLE__)
  return @".boomhauer/apple/boomhauer-app";
#else
  return ALNTestExecutablePath(@".boomhauer/build/boomhauer-app");
#endif
}

NSString *ALNTestExecutablePath(NSString *path) {
#if defined(_WIN32)
  return [[path pathExtension] length] > 0 ? path : [path stringByAppendingPathExtension:@"exe"];
#else
  return path;
#endif
}

NSString *ALNTestClientCompileCommand(NSArray<NSString *> *sources, NSString *includeDirectory, NSString *output) {
  NSMutableArray *quoted = [NSMutableArray array];
  for (NSString *source in sources) {
    [quoted addObject:ALNTestShellQuote(source)];
  }
  NSString *includes = [includeDirectory length] ? [@"-I" stringByAppendingString:ALNTestShellQuote(includeDirectory)] : @"";
#if defined(__APPLE__)
  return [NSString stringWithFormat:@"%@ --output %@ %@ %@",
                                    ALNTestShellQuote([ALNTestRepoRoot()
                                        stringByAppendingPathComponent:@"tools/apple_compile_program.sh"]),
                                    ALNTestShellQuote(output), includes, [quoted componentsJoinedByString:@" "]];
#endif
  return [NSString stringWithFormat:@"%@ && make -C %@ test-client-program %@ %@ %@",
      ALNTestGNUstepSourceCommandForRepoRoot(ALNTestRepoRoot()), ALNTestShellQuote(ALNTestRepoRoot()),
      ALNTestShellQuote([@"CLIENT_SOURCES=" stringByAppendingString:[quoted componentsJoinedByString:@" "]]),
      ALNTestShellQuote([@"CLIENT_INCLUDE_FLAGS=" stringByAppendingString:includes]),
      ALNTestShellQuote([@"CLIENT_OUTPUT=" stringByAppendingString:output])];
}

NSDictionary *ALNTestRunShellCaptureStreams(NSString *command) {
  NSString *directory = ALNTestTemporaryDirectory(@"arlen-stream-capture");
  if (directory == nil) {
    return @{ @"status" : @127, @"stdout" : @"", @"stderr" : @"failed creating capture directory" };
  }
  NSMutableArray *handles = [NSMutableArray array];
  @try {
    for (NSString *name in @[ @"stdout", @"stderr" ]) {
      NSString *path = [directory stringByAppendingPathComponent:name];
      [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
      NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
      if (handle == nil) {
        return @{ @"status" : @127, @"stdout" : @"", @"stderr" : @"failed opening capture file" };
      }
      [handles addObject:handle];
    }
    NSTask *task = [[NSTask alloc] init];
    task.environment = ALNTestShellEnvironment([[NSProcessInfo processInfo] environment]);
    task.launchPath = ALNTestBashPath();
    task.arguments = @[ @"-lc", command ?: @"" ];
    task.standardOutput = handles[0];
    task.standardError = handles[1];
    [task launch];
    [task waitUntilExit];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:@(task.terminationStatus) forKey:@"status"];
    for (NSString *name in @[ @"stdout", @"stderr" ]) {
      result[name] = [NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:name]
                                             encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    }
    return result;
  } @catch (NSException *exception) {
    return @{ @"status" : @127, @"stdout" : @"", @"stderr" : exception.reason ?: @"launch failed" };
  } @finally {
    for (NSFileHandle *handle in handles) {
      [handle closeFile];
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
  }
}

BOOL ALNTestStopServerTask(NSTask *task) {
  if (task == nil) {
    return YES;
  }
  if ([task isRunning]) {
#if defined(_WIN32)
    // No signals on Windows, and ending a process does not end its children:
    // an MSYS2 `exec` leaves bash waiting on the exec'd program, and servers
    // started through a shell outlive it. Kill the whole tree, as the
    // phase24 runtime tests do, then fall back to -terminate.
    NSTask *killer = [[NSTask alloc] init];
    killer.launchPath = @"C:/Windows/System32/taskkill.exe";
    killer.arguments = @[ @"/T", @"/F", @"/PID", [NSString stringWithFormat:@"%d", task.processIdentifier] ];
    killer.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    killer.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
      [killer launch];
      [killer waitUntilExit];
    } @catch (NSException *exception) {
      (void)exception;
    }
    if (!ALNTestWaitForTaskExit(task, 5.0)) {
      [task terminate];
      (void)ALNTestWaitForTaskExit(task, 5.0);
    }
#else
    kill(task.processIdentifier, SIGTERM);
    if (!ALNTestWaitForTaskExit(task, 5.0)) {
      kill(task.processIdentifier, SIGKILL);
    }
#endif
  }
  [task waitUntilExit];
  return ![task isRunning];
}

BOOL ALNTestCreatePipe(int fds[2], BOOL nonBlockingRead) {
  fds[0] = -1;
  fds[1] = -1;
#if defined(_WIN32)
  (void)nonBlockingRead;
  return _pipe(fds, 1u << 20, _O_BINARY) == 0;
#else
  if (pipe(fds) != 0) {
    return NO;
  }
  if (nonBlockingRead) {
    int flags = fcntl(fds[0], F_GETFL);
    if (flags < 0 || fcntl(fds[0], F_SETFL, flags | O_NONBLOCK) != 0) {
      return NO;
    }
  }
  return YES;
#endif
}

uint32_t ALNTestRandomUniform(uint32_t upperBound) {
  if (upperBound < 2) {
    return 0;
  }
  // Rejection sampling, as arc4random_uniform does, to avoid modulo bias.
  uint32_t limit = UINT32_MAX - (UINT32_MAX % upperBound);
  uint32_t value = 0;
  do {
    if (!ALNPlatformFillRandomBytes(&value, sizeof(value))) {
      value = (uint32_t)[[NSUUID UUID] hash];
    }
  } while (value >= limit);
  return value % upperBound;
}

BOOL ALNTestProcessExists(int pid) {
  if (pid <= 0) {
    return NO;
  }
#if defined(_WIN32)
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, (DWORD)pid);
  if (process == NULL) {
    return NO;
  }
  BOOL running = (WaitForSingleObject(process, 0) == WAIT_TIMEOUT);
  CloseHandle(process);
  return running;
#else
  return kill(pid, 0) == 0 || errno == EPERM;
#endif
}

NSString *ALNTestBashPath(void) {
  return ALNPlatformBashPath();
}

NSString *ALNTestToolPath(NSString *tool) {
  NSString *path = [[NSProcessInfo processInfo] environment][@"PATH"] ?: @"";
#if defined(_WIN32)
  NSString *separator = @";";
  NSString *name = [[tool pathExtension] length] > 0 ? tool : [tool stringByAppendingPathExtension:@"exe"];
#else
  NSString *separator = @":";
  NSString *name = tool;
#endif
  for (NSString *directory in [path componentsSeparatedByString:separator]) {
    if ([directory length] == 0) {
      continue;
    }
    NSString *candidate = [directory stringByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }
  return tool;
}

NSString *ALNTestPlatformObjCFlags(void) {
#if defined(_WIN32)
  return @"-DHAVE_MODE_T=1 -UGNUSTEP_WITH_DLL -DGNUSTEP_WITHOUT_DLL=1";
#else
  return @"";
#endif
}

NSString *ALNTestPlatformLinkLibraries(void) {
#if defined(_WIN32)
  return @"-lws2_32 -lbcrypt";
#else
  return @"-ldl";
#endif
}

int ALNTestKill(int pid, int signal) {
#if defined(_WIN32)
  if (signal != SIGTERM && signal != SIGKILL) {
    errno = ENOSYS;
    return -1;
  }
  if (pid <= 0) {
    errno = EINVAL;
    return -1;
  }
  NSTask *killer = [[NSTask alloc] init];
  killer.launchPath = @"C:/Windows/System32/taskkill.exe";
  killer.arguments = @[ @"/T", @"/F", @"/PID", [NSString stringWithFormat:@"%d", pid] ];
  killer.standardOutput = [NSFileHandle fileHandleWithNullDevice];
  killer.standardError = [NSFileHandle fileHandleWithNullDevice];
  @try {
    [killer launch];
    [killer waitUntilExit];
  } @catch (NSException *exception) {
    (void)exception;
    errno = ESRCH;
    return -1;
  }
  if (killer.terminationStatus != 0) {
    errno = ESRCH;
    return -1;
  }
  return 0;
#else
  return kill(pid, signal);
#endif
}
