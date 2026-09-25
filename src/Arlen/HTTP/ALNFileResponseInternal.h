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

#endif
