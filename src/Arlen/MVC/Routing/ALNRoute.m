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

@interface ALNRoute ()

@property(nonatomic, copy, readwrite) NSString *method;
@property(nonatomic, copy, readwrite) NSString *pathPattern;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, assign, readwrite) Class controllerClass;
@property(nonatomic, assign, readwrite) SEL actionSelector;
@property(nonatomic, copy, readwrite) NSString *actionName;
@property(nonatomic, assign, readwrite) NSUInteger registrationIndex;
@property(nonatomic, assign, readwrite) ALNRouteKind kind;
@property(nonatomic, assign, readwrite) NSUInteger staticSegmentCount;
@property(nonatomic, strong) NSArray *segments;

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
  self = [super init];
  if (self) {
    _method = [[method uppercaseString] copy];
    _pathPattern = [pathPattern copy];
    _name = [name copy] ?: @"";
    _controllerClass = controllerClass;
    _actionName = [actionName copy];
    _actionSelector = NSSelectorFromString([NSString stringWithFormat:@"%@:", actionName]);
    _registrationIndex = registrationIndex;
    _segments = ALNSplitPathSegments(pathPattern);

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
  }
  return self;
}

- (NSDictionary *)matchPath:(NSString *)path {
  NSArray *incoming = ALNSplitPathSegments(path);
  NSMutableDictionary *params = [NSMutableDictionary dictionary];
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
  return params;
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    @"method" : self.method ?: @"",
    @"path" : self.pathPattern ?: @"",
    @"name" : self.name ?: @"",
    @"controller" : NSStringFromClass(self.controllerClass ?: [NSObject class]),
    @"action" : self.actionName ?: @"",
  };
}

@end
