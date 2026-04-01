#import <Foundation/Foundation.h>

#import "ALNApplication.h"
#import "ALNSearchModule.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const Phase27SearchPredicateAllowedStashKey;

FOUNDATION_EXPORT NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase27SearchProductStore(void);
FOUNDATION_EXPORT void Phase27SearchResetStores(void);
FOUNDATION_EXPORT void Phase27SearchSetProductsBuildShouldFail(BOOL shouldFail);
FOUNDATION_EXPORT NSString *Phase27SearchUniquePostgresTableName(void);

@interface Phase27SearchProvider : NSObject <ALNSearchResourceProvider>
@end

@interface Phase27SearchContextMiddleware : NSObject <ALNMiddleware>
@end

NS_ASSUME_NONNULL_END
