# ALNDatabaseArrayValue

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `items` | `NSArray *` | `nonatomic, copy, readonly` | Public `items` property available on `ALNDatabaseArrayValue`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `valueWithItems:` | `+ (instancetype)valueWithItems:(nullable NSArray *)items;` | Perform `value with items` for `ALNDatabaseArrayValue`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDatabaseArrayValue` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithItems:` | `- (instancetype)initWithItems:(nullable NSArray *)items NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDatabaseArrayValue` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
