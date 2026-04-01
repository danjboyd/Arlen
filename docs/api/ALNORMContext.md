# ALNORMContext

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMContext.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `adapter` | `id<ALNDatabaseAdapter>` | `nonatomic, strong, readonly` | Public `adapter` property available on `ALNORMContext`. |
| `capabilityMetadata` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `capabilityMetadata` property available on `ALNORMContext`. |
| `identityTrackingEnabled` | `BOOL` | `nonatomic, assign, readonly, getter=isIdentityTrackingEnabled` | Public `identityTrackingEnabled` property available on `ALNORMContext`. |
| `defaultStrictLoadingEnabled` | `BOOL` | `nonatomic, assign` | Public `defaultStrictLoadingEnabled` property available on `ALNORMContext`. |
| `queryCount` | `NSUInteger` | `nonatomic, assign, readonly` | Public `queryCount` property available on `ALNORMContext`. |
| `queryEvents` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `queryEvents` property available on `ALNORMContext`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithAdapter:` | `- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter;` | Initialize and return a new `ALNORMContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithAdapter:identityTrackingEnabled:` | `- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter identityTrackingEnabled:(BOOL)identityTrackingEnabled NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `capabilityMetadataForAdapter:` | `+ (NSDictionary<NSString *, id> *)capabilityMetadataForAdapter:(nullable id<ALNDatabaseAdapter>)adapter;` | Perform `capability metadata for adapter` for `ALNORMContext`. | Call on the class type, not on an instance. |
| `repositoryForModelClass:` | `- (nullable ALNORMRepository *)repositoryForModelClass:(Class)modelClass;` | Perform `repository for model class` for `ALNORMContext`. | Capture the returned value and propagate errors/validation as needed. |
| `registerFieldConverters:forModelClass:` | `- (void)registerFieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters forModelClass:(Class)modelClass;` | Register this component so it participates in runtime behavior. | Call during bootstrap/setup before this behavior is exercised. |
| `fieldConvertersForModelClass:` | `- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass;` | Perform `field converters for model class` for `ALNORMContext`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `registerDefaultWriteOptions:forModelClass:` | `- (void)registerDefaultWriteOptions:(ALNORMWriteOptions *)writeOptions forModelClass:(Class)modelClass;` | Register this component so it participates in runtime behavior. | Call during bootstrap/setup before this behavior is exercised. |
| `defaultWriteOptionsForModelClass:` | `- (nullable ALNORMWriteOptions *)defaultWriteOptionsForModelClass:(Class)modelClass;` | Perform `default write options for model class` for `ALNORMContext`. | Capture the returned value and propagate errors/validation as needed. |
| `resetTracking` | `- (void)resetTracking;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |
| `detachModel:` | `- (void)detachModel:(ALNORMModel *)model;` | Perform `detach model` for `ALNORMContext`. | Call for side effects; this method does not return a value. |
| `reloadModel:error:` | `- (nullable ALNORMModel *)reloadModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `reload model` for `ALNORMContext`. | Pass `NSError **` and treat a `nil` result as failure. |
| `withTransactionUsingBlock:error:` | `- (BOOL)withTransactionUsingBlock:(ALNORMContextBlock)block error:(NSError *_Nullable *_Nullable)error;` | Run a callback inside a managed transaction. | Return `YES` from block to commit; return `NO` or set `error` to trigger rollback. |
| `withSavepointNamed:usingBlock:error:` | `- (BOOL)withSavepointNamed:(NSString *)name usingBlock:(ALNORMContextBlock)block error:(NSError *_Nullable *_Nullable)error;` | Run a scoped callback with managed lifecycle semantics. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `withQueryBudget:usingBlock:error:` | `- (BOOL)withQueryBudget:(NSUInteger)maximum usingBlock:(ALNORMContextBlock)block error:(NSError *_Nullable *_Nullable)error;` | Run a scoped callback with managed lifecycle semantics. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `queryForRelationNamed:fromModel:error:` | `- (nullable ALNORMQuery *)queryForRelationNamed:(NSString *)relationName fromModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `query for relation named` for `ALNORMContext`. | Pass `NSError **` and treat a `nil` result as failure. |
| `loadRelationNamed:fromModel:strategy:error:` | `- (BOOL)loadRelationNamed:(NSString *)relationName fromModel:(ALNORMModel *)model strategy:(ALNORMRelationLoadStrategy)strategy error:(NSError *_Nullable *_Nullable)error;` | Load and normalize configuration data. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `allForRelationNamed:fromModel:error:` | `- (nullable NSArray *)allForRelationNamed:(NSString *)relationName fromModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `all for relation named` for `ALNORMContext`. | Pass `NSError **` and treat a `nil` result as failure. |
