#import "ALNRoute.h"

static NSArray *ALNSplitPathSegments(NSString *path) {
  if (path == nil || [path length] == 0 || [path isEqualToString:@"/"]) {
    return @[];
  }

  NSString *normalized = [path copy];
  while ([normalized hasPrefix:@"/"]) {
    normalized = [normalized substringFromIndex:1];
  }
  while ([normalized hasSuffix:@"/"]) {
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  if ([normalized length] == 0) {
    return @[];
  }
  return [normalized componentsSeparatedByString:@"/"];
}

static NSString *ALNNormalizeRouteFormat(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed =
      [[value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSString *ALNNormalizedPathForFastMatch(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return @"/";
  }
  NSString *normalized = [path copy];
  while ([normalized hasSuffix:@"/"] && [normalized length] > 1) {
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  return ([normalized length] > 0) ? normalized : @"/";
}

@interface ALNRoute ()

@property(nonatomic, copy, readwrite) NSString *method;
@property(nonatomic, copy, readwrite) NSString *pathPattern;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, assign, readwrite) Class controllerClass;
@property(nonatomic, assign, readwrite) SEL actionSelector;
@property(nonatomic, copy, readwrite) NSString *actionName;
@property(nonatomic, assign, readwrite) SEL guardSelector;
@property(nonatomic, copy, readwrite) NSString *guardActionName;
@property(nonatomic, copy, readwrite) NSArray *formats;
@property(nonatomic, assign, readwrite) NSUInteger registrationIndex;
@property(nonatomic, assign, readwrite) ALNRouteKind kind;
@property(nonatomic, assign, readwrite) NSUInteger staticSegmentCount;
@property(nonatomic, strong) NSArray *segments;
@property(nonatomic, assign) BOOL parameterizedFastPathEnabled;
@property(nonatomic, copy) NSString *parameterizedFastPathPrefix;
@property(nonatomic, copy) NSString *parameterizedFastPathParamName;

@end

@implementation ALNRouteMatch

- (instancetype)initWithRoute:(ALNRoute *)route params:(NSDictionary *)params {
  self = [super init];
  if (self) {
    _route = route;
    _params = [params copy] ?: @{};
  }
  return self;
}

@end

@implementation ALNRoute

- (instancetype)initWithMethod:(NSString *)method
                   pathPattern:(NSString *)pathPattern
                          name:(NSString *)name
               controllerClass:(Class)controllerClass
                    actionName:(NSString *)actionName
             registrationIndex:(NSUInteger)registrationIndex {
  return [self initWithMethod:method
                  pathPattern:pathPattern
                         name:name
                      formats:nil
              controllerClass:controllerClass
              guardActionName:nil
                   actionName:actionName
            registrationIndex:registrationIndex];
}

- (instancetype)initWithMethod:(NSString *)method
                   pathPattern:(NSString *)pathPattern
                          name:(NSString *)name
                       formats:(NSArray *)formats
               controllerClass:(Class)controllerClass
               guardActionName:(NSString *)guardActionName
                    actionName:(NSString *)actionName
             registrationIndex:(NSUInteger)registrationIndex {
  self = [super init];
  if (self) {
    _method = [[method uppercaseString] copy];
    _pathPattern = [pathPattern copy];
    _name = [name copy] ?: @"";
    _controllerClass = controllerClass;
    _actionName = [actionName copy];
    _actionSelector = NSSelectorFromString([NSString stringWithFormat:@"%@:", actionName]);
    _guardActionName = [guardActionName copy] ?: @"";
    _guardSelector = ([guardActionName length] > 0)
                         ? NSSelectorFromString([NSString stringWithFormat:@"%@:", guardActionName])
                         : NULL;
    NSMutableArray *normalizedFormats = [NSMutableArray array];
    for (id value in formats ?: @[]) {
      NSString *normalized = ALNNormalizeRouteFormat(value);
      if ([normalized length] == 0) {
        continue;
      }
      if ([normalizedFormats containsObject:normalized]) {
        continue;
      }
      [normalizedFormats addObject:normalized];
    }
    _formats = [NSArray arrayWithArray:normalizedFormats];
    _registrationIndex = registrationIndex;
    _segments = ALNSplitPathSegments(pathPattern);
    _requestSchema = @{};
    _responseSchema = @{};
    _summary = @"";
    _operationID = @"";
    _tags = @[];
    _requiredScopes = @[];
    _requiredRoles = @[];
    _includeInOpenAPI = YES;
    _compiledActionSignature = nil;
    _compiledGuardSignature = nil;
    _compiledActionIMP = NULL;
    _compiledGuardIMP = NULL;
    _compiledActionReturnKind = ALNRouteInvocationReturnKindUnknown;
    _compiledGuardReturnKind = ALNRouteInvocationReturnKindUnknown;
    _compiledInvocationMetadata = NO;

    BOOL hasWildcard = NO;
    BOOL hasParam = NO;
    NSUInteger staticCount = 0;
    for (NSString *segment in _segments) {
      if ([segment hasPrefix:@"*"]) {
        hasWildcard = YES;
      } else if ([segment hasPrefix:@":"]) {
        hasParam = YES;
      } else {
        staticCount += 1;
      }
    }

    if (hasWildcard) {
      _kind = ALNRouteKindWildcard;
    } else if (hasParam) {
      _kind = ALNRouteKindParameterized;
    } else {
      _kind = ALNRouteKindStatic;
    }
    _staticSegmentCount = staticCount;

    _parameterizedFastPathEnabled = NO;
    _parameterizedFastPathPrefix = @"";
    _parameterizedFastPathParamName = @"";
    if (!hasWildcard && hasParam && [_segments count] > 0) {
      NSUInteger parameterCount = 0;
      BOOL allStaticBeforeTail = YES;
      NSString *tailParamName = nil;
      NSUInteger tailSegmentLength = 0;
      NSUInteger lastIndex = [_segments count] - 1;
      for (NSUInteger idx = 0; idx < [_segments count]; idx++) {
        NSString *segment = _segments[idx];
        if ([segment hasPrefix:@":"]) {
          parameterCount += 1;
          if (idx == lastIndex) {
            tailParamName = [segment substringFromIndex:1];
            tailSegmentLength = [segment length];
          } else {
            allStaticBeforeTail = NO;
          }
        } else if ([segment hasPrefix:@"*"]) {
          allStaticBeforeTail = NO;
        } else if (idx == lastIndex) {
          allStaticBeforeTail = NO;
        }
      }
      if (parameterCount == 1 && allStaticBeforeTail && [tailParamName length] > 0) {
        NSString *prefix = [_pathPattern substringToIndex:[_pathPattern length] - tailSegmentLength];
        _parameterizedFastPathEnabled = YES;
        _parameterizedFastPathPrefix = [prefix copy] ?: @"";
        _parameterizedFastPathParamName = [tailParamName copy] ?: @"";
      }
    }
  }
  return self;
}

- (NSDictionary *)matchPath:(NSString *)path {
  return [self matchPath:path pathSegments:nil];
}

- (BOOL)usesParameterizedFastPath {
  return self.parameterizedFastPathEnabled;
}

- (BOOL)matchesPath:(NSString *)path {
  return [self matchesPath:path pathSegments:nil];
}

- (BOOL)matchesPath:(NSString *)path pathSegments:(NSArray *)pathSegments {
  if (self.parameterizedFastPathEnabled && ![pathSegments isKindOfClass:[NSArray class]]) {
    NSString *normalizedPath = ALNNormalizedPathForFastMatch(path);
    if (![normalizedPath hasPrefix:self.parameterizedFastPathPrefix]) {
      return NO;
    }
    if ([normalizedPath length] <= [self.parameterizedFastPathPrefix length]) {
      return NO;
    }
    NSString *tail = [normalizedPath substringFromIndex:[self.parameterizedFastPathPrefix length]];
    return ([tail length] > 0 && [tail rangeOfString:@"/"].location == NSNotFound);
  }

  NSArray *incoming = [pathSegments isKindOfClass:[NSArray class]]
                          ? pathSegments
                          : ALNSplitPathSegments(path);
  NSUInteger patternCount = [self.segments count];
  NSUInteger incomingCount = [incoming count];

  for (NSUInteger idx = 0; idx < patternCount; idx++) {
    NSString *patternSegment = self.segments[idx];
    BOOL isWildcard = [patternSegment hasPrefix:@"*"];
    BOOL isParam = [patternSegment hasPrefix:@":"];

    if (isWildcard) {
      return YES;
    }

    if (idx >= incomingCount) {
      return NO;
    }

    NSString *incomingSegment = incoming[idx];
    if (isParam) {
      NSString *name = [patternSegment substringFromIndex:1];
      if ([name length] == 0) {
        return NO;
      }
      continue;
    }

    if (![patternSegment isEqualToString:incomingSegment]) {
      return NO;
    }
  }

  if (incomingCount != patternCount) {
    return NO;
  }
  return YES;
}

- (NSDictionary *)paramsForPath:(NSString *)path pathSegments:(NSArray *)pathSegments {
  if (self.parameterizedFastPathEnabled && ![pathSegments isKindOfClass:[NSArray class]]) {
    NSString *normalizedPath = ALNNormalizedPathForFastMatch(path);
    if (![normalizedPath hasPrefix:self.parameterizedFastPathPrefix]) {
      return nil;
    }
    if ([normalizedPath length] <= [self.parameterizedFastPathPrefix length]) {
      return nil;
    }
    NSString *tail = [normalizedPath substringFromIndex:[self.parameterizedFastPathPrefix length]];
    if ([tail length] == 0 || [tail rangeOfString:@"/"].location != NSNotFound) {
      return nil;
    }
    return @{
      self.parameterizedFastPathParamName : tail
    };
  }

  NSArray *incoming = [pathSegments isKindOfClass:[NSArray class]]
                          ? pathSegments
                          : ALNSplitPathSegments(path);
  NSMutableDictionary *params = nil;
  NSUInteger patternCount = [self.segments count];
  NSUInteger incomingCount = [incoming count];

  for (NSUInteger idx = 0; idx < patternCount; idx++) {
    NSString *patternSegment = self.segments[idx];
    BOOL isWildcard = [patternSegment hasPrefix:@"*"];
    BOOL isParam = [patternSegment hasPrefix:@":"];

    if (isWildcard) {
      NSString *name = [patternSegment substringFromIndex:1];
      if ([name length] == 0) {
        name = @"wildcard";
      }
      if (params == nil) {
        params = [NSMutableDictionary dictionaryWithCapacity:1];
      }
      if (idx > incomingCount) {
        params[name] = @"";
      } else {
        NSArray *tail = [incoming subarrayWithRange:NSMakeRange(
                                             idx, incomingCount >= idx ? incomingCount - idx : 0)];
        params[name] = [tail componentsJoinedByString:@"/"];
      }
      return params;
    }

    if (idx >= incomingCount) {
      return nil;
    }

    NSString *incomingSegment = incoming[idx];
    if (isParam) {
      NSString *name = [patternSegment substringFromIndex:1];
      if ([name length] == 0) {
        return nil;
      }
      if (params == nil) {
        params = [NSMutableDictionary dictionaryWithCapacity:2];
      }
      params[name] = incomingSegment ?: @"";
      continue;
    }

    if (![patternSegment isEqualToString:incomingSegment]) {
      return nil;
    }
  }

  if (incomingCount != patternCount) {
    return nil;
  }
  return params ?: @{};
}

- (NSDictionary *)matchPath:(NSString *)path pathSegments:(NSArray *)pathSegments {
  return [self paramsForPath:path pathSegments:pathSegments];
}

+ (NSArray *)pathSegmentsForPath:(NSString *)path {
  return ALNSplitPathSegments(path);
}

- (BOOL)matchesFormat:(NSString *)format {
  if ([self.formats count] == 0) {
    return YES;
  }

  NSString *requested = ALNNormalizeRouteFormat(format) ?: @"html";
  for (NSString *candidate in self.formats) {
    if ([candidate isEqualToString:@"*"] || [candidate isEqualToString:requested]) {
      return YES;
    }
  }
  return NO;
}

- (NSDictionary *)dictionaryRepresentation {
  NSMutableDictionary *representation = [NSMutableDictionary dictionaryWithDictionary:@{
    @"method" : self.method ?: @"",
    @"path" : self.pathPattern ?: @"",
    @"name" : self.name ?: @"",
    @"controller" : NSStringFromClass(self.controllerClass ?: [NSObject class]),
    @"action" : self.actionName ?: @"",
  }];
  if ([self.guardActionName length] > 0) {
    representation[@"guard"] = self.guardActionName;
  }
  if ([self.formats count] > 0) {
    representation[@"formats"] = self.formats;
  }
  if ([self.summary length] > 0) {
    representation[@"summary"] = self.summary;
  }
  if ([self.operationID length] > 0) {
    representation[@"operationId"] = self.operationID;
  }
  if ([self.tags count] > 0) {
    representation[@"tags"] = self.tags;
  }
  if ([self.requiredScopes count] > 0) {
    representation[@"requiredScopes"] = self.requiredScopes;
  }
  if ([self.requiredRoles count] > 0) {
    representation[@"requiredRoles"] = self.requiredRoles;
  }
  if ([self.requestSchema count] > 0) {
    representation[@"requestSchema"] = self.requestSchema;
  }
  if ([self.responseSchema count] > 0) {
    representation[@"responseSchema"] = self.responseSchema;
  }
  representation[@"includeInOpenAPI"] = @(self.includeInOpenAPI);
  return representation;
}

@end
