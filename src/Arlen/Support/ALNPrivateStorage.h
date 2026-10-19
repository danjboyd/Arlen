#ifndef ALN_PRIVATE_STORAGE_H
#define ALN_PRIVATE_STORAGE_H
#import <Foundation/Foundation.h>

// Internal Windows storage seam, shared by adapters and the storage catalog.
// The path must exist; final reparse points and unexpected file kinds fail.
#if defined(_WIN32)
FOUNDATION_EXPORT BOOL ALNWindowsSecurePrivatePath(NSString *path, BOOL directory, NSError **error);
#endif
#endif
