#import "ALNView.h"

#import "ALNEOCRuntime.h"

@implementation ALNView

+ (NSString *)normalizeTemplateLogicalPath:(NSString *)templateName {
  if ([templateName length] == 0) {
    return @"";
  }
  NSString *normalized = [templateName copy];
  if (![normalized hasSuffix:@".html.eoc"]) {
    normalized = [normalized stringByAppendingString:@".html.eoc"];
  }
  while ([normalized hasPrefix:@"/"]) {
    normalized = [normalized substringFromIndex:1];
  }
  return normalized;
}

+ (NSString *)renderTemplate:(NSString *)templateName
                     context:(NSDictionary *)context
                      layout:(NSString *)layoutName
                       error:(NSError **)error {
  NSString *logical = [self normalizeTemplateLogicalPath:templateName];
  NSString *body = ALNEOCRenderTemplate(logical, context ?: @{}, error);
  if (body == nil) {
    return nil;
  }

  if ([layoutName length] == 0) {
    return body;
  }

  NSMutableDictionary *layoutContext =
      [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
  layoutContext[@"content"] = body;
  NSString *layoutLogical = [self normalizeTemplateLogicalPath:layoutName];
  return ALNEOCRenderTemplate(layoutLogical, layoutContext, error);
}

@end
