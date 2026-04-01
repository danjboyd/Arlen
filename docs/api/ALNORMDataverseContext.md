# ALNORMDataverseContext

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseContext.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `client` | `ALNDataverseClient *` | `nonatomic, strong, readonly` | Public `client` property available on `ALNORMDataverseContext`. |
| `capabilityMetadata` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `capabilityMetadata` property available on `ALNORMDataverseContext`. |
| `identityTrackingEnabled` | `BOOL` | `nonatomic, assign, readonly` | Public `identityTrackingEnabled` property available on `ALNORMDataverseContext`. |
| `queryCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `queryCount` property available on `ALNORMDataverseContext`. |
| `queryEvents` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `queryEvents` property available on `ALNORMDataverseContext`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMDataverseContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithClient:` | `- (instancetype)initWithClient:(ALNDataverseClient *)client;` | Initialize and return a new `ALNORMDataverseContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithClient:identityTrackingEnabled:` | `- (instancetype)initWithClient:(ALNDataverseClient *)client identityTrackingEnabled:(BOOL)identityTrackingEnabled NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `capabilityMetadataForClient:` | `+ (NSDictionary<NSString *, id> *)capabilityMetadataForClient:(nullable ALNDataverseClient *)client;` | Perform `capability metadata for client` for `ALNORMDataverseContext`. | Call on the class type, not on an instance. |
| `repositoryForModelClass:` | `- (nullable ALNORMDataverseRepository *)repositoryForModelClass:(Class)modelClass;` | Perform `repository for model class` for `ALNORMDataverseContext`. | Capture the returned value and propagate errors/validation as needed. |
| `registerFieldConverters:forModelClass:` | `- (void)registerFieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters forModelClass:(Class)modelClass;` | Register this component so it participates in runtime behavior. | Call during bootstrap/setup before this behavior is exercised. |
| `fieldConvertersForModelClass:` | `- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass;` | Perform `field converters for model class` for `ALNORMDataverseContext`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `loadRelationNamed:fromModel:error:` | `- (BOOL)loadRelationNamed:(NSString *)relationName fromModel:(ALNORMDataverseModel *)model error:(NSError *_Nullable *_Nullable)error;` | Load and normalize configuration data. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `resetTracking` | `- (void)resetTracking;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
| `detachModel:` | `- (void)detachModel:(ALNORMDataverseModel *)model;` | Perform `detach model` for `ALNORMDataverseContext`. | Call for side effects; this method does not return a value. |
