# ALNORMDataverseRepository

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseRepository.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `context` | `ALNORMDataverseContext *` | `nonatomic, strong, readonly` | Public `context` property available on `ALNORMDataverseRepository`. |
| `modelClass` | `Class` | `nonatomic, assign, readonly` | Public `modelClass` property available on `ALNORMDataverseRepository`. |
| `descriptor` | `ALNORMDataverseModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMDataverseRepository`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMDataverseRepository` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithContext:modelClass:` | `- (instancetype)initWithContext:(ALNORMDataverseContext *)context modelClass:(Class)modelClass NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseRepository` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `query` | `- (nullable ALNDataverseQuery *)query;` | Perform `query` for `ALNORMDataverseRepository`. | Read this value when you need current runtime/request state. |
| `all:` | `- (nullable NSArray *)all:(NSError *_Nullable *_Nullable)error;` | Perform `all` for `ALNORMDataverseRepository`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `allMatchingQuery:error:` | `- (nullable NSArray *)allMatchingQuery:(nullable ALNDataverseQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `all matching query` for `ALNORMDataverseRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `firstMatchingQuery:error:` | `- (nullable id)firstMatchingQuery:(nullable ALNDataverseQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `first matching query` for `ALNORMDataverseRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `findByPrimaryID:error:` | `- (nullable id)findByPrimaryID:(NSString *)primaryID error:(NSError *_Nullable *_Nullable)error;` | Perform `find by primary id` for `ALNORMDataverseRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `findByAlternateKeyValues:error:` | `- (nullable id)findByAlternateKeyValues:(NSDictionary<NSString *, id> *)alternateKeyValues error:(NSError *_Nullable *_Nullable)error;` | Perform `find by alternate key values` for `ALNORMDataverseRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `loadRelationNamed:fromModel:error:` | `- (BOOL)loadRelationNamed:(NSString *)relationName fromModel:(ALNORMDataverseModel *)model error:(NSError *_Nullable *_Nullable)error;` | Load and normalize configuration data. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `saveModel:error:` | `- (BOOL)saveModel:(ALNORMDataverseModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `save model` for `ALNORMDataverseRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `saveModel:changeset:error:` | `- (BOOL)saveModel:(ALNORMDataverseModel *)model changeset:(nullable ALNORMDataverseChangeset *)changeset error:(NSError *_Nullable *_Nullable)error;` | Perform `save model` for `ALNORMDataverseRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `upsertModel:alternateKeyFields:changeset:error:` | `- (BOOL)upsertModel:(ALNORMDataverseModel *)model alternateKeyFields:(NSArray<NSString *> *)alternateKeyFields changeset:(nullable ALNORMDataverseChangeset *)changeset error:(NSError *_Nullable *_Nullable)error;` | Perform `upsert model` for `ALNORMDataverseRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `deleteModel:error:` | `- (BOOL)deleteModel:(ALNORMDataverseModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `delete model` for `ALNORMDataverseRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `saveModelsInBatch:changesets:error:` | `- (BOOL)saveModelsInBatch:(NSArray<ALNORMDataverseModel *> *)models changesets:(nullable NSArray<ALNORMDataverseChangeset *> *)changesets error:(NSError *_Nullable *_Nullable)error;` | Perform `save models in batch` for `ALNORMDataverseRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
