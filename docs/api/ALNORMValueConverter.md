# ALNORMValueConverter

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMValueConverter.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `decodeBlock` | `ALNORMValueConversionBlock` | `nonatomic, copy, readonly` | Public `decodeBlock` property available on `ALNORMValueConverter`. |
| `encodeBlock` | `ALNORMValueConversionBlock` | `nonatomic, copy, readonly` | Public `encodeBlock` property available on `ALNORMValueConverter`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `converterWithDecodeBlock:encodeBlock:` | `+ (instancetype)converterWithDecodeBlock:(ALNORMValueConversionBlock)decodeBlock encodeBlock:(ALNORMValueConversionBlock)encodeBlock;` | Perform `converter with decode block` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `passthroughConverter` | `+ (instancetype)passthroughConverter;` | Perform `passthrough converter` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `stringConverter` | `+ (instancetype)stringConverter;` | Perform `string converter` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `numberConverter` | `+ (instancetype)numberConverter;` | Perform `number converter` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `integerConverter` | `+ (instancetype)integerConverter;` | Perform `integer converter` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `ISO8601DateTimeConverter` | `+ (instancetype)ISO8601DateTimeConverter;` | Return whether `ALNORMValueConverter` currently satisfies this condition. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `JSONConverter` | `+ (instancetype)JSONConverter;` | Perform `json converter` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `arrayConverter` | `+ (instancetype)arrayConverter;` | Perform `array converter` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `enumConverterWithAllowedValues:` | `+ (instancetype)enumConverterWithAllowedValues:(NSArray<NSString *> *)allowedValues;` | Perform `enum converter with allowed values` for `ALNORMValueConverter`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMValueConverter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDecodeBlock:encodeBlock:` | `- (instancetype)initWithDecodeBlock:(ALNORMValueConversionBlock)decodeBlock encodeBlock:(ALNORMValueConversionBlock)encodeBlock NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMValueConverter` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `decodeValue:error:` | `- (nullable id)decodeValue:(nullable id)value error:(NSError *_Nullable *_Nullable)error;` | Perform `decode value` for `ALNORMValueConverter`. | Pass `NSError **` and treat a `nil` result as failure. |
| `encodeValue:error:` | `- (nullable id)encodeValue:(nullable id)value error:(NSError *_Nullable *_Nullable)error;` | Perform `encode value` for `ALNORMValueConverter`. | Pass `NSError **` and treat a `nil` result as failure. |
