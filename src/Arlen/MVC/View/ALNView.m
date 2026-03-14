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
         defaultLayoutEnabled:YES
                 strictLocals:NO
              strictStringify:NO
                        error:error];
}

+ (NSString *)renderTemplate:(NSString *)templateName
                     context:(NSDictionary *)context
                      layout:(NSString *)layoutName
        defaultLayoutEnabled:(BOOL)defaultLayoutEnabled
                strictLocals:(BOOL)strictLocals
             strictStringify:(BOOL)strictStringify
                       error:(NSError **)error {
  NSString *logical = [self normalizeTemplateLogicalPath:templateName];
  NSString *resolvedLayout = nil;
  if ([layoutName length] > 0) {
    resolvedLayout = [self normalizeTemplateLogicalPath:layoutName];
  } else if (defaultLayoutEnabled) {
    resolvedLayout = ALNEOCResolveTemplateLayout(logical);
  }
  NSDictionary *bodyToken = ALNEOCPushRenderOptions(strictLocals, strictStringify);
  NSDictionary *compositionToken = ALNEOCPushCompositionState();
  NSString *body = nil;
  @try {
    body = ALNEOCRenderTemplate(logical, context ?: @{}, error);
  } @finally {
    if (body != nil) {
      ALNEOCSetSlotContent(@"content", body);
    }
  }
  @try {
    if (body == nil) {
      return nil;
    }

    if ([resolvedLayout length] == 0) {
      return body;
    }

    NSMutableDictionary *layoutContext =
        [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
    layoutContext[@"content"] = body;
    return ALNEOCRenderTemplate(resolvedLayout, layoutContext, error);
  } @finally {
    ALNEOCPopCompositionState(compositionToken);
    ALNEOCPopRenderOptions(bodyToken);
  }
}

+ (NSString *)renderTemplate:(NSString *)templateName
                     context:(NSDictionary *)context
                      layout:(NSString *)layoutName
                strictLocals:(BOOL)strictLocals
             strictStringify:(BOOL)strictStringify
                       error:(NSError **)error {
  return [self renderTemplate:templateName
                      context:context
                       layout:layoutName
         defaultLayoutEnabled:YES
                 strictLocals:strictLocals
              strictStringify:strictStringify
                        error:error];
}

@end
