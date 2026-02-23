#import "ALNDatabaseRouter.h"

NSString *const ALNDatabaseRouterErrorDomain = @"Arlen.Data.Router.Error";

NSString *const ALNDatabaseRoutingContextTenantKey = @"tenant";
NSString *const ALNDatabaseRoutingContextShardKey = @"shard";
NSString *const ALNDatabaseRoutingContextStickinessScopeKey = @"stickiness_scope";

NSString *const ALNDatabaseRouterEventStageKey = @"stage";
NSString *const ALNDatabaseRouterEventOperationClassKey = @"operation_class";
NSString *const ALNDatabaseRouterEventSelectedTargetKey = @"selected_target";
NSString *const ALNDatabaseRouterEventDefaultTargetKey = @"default_target";
NSString *const ALNDatabaseRouterEventFallbackTargetKey = @"fallback_target";
NSString *const ALNDatabaseRouterEventUsedStickinessKey = @"used_stickiness";
NSString *const ALNDatabaseRouterEventStickinessScopeKey = @"stickiness_scope";
NSString *const ALNDatabaseRouterEventTenantKey = @"tenant";
NSString *const ALNDatabaseRouterEventShardKey = @"shard";
NSString *const ALNDatabaseRouterEventResolverOverrideKey = @"resolver_override";
NSString *const ALNDatabaseRouterEventErrorDomainKey = @"error_domain";
NSString *const ALNDatabaseRouterEventErrorCodeKey = @"error_code";

static NSError *ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorCode code,
                                           NSString *message,
                                           NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"database router error";
  return [NSError errorWithDomain:ALNDatabaseRouterErrorDomain
                             code:code
                         userInfo:details];
}

NSString *ALNDatabaseRouteOperationClassName(ALNDatabaseRouteOperationClass operationClass) {
  switch (operationClass) {
  case ALNDatabaseRouteOperationClassRead:
    return @"read";
  case ALNDatabaseRouteOperationClassWrite:
    return @"write";
  case ALNDatabaseRouteOperationClassTransaction:
    return @"transaction";
  }
  return @"unknown";
}

@interface ALNDatabaseRouter ()

@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id<ALNDatabaseAdapter>> *targets;
@property(nonatomic, copy, readwrite) NSString *defaultReadTarget;
@property(nonatomic, copy, readwrite) NSString *defaultWriteTarget;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastWriteByScope;

@end

@implementation ALNDatabaseRouter

- (nullable instancetype)initWithTargets:(NSDictionary<NSString *, id<ALNDatabaseAdapter>> *)targets
                       defaultReadTarget:(NSString *)defaultReadTarget
                      defaultWriteTarget:(NSString *)defaultWriteTarget
                                   error:(NSError **)error {
  self = [super init];
  if (self == nil) {
    return nil;
  }

  NSDictionary *normalizedTargets =
      [targets isKindOfClass:[NSDictionary class]] ? targets : @{};
  if ([normalizedTargets count] == 0) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorInvalidArgument,
                                          @"at least one routing target is required",
                                          nil);
    }
    return nil;
  }
  if ([defaultReadTarget length] == 0 || [defaultWriteTarget length] == 0) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorInvalidArgument,
                                          @"default read/write targets are required",
                                          nil);
    }
    return nil;
  }

  for (id key in normalizedTargets) {
    if (![key isKindOfClass:[NSString class]] || [(NSString *)key length] == 0) {
      if (error != NULL) {
        *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorInvalidArgument,
                                            @"routing target keys must be non-empty strings",
                                            nil);
      }
      return nil;
    }
    id value = normalizedTargets[key];
    if (value == nil || ![value conformsToProtocol:@protocol(ALNDatabaseAdapter)]) {
      if (error != NULL) {
        *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorInvalidArgument,
                                            @"routing target values must conform to ALNDatabaseAdapter",
                                            @{ @"target" : (NSString *)key });
      }
      return nil;
    }
  }
  if (normalizedTargets[defaultReadTarget] == nil || normalizedTargets[defaultWriteTarget] == nil) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorMissingAdapter,
                                          @"default read/write targets must exist in targets",
                                          @{
                                            @"default_read_target" : defaultReadTarget,
                                            @"default_write_target" : defaultWriteTarget,
                                          });
    }
    return nil;
  }

  _targets = [NSDictionary dictionaryWithDictionary:normalizedTargets];
  _defaultReadTarget = [defaultReadTarget copy];
  _defaultWriteTarget = [defaultWriteTarget copy];
  _readAfterWriteStickinessSeconds = 0;
  _stickinessScopeContextKey = [ALNDatabaseRoutingContextStickinessScopeKey copy];
  _fallbackReadToWriteOnError = YES;
  _lastWriteByScope = [NSMutableDictionary dictionary];
  _routeTargetResolver = nil;
  _routingDiagnosticsListener = nil;
  return self;
}

- (NSString *)adapterName {
  return @"router";
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  id<ALNDatabaseAdapter> adapter = self.targets[self.defaultWriteTarget];
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorMissingAdapter,
                                          @"default write adapter is not configured",
                                          @{ @"target" : self.defaultWriteTarget ?: @"" });
    }
    return nil;
  }
  return [adapter acquireAdapterConnection:error];
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  id<ALNDatabaseAdapter> adapter = self.targets[self.defaultWriteTarget];
  if (adapter != nil) {
    [adapter releaseAdapterConnection:connection];
  }
}

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError **)error {
  return [self executeQuery:sql parameters:parameters routingContext:nil error:error];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  return [self executeCommand:sql parameters:parameters routingContext:nil error:error];
}

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                            error:(NSError **)error {
  return [self withTransactionUsingBlock:block routingContext:nil error:error];
}

- (nullable NSString *)resolveTargetForOperationClass:(ALNDatabaseRouteOperationClass)operationClass
                                       routingContext:(NSDictionary<NSString *, id> *)routingContext
                                                error:(NSError **)error {
  NSDictionary *descriptor =
      [self routeDescriptorForOperationClass:operationClass routingContext:routingContext error:error];
  if (descriptor == nil) {
    return nil;
  }
  return descriptor[ALNDatabaseRouterEventSelectedTargetKey];
}

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                    routingContext:(NSDictionary<NSString *, id> *)routingContext
                                             error:(NSError **)error {
  NSDictionary *descriptor = [self routeDescriptorForOperationClass:ALNDatabaseRouteOperationClassRead
                                                      routingContext:routingContext
                                                               error:error];
  if (descriptor == nil) {
    return nil;
  }

  NSString *target = descriptor[ALNDatabaseRouterEventSelectedTargetKey];
  id<ALNDatabaseAdapter> adapter = self.targets[target];
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorMissingAdapter,
                                          @"resolved read target is not configured",
                                          @{ @"target" : target ?: @"" });
    }
    return nil;
  }

  [self emitRoutingEventWithStage:@"route"
                       descriptor:descriptor
                   fallbackTarget:nil
                            error:nil];

  NSError *queryError = nil;
  NSArray<NSDictionary *> *rows = [adapter executeQuery:sql parameters:parameters ?: @[] error:&queryError];
  if (rows != nil) {
    return rows;
  }

  if (queryError == nil) {
    queryError = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorConformanceFailed,
                                             @"read query returned nil without an error",
                                             @{ @"target" : target ?: @"" });
  }

  NSString *writeTarget = self.defaultWriteTarget ?: @"";
  id<ALNDatabaseAdapter> writeAdapter = self.targets[writeTarget];
  BOOL shouldFallback =
      self.fallbackReadToWriteOnError && [writeTarget length] > 0 &&
      ![target isEqualToString:writeTarget] && writeAdapter != nil;
  if (!shouldFallback) {
    if (error != NULL) {
      *error = queryError;
    }
    return nil;
  }

  [self emitRoutingEventWithStage:@"fallback"
                       descriptor:descriptor
                   fallbackTarget:writeTarget
                            error:queryError];

  NSError *fallbackError = nil;
  NSArray<NSDictionary *> *fallbackRows =
      [writeAdapter executeQuery:sql parameters:parameters ?: @[] error:&fallbackError];
  if (fallbackRows != nil) {
    return fallbackRows;
  }

  if (error != NULL) {
    *error = fallbackError ?: queryError;
  }
  return nil;
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
             routingContext:(NSDictionary<NSString *, id> *)routingContext
                      error:(NSError **)error {
  NSDictionary *descriptor = [self routeDescriptorForOperationClass:ALNDatabaseRouteOperationClassWrite
                                                      routingContext:routingContext
                                                               error:error];
  if (descriptor == nil) {
    return -1;
  }

  NSString *target = descriptor[ALNDatabaseRouterEventSelectedTargetKey];
  id<ALNDatabaseAdapter> adapter = self.targets[target];
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorMissingAdapter,
                                          @"resolved write target is not configured",
                                          @{ @"target" : target ?: @"" });
    }
    return -1;
  }

  [self emitRoutingEventWithStage:@"route"
                       descriptor:descriptor
                   fallbackTarget:nil
                            error:nil];

  NSError *commandError = nil;
  NSInteger result = [adapter executeCommand:sql parameters:parameters ?: @[] error:&commandError];
  if (result >= 0) {
    NSString *scope = descriptor[ALNDatabaseRouterEventStickinessScopeKey] ?: @"__global__";
    [self recordWriteForScope:scope atDate:[NSDate date]];
  } else if (error != NULL) {
    *error = commandError;
  }
  return result;
}

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                  routingContext:(NSDictionary<NSString *, id> *)routingContext
                            error:(NSError **)error {
  if (block == nil) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                           @"transaction block is required",
                                           nil);
    }
    return NO;
  }

  NSDictionary *descriptor =
      [self routeDescriptorForOperationClass:ALNDatabaseRouteOperationClassTransaction
                              routingContext:routingContext
                                       error:error];
  if (descriptor == nil) {
    return NO;
  }

  NSString *target = descriptor[ALNDatabaseRouterEventSelectedTargetKey];
  id<ALNDatabaseAdapter> adapter = self.targets[target];
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorMissingAdapter,
                                          @"resolved transaction target is not configured",
                                          @{ @"target" : target ?: @"" });
    }
    return NO;
  }

  [self emitRoutingEventWithStage:@"route"
                       descriptor:descriptor
                   fallbackTarget:nil
                            error:nil];

  NSError *txError = nil;
  BOOL ok = [adapter withTransactionUsingBlock:block error:&txError];
  if (ok) {
    NSString *scope = descriptor[ALNDatabaseRouterEventStickinessScopeKey] ?: @"__global__";
    [self recordWriteForScope:scope atDate:[NSDate date]];
  } else if (error != NULL) {
    *error = txError;
  }
  return ok;
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"adapter" : @"router",
    @"dialect" : @"multi_target",
    @"supports_read_write_routing" : @YES,
    @"supports_read_after_write_stickiness" : @YES,
    @"supports_tenant_shard_routing_hook" : @YES,
    @"supports_route_fallback_to_write" : @(self.fallbackReadToWriteOnError),
    @"supports_routing_diagnostics" : @YES,
  };
}

- (nullable NSDictionary<NSString *, id> *)routeDescriptorForOperationClass:(ALNDatabaseRouteOperationClass)operationClass
                                                              routingContext:(NSDictionary<NSString *, id> *)routingContext
                                                                       error:(NSError **)error {
  NSDictionary *context = [routingContext isKindOfClass:[NSDictionary class]] ? routingContext : @{};
  NSString *scope = [self stickinessScopeForContext:context];
  NSString *defaultTarget =
      (operationClass == ALNDatabaseRouteOperationClassRead) ? self.defaultReadTarget : self.defaultWriteTarget;
  BOOL usedStickiness = NO;
  if (operationClass == ALNDatabaseRouteOperationClassRead &&
      [self shouldUseStickinessForScope:scope atDate:[NSDate date]]) {
    defaultTarget = self.defaultWriteTarget;
    usedStickiness = YES;
  }

  NSString *selectedTarget = defaultTarget;
  BOOL resolverOverride = NO;
  if (self.routeTargetResolver != nil) {
    NSString *resolved = self.routeTargetResolver(operationClass, context, defaultTarget ?: @"");
    if ([resolved isKindOfClass:[NSString class]] && [resolved length] > 0) {
      selectedTarget = resolved;
      resolverOverride = ![selectedTarget isEqualToString:(defaultTarget ?: @"")];
    }
  }

  if ([selectedTarget length] == 0) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorUnknownTarget,
                                          @"route resolution returned an empty target",
                                          @{ @"operation_class" : ALNDatabaseRouteOperationClassName(operationClass) });
    }
    return nil;
  }
  if (self.targets[selectedTarget] == nil) {
    if (error != NULL) {
      *error = ALNDatabaseRouterMakeError(ALNDatabaseRouterErrorUnknownTarget,
                                          @"resolved target does not exist",
                                          @{
                                            @"operation_class" : ALNDatabaseRouteOperationClassName(operationClass),
                                            @"target" : selectedTarget,
                                          });
    }
    return nil;
  }

  NSMutableDictionary *descriptor = [NSMutableDictionary dictionary];
  descriptor[ALNDatabaseRouterEventOperationClassKey] = ALNDatabaseRouteOperationClassName(operationClass);
  descriptor[ALNDatabaseRouterEventSelectedTargetKey] = selectedTarget;
  descriptor[ALNDatabaseRouterEventDefaultTargetKey] = defaultTarget ?: @"";
  descriptor[ALNDatabaseRouterEventUsedStickinessKey] = @(usedStickiness);
  descriptor[ALNDatabaseRouterEventStickinessScopeKey] = scope;
  descriptor[ALNDatabaseRouterEventResolverOverrideKey] = @(resolverOverride);

  NSString *tenant = [context[ALNDatabaseRoutingContextTenantKey] isKindOfClass:[NSString class]]
                         ? context[ALNDatabaseRoutingContextTenantKey]
                         : @"";
  NSString *shard = [context[ALNDatabaseRoutingContextShardKey] isKindOfClass:[NSString class]]
                        ? context[ALNDatabaseRoutingContextShardKey]
                        : @"";
  if ([tenant length] > 0) {
    descriptor[ALNDatabaseRouterEventTenantKey] = tenant;
  }
  if ([shard length] > 0) {
    descriptor[ALNDatabaseRouterEventShardKey] = shard;
  }
  return descriptor;
}

- (NSString *)stickinessScopeForContext:(NSDictionary<NSString *, id> *)context {
  NSString *key = [self.stickinessScopeContextKey isKindOfClass:[NSString class]]
                      ? self.stickinessScopeContextKey
                      : @"";
  if ([key length] == 0) {
    key = ALNDatabaseRoutingContextStickinessScopeKey;
  }
  NSString *scope = [context[key] isKindOfClass:[NSString class]] ? context[key] : @"";
  scope = [scope stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([scope length] > 0) ? scope : @"__global__";
}

- (BOOL)shouldUseStickinessForScope:(NSString *)scope atDate:(NSDate *)now {
  if (self.readAfterWriteStickinessSeconds <= 0) {
    return NO;
  }
  NSString *safeScope = ([scope length] > 0) ? scope : @"__global__";

  @synchronized(self) {
    NSDate *lastWrite = self.lastWriteByScope[safeScope];
    if (lastWrite == nil) {
      return NO;
    }
    NSTimeInterval age = [now timeIntervalSinceDate:lastWrite];
    if (age <= self.readAfterWriteStickinessSeconds) {
      return YES;
    }
    [self.lastWriteByScope removeObjectForKey:safeScope];
    return NO;
  }
}

- (void)recordWriteForScope:(NSString *)scope atDate:(NSDate *)now {
  NSString *safeScope = ([scope length] > 0) ? scope : @"__global__";
  @synchronized(self) {
    self.lastWriteByScope[safeScope] = now ?: [NSDate date];
  }
}

- (void)emitRoutingEventWithStage:(NSString *)stage
                       descriptor:(NSDictionary<NSString *, id> *)descriptor
                   fallbackTarget:(NSString *)fallbackTarget
                            error:(NSError *)error {
  if (self.routingDiagnosticsListener == nil) {
    return;
  }

  NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:descriptor ?: @{}];
  event[ALNDatabaseRouterEventStageKey] = stage ?: @"route";
  if ([fallbackTarget length] > 0) {
    event[ALNDatabaseRouterEventFallbackTargetKey] = fallbackTarget;
  }
  if (error != nil) {
    event[ALNDatabaseRouterEventErrorDomainKey] = error.domain ?: @"";
    event[ALNDatabaseRouterEventErrorCodeKey] = @(error.code);
  }
  self.routingDiagnosticsListener([NSDictionary dictionaryWithDictionary:event]);
}

@end
