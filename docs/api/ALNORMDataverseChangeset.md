# ALNORMDataverseChangeset

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseChangeset.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `descriptor` | `ALNORMDataverseModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMDataverseChangeset`. |
| `model` | `ALNORMDataverseModel *` | `nonatomic, weak, readonly, nullable` | Public `model` property available on `ALNORMDataverseChangeset`. |
| `values` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `values` property available on `ALNORMDataverseChangeset`. |
| `fieldErrors` | `NSDictionary<NSString *, NSArray<NSString *> *> *` | `nonatomic, copy, readonly` | Public `fieldErrors` property available on `ALNORMDataverseChangeset`. |
| `fieldConverters` | `NSDictionary<NSString *, ALNORMValueConverter *> *` | `nonatomic, copy, readonly` | Public `fieldConverters` property available on `ALNORMDataverseChangeset`. |
| `requiredFieldNames` | `NSSet<NSString *> *` | `nonatomic, copy, readonly` | Public `requiredFieldNames` property available on `ALNORMDataverseChangeset`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMDataverseChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `changesetWithModel:` | `+ (instancetype)changesetWithModel:(ALNORMDataverseModel *)model;` | Perform `changeset with model` for `ALNORMDataverseChangeset`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDescriptor:model:fieldConverters:requiredFieldNames:` | `- (instancetype)initWithDescriptor:(ALNORMDataverseModelDescriptor *)descriptor model:(nullable ALNORMDataverseModel *)model fieldConverters:(nullable NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters requiredFieldNames:(nullable NSArray<NSString *> *)requiredFieldNames NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `castInputValue:forFieldName:error:` | `- (BOOL)castInputValue:(nullable id)value forFieldName:(NSString *)fieldName error:(NSError *_Nullable *_Nullable)error;` | Perform `cast input value` for `ALNORMDataverseChangeset`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `applyInputValues:error:` | `- (BOOL)applyInputValues:(NSDictionary<NSString *, id> *)values error:(NSError *_Nullable *_Nullable)error;` | Apply this helper to context and update response state. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `addError:forFieldName:` | `- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName;` | Add this item to the current runtime collection. | Call during bootstrap/setup before this behavior is exercised. |
| `validateRequiredFields` | `- (BOOL)validateRequiredFields;` | Perform `validate required fields` for `ALNORMDataverseChangeset`. | Check the return value to confirm the operation succeeded. |
| `applyToModel:` | `- (BOOL)applyToModel:(NSError *_Nullable *_Nullable)error;` | Apply this helper to context and update response state. | Check the return value to confirm the operation succeeded. |
| `encodedValues:` | `- (nullable NSDictionary<NSString *, id> *)encodedValues:(NSError *_Nullable *_Nullable)error;` | Perform `encoded values` for `ALNORMDataverseChangeset`. | Treat returned collection values as snapshots unless the API documents mutability. |
| `hasErrors` | `- (BOOL)hasErrors;` | Return whether `ALNORMDataverseChangeset` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `changedFieldNames` | `- (NSArray<NSString *> *)changedFieldNames;` | Perform `changed field names` for `ALNORMDataverseChangeset`. | Read this value when you need current runtime/request state. |
