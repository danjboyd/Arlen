#import "ALNTestSupport.h"

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
  @try {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[ @"-lc", [command isKindOfClass:[NSString class]] ? command : @"" ];

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    [task launch];
    [task waitUntilExit];

    if (exitCode != NULL) {
      *exitCode = task.terminationStatus;
    }

    NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
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
