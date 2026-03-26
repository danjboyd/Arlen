# ALNDatabaseJSONValue

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `object` | `id` | `nonatomic, strong, readonly` | Public `object` property available on `ALNDatabaseJSONValue`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `valueWithObject:` | `+ (instancetype)valueWithObject:(nullable id)object;` | Perform `value with object` for `ALNDatabaseJSONValue`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDatabaseJSONValue` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithObject:` | `- (instancetype)initWithObject:(nullable id)object NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDatabaseJSONValue` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
