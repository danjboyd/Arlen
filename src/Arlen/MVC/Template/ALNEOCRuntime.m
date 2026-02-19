#import "ALNEOCRuntime.h"

NSString *const ALNEOCErrorDomain = @"Arlen.EOC.Error";
NSString *const ALNEOCErrorLineKey = @"line";
NSString *const ALNEOCErrorColumnKey = @"column";
NSString *const ALNEOCErrorPathKey = @"path";

static NSMutableDictionary *ALNEOCTemplateRegistry(void) {
  static NSMutableDictionary *registry = nil;
  if (registry == nil) {
    registry = [[NSMutableDictionary alloc] init];
  }
  return registry;
}

static NSString *ALNEOCStringValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]]) {
    return (NSString *)value;
  }
  return [value description];
}

NSString *ALNEOCCanonicalTemplatePath(NSString *path) {
  if (path == nil) {
    return @"";
  }

  NSString *result = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  while ([result hasPrefix:@"./"]) {
    result = [result substringFromIndex:2];
  }
  while ([result hasPrefix:@"/"]) {
    result = [result substringFromIndex:1];
  }
  return result;
}

NSString *ALNEOCEscapeHTMLString(NSString *input) {
  if (input == nil || [input length] == 0) {
    return @"";
  }

  NSMutableString *escaped = [NSMutableString stringWithCapacity:[input length]];
  NSUInteger length = [input length];
  for (NSUInteger idx = 0; idx < length; idx++) {
    unichar ch = [input characterAtIndex:idx];
    switch (ch) {
    case '&':
      [escaped appendString:@"&amp;"];
      break;
    case '<':
      [escaped appendString:@"&lt;"];
      break;
    case '>':
      [escaped appendString:@"&gt;"];
      break;
    case '"':
      [escaped appendString:@"&quot;"];
      break;
    case '\'':
      [escaped appendString:@"&#39;"];
      break;
    default:
      [escaped appendFormat:@"%C", ch];
      break;
    }
  }
  return escaped;
}

void ALNEOCAppendEscaped(NSMutableString *out, id value) {
  if (out == nil) {
    return;
  }
  [out appendString:ALNEOCEscapeHTMLString(ALNEOCStringValue(value))];
}

void ALNEOCAppendRaw(NSMutableString *out, id value) {
  if (out == nil) {
    return;
  }
  [out appendString:ALNEOCStringValue(value)];
}

void ALNEOCClearTemplateRegistry(void) {
  @synchronized(ALNEOCTemplateRegistry()) {
    [ALNEOCTemplateRegistry() removeAllObjects];
  }
}

void ALNEOCRegisterTemplate(NSString *logicalPath, ALNEOCRenderFunction function) {
  NSString *canonical = ALNEOCCanonicalTemplatePath(logicalPath);
  if ([canonical length] == 0 || function == NULL) {
    return;
  }

  @synchronized(ALNEOCTemplateRegistry()) {
    ALNEOCTemplateRegistry()[canonical] = [NSValue valueWithPointer:function];
  }
}

ALNEOCRenderFunction ALNEOCResolveTemplate(NSString *logicalPath) {
  NSString *canonical = ALNEOCCanonicalTemplatePath(logicalPath);
  if ([canonical length] == 0) {
    return NULL;
  }

  NSValue *ptr = nil;
  @synchronized(ALNEOCTemplateRegistry()) {
    ptr = ALNEOCTemplateRegistry()[canonical];
  }

  if (ptr == nil) {
    return NULL;
  }
  return [ptr pointerValue];
}

NSString *ALNEOCRenderTemplate(NSString *logicalPath, id ctx, NSError **error) {
  ALNEOCRenderFunction function = ALNEOCResolveTemplate(logicalPath);
  if (function == NULL) {
    if (error != NULL) {
      NSString *canonical = ALNEOCCanonicalTemplatePath(logicalPath);
      *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                   code:ALNEOCErrorTemplateNotFound
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"Template not found: %@",
                                                              canonical],
                                 ALNEOCErrorPathKey : canonical
                               }];
    }
    return nil;
  }

  NSError *innerError = nil;
  NSString *rendered = function(ctx, &innerError);
  if (rendered == nil) {
    if (error != NULL) {
      if (innerError != nil) {
        *error = innerError;
      } else {
        NSString *canonical = ALNEOCCanonicalTemplatePath(logicalPath);
        *error = [NSError
            errorWithDomain:ALNEOCErrorDomain
                       code:ALNEOCErrorTemplateExecutionFailed
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Template render failed: %@",
                                                  canonical],
                     ALNEOCErrorPathKey : canonical
                   }];
      }
    }
    return nil;
  }
  return rendered;
}

BOOL ALNEOCInclude(NSMutableString *out, id ctx, NSString *logicalPath, NSError **error) {
  NSString *rendered = ALNEOCRenderTemplate(logicalPath, ctx, error);
  if (rendered == nil) {
    return NO;
  }
  [out appendString:rendered];
  return YES;
}
