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
@property(nonatomic, assign, readonly) SEL guardSelector;
@property(nonatomic, copy, readonly) NSString *guardActionName;
@property(nonatomic, copy, readonly) NSArray *formats;
@property(nonatomic, assign, readonly) NSUInteger registrationIndex;
@property(nonatomic, assign, readonly) ALNRouteKind kind;
@property(nonatomic, assign, readonly) NSUInteger staticSegmentCount;
@property(nonatomic, copy) NSDictionary *requestSchema;
@property(nonatomic, copy) NSDictionary *responseSchema;
@property(nonatomic, copy) NSString *summary;
@property(nonatomic, copy) NSString *operationID;
@property(nonatomic, copy) NSArray *tags;
@property(nonatomic, copy) NSArray *requiredScopes;
@property(nonatomic, copy) NSArray *requiredRoles;
@property(nonatomic, assign) BOOL includeInOpenAPI;
@property(nonatomic, strong, nullable) NSMethodSignature *compiledActionSignature;
@property(nonatomic, strong, nullable) NSMethodSignature *compiledGuardSignature;
@property(nonatomic, assign) BOOL compiledInvocationMetadata;

- (instancetype)initWithMethod:(NSString *)method
                   pathPattern:(NSString *)pathPattern
                          name:(nullable NSString *)name
               controllerClass:(Class)controllerClass
                    actionName:(NSString *)actionName
             registrationIndex:(NSUInteger)registrationIndex;
- (instancetype)initWithMethod:(NSString *)method
                   pathPattern:(NSString *)pathPattern
                          name:(nullable NSString *)name
                       formats:(nullable NSArray *)formats
               controllerClass:(Class)controllerClass
               guardActionName:(nullable NSString *)guardActionName
                    actionName:(NSString *)actionName
             registrationIndex:(NSUInteger)registrationIndex;

- (nullable NSDictionary *)matchPath:(NSString *)path;
- (BOOL)matchesFormat:(nullable NSString *)format;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
