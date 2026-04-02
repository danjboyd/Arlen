# ALNORMChangeset

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMChangeset.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `descriptor` | `ALNORMModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMChangeset`. |
| `model` | `ALNORMModel *` | `nonatomic, weak, readonly` | Public `model` property available on `ALNORMChangeset`. |
| `values` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `values` property available on `ALNORMChangeset`. |
| `fieldErrors` | `NSDictionary<NSString *, NSArray<NSString *> *> *` | `nonatomic, copy, readonly` | Public `fieldErrors` property available on `ALNORMChangeset`. |
| `fieldConverters` | `NSDictionary<NSString *, ALNORMValueConverter *> *` | `nonatomic, copy, readonly` | Public `fieldConverters` property available on `ALNORMChangeset`. |
| `requiredFieldNames` | `NSSet<NSString *> *` | `nonatomic, copy, readonly` | Public `requiredFieldNames` property available on `ALNORMChangeset`. |
| `nestedChangesets` | `NSDictionary<NSString *, ALNORMChangeset *> *` | `nonatomic, copy, readonly` | Public `nestedChangesets` property available on `ALNORMChangeset`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `changesetWithModel:` | `+ (instancetype)changesetWithModel:(ALNORMModel *)model;` | Perform `changeset with model` for `ALNORMChangeset`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDescriptor:model:` | `- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor model:(nullable ALNORMModel *)model;` | Initialize and return a new `ALNORMChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDescriptor:model:fieldConverters:requiredFieldNames:` | `- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor model:(nullable ALNORMModel *)model fieldConverters:(nullable NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters requiredFieldNames:(nullable NSArray<NSString *> *)requiredFieldNames NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `setObject:forFieldName:error:` | `- (BOOL)setObject:(nullable id)value forFieldName:(NSString *)fieldName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `castInputValue:forFieldName:error:` | `- (BOOL)castInputValue:(nullable id)value forFieldName:(NSString *)fieldName error:(NSError *_Nullable *_Nullable)error;` | Perform `cast input value` for `ALNORMChangeset`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `applyInputValues:error:` | `- (BOOL)applyInputValues:(NSDictionary<NSString *, id> *)values error:(NSError *_Nullable *_Nullable)error;` | Apply this helper to context and update response state. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `objectForFieldName:` | `- (nullable id)objectForFieldName:(NSString *)fieldName;` | Perform `object for field name` for `ALNORMChangeset`. | Capture the returned value and propagate errors/validation as needed. |
| `addError:forFieldName:` | `- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName;` | Add this item to the current runtime collection. | Call during bootstrap/setup before this behavior is exercised. |
| `validateRequiredFields` | `- (BOOL)validateRequiredFields;` | Perform `validate required fields` for `ALNORMChangeset`. | Check the return value to confirm the operation succeeded. |
| `validateFieldName:usingBlock:` | `- (BOOL)validateFieldName:(NSString *)fieldName usingBlock:(ALNORMFieldValidationBlock)validationBlock;` | Perform `validate field name` for `ALNORMChangeset`. | Check the return value to confirm the operation succeeded. |
| `setNestedChangeset:forRelationName:error:` | `- (BOOL)setNestedChangeset:(ALNORMChangeset *)changeset forRelationName:(NSString *)relationName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `nestedChangesetForRelationName:` | `- (nullable ALNORMChangeset *)nestedChangesetForRelationName:(NSString *)relationName;` | Perform `nested changeset for relation name` for `ALNORMChangeset`. | Capture the returned value and propagate errors/validation as needed. |
| `applyToModel:` | `- (BOOL)applyToModel:(NSError *_Nullable *_Nullable)error;` | Apply this helper to context and update response state. | Check the return value to confirm the operation succeeded. |
| `encodedValues:` | `- (nullable NSDictionary<NSString *, id> *)encodedValues:(NSError *_Nullable *_Nullable)error;` | Perform `encoded values` for `ALNORMChangeset`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `hasErrors` | `- (BOOL)hasErrors;` | Return whether `ALNORMChangeset` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `changedFieldNames` | `- (NSArray<NSString *> *)changedFieldNames;` | Perform `changed field names` for `ALNORMChangeset`. | Read this value when you need current runtime/request state. |
