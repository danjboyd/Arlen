# ALNDataverseChoiceValue

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseClient.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `numericValue` | `NSNumber *` | `nonatomic, copy, readonly` | Public `numericValue` property available on `ALNDataverseChoiceValue`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `valueWithIntegerValue:` | `+ (instancetype)valueWithIntegerValue:(NSNumber *)integerValue;` | Perform `value with integer value` for `ALNDataverseChoiceValue`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseChoiceValue` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithIntegerValue:` | `- (instancetype)initWithIntegerValue:(NSNumber *)integerValue NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseChoiceValue` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
