#import "ALNTemplateTestSupport.h"

#import "ALNTestSupport.h"

NSString *ALNTemplateFixturePath(NSString *relativePath) {
  NSString *suffix = [relativePath isKindOfClass:[NSString class]] ? relativePath : @"";
  return ALNTestPathFromRepoRoot([@"tests/fixtures/templates" stringByAppendingPathComponent:suffix]);
}

NSString *ALNTemplateFixtureText(NSString *relativePath, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *path = ALNTemplateFixturePath(relativePath);
  NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:error];
  return content;
}

NSDictionary *ALNTemplateRegressionCatalog(NSError **error) {
  return ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/templates/regressions/regression_catalog.json",
                                             error);
}

NSString *ALNTemplateModuleTemplateRoot(void) {
  return ALNTestPathFromRepoRoot(@"modules/auth/Resources/Templates");
}
