#ifndef ALN_ROUTER_H
#define ALN_ROUTER_H

#import <Foundation/Foundation.h>

#import "ALNRoute.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNRouter : NSObject

- (ALNRoute *)addRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(nullable NSString *)name
            controllerClass:(Class)controllerClass
                     action:(NSString *)action;
- (nullable ALNRouteMatch *)matchMethod:(NSString *)method path:(NSString *)path;
- (NSArray *)routeTable;

@end

NS_ASSUME_NONNULL_END

#endif
