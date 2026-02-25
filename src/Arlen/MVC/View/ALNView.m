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
  NSDictionary *bodyToken = ALNEOCPushRenderOptions(strictLocals, strictStringify);
  NSString *body = nil;
  @try {
    body = ALNEOCRenderTemplate(logical, context ?: @{}, error);
  } @finally {
    ALNEOCPopRenderOptions(bodyToken);
  }
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
  NSDictionary *layoutToken = ALNEOCPushRenderOptions(strictLocals, strictStringify);
  NSString *renderedLayout = nil;
  @try {
    renderedLayout = ALNEOCRenderTemplate(layoutLogical, layoutContext, error);
  } @finally {
    ALNEOCPopRenderOptions(layoutToken);
  }
  return renderedLayout;
}

@end
