#import "ALNRouter.h"

@interface ALNRouter ()

@property(nonatomic, strong) NSMutableArray *routes;
@property(nonatomic, assign) NSUInteger routeCounter;

@end

@implementation ALNRouter

- (instancetype)init {
  self = [super init];
  if (self) {
    _routes = [NSMutableArray array];
    _routeCounter = 0;
  }
  return self;
}

- (ALNRoute *)addRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(NSString *)name
            controllerClass:(Class)controllerClass
                     action:(NSString *)action {
  ALNRoute *route = [[ALNRoute alloc] initWithMethod:method
                                       pathPattern:path
                                              name:name
                                   controllerClass:controllerClass
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
  ALNRoute *bestRoute = nil;
  NSDictionary *bestParams = nil;

  for (ALNRoute *route in self.routes) {
    if (!ALNIsMethodMatch(route.method, method)) {
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

- (NSArray *)routeTable {
  NSMutableArray *rows = [NSMutableArray array];
  for (ALNRoute *route in self.routes) {
    [rows addObject:[route dictionaryRepresentation]];
  }
  return rows;
}

@end
