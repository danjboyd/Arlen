#import "ALNSPAFallbackController.h"

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNFileResponse.h"

@implementation ALNSPAFallbackController

- (id)shell:(ALNContext *)ctx {
  NSDictionary *fallback = [ctx application].spaFallback;
  NSString *file = [fallback[@"file"] isKindOfClass:[NSString class]] ? fallback[@"file"] : @"";
  NSString *cacheControl =
      [fallback[@"cacheControl"] isKindOfClass:[NSString class]] ? fallback[@"cacheControl"] : @"no-cache";
  [self renderFileAtPath:file
             contentType:@"text/html; charset=utf-8"
                 options:@{ ALNFileResponseCacheControlOption : cacheControl }];
  return nil;
}

@end
