#ifndef ALN_TEMPLATE_TEST_SUPPORT_H
#define ALN_TEMPLATE_TEST_SUPPORT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNTemplateFixturePath(NSString *relativePath);
FOUNDATION_EXPORT NSString *_Nullable ALNTemplateFixtureText(NSString *relativePath,
                                                             NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNTemplateRegressionCatalog(
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSString *ALNTemplateModuleTemplateRoot(void);

NS_ASSUME_NONNULL_END

#endif
