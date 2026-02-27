#import "ALNRouter.h"

@interface ALNRouter ()

@property(nonatomic, strong) NSMutableArray *routes;
@property(nonatomic, strong) NSMutableDictionary *routesByMethod;
@property(nonatomic, strong) NSMutableArray *routeGroups;
@property(nonatomic, assign) NSUInteger routeCounter;
@property(nonatomic, assign, readwrite) BOOL hasFormatConstrainedRoutes;

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

static NSString *ALNNormalizedMethodName(NSString *method) {
  if (![method isKindOfClass:[NSString class]] || [method length] == 0) {
    return @"GET";
  }
  return [[method uppercaseString] copy];
}

static BOOL ALNRouteShouldReplace(ALNRoute *candidate, ALNRoute *bestRoute) {
  if (bestRoute == nil) {
    return YES;
  }
  if (candidate.kind > bestRoute.kind) {
    return YES;
  }
  if (candidate.kind == bestRoute.kind &&
      candidate.staticSegmentCount > bestRoute.staticSegmentCount) {
    return YES;
  }
  if (candidate.kind == bestRoute.kind &&
      candidate.staticSegmentCount == bestRoute.staticSegmentCount &&
      candidate.registrationIndex < bestRoute.registrationIndex) {
    return YES;
  }
  return NO;
}

static ALNRouteMatch *ALNBestRouteMatchInCandidates(NSArray *candidates,
                                                     NSString *path,
                                                     NSString *format) {
  ALNRoute *bestRoute = nil;
  NSDictionary *bestParams = nil;
  NSArray *lazyPathSegments = nil;

  for (ALNRoute *route in candidates) {
    if (![route matchesFormat:format]) {
      continue;
    }

    BOOL useFastPath = [route usesParameterizedFastPath];
    NSArray *candidateSegments = nil;
    if (!useFastPath) {
      if (lazyPathSegments == nil) {
        lazyPathSegments = [ALNRoute pathSegmentsForPath:path];
      }
      candidateSegments = lazyPathSegments;
    }
    NSDictionary *candidateParams = [route matchPath:path pathSegments:candidateSegments];
    if (candidateParams == nil) {
      continue;
    }

    if (ALNRouteShouldReplace(route, bestRoute)) {
      bestRoute = route;
      bestParams = candidateParams;
    }
  }

  if (bestRoute == nil || bestParams == nil) {
    return nil;
  }
  return [[ALNRouteMatch alloc] initWithRoute:bestRoute params:bestParams];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _routes = [NSMutableArray array];
    _routesByMethod = [NSMutableDictionary dictionary];
    _routeGroups = [NSMutableArray array];
    _routeCounter = 0;
    _hasFormatConstrainedRoutes = NO;
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
  if ([resolvedFormats count] > 0) {
    self.hasFormatConstrainedRoutes = YES;
  }

  ALNRoute *route = [[ALNRoute alloc] initWithMethod:method
                                       pathPattern:resolvedPath
                                              name:name
                                           formats:resolvedFormats
                                   controllerClass:controllerClass
                                   guardActionName:resolvedGuard
                                        actionName:action
                                 registrationIndex:self.routeCounter++];
  [self.routes addObject:route];

  NSString *bucketKey = ALNNormalizedMethodName(route.method);
  NSMutableArray *bucket =
      [self.routesByMethod[bucketKey] isKindOfClass:[NSMutableArray class]]
          ? self.routesByMethod[bucketKey]
          : [NSMutableArray array];
  [bucket addObject:route];
  self.routesByMethod[bucketKey] = bucket;
  return route;
}

- (ALNRouteMatch *)matchMethod:(NSString *)method path:(NSString *)path {
  return [self matchMethod:method path:path format:nil];
}

- (ALNRouteMatch *)matchMethod:(NSString *)method
                          path:(NSString *)path
                        format:(NSString *)format {
  NSString *requestMethod = ALNNormalizedMethodName(method);
  NSString *normalizedPath =
      ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : @"/";
  NSArray *methodCandidates =
      [self.routesByMethod[requestMethod] isKindOfClass:[NSArray class]]
          ? self.routesByMethod[requestMethod]
          : @[];
  NSArray *anyCandidates =
      [self.routesByMethod[@"ANY"] isKindOfClass:[NSArray class]]
          ? self.routesByMethod[@"ANY"]
          : @[];

  ALNRouteMatch *methodMatch =
      ALNBestRouteMatchInCandidates(methodCandidates, normalizedPath, format);
  if (methodMatch != nil || [requestMethod isEqualToString:@"ANY"]) {
    return methodMatch;
  }
  return ALNBestRouteMatchInCandidates(anyCandidates, normalizedPath, format);
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
