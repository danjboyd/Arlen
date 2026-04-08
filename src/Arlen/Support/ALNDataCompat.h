#import <Foundation/Foundation.h>

static inline NSData *ALNDataReadFromFile(NSString *path, NSUInteger options, NSError **error) {
  (void)options;

  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil && error != NULL) {
    *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                 code:NSFileReadUnknownError
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"Failed reading file at %@", path ?: @""],
                               NSFilePathErrorKey : path ?: @""
                             }];
  }
  return data;
}
