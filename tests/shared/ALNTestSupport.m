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
