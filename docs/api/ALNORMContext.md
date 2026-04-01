# ALNORMContext

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMContext.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `adapter` | `id<ALNDatabaseAdapter>` | `nonatomic, strong, readonly` | Public `adapter` property available on `ALNORMContext`. |
| `capabilityMetadata` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `capabilityMetadata` property available on `ALNORMContext`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithAdapter:` | `- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMContext` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `capabilityMetadataForAdapter:` | `+ (NSDictionary<NSString *, id> *)capabilityMetadataForAdapter:(nullable id<ALNDatabaseAdapter>)adapter;` | Perform `capability metadata for adapter` for `ALNORMContext`. | Call on the class type, not on an instance. |
| `repositoryForModelClass:` | `- (nullable ALNORMRepository *)repositoryForModelClass:(Class)modelClass;` | Perform `repository for model class` for `ALNORMContext`. | Capture the returned value and propagate errors/validation as needed. |
| `queryForRelationNamed:fromModel:error:` | `- (nullable ALNORMQuery *)queryForRelationNamed:(NSString *)relationName fromModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `query for relation named` for `ALNORMContext`. | Pass `NSError **` and treat a `nil` result as failure. |
| `allForRelationNamed:fromModel:error:` | `- (nullable NSArray *)allForRelationNamed:(NSString *)relationName fromModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `all for relation named` for `ALNORMContext`. | Pass `NSError **` and treat a `nil` result as failure. |
