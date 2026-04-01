# ALNORMModel

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMModel.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `descriptor` | `ALNORMModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMModel`. |
| `state` | `ALNORMModelState` | `nonatomic, assign, readonly` | Public `state` property available on `ALNORMModel`. |
| `fieldValues` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `fieldValues` property available on `ALNORMModel`. |
| `relationValues` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `relationValues` property available on `ALNORMModel`. |
| `dirtyFieldNames` | `NSSet<NSString *> *` | `nonatomic, copy, readonly` | Public `dirtyFieldNames` property available on `ALNORMModel`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init;` | Initialize and return a new `ALNORMModel` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDescriptor:` | `- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMModel` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `modelDescriptor` | `+ (nullable ALNORMModelDescriptor *)modelDescriptor;` | Perform `model descriptor` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `query` | `+ (nullable ALNORMQuery *)query;` | Perform `query` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `repositoryWithContext:` | `+ (nullable ALNORMRepository *)repositoryWithContext:(ALNORMContext *)context;` | Perform `repository with context` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `modelFromRow:error:` | `+ (nullable instancetype)modelFromRow:(NSDictionary<NSString *, id> *)row error:(NSError *_Nullable *_Nullable)error;` | Perform `model from row` for `ALNORMModel`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `allFieldNames` | `+ (NSArray<NSString *> *)allFieldNames;` | Perform `all field names` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `allColumnNames` | `+ (NSArray<NSString *> *)allColumnNames;` | Perform `all column names` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `allQualifiedColumnNames` | `+ (NSArray<NSString *> *)allQualifiedColumnNames;` | Perform `all qualified column names` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `entityName` | `+ (NSString *)entityName;` | Perform `entity name` for `ALNORMModel`. | Call on the class type, not on an instance. |
| `objectForFieldName:` | `- (nullable id)objectForFieldName:(NSString *)fieldName;` | Perform `object for field name` for `ALNORMModel`. | Capture the returned value and propagate errors/validation as needed. |
| `objectForPropertyName:` | `- (nullable id)objectForPropertyName:(NSString *)propertyName;` | Perform `object for property name` for `ALNORMModel`. | Capture the returned value and propagate errors/validation as needed. |
| `objectForColumnName:` | `- (nullable id)objectForColumnName:(NSString *)columnName;` | Perform `object for column name` for `ALNORMModel`. | Capture the returned value and propagate errors/validation as needed. |
| `setObject:forFieldName:error:` | `- (BOOL)setObject:(nullable id)value forFieldName:(NSString *)fieldName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `setObject:forPropertyName:error:` | `- (BOOL)setObject:(nullable id)value forPropertyName:(NSString *)propertyName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `applyRow:error:` | `- (BOOL)applyRow:(NSDictionary<NSString *, id> *)row error:(NSError *_Nullable *_Nullable)error;` | Apply this helper to context and update response state. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `markClean` | `- (void)markClean;` | Perform `mark clean` for `ALNORMModel`. | Call for side effects; this method does not return a value. |
| `markDetached` | `- (void)markDetached;` | Perform `mark detached` for `ALNORMModel`. | Call for side effects; this method does not return a value. |
| `setRelationObject:forRelationName:error:` | `- (BOOL)setRelationObject:(nullable id)value forRelationName:(NSString *)relationName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `relationObjectForName:` | `- (nullable id)relationObjectForName:(NSString *)relationName;` | Perform `relation object for name` for `ALNORMModel`. | Capture the returned value and propagate errors/validation as needed. |
| `primaryKeyValues` | `- (NSDictionary<NSString *, id> *)primaryKeyValues;` | Perform `primary key values` for `ALNORMModel`. | Read this value when you need current runtime/request state. |
| `changedFieldValues` | `- (NSDictionary<NSString *, id> *)changedFieldValues;` | Perform `changed field values` for `ALNORMModel`. | Read this value when you need current runtime/request state. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
