#ifndef ALN_DATABASE_ROUTER_H
#define ALN_DATABASE_ROUTER_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDatabaseRouterErrorDomain;

typedef NS_ENUM(NSInteger, ALNDatabaseRouterErrorCode) {
  ALNDatabaseRouterErrorInvalidArgument = 1,
  ALNDatabaseRouterErrorUnknownTarget = 2,
  ALNDatabaseRouterErrorMissingAdapter = 3,
};

typedef NS_ENUM(NSInteger, ALNDatabaseRouteOperationClass) {
  ALNDatabaseRouteOperationClassRead = 1,
  ALNDatabaseRouteOperationClassWrite = 2,
  ALNDatabaseRouteOperationClassTransaction = 3,
};

FOUNDATION_EXPORT NSString *ALNDatabaseRouteOperationClassName(ALNDatabaseRouteOperationClass operationClass);

extern NSString *const ALNDatabaseRoutingContextTenantKey;
extern NSString *const ALNDatabaseRoutingContextShardKey;
extern NSString *const ALNDatabaseRoutingContextStickinessScopeKey;

extern NSString *const ALNDatabaseRouterEventStageKey;
extern NSString *const ALNDatabaseRouterEventOperationClassKey;
extern NSString *const ALNDatabaseRouterEventSelectedTargetKey;
extern NSString *const ALNDatabaseRouterEventDefaultTargetKey;
extern NSString *const ALNDatabaseRouterEventFallbackTargetKey;
extern NSString *const ALNDatabaseRouterEventUsedStickinessKey;
extern NSString *const ALNDatabaseRouterEventStickinessScopeKey;
extern NSString *const ALNDatabaseRouterEventTenantKey;
extern NSString *const ALNDatabaseRouterEventShardKey;
extern NSString *const ALNDatabaseRouterEventResolverOverrideKey;
extern NSString *const ALNDatabaseRouterEventErrorDomainKey;
extern NSString *const ALNDatabaseRouterEventErrorCodeKey;

typedef NSString *_Nullable (^ALNDatabaseRouteTargetResolver)(
    ALNDatabaseRouteOperationClass operationClass,
    NSDictionary<NSString *, id> *routingContext,
    NSString *defaultTarget);

typedef void (^ALNDatabaseRoutingDiagnosticsListener)(NSDictionary<NSString *, id> *event);

@interface ALNDatabaseRouter : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy, readonly) NSDictionary<NSString *, id<ALNDatabaseAdapter>> *targets;
@property(nonatomic, copy, readonly) NSString *defaultReadTarget;
@property(nonatomic, copy, readonly) NSString *defaultWriteTarget;

@property(nonatomic, assign) NSTimeInterval readAfterWriteStickinessSeconds;
@property(nonatomic, copy) NSString *stickinessScopeContextKey;
@property(nonatomic, assign) BOOL fallbackReadToWriteOnError;

@property(nonatomic, copy, nullable) ALNDatabaseRouteTargetResolver routeTargetResolver;
@property(nonatomic, copy, nullable) ALNDatabaseRoutingDiagnosticsListener routingDiagnosticsListener;

- (nullable instancetype)initWithTargets:(NSDictionary<NSString *, id<ALNDatabaseAdapter>> *)targets
                       defaultReadTarget:(NSString *)defaultReadTarget
                      defaultWriteTarget:(NSString *)defaultWriteTarget
                                   error:(NSError *_Nullable *_Nullable)error;

- (nullable NSString *)resolveTargetForOperationClass:(ALNDatabaseRouteOperationClass)operationClass
                                       routingContext:(nullable NSDictionary<NSString *, id> *)routingContext
                                                error:(NSError *_Nullable *_Nullable)error;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                    routingContext:(nullable NSDictionary<NSString *, id> *)routingContext
                                             error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
             routingContext:(nullable NSDictionary<NSString *, id> *)routingContext
                      error:(NSError *_Nullable *_Nullable)error;

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                  routingContext:(nullable NSDictionary<NSString *, id> *)routingContext
                            error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
