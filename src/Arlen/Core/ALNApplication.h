#ifndef ALN_APPLICATION_H
#define ALN_APPLICATION_H

#import <Foundation/Foundation.h>
#import "ALNServices.h"

@class ALNRequest;
@class ALNResponse;
@class ALNRouter;
@class ALNLogger;
@class ALNContext;
@class ALNMetricsRegistry;
@class ALNRoute;
@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

@protocol ALNMiddleware <NSObject>
- (BOOL)processContext:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;
@optional
- (void)didProcessContext:(ALNContext *)context;
@end

@protocol ALNLifecycleHook <NSObject>
@optional
- (BOOL)applicationWillStart:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;
- (void)applicationDidStart:(ALNApplication *)application;
- (void)applicationWillStop:(ALNApplication *)application;
- (void)applicationDidStop:(ALNApplication *)application;
@end

@protocol ALNPlugin <NSObject>
- (NSString *)pluginName;
- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;
@optional
- (NSArray *)middlewaresForApplication:(ALNApplication *)application;
@end

@protocol ALNTraceExporter <NSObject>
- (void)exportTrace:(NSDictionary *)trace
            request:(ALNRequest *)request
           response:(ALNResponse *)response
          routeName:(NSString *)routeName
     controllerName:(NSString *)controllerName
         actionName:(NSString *)actionName;
@end

@interface ALNApplication : NSObject

@property(nonatomic, strong, readonly) ALNRouter *router;
@property(nonatomic, copy, readonly) NSDictionary *config;
@property(nonatomic, copy, readonly) NSString *environment;
@property(nonatomic, strong, readonly) ALNLogger *logger;
@property(nonatomic, strong, readonly) ALNMetricsRegistry *metrics;
@property(nonatomic, copy, readonly) NSArray *middlewares;
@property(nonatomic, copy, readonly) NSArray *plugins;
@property(nonatomic, copy, readonly) NSArray *lifecycleHooks;
@property(nonatomic, strong, readonly) id<ALNJobAdapter> jobsAdapter;
@property(nonatomic, strong, readonly) id<ALNCacheAdapter> cacheAdapter;
@property(nonatomic, strong, readonly) id<ALNLocalizationAdapter> localizationAdapter;
@property(nonatomic, strong, readonly) id<ALNMailAdapter> mailAdapter;
@property(nonatomic, strong, readonly) id<ALNAttachmentAdapter> attachmentAdapter;
@property(nonatomic, assign, readonly, getter=isStarted) BOOL started;
@property(nonatomic, strong, nullable) id<ALNTraceExporter> traceExporter;

- (nullable instancetype)initWithEnvironment:(NSString *)environment
                                   configRoot:(NSString *)configRoot
                                        error:(NSError *_Nullable *_Nullable)error;
- (instancetype)initWithConfig:(NSDictionary *)config;

- (ALNRoute *)registerRouteMethod:(NSString *)method
                              path:(NSString *)path
                              name:(nullable NSString *)name
                   controllerClass:(Class)controllerClass
                            action:(NSString *)actionName;
- (ALNRoute *)registerRouteMethod:(NSString *)method
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
- (BOOL)mountApplication:(ALNApplication *)application atPrefix:(NSString *)prefix;
- (void)addMiddleware:(id<ALNMiddleware>)middleware;
- (void)setJobsAdapter:(id<ALNJobAdapter>)adapter;
- (void)setCacheAdapter:(id<ALNCacheAdapter>)adapter;
- (void)setLocalizationAdapter:(id<ALNLocalizationAdapter>)adapter;
- (void)setMailAdapter:(id<ALNMailAdapter>)adapter;
- (void)setAttachmentAdapter:(id<ALNAttachmentAdapter>)adapter;
- (NSString *)localizedStringForKey:(NSString *)key
                              locale:(nullable NSString *)locale
                      fallbackLocale:(nullable NSString *)fallbackLocale
                        defaultValue:(nullable NSString *)defaultValue
                           arguments:(nullable NSDictionary *)arguments;
- (BOOL)registerLifecycleHook:(id<ALNLifecycleHook>)hook;
- (BOOL)registerPlugin:(id<ALNPlugin>)plugin error:(NSError *_Nullable *_Nullable)error;
- (BOOL)registerPluginClassNamed:(NSString *)className error:(NSError *_Nullable *_Nullable)error;

- (BOOL)configureRouteNamed:(NSString *)routeName
                    requestSchema:(nullable NSDictionary *)requestSchema
                   responseSchema:(nullable NSDictionary *)responseSchema
                          summary:(nullable NSString *)summary
                      operationID:(nullable NSString *)operationID
                             tags:(nullable NSArray *)tags
                    requiredScopes:(nullable NSArray *)requiredScopes
                     requiredRoles:(nullable NSArray *)requiredRoles
                   includeInOpenAPI:(BOOL)includeInOpenAPI
                             error:(NSError *_Nullable *_Nullable)error;

- (ALNResponse *)dispatchRequest:(ALNRequest *)request;
- (NSArray *)routeTable;
- (NSDictionary *)openAPISpecification;
- (BOOL)writeOpenAPISpecToPath:(NSString *)path
                        pretty:(BOOL)pretty
                         error:(NSError *_Nullable *_Nullable)error;
- (BOOL)startWithError:(NSError *_Nullable *_Nullable)error;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END

#endif
