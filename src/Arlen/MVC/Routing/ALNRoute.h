#ifndef ALN_ROUTE_H
#define ALN_ROUTE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ALNRouteKind) {
  ALNRouteKindStatic = 3,
  ALNRouteKindParameterized = 2,
  ALNRouteKindWildcard = 1,
};

@class ALNRoute;

@interface ALNRouteMatch : NSObject

@property(nonatomic, strong, readonly) ALNRoute *route;
@property(nonatomic, copy, readonly) NSDictionary *params;

- (instancetype)initWithRoute:(ALNRoute *)route params:(NSDictionary *)params;

@end

@interface ALNRoute : NSObject

@property(nonatomic, copy, readonly) NSString *method;
@property(nonatomic, copy, readonly) NSString *pathPattern;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly) Class controllerClass;
@property(nonatomic, assign, readonly) SEL actionSelector;
@property(nonatomic, copy, readonly) NSString *actionName;
@property(nonatomic, assign, readonly) NSUInteger registrationIndex;
@property(nonatomic, assign, readonly) ALNRouteKind kind;
@property(nonatomic, assign, readonly) NSUInteger staticSegmentCount;

- (instancetype)initWithMethod:(NSString *)method
                   pathPattern:(NSString *)pathPattern
                          name:(nullable NSString *)name
               controllerClass:(Class)controllerClass
                    actionName:(NSString *)actionName
             registrationIndex:(NSUInteger)registrationIndex;

- (nullable NSDictionary *)matchPath:(NSString *)path;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
