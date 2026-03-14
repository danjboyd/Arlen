#import "ALNEOCRuntime.h"

NSString *const ALNEOCErrorDomain = @"Arlen.EOC.Error";
NSString *const ALNEOCErrorLineKey = @"line";
NSString *const ALNEOCErrorColumnKey = @"column";
NSString *const ALNEOCErrorPathKey = @"path";
NSString *const ALNEOCErrorLocalNameKey = @"local";
NSString *const ALNEOCErrorKeyPathKey = @"key_path";
NSString *const ALNEOCErrorSegmentKey = @"segment";

static NSString *const ALNEOCThreadOptionsKey = @"aln.eoc.render_options";
static NSString *const ALNEOCThreadStrictLocalsKey = @"strict_locals";
static NSString *const ALNEOCThreadStrictStringifyKey = @"strict_stringify";
static NSString *const ALNEOCThreadOptionsStackKey = @"aln.eoc.render_options_stack";
static NSString *const ALNEOCThreadCompositionStackKey = @"aln.eoc.composition_stack";
static NSString *const ALNEOCCompositionSlotsKey = @"slots";

static id ALNEOCLookupValueOnObject(id object, NSString *name, BOOL *found);

@interface ALNEOCOverlayContext : NSObject

- (instancetype)initWithBaseContext:(id)baseContext locals:(id)locals;
- (id)objectForKey:(id)key;
- (id)valueForKey:(NSString *)key;

@end

@implementation ALNEOCOverlayContext {
  id _baseContext;
  id _locals;
}

- (instancetype)initWithBaseContext:(id)baseContext locals:(id)locals {
  self = [super init];
  if (self != nil) {
    _baseContext = baseContext;
    _locals = locals;
  }
  return self;
}

- (id)objectForKey:(id)key {
  NSString *name = [key isKindOfClass:[NSString class]] ? key : @"";
  BOOL found = NO;
  id value = ALNEOCLookupValueOnObject(_locals, name, &found);
  if (found) {
    return value;
  }
  return ALNEOCLookupValueOnObject(_baseContext, name, NULL);
}

- (id)valueForKey:(NSString *)key {
  return [self objectForKey:key];
}

- (BOOL)respondsToSelector:(SEL)selector {
  if (selector == @selector(objectForKey:) || selector == @selector(valueForKey:)) {
    return YES;
  }
  return [super respondsToSelector:selector] || [_baseContext respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
  if (selector == @selector(objectForKey:) || selector == @selector(valueForKey:)) {
    return nil;
  }
  if ([_baseContext respondsToSelector:selector]) {
    return _baseContext;
  }
  return [super forwardingTargetForSelector:selector];
}

- (NSString *)description {
  return [_baseContext description] ?: [super description];
}

@end

static NSMutableDictionary *ALNEOCTemplateRegistry(void) {
  static NSMutableDictionary *registry = nil;
  @synchronized([NSThread class]) {
    if (registry == nil) {
      registry = [[NSMutableDictionary alloc] init];
    }
    return registry;
  }
}

static NSMutableDictionary *ALNEOCTemplateLayoutRegistry(void) {
  static NSMutableDictionary *registry = nil;
  @synchronized([NSThread class]) {
    if (registry == nil) {
      registry = [[NSMutableDictionary alloc] init];
    }
    return registry;
  }
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

static NSMutableArray *ALNEOCThreadOptionStack(void) {
  NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
  id current = threadDictionary[ALNEOCThreadOptionsStackKey];
  if ([current isKindOfClass:[NSMutableArray class]]) {
    return current;
  }
  NSMutableArray *stack = [NSMutableArray array];
  threadDictionary[ALNEOCThreadOptionsStackKey] = stack;
  return stack;
}

static NSMutableArray *ALNEOCThreadCompositionStack(void) {
  NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
  id current = threadDictionary[ALNEOCThreadCompositionStackKey];
  if ([current isKindOfClass:[NSMutableArray class]]) {
    return current;
  }
  NSMutableArray *stack = [NSMutableArray array];
  threadDictionary[ALNEOCThreadCompositionStackKey] = stack;
  return stack;
}

static BOOL ALNEOCCompositionStateIsActive(void) {
  return [ALNEOCThreadCompositionStack() count] > 0;
}

static NSMutableDictionary *ALNEOCCurrentCompositionState(void) {
  NSMutableArray *stack = ALNEOCThreadCompositionStack();
  id current = [stack lastObject];
  return [current isKindOfClass:[NSMutableDictionary class]] ? current : nil;
}

static NSMutableDictionary *ALNEOCCurrentSlotMap(void) {
  NSMutableDictionary *state = ALNEOCCurrentCompositionState();
  id current = state[ALNEOCCompositionSlotsKey];
  if ([current isKindOfClass:[NSMutableDictionary class]]) {
    return current;
  }
  return nil;
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

NSDictionary *ALNEOCPushRenderOptions(BOOL strictLocals, BOOL strictStringify) {
  NSDictionary *snapshot = @{
    ALNEOCThreadStrictLocalsKey : @(ALNEOCStrictLocalsEnabled()),
    ALNEOCThreadStrictStringifyKey : @(ALNEOCStrictStringifyEnabled()),
  };
  [ALNEOCThreadOptionStack() addObject:snapshot];
  ALNEOCSetStrictLocalsEnabled(strictLocals);
  ALNEOCSetStrictStringifyEnabled(strictStringify);
  return snapshot;
}

void ALNEOCPopRenderOptions(NSDictionary *token) {
  (void)token;
  NSMutableArray *stack = ALNEOCThreadOptionStack();
  if ([stack count] == 0) {
    return;
  }
  NSDictionary *restore = nil;
  id candidate = [stack lastObject];
  if ([candidate isKindOfClass:[NSDictionary class]]) {
    restore = candidate;
  }
  [stack removeLastObject];
  BOOL strictLocals = [restore[ALNEOCThreadStrictLocalsKey] boolValue];
  BOOL strictStringify = [restore[ALNEOCThreadStrictStringifyKey] boolValue];
  ALNEOCSetStrictLocalsEnabled(strictLocals);
  ALNEOCSetStrictStringifyEnabled(strictStringify);

  if ([stack count] == 0) {
    [[[NSThread currentThread] threadDictionary] removeObjectForKey:ALNEOCThreadOptionsStackKey];
  }
}

NSDictionary *ALNEOCPushCompositionState(void) {
  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  state[ALNEOCCompositionSlotsKey] = [NSMutableDictionary dictionary];
  [ALNEOCThreadCompositionStack() addObject:state];
  return state;
}

void ALNEOCPopCompositionState(NSDictionary *token) {
  (void)token;
  NSMutableArray *stack = ALNEOCThreadCompositionStack();
  if ([stack count] == 0) {
    return;
  }
  [stack removeLastObject];
  if ([stack count] == 0) {
    [[[NSThread currentThread] threadDictionary] removeObjectForKey:ALNEOCThreadCompositionStackKey];
  }
}

static NSError *ALNEOCTemplateExecutionError(NSString *message,
                                             NSString *templatePath,
                                             NSUInteger line,
                                             NSUInteger column,
                                             NSString *localName,
                                             NSString *keyPath,
                                             NSString *segment) {
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
  if ([keyPath length] > 0) {
    userInfo[ALNEOCErrorKeyPathKey] = keyPath;
  }
  if ([segment length] > 0) {
    userInfo[ALNEOCErrorSegmentKey] = segment;
  }
  return [NSError errorWithDomain:ALNEOCErrorDomain
                             code:ALNEOCErrorTemplateExecutionFailed
                         userInfo:userInfo];
}

static NSError *ALNEOCInvalidArgumentError(NSString *message,
                                           NSString *templatePath,
                                           NSUInteger line,
                                           NSUInteger column) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"Invalid EOC argument";
  if ([templatePath length] > 0) {
    userInfo[ALNEOCErrorPathKey] = templatePath;
  }
  if (line > 0) {
    userInfo[ALNEOCErrorLineKey] = @(line);
  }
  if (column > 0) {
    userInfo[ALNEOCErrorColumnKey] = @(column);
  }
  return [NSError errorWithDomain:ALNEOCErrorDomain
                             code:ALNEOCErrorInvalidArgument
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

static id ALNEOCLookupValueOnObject(id object, NSString *name, BOOL *found) {
  if (found != NULL) {
    *found = NO;
  }
  if (object == nil || [name length] == 0) {
    return nil;
  }

  if ([object isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictionary = (NSDictionary *)object;
    id value = dictionary[name];
    if (value != nil && found != NULL) {
      *found = YES;
    }
    return value;
  }

  if ([object respondsToSelector:@selector(objectForKey:)]) {
    id value = [object objectForKey:name];
    if (value != nil && found != NULL) {
      *found = YES;
    }
    return value;
  }

  if ([object respondsToSelector:@selector(valueForKey:)]) {
    @try {
      id value = [object valueForKey:name];
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

static id ALNEOCLookupLocal(id ctx, NSString *name, BOOL *found) {
  return ALNEOCLookupValueOnObject(ctx, name, found);
}

static id ALNEOCContextWithLocals(id ctx,
                                  id locals,
                                  NSString *templatePath,
                                  NSUInteger line,
                                  NSUInteger column,
                                  NSError **error) {
  if (locals == nil || locals == [NSNull null]) {
    return ctx;
  }
  if ([locals isKindOfClass:[NSDictionary class]] ||
      [locals respondsToSelector:@selector(objectForKey:)]) {
    return [[ALNEOCOverlayContext alloc] initWithBaseContext:ctx locals:locals];
  }
  if (error != NULL) {
    *error = ALNEOCInvalidArgumentError(
        @"EOC locals overlay must be dictionary-like", templatePath, line, column);
  }
  return nil;
}

static BOOL ALNEOCIsEnumerableCollection(id value) {
  if (value == nil || value == [NSNull null]) {
    return YES;
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]]) {
    return NO;
  }
  return [value respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)];
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
    *error = ALNEOCTemplateExecutionError(
        message, templatePath, line, column, name, nil, nil);
  }
  return nil;
}

id ALNEOCLocalPath(id ctx,
                   NSString *keyPath,
                   NSString *templatePath,
                   NSUInteger line,
                   NSUInteger column,
                   NSError **error) {
  if ([keyPath length] == 0) {
    return nil;
  }

  NSArray *segments = [keyPath componentsSeparatedByString:@"."];
  if ([segments count] == 0) {
    return ALNEOCLocal(ctx, keyPath, templatePath, line, column, error);
  }

  NSString *rootLocal = [segments[0] isKindOfClass:[NSString class]] ? segments[0] : @"";
  BOOL found = NO;
  id current = ALNEOCLookupLocal(ctx, rootLocal, &found);
  if (!found) {
    if (ALNEOCStrictLocalsEnabled() && error != NULL) {
      NSString *message = [NSString stringWithFormat:@"Undefined EOC local: $%@",
                                                     rootLocal ?: @""];
      *error = ALNEOCTemplateExecutionError(message,
                                            templatePath,
                                            line,
                                            column,
                                            rootLocal,
                                            keyPath,
                                            rootLocal);
    }
    return nil;
  }

  if ([segments count] == 1) {
    return current;
  }

  for (NSUInteger idx = 1; idx < [segments count]; idx++) {
    NSString *segment =
        [segments[idx] isKindOfClass:[NSString class]] ? segments[idx] : @"";
    BOOL segmentFound = NO;
    current = ALNEOCLookupValueOnObject(current, segment, &segmentFound);
    if (!segmentFound) {
      if (ALNEOCStrictLocalsEnabled() && error != NULL) {
        NSString *message = [NSString
            stringWithFormat:@"Undefined EOC key path segment '%@' in $%@",
                             segment ?: @"", keyPath ?: @""];
        *error = ALNEOCTemplateExecutionError(message,
                                              templatePath,
                                              line,
                                              column,
                                              rootLocal,
                                              keyPath,
                                              segment);
      }
      return nil;
    }
  }

  return current;
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

NSString *ALNEOCNormalizeTemplateReference(NSString *path) {
  NSString *canonical = ALNEOCCanonicalTemplatePath(path);
  if ([canonical length] == 0) {
    return @"";
  }
  if (![canonical hasSuffix:@".html.eoc"]) {
    canonical = [canonical stringByAppendingString:@".html.eoc"];
  }
  return canonical;
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
      *error = ALNEOCTemplateExecutionError(
          message, templatePath, line, column, nil, nil, nil);
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

BOOL ALNEOCEnsureRequiredLocals(id ctx,
                                NSArray<NSString *> *requiredLocals,
                                NSString *templatePath,
                                NSUInteger line,
                                NSUInteger column,
                                NSError **error) {
  for (id rawName in requiredLocals ?: @[]) {
    NSString *name = [rawName isKindOfClass:[NSString class]] ? rawName : @"";
    if ([name length] == 0) {
      continue;
    }
    BOOL found = NO;
    (void)ALNEOCLookupLocal(ctx, name, &found);
    if (!found) {
      if (error != NULL) {
        NSString *message =
            [NSString stringWithFormat:@"Missing required EOC local: $%@", name];
        *error = ALNEOCTemplateExecutionError(
            message, templatePath, line, column, name, nil, nil);
      }
      return NO;
    }
  }
  return YES;
}

BOOL ALNEOCSetSlot(id ctx,
                   NSString *slotName,
                   NSString *content,
                   NSString *templatePath,
                   NSUInteger line,
                   NSUInteger column,
                   NSError **error) {
  (void)ctx;
  if ([slotName length] == 0) {
    if (error != NULL) {
      *error = ALNEOCInvalidArgumentError(
          @"EOC slot name cannot be empty", templatePath, line, column);
    }
    return NO;
  }
  NSMutableDictionary *slots = ALNEOCCurrentSlotMap();
  if (slots == nil) {
    if (error != NULL) {
      *error = ALNEOCInvalidArgumentError(
          @"EOC composition state is not active", templatePath, line, column);
    }
    return NO;
  }
  slots[slotName] = content ?: @"";
  return YES;
}

void ALNEOCSetSlotContent(NSString *slotName, NSString *content) {
  if ([slotName length] == 0) {
    return;
  }
  NSMutableDictionary *slots = ALNEOCCurrentSlotMap();
  if (slots == nil) {
    return;
  }
  slots[slotName] = content ?: @"";
}

BOOL ALNEOCAppendYield(NSMutableString *out,
                       id ctx,
                       NSString *slotName,
                       NSString *templatePath,
                       NSUInteger line,
                       NSUInteger column,
                       NSError **error) {
  NSString *resolvedSlot = ([slotName length] > 0) ? slotName : @"content";
  NSMutableDictionary *slots = ALNEOCCurrentSlotMap();
  id value = slots[resolvedSlot];
  if (value == nil) {
    BOOL found = NO;
    value = ALNEOCLookupValueOnObject(ctx, resolvedSlot, &found);
    if (!found) {
      value = @"";
    }
  }
  return ALNEOCAppendRawChecked(out, value, templatePath, line, column, error);
}

void ALNEOCClearTemplateRegistry(void) {
  @synchronized(ALNEOCTemplateRegistry()) {
    [ALNEOCTemplateRegistry() removeAllObjects];
  }
  @synchronized(ALNEOCTemplateLayoutRegistry()) {
    [ALNEOCTemplateLayoutRegistry() removeAllObjects];
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

void ALNEOCRegisterTemplateLayout(NSString *logicalPath, NSString *layoutLogicalPath) {
  NSString *canonical = ALNEOCCanonicalTemplatePath(logicalPath);
  NSString *normalizedLayout = ALNEOCNormalizeTemplateReference(layoutLogicalPath);
  if ([canonical length] == 0 || [normalizedLayout length] == 0) {
    return;
  }

  @synchronized(ALNEOCTemplateLayoutRegistry()) {
    ALNEOCTemplateLayoutRegistry()[canonical] = normalizedLayout;
  }
}

NSString *ALNEOCResolveTemplateLayout(NSString *logicalPath) {
  NSString *canonical = ALNEOCCanonicalTemplatePath(logicalPath);
  if ([canonical length] == 0) {
    return nil;
  }

  NSString *layout = nil;
  @synchronized(ALNEOCTemplateLayoutRegistry()) {
    id current = ALNEOCTemplateLayoutRegistry()[canonical];
    if ([current isKindOfClass:[NSString class]]) {
      layout = current;
    }
  }
  return layout;
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
  NSString *normalizedPath = ALNEOCNormalizeTemplateReference(logicalPath);
  NSString *resolvedPath = ([normalizedPath length] > 0) ? normalizedPath : logicalPath;
  ALNEOCRenderFunction function = ALNEOCResolveTemplate(resolvedPath);
  if (function == NULL) {
    if (error != NULL) {
      NSString *canonical = ALNEOCCanonicalTemplatePath(resolvedPath);
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

  BOOL ownsCompositionState = !ALNEOCCompositionStateIsActive();
  NSDictionary *compositionToken = ownsCompositionState ? ALNEOCPushCompositionState() : nil;
  NSError *innerError = nil;
  NSString *rendered = nil;
  @try {
    rendered = function(ctx, &innerError);
  } @finally {
    if (ownsCompositionState) {
      ALNEOCPopCompositionState(compositionToken);
    }
  }
  if (rendered == nil) {
    if (error != NULL) {
      if (innerError != nil) {
        *error = innerError;
      } else {
        NSString *canonical = ALNEOCCanonicalTemplatePath(resolvedPath);
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

BOOL ALNEOCIncludeWithLocals(NSMutableString *out,
                             id ctx,
                             NSString *logicalPath,
                             id locals,
                             NSString *templatePath,
                             NSUInteger line,
                             NSUInteger column,
                             NSError **error) {
  NSString *normalizedPath = ALNEOCNormalizeTemplateReference(logicalPath);
  id effectiveContext =
      ALNEOCContextWithLocals(ctx, locals, templatePath, line, column, error);
  if (effectiveContext == nil && locals != nil && locals != [NSNull null]) {
    return NO;
  }
  return ALNEOCInclude(out, effectiveContext, normalizedPath, error);
}

BOOL ALNEOCRenderCollection(NSMutableString *out,
                            id ctx,
                            NSString *logicalPath,
                            id collection,
                            NSString *itemLocalName,
                            NSString *emptyLogicalPath,
                            id locals,
                            NSString *templatePath,
                            NSUInteger line,
                            NSUInteger column,
                            NSError **error) {
  if ([itemLocalName length] == 0) {
    if (error != NULL) {
      *error = ALNEOCInvalidArgumentError(
          @"EOC collection render requires a non-empty item local name",
          templatePath,
          line,
          column);
    }
    return NO;
  }

  if (!ALNEOCIsEnumerableCollection(collection)) {
    if (error != NULL) {
      *error = ALNEOCInvalidArgumentError(
          @"EOC collection render requires an enumerable collection",
          templatePath,
          line,
          column);
    }
    return NO;
  }

  NSString *normalizedPath = ALNEOCNormalizeTemplateReference(logicalPath);
  NSString *normalizedEmptyPath = ALNEOCNormalizeTemplateReference(emptyLogicalPath ?: @"");

  BOOL renderedAny = NO;
  for (id item in collection ?: @[]) {
    renderedAny = YES;
    id overlayContext =
        ALNEOCContextWithLocals(ctx, locals, templatePath, line, column, error);
    if (overlayContext == nil && locals != nil && locals != [NSNull null]) {
      return NO;
    }
    overlayContext = [[ALNEOCOverlayContext alloc]
        initWithBaseContext:overlayContext
                     locals:@{ itemLocalName : item ?: [NSNull null] }];
    if (!ALNEOCInclude(out, overlayContext, normalizedPath, error)) {
      return NO;
    }
  }

  if (!renderedAny && [normalizedEmptyPath length] > 0) {
    return ALNEOCIncludeWithLocals(out,
                                   ctx,
                                   normalizedEmptyPath,
                                   locals,
                                   templatePath,
                                   line,
                                   column,
                                   error);
  }
  return YES;
}
