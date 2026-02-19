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
  return [self renderTemplate:templateName
                      context:context
                       layout:layoutName
                 strictLocals:NO
              strictStringify:NO
                        error:error];
}

+ (NSString *)renderTemplate:(NSString *)templateName
                     context:(NSDictionary *)context
                      layout:(NSString *)layoutName
                strictLocals:(BOOL)strictLocals
             strictStringify:(BOOL)strictStringify
                       error:(NSError **)error {
  NSString *logical = [self normalizeTemplateLogicalPath:templateName];
  BOOL previousStrictLocals = ALNEOCStrictLocalsEnabled();
  BOOL previousStrictStringify = ALNEOCStrictStringifyEnabled();
  ALNEOCSetStrictLocalsEnabled(strictLocals);
  ALNEOCSetStrictStringifyEnabled(strictStringify);

  NSString *body = ALNEOCRenderTemplate(logical, context ?: @{}, error);
  ALNEOCSetStrictLocalsEnabled(previousStrictLocals);
  ALNEOCSetStrictStringifyEnabled(previousStrictStringify);
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
  ALNEOCSetStrictLocalsEnabled(strictLocals);
  ALNEOCSetStrictStringifyEnabled(strictStringify);
  NSString *renderedLayout = ALNEOCRenderTemplate(layoutLogical, layoutContext, error);
  ALNEOCSetStrictLocalsEnabled(previousStrictLocals);
  ALNEOCSetStrictStringifyEnabled(previousStrictStringify);
  return renderedLayout;
}

@end
