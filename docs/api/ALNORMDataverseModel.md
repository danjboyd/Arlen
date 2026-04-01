# ALNORMDataverseModel

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseModel.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `descriptor` | `ALNORMDataverseModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMDataverseModel`. |
| `fieldValues` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `fieldValues` property available on `ALNORMDataverseModel`. |
| `relationValues` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `relationValues` property available on `ALNORMDataverseModel`. |
| `dirtyFieldNames` | `NSSet<NSString *> *` | `nonatomic, copy, readonly` | Public `dirtyFieldNames` property available on `ALNORMDataverseModel`. |
| `loadedRelationNames` | `NSSet<NSString *> *` | `nonatomic, copy, readonly` | Public `loadedRelationNames` property available on `ALNORMDataverseModel`. |
| `rawDictionary` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `rawDictionary` property available on `ALNORMDataverseModel`. |
| `etag` | `NSString *` | `nonatomic, copy, readonly` | Public `etag` property available on `ALNORMDataverseModel`. |
| `context` | `ALNORMDataverseContext *` | `nonatomic, weak, readonly, nullable` | Public `context` property available on `ALNORMDataverseModel`. |
| `persisted` | `BOOL` | `nonatomic, assign, readonly, getter=isPersisted` | Public `persisted` property available on `ALNORMDataverseModel`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init;` | Initialize and return a new `ALNORMDataverseModel` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDescriptor:` | `- (instancetype)initWithDescriptor:(ALNORMDataverseModelDescriptor *)descriptor NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseModel` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dataverseModelDescriptor` | `+ (nullable ALNORMDataverseModelDescriptor *)dataverseModelDescriptor;` | Perform `dataverse model descriptor` for `ALNORMDataverseModel`. | Call on the class type, not on an instance. |
| `query` | `+ (nullable ALNDataverseQuery *)query;` | Perform `query` for `ALNORMDataverseModel`. | Call on the class type, not on an instance. |
| `repositoryWithContext:` | `+ (nullable ALNORMDataverseRepository *)repositoryWithContext:(ALNORMDataverseContext *)context;` | Perform `repository with context` for `ALNORMDataverseModel`. | Call on the class type, not on an instance. |
| `modelFromRecord:error:` | `+ (nullable instancetype)modelFromRecord:(ALNDataverseRecord *)record error:(NSError *_Nullable *_Nullable)error;` | Perform `model from record` for `ALNORMDataverseModel`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `objectForFieldName:` | `- (nullable id)objectForFieldName:(NSString *)fieldName;` | Perform `object for field name` for `ALNORMDataverseModel`. | Capture the returned value and propagate errors/validation as needed. |
| `setObject:forFieldName:error:` | `- (BOOL)setObject:(nullable id)value forFieldName:(NSString *)fieldName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `applyRecord:error:` | `- (BOOL)applyRecord:(ALNDataverseRecord *)record error:(NSError *_Nullable *_Nullable)error;` | Apply this helper to context and update response state. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `markClean` | `- (void)markClean;` | Perform `mark clean` for `ALNORMDataverseModel`. | Call for side effects; this method does not return a value. |
| `attachToContext:` | `- (void)attachToContext:(nullable ALNORMDataverseContext *)context;` | Perform `attach to context` for `ALNORMDataverseModel`. | Call for side effects; this method does not return a value. |
| `relationObjectForName:` | `- (nullable id)relationObjectForName:(NSString *)relationName;` | Perform `relation object for name` for `ALNORMDataverseModel`. | Capture the returned value and propagate errors/validation as needed. |
| `markRelationLoaded:value:error:` | `- (BOOL)markRelationLoaded:(NSString *)relationName value:(nullable id)value error:(NSError *_Nullable *_Nullable)error;` | Perform `mark relation loaded` for `ALNORMDataverseModel`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `primaryIDValue` | `- (nullable id)primaryIDValue;` | Perform `primary id value` for `ALNORMDataverseModel`. | Read this value when you need current runtime/request state. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
