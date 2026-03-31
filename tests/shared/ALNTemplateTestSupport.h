#ifndef ALN_TEMPLATE_TEST_SUPPORT_H
#define ALN_TEMPLATE_TEST_SUPPORT_H

#import <Foundation/Foundation.h>
#import "ALNExports.h"

NS_ASSUME_NONNULL_BEGIN

ALN_EXPORT NSString *ALNTemplateFixturePath(NSString *relativePath);
ALN_EXPORT NSString *_Nullable ALNTemplateFixtureText(NSString *relativePath,
                                                      NSError *_Nullable *_Nullable error);
ALN_EXPORT NSDictionary *_Nullable ALNTemplateRegressionCatalog(
    NSError *_Nullable *_Nullable error);
ALN_EXPORT NSString *ALNTemplateModuleTemplateRoot(void);

NS_ASSUME_NONNULL_END

#endif
