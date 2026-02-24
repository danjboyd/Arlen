# ALNDatabaseRouter

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseRouter.h`

Read/write routing layer that selects database targets by operation class and routing context.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `targets` | `NSDictionary<NSString *, id<ALNDatabaseAdapter>> *` | `nonatomic, copy, readonly` | Public `targets` property available on `ALNDatabaseRouter`. |
| `defaultReadTarget` | `NSString *` | `nonatomic, copy, readonly` | Public `defaultReadTarget` property available on `ALNDatabaseRouter`. |
| `defaultWriteTarget` | `NSString *` | `nonatomic, copy, readonly` | Public `defaultWriteTarget` property available on `ALNDatabaseRouter`. |
| `readAfterWriteStickinessSeconds` | `NSTimeInterval` | `nonatomic, assign` | Public `readAfterWriteStickinessSeconds` property available on `ALNDatabaseRouter`. |
| `stickinessScopeContextKey` | `NSString *` | `nonatomic, copy` | Public `stickinessScopeContextKey` property available on `ALNDatabaseRouter`. |
| `fallbackReadToWriteOnError` | `BOOL` | `nonatomic, assign` | Public `fallbackReadToWriteOnError` property available on `ALNDatabaseRouter`. |
| `routeTargetResolver` | `ALNDatabaseRouteTargetResolver` | `nonatomic, copy, nullable` | Public `routeTargetResolver` property available on `ALNDatabaseRouter`. |
| `routingDiagnosticsListener` | `ALNDatabaseRoutingDiagnosticsListener` | `nonatomic, copy, nullable` | Public `routingDiagnosticsListener` property available on `ALNDatabaseRouter`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithTargets:defaultReadTarget:defaultWriteTarget:error:` | `- (nullable instancetype)initWithTargets:(NSDictionary<NSString *, id<ALNDatabaseAdapter>> *)targets defaultReadTarget:(NSString *)defaultReadTarget defaultWriteTarget:(NSString *)defaultWriteTarget error:(NSError *_Nullable *_Nullable)error;` | Initialize and return a new `ALNDatabaseRouter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `resolveTargetForOperationClass:routingContext:error:` | `- (nullable NSString *)resolveTargetForOperationClass:(ALNDatabaseRouteOperationClass)operationClass routingContext:(nullable NSDictionary<NSString *, id> *)routingContext error:(NSError *_Nullable *_Nullable)error;` | Resolve database target for read/write operation class. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeQuery:parameters:routingContext:error:` | `- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters routingContext:(nullable NSDictionary<NSString *, id> *)routingContext error:(NSError *_Nullable *_Nullable)error;` | Execute routed read query using router target policy. | Pass `NSError **` and treat a `nil` result as failure. |
| `executeCommand:parameters:routingContext:error:` | `- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters routingContext:(nullable NSDictionary<NSString *, id> *)routingContext error:(NSError *_Nullable *_Nullable)error;` | Execute routed write command using router target policy. | Pass `NSError **` when you need detailed failure diagnostics. |
| `withTransactionUsingBlock:routingContext:error:` | `- (BOOL)withTransactionUsingBlock: (BOOL (^)(id<ALNDatabaseConnection> connection, NSError *_Nullable *_Nullable error))block routingContext:(nullable NSDictionary<NSString *, id> *)routingContext error:(NSError *_Nullable *_Nullable)error;` | Run a routed transaction callback on selected write target. | Provide routing context when read/write routing policy depends on tenant/request hints. |
