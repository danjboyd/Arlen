#ifndef ALN_APPLICATION_H
#define ALN_APPLICATION_H

#import <Foundation/Foundation.h>

@class ALNRequest;
@class ALNResponse;
@class ALNRouter;
@class ALNLogger;
@class ALNContext;

NS_ASSUME_NONNULL_BEGIN

@protocol ALNMiddleware <NSObject>
- (BOOL)processContext:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;
@optional
- (void)didProcessContext:(ALNContext *)context;
@end

@interface ALNApplication : NSObject

@property(nonatomic, strong, readonly) ALNRouter *router;
@property(nonatomic, copy, readonly) NSDictionary *config;
@property(nonatomic, copy, readonly) NSString *environment;
@property(nonatomic, strong, readonly) ALNLogger *logger;
@property(nonatomic, copy, readonly) NSArray *middlewares;

- (nullable instancetype)initWithEnvironment:(NSString *)environment
                                   configRoot:(NSString *)configRoot
                                        error:(NSError *_Nullable *_Nullable)error;
- (instancetype)initWithConfig:(NSDictionary *)config;

- (void)registerRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(nullable NSString *)name
            controllerClass:(Class)controllerClass
                     action:(NSString *)actionName;
- (void)registerRouteMethod:(NSString *)method
                       path:(NSString *)path
                       name:(nullable NSString *)name
                    formats:(nullable NSArray *)formats
            controllerClass:(Class)controllerClass
                guardAction:(nullable NSString *)guardAction
                     action:(NSString *)actionName;
- (void)beginRouteGroupWithPrefix:(NSString *)prefix
                      guardAction:(nullable NSString *)guardAction
                          formats:(nullable NSArray *)formats;
- (void)endRouteGroup;
- (void)addMiddleware:(id<ALNMiddleware>)middleware;

- (ALNResponse *)dispatchRequest:(ALNRequest *)request;
- (NSArray *)routeTable;

@end

NS_ASSUME_NONNULL_END

#endif
