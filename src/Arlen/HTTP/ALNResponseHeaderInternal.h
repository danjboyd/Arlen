#import <Foundation/Foundation.h>
#import "ALNResponse.h"

@class ALNApplication;

// Private immutable, validated snapshot. Never exported by the public umbrella.
@interface ALNPreparedResponseHeaders : NSObject
- (instancetype)initWithHeaders:(NSDictionary<NSString *, NSString *> *)headers;
@end

@interface ALNResponse (ALNPreparedHeaders)
- (void)aln_setPreparedHeadersIfMissing:(ALNPreparedResponseHeaders *)headers;
@end

FOUNDATION_EXPORT void ALNApplyBaselineSecurityHeaders(ALNApplication *application,
                                                      ALNResponse *response);
