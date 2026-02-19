#import "ALNRouter.h"

@interface ALNRouter ()

@property(nonatomic, strong) NSMutableArray *routes;
@property(nonatomic, strong) NSMutableArray *routeGroups;
@property(nonatomic, assign) NSUInteger routeCounter;

@end

@implementation ALNRouter

static NSString *const ALNRouteGroupPrefixKey = @"prefix";
static NSString *const ALNRouteGroupGuardKey = @"guard";
static NSString *const ALNRouteGroupFormatsKey = @"formats";

static NSString *ALNNormalizeGroupPath(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return @"/";
  }

  NSString *normalized = [path copy];
  while ([normalized containsString:@"//"]) {
    normalized = [normalized stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
  }
  if (![normalized hasPrefix:@"/"]) {
    normalized = [@"/" stringByAppendingString:normalized];
  }
  while ([normalized length] > 1 && [normalized hasSuffix:@"/"]) {
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  return ([normalized length] > 0) ? normalized : @"/";
}

static NSString *ALNJoinPaths(NSString *left, NSString *right) {
  NSString *lhs = ALNNormalizeGroupPath(left);
  NSString *rhs = ALNNormalizeGroupPath(right);
  if ([lhs isEqualToString:@"/"]) {
    return rhs;
  }
  if ([rhs isEqualToString:@"/"]) {
    return lhs;
  }
  return [NSString stringWithFormat:@"%@%@", lhs, rhs];
}

static NSArray *ALNNormalizeFormats(NSArray *formats) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in formats ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed =
        [[(NSString *)value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0 || [normalized containsObject:trimmed]) {
      continue;
    }
    [normalized addObject:trimmed];
  }
  return [NSArray arrayWithArray:normalized];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _routes = [NSMutableArray array];
    _routeGroups = [NSMutableArray array];
    _routeCounter = 0;
  }
  return self;
}

- (ALNRoute *)addRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(NSString *)name
            controllerClass:(Class)controllerClass
                     action:(NSString *)action {
  return [self addRouteMethod:method
                         path:path
                         name:name
                      formats:nil
              controllerClass:controllerClass
                  guardAction:nil
                       action:action];
}

- (ALNRoute *)addRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(NSString *)name
                    formats:(NSArray *)formats
            controllerClass:(Class)controllerClass
                guardAction:(NSString *)guardAction
                     action:(NSString *)action {
  NSString *groupPrefix = @"/";
  NSString *inheritedGuard = nil;
  NSArray *inheritedFormats = nil;
  for (NSDictionary *group in self.routeGroups) {
    NSString *prefix = group[ALNRouteGroupPrefixKey] ?: @"/";
    groupPrefix = ALNJoinPaths(groupPrefix, prefix);

    NSString *candidateGuard = group[ALNRouteGroupGuardKey];
    if ([candidateGuard length] > 0) {
      inheritedGuard = candidateGuard;
    }

    NSArray *candidateFormats = group[ALNRouteGroupFormatsKey];
    if ([candidateFormats count] > 0) {
      inheritedFormats = candidateFormats;
    }
  }
  NSString *resolvedPath = ALNJoinPaths(groupPrefix, ALNNormalizeGroupPath(path));
  NSString *resolvedGuard =
      ([guardAction length] > 0) ? [guardAction copy] : [inheritedGuard copy];
  NSArray *resolvedFormats = ([formats count] > 0) ? ALNNormalizeFormats(formats) : inheritedFormats;

  ALNRoute *route = [[ALNRoute alloc] initWithMethod:method
                                       pathPattern:resolvedPath
                                              name:name
                                           formats:resolvedFormats
                                   controllerClass:controllerClass
                                   guardActionName:resolvedGuard
                                        actionName:action
                                 registrationIndex:self.routeCounter++];
  [self.routes addObject:route];
  return route;
}

static BOOL ALNIsMethodMatch(NSString *routeMethod, NSString *requestMethod) {
  if ([routeMethod isEqualToString:@"ANY"]) {
    return YES;
  }
  return [routeMethod isEqualToString:[requestMethod uppercaseString]];
}

- (ALNRouteMatch *)matchMethod:(NSString *)method path:(NSString *)path {
  return [self matchMethod:method path:path format:nil];
}

- (ALNRouteMatch *)matchMethod:(NSString *)method
                          path:(NSString *)path
                        format:(NSString *)format {
  ALNRoute *bestRoute = nil;
  NSDictionary *bestParams = nil;

  for (ALNRoute *route in self.routes) {
    if (!ALNIsMethodMatch(route.method, method)) {
      continue;
    }
    if (![route matchesFormat:format]) {
      continue;
    }
    NSDictionary *params = [route matchPath:path];
    if (params == nil) {
      continue;
    }

    if (bestRoute == nil) {
      bestRoute = route;
      bestParams = params;
      continue;
    }

    BOOL shouldReplace = NO;
    if (route.kind > bestRoute.kind) {
      shouldReplace = YES;
    } else if (route.kind == bestRoute.kind &&
               route.staticSegmentCount > bestRoute.staticSegmentCount) {
      shouldReplace = YES;
    } else if (route.kind == bestRoute.kind &&
               route.staticSegmentCount == bestRoute.staticSegmentCount &&
               route.registrationIndex < bestRoute.registrationIndex) {
      shouldReplace = YES;
    }

    if (shouldReplace) {
      bestRoute = route;
      bestParams = params;
    }
  }

  if (bestRoute == nil) {
    return nil;
  }
  return [[ALNRouteMatch alloc] initWithRoute:bestRoute params:bestParams];
}

- (void)beginRouteGroupWithPrefix:(NSString *)prefix
                      guardAction:(NSString *)guardAction
                          formats:(NSArray *)formats {
  NSDictionary *entry = @{
    ALNRouteGroupPrefixKey : ALNNormalizeGroupPath(prefix),
    ALNRouteGroupGuardKey : [guardAction copy] ?: @"",
    ALNRouteGroupFormatsKey : ALNNormalizeFormats(formats)
  };
  [self.routeGroups addObject:entry];
}

- (void)endRouteGroup {
  if ([self.routeGroups count] == 0) {
    return;
  }
  [self.routeGroups removeLastObject];
}

- (ALNRoute *)routeNamed:(NSString *)name {
  if ([name length] == 0) {
    return nil;
  }
  for (ALNRoute *route in self.routes) {
    if ([route.name isEqualToString:name]) {
      return route;
    }
  }
  return nil;
}

- (NSArray *)allRoutes {
  return [NSArray arrayWithArray:self.routes];
}

- (NSArray *)routeTable {
  NSMutableArray *rows = [NSMutableArray array];
  for (ALNRoute *route in self.routes) {
    [rows addObject:[route dictionaryRepresentation]];
  }
  return rows;
}

@end
