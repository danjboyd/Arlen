# ALNDatabaseRow

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `dictionaryRepresentation` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly` | Public `dictionaryRepresentation` property available on `ALNDatabaseRow`. |
| `columns` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `columns` property available on `ALNDatabaseRow`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `rowWithDictionary:` | `+ (instancetype)rowWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;` | Perform `row with dictionary` for `ALNDatabaseRow`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `rowWithDictionary:orderedColumns:orderedValues:` | `+ (instancetype)rowWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary orderedColumns:(nullable NSArray<NSString *> *)orderedColumns orderedValues:(nullable NSArray *)orderedValues;` | Perform `row with dictionary` for `ALNDatabaseRow`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDatabaseRow` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDictionary:` | `- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;` | Initialize and return a new `ALNDatabaseRow` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithDictionary:orderedColumns:orderedValues:` | `- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary orderedColumns:(nullable NSArray<NSString *> *)orderedColumns orderedValues:(nullable NSArray *)orderedValues NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDatabaseRow` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `objectForColumn:` | `- (nullable id)objectForColumn:(NSString *)columnName;` | Perform `object for column` for `ALNDatabaseRow`. | Capture the returned value and propagate errors/validation as needed. |
| `objectAtColumnIndex:` | `- (nullable id)objectAtColumnIndex:(NSUInteger)index;` | Perform `object at column index` for `ALNDatabaseRow`. | Capture the returned value and propagate errors/validation as needed. |
| `objectForKeyedSubscript:` | `- (nullable id)objectForKeyedSubscript:(NSString *)columnName;` | Perform `object for keyed subscript` for `ALNDatabaseRow`. | Capture the returned value and propagate errors/validation as needed. |
