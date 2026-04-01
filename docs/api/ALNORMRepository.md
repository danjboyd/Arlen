# ALNORMRepository

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMRepository.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `context` | `ALNORMContext *` | `nonatomic, strong, readonly` | Public `context` property available on `ALNORMRepository`. |
| `modelClass` | `Class` | `nonatomic, assign, readonly` | Public `modelClass` property available on `ALNORMRepository`. |
| `descriptor` | `ALNORMModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMRepository`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMRepository` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithContext:modelClass:` | `- (instancetype)initWithContext:(ALNORMContext *)context modelClass:(Class)modelClass NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMRepository` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `query` | `- (nullable ALNORMQuery *)query;` | Perform `query` for `ALNORMRepository`. | Read this value when you need current runtime/request state. |
| `queryByApplyingScope:` | `- (nullable ALNORMQuery *)queryByApplyingScope:(nullable ALNORMQueryScope)scope;` | Perform `query by applying scope` for `ALNORMRepository`. | Capture the returned value and propagate errors/validation as needed. |
| `all:` | `- (nullable NSArray *)all:(NSError *_Nullable *_Nullable)error;` | Perform `all` for `ALNORMRepository`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `allMatchingQuery:error:` | `- (nullable NSArray *)allMatchingQuery:(nullable ALNORMQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `all matching query` for `ALNORMRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `first:` | `- (nullable id)first:(NSError *_Nullable *_Nullable)error;` | Perform `first` for `ALNORMRepository`. | Capture the returned value and propagate errors/validation as needed. |
| `firstMatchingQuery:error:` | `- (nullable id)firstMatchingQuery:(nullable ALNORMQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `first matching query` for `ALNORMRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `count:` | `- (NSUInteger)count:(NSError *_Nullable *_Nullable)error;` | Perform `count` for `ALNORMRepository`. | Capture the returned value and propagate errors/validation as needed. |
| `countMatchingQuery:error:` | `- (NSUInteger)countMatchingQuery:(nullable ALNORMQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `count matching query` for `ALNORMRepository`. | Pass `NSError **` when you need detailed failure diagnostics. |
| `exists:` | `- (BOOL)exists:(NSError *_Nullable *_Nullable)error;` | Perform `exists` for `ALNORMRepository`. | Check the return value to confirm the operation succeeded. |
| `existsMatchingQuery:error:` | `- (BOOL)existsMatchingQuery:(nullable ALNORMQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `exists matching query` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `findByPrimaryKey:error:` | `- (nullable id)findByPrimaryKey:(id)primaryKey error:(NSError *_Nullable *_Nullable)error;` | Perform `find by primary key` for `ALNORMRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `findByPrimaryKeyValues:error:` | `- (nullable id)findByPrimaryKeyValues:(NSDictionary<NSString *, id> *)primaryKeyValues error:(NSError *_Nullable *_Nullable)error;` | Perform `find by primary key values` for `ALNORMRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
| `saveModel:error:` | `- (BOOL)saveModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `save model` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `saveModel:options:error:` | `- (BOOL)saveModel:(ALNORMModel *)model options:(nullable ALNORMWriteOptions *)options error:(NSError *_Nullable *_Nullable)error;` | Perform `save model` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `saveModel:changeset:options:error:` | `- (BOOL)saveModel:(ALNORMModel *)model changeset:(nullable ALNORMChangeset *)changeset options:(nullable ALNORMWriteOptions *)options error:(NSError *_Nullable *_Nullable)error;` | Perform `save model` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `deleteModel:error:` | `- (BOOL)deleteModel:(ALNORMModel *)model error:(NSError *_Nullable *_Nullable)error;` | Perform `delete model` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `deleteModel:options:error:` | `- (BOOL)deleteModel:(ALNORMModel *)model options:(nullable ALNORMWriteOptions *)options error:(NSError *_Nullable *_Nullable)error;` | Perform `delete model` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `upsertModel:options:error:` | `- (BOOL)upsertModel:(ALNORMModel *)model options:(nullable ALNORMWriteOptions *)options error:(NSError *_Nullable *_Nullable)error;` | Perform `upsert model` for `ALNORMRepository`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `compiledPlanForQuery:error:` | `- (nullable NSDictionary<NSString *, id> *)compiledPlanForQuery:(nullable ALNORMQuery *)query error:(NSError *_Nullable *_Nullable)error;` | Perform `compiled plan for query` for `ALNORMRepository`. | Pass `NSError **` and treat a `nil` result as failure. |
