# ALNDataverseTarget

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `serviceRootURLString` | `NSString *` | `nonatomic, copy, readonly` | Public `serviceRootURLString` property available on `ALNDataverseTarget`. |
| `environmentURLString` | `NSString *` | `nonatomic, copy, readonly` | Public `environmentURLString` property available on `ALNDataverseTarget`. |
| `tenantID` | `NSString *` | `nonatomic, copy, readonly` | Public `tenantID` property available on `ALNDataverseTarget`. |
| `clientID` | `NSString *` | `nonatomic, copy, readonly` | Public `clientID` property available on `ALNDataverseTarget`. |
| `clientSecret` | `NSString *` | `nonatomic, copy, readonly` | Public `clientSecret` property available on `ALNDataverseTarget`. |
| `targetName` | `NSString *` | `nonatomic, copy, readonly` | Public `targetName` property available on `ALNDataverseTarget`. |
| `timeoutInterval` | `NSTimeInterval` | `nonatomic, assign, readonly` | Public `timeoutInterval` property available on `ALNDataverseTarget`. |
| `maxRetries` | `NSUInteger` | `nonatomic, assign, readonly` | Public `maxRetries` property available on `ALNDataverseTarget`. |
| `pageSize` | `NSUInteger` | `nonatomic, assign, readonly` | Public `pageSize` property available on `ALNDataverseTarget`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `normalizedEnvironmentURLStringFromServiceRootURLString:` | `+ (nullable NSString *)normalizedEnvironmentURLStringFromServiceRootURLString: (NSString *)serviceRootURLString;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. |
| `configuredTargetNamesFromConfig:` | `+ (NSArray<NSString *> *)configuredTargetNamesFromConfig:(nullable NSDictionary *)config;` | Configure behavior for an already-registered runtime element. | Call on the class type, not on an instance. |
| `configurationNamed:fromConfig:` | `+ (nullable NSDictionary<NSString *, id> *)configurationNamed:(nullable NSString *)targetName fromConfig:(nullable NSDictionary *)config;` | Perform `configuration named` for `ALNDataverseTarget`. | Call on the class type, not on an instance. |
| `targetNamed:fromConfig:error:` | `+ (nullable instancetype)targetNamed:(nullable NSString *)targetName fromConfig:(nullable NSDictionary *)config error:(NSError *_Nullable *_Nullable)error;` | Perform `target named` for `ALNDataverseTarget`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseTarget` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithServiceRootURLString:tenantID:clientID:clientSecret:targetName:timeoutInterval:maxRetries:pageSize:error:` | `- (nullable instancetype)initWithServiceRootURLString:(NSString *)serviceRootURLString tenantID:(NSString *)tenantID clientID:(NSString *)clientID clientSecret:(NSString *)clientSecret targetName:(nullable NSString *)targetName timeoutInterval:(NSTimeInterval)timeoutInterval maxRetries:(NSUInteger)maxRetries pageSize:(NSUInteger)pageSize error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseTarget` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
