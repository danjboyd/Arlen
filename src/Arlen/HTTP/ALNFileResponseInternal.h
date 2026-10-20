#ifndef ALN_FILE_RESPONSE_INTERNAL_H
#define ALN_FILE_RESPONSE_INTERNAL_H

#import <Foundation/Foundation.h>
#import <sys/stat.h>

#import "ALNFileResponse.h"

// Framework-internal entry point for callers that have already stat'ed and
// authorized filePath (static mounts). Not exported from Arlen.h.
FOUNDATION_EXPORT void ALNFileResponseApplyStat(ALNResponse *response,
                                                ALNRequest *request,
                                                NSString *filePath,
                                                const struct stat *fileStat,
                                                NSString *contentType,
                                                NSDictionary *options);

// Static-mount Cache-Control rules. `config` is either one header value or a
// dictionary of glob pattern -> value with an optional `default` key. Patterns
// match the file path relative to the mount root: `*` and `?` stay within one
// path segment, `**` spans segments. Returns nil and sets *reason when invalid;
// returns an empty array for a nil config. More literal characters win.
FOUNDATION_EXPORT NSArray *ALNStaticCacheControlRules(id config, NSString **reason);
FOUNDATION_EXPORT NSString *ALNStaticCacheControlForPath(NSArray *rules, NSString *relativePath);

// YES when a request path below a static mount names a hidden file or
// directory: any component starting with "." (".env.json", ".git/config.json"),
// splitting on "/" and "\" (a separator on Windows). ".well-known" (RFC 8615)
// is the one public dot-directory and is not hidden.
FOUNDATION_EXPORT BOOL ALNStaticRelativePathIsHidden(NSString *relativePath);

// The C string for a file path, or NULL when the path is empty or holds a
// control character. An NSString can contain U+0000, which a C path ends at,
// so a check made on the NSString (such as hasSuffix:@".pdf") would describe
// a different file than the one stat()/open() reach.
FOUNDATION_EXPORT const char *ALNFileResponseFilesystemPathCString(NSString *path);
// Same validated paths with native wide-character Windows filesystem calls.
FOUNDATION_EXPORT int ALNFileResponseStatPath(NSString *path, struct stat *info);
FOUNDATION_EXPORT int ALNFileResponseOpenPath(NSString *path, int flags);
// Windows returns an independent file position on the same pinned file object;
// POSIX callers use pread, so dup is sufficient there.
FOUNDATION_EXPORT int ALNFileResponseDuplicateReadDescriptor(int descriptor);

#endif
