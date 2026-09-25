#ifndef ALN_FILE_RESPONSE_H
#define ALN_FILE_RESPONSE_H

#import <Foundation/Foundation.h>

@class ALNRequest;
@class ALNResponse;

NS_ASSUME_NONNULL_BEGIN

// Option keys for +prepareResponse:forRequest:filePath:contentType:options:.
extern NSString *const ALNFileResponseCacheControlOption; // NSString Cache-Control value
extern NSString *const ALNFileResponseDownloadNameOption; // NSString; sends Content-Disposition: attachment
extern NSString *const ALNFileResponseETagOption;         // NSString strong or W/ entity tag
extern NSString *const ALNFileResponseMIMETypesOption;    // NSDictionary extension -> Content-Type overrides

// Serves a regular file with the same validator, conditional-request, single
// byte-range, HEAD and sendfile behavior as static mounts (docs/STATIC_FILES.md).
// On success the response is committed with status 200, 206, 304, 412 or 416 and
// YES is returned. A missing, non-regular or unreadable file commits a 404 and
// returns NO. The caller is responsible for authorizing access to filePath.
@interface ALNFileResponse : NSObject

+ (BOOL)prepareResponse:(ALNResponse *)response
             forRequest:(ALNRequest *)request
               filePath:(NSString *)filePath
            contentType:(nullable NSString *)contentType
                options:(nullable NSDictionary *)options;

@end

NS_ASSUME_NONNULL_END

#endif
