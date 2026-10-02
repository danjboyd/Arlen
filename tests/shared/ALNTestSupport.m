#import "ALNTestSupport.h"
#import <signal.h>

#import <ctype.h>
#import <string.h>
#import <unistd.h>

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
  const char *templateCString = [templatePath fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  char *created = (buffer != NULL) ? mkdtemp(buffer) : NULL;
  NSString *result = created != NULL
                         ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                         length:strlen(created)]
                         : nil;
  free(buffer);
  return result;
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
    task.launchPath = @"/bin/bash";
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

NSString *ALNTestClientCompileCommand(NSArray<NSString *> *sources, NSString *includeDirectory, NSString *output) {
  NSMutableArray *quoted = [NSMutableArray array];
  for (NSString *source in sources) {
    [quoted addObject:ALNTestShellQuote(source)];
  }
  NSString *includes = [includeDirectory length] ? [@"-I" stringByAppendingString:ALNTestShellQuote(includeDirectory)] : @"";
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
    task.launchPath = @"/bin/bash";
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
    kill(task.processIdentifier, SIGTERM);
    for (NSUInteger attempt = 0; attempt < 100 && [task isRunning]; attempt++) {
      [NSThread sleepForTimeInterval:0.05];
    }
    if ([task isRunning]) {
      kill(task.processIdentifier, SIGKILL);
    }
  }
  [task waitUntilExit];
  return ![task isRunning];
}
