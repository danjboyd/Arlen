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

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDescriptor:model:` | `- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor model:(nullable ALNORMModel *)model NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMChangeset` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `setObject:forFieldName:error:` | `- (BOOL)setObject:(nullable id)value forFieldName:(NSString *)fieldName error:(NSError *_Nullable *_Nullable)error;` | Set or override the current value for this concern. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `objectForFieldName:` | `- (nullable id)objectForFieldName:(NSString *)fieldName;` | Perform `object for field name` for `ALNORMChangeset`. | Capture the returned value and propagate errors/validation as needed. |
| `addError:forFieldName:` | `- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName;` | Add this item to the current runtime collection. | Call during bootstrap/setup before this behavior is exercised. |
| `hasErrors` | `- (BOOL)hasErrors;` | Return whether `ALNORMChangeset` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `changedFieldNames` | `- (NSArray<NSString *> *)changedFieldNames;` | Perform `changed field names` for `ALNORMChangeset`. | Read this value when you need current runtime/request state. |
