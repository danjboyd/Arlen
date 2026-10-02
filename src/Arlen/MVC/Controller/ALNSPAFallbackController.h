#ifndef ALN_SPA_FALLBACK_CONTROLLER_H
#define ALN_SPA_FALLBACK_CONTROLLER_H

#import "ALNController.h"

NS_ASSUME_NONNULL_BEGIN

// Framework-owned controller for the `spaFallback` app shell. Dispatch selects it
// only after the router and route-miss built-ins decline an eligible request.
@interface ALNSPAFallbackController : ALNController

- (nullable id)shell:(ALNContext *)ctx;

@end

NS_ASSUME_NONNULL_END

#endif
