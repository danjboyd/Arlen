#import "ALNEOCRuntime.h"

NSString *const ALNEOCErrorDomain = @"Arlen.EOC.Error";
NSString *const ALNEOCErrorLineKey = @"line";
NSString *const ALNEOCErrorColumnKey = @"column";
NSString *const ALNEOCErrorPathKey = @"path";
NSString *const ALNEOCErrorLocalNameKey = @"local";

static NSString *const ALNEOCThreadOptionsKey = @"aln.eoc.render_options";
static NSString *const ALNEOCThreadStrictLocalsKey = @"strict_locals";
static NSString *const ALNEOCThreadStrictStringifyKey = @"strict_stringify";

static NSMutableDictionary *ALNEOCTemplateRegistry(void) {
  static NSMutableDictionary *registry = nil;
  if (registry == nil) {
    registry = [[NSMutableDictionary alloc] init];
  }
  return registry;
}

static NSMutableDictionary *ALNEOCThreadOptions(void) {
  NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
  id current = threadDictionary[ALNEOCThreadOptionsKey];
  if ([current isKindOfClass:[NSMutableDictionary class]]) {
    return current;
  }
  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  options[ALNEOCThreadStrictLocalsKey] = @(NO);
  options[ALNEOCThreadStrictStringifyKey] = @(NO);
  threadDictionary[ALNEOCThreadOptionsKey] = options;
  return options;
}

BOOL ALNEOCStrictLocalsEnabled(void) {
  return [ALNEOCThreadOptions()[ALNEOCThreadStrictLocalsKey] boolValue];
}

BOOL ALNEOCStrictStringifyEnabled(void) {
  return [ALNEOCThreadOptions()[ALNEOCThreadStrictStringifyKey] boolValue];
}

void ALNEOCSetStrictLocalsEnabled(BOOL enabled) {
  ALNEOCThreadOptions()[ALNEOCThreadStrictLocalsKey] = @(enabled);
}

void ALNEOCSetStrictStringifyEnabled(BOOL enabled) {
  ALNEOCThreadOptions()[ALNEOCThreadStrictStringifyKey] = @(enabled);
}

static NSError *ALNEOCTemplateExecutionError(NSString *message,
                                             NSString *templatePath,
                                             NSUInteger line,
                                             NSUInteger column,
                                             NSString *localName) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"Template execution failed";
  if ([templatePath length] > 0) {
    userInfo[ALNEOCErrorPathKey] = templatePath;
  }
  if (line > 0) {
    userInfo[ALNEOCErrorLineKey] = @(line);
  }
  if (column > 0) {
    userInfo[ALNEOCErrorColumnKey] = @(column);
  }
  if ([localName length] > 0) {
    userInfo[ALNEOCErrorLocalNameKey] = localName;
  }
  return [NSError errorWithDomain:ALNEOCErrorDomain
                             code:ALNEOCErrorTemplateExecutionFailed
                         userInfo:userInfo];
}

static NSString *ALNEOCStringValueWithOptions(id value,
                                              BOOL strictStringify,
                                              BOOL *conversionOK) {
  if (value == nil || value == [NSNull null]) {
    if (conversionOK != NULL) {
      *conversionOK = YES;
    }
    return @"";
  }
  if ([value isKindOfClass:[NSString class]]) {
    if (conversionOK != NULL) {
      *conversionOK = YES;
    }
    return (NSString *)value;
  }

  if ([value respondsToSelector:@selector(stringValue)]) {
    id candidate = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    candidate = [value performSelector:@selector(stringValue)];
#pragma clang diagnostic pop
    if ([candidate isKindOfClass:[NSString class]]) {
      if (conversionOK != NULL) {
        *conversionOK = YES;
      }
      return candidate;
    }
  }

  if (strictStringify) {
    if (conversionOK != NULL) {
      *conversionOK = NO;
    }
    return nil;
  }

  if (conversionOK != NULL) {
    *conversionOK = YES;
  }
  return [value description] ?: @"";
}

static id ALNEOCLookupLocal(id ctx, NSString *name, BOOL *found) {
  if (found != NULL) {
    *found = NO;
  }
  if (ctx == nil || [name length] == 0) {
    return nil;
  }

  if ([ctx isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictionary = (NSDictionary *)ctx;
    id value = dictionary[name];
    if (value != nil && found != NULL) {
      *found = YES;
    }
    return value;
  }

  if ([ctx respondsToSelector:@selector(objectForKey:)]) {
    id value = [ctx objectForKey:name];
    if (value != nil && found != NULL) {
      *found = YES;
    }
    return value;
  }

  if ([ctx respondsToSelector:@selector(valueForKey:)]) {
    @try {
      id value = [ctx valueForKey:name];
      if (value != nil && found != NULL) {
        *found = YES;
      }
      return value;
    } @catch (NSException *exception) {
      (void)exception;
      return nil;
    }
  }

  return nil;
}

id ALNEOCLocal(id ctx,
               NSString *name,
               NSString *templatePath,
               NSUInteger line,
               NSUInteger column,
               NSError **error) {
  BOOL found = NO;
  id value = ALNEOCLookupLocal(ctx, name, &found);
  if (found) {
    return value;
  }

  if (ALNEOCStrictLocalsEnabled() && error != NULL) {
    NSString *message =
        [NSString stringWithFormat:@"Undefined EOC local: $%@", name ?: @""];
    *error = ALNEOCTemplateExecutionError(message, templatePath, line, column, name);
  }
  return nil;
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
  BOOL conversionOK = YES;
  NSString *rendered = ALNEOCStringValueWithOptions(value, NO, &conversionOK);
  (void)conversionOK;
  [out appendString:ALNEOCEscapeHTMLString(rendered ?: @"")];
}

void ALNEOCAppendRaw(NSMutableString *out, id value) {
  if (out == nil) {
    return;
  }
  BOOL conversionOK = YES;
  NSString *rendered = ALNEOCStringValueWithOptions(value, NO, &conversionOK);
  (void)conversionOK;
  [out appendString:rendered ?: @""];
}

static BOOL ALNEOCAppendChecked(NSMutableString *out,
                                id value,
                                BOOL escape,
                                NSString *templatePath,
                                NSUInteger line,
                                NSUInteger column,
                                NSError **error) {
  if (out == nil) {
    return YES;
  }

  BOOL conversionOK = YES;
  NSString *rendered =
      ALNEOCStringValueWithOptions(value, ALNEOCStrictStringifyEnabled(), &conversionOK);
  if (!conversionOK || rendered == nil) {
    if (error != NULL) {
      NSString *message = @"Expression output is not string-convertible in strict stringify mode";
      *error = ALNEOCTemplateExecutionError(message, templatePath, line, column, nil);
    }
    return NO;
  }

  if (escape) {
    [out appendString:ALNEOCEscapeHTMLString(rendered)];
  } else {
    [out appendString:rendered];
  }
  return YES;
}

BOOL ALNEOCAppendEscapedChecked(NSMutableString *out,
                                id value,
                                NSString *templatePath,
                                NSUInteger line,
                                NSUInteger column,
                                NSError **error) {
  return ALNEOCAppendChecked(out, value, YES, templatePath, line, column, error);
}

BOOL ALNEOCAppendRawChecked(NSMutableString *out,
                            id value,
                            NSString *templatePath,
                            NSUInteger line,
                            NSUInteger column,
                            NSError **error) {
  return ALNEOCAppendChecked(out, value, NO, templatePath, line, column, error);
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
