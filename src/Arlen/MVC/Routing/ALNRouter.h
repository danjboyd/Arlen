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
- (ALNRoute *)addRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(nullable NSString *)name
                    formats:(nullable NSArray *)formats
            controllerClass:(Class)controllerClass
                guardAction:(nullable NSString *)guardAction
                     action:(NSString *)action;
- (nullable ALNRouteMatch *)matchMethod:(NSString *)method path:(NSString *)path;
- (nullable ALNRouteMatch *)matchMethod:(NSString *)method
                                   path:(NSString *)path
                                 format:(nullable NSString *)format;
- (void)beginRouteGroupWithPrefix:(NSString *)prefix
                      guardAction:(nullable NSString *)guardAction
                          formats:(nullable NSArray *)formats;
- (void)endRouteGroup;
- (nullable ALNRoute *)routeNamed:(NSString *)name;
- (NSArray *)allRoutes;
- (NSArray *)routeTable;

@end

NS_ASSUME_NONNULL_END

#endif
