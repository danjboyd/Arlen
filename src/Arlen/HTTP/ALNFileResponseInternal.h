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

#endif
