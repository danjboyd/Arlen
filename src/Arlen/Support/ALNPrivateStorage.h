#ifndef ALN_PRIVATE_STORAGE_H
#define ALN_PRIVATE_STORAGE_H
#import <Foundation/Foundation.h>

// Internal atomic writer for generated secrets. Secures the containing directory
// before creating payload files; uses owner-only permissions or a private DACL.
FOUNDATION_EXPORT BOOL ALNWritePrivateDataAtomically(NSData *data, NSString *path, NSError **error);

// Internal Windows storage seam, shared by adapters and the storage catalog.
// The path must exist; final reparse points and unexpected file kinds fail.
#if defined(_WIN32)
FOUNDATION_EXPORT BOOL ALNWindowsSecurePrivatePath(NSString *path, BOOL directory, NSError **error);
#endif
#endif
