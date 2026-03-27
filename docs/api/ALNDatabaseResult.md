# ALNDatabaseResult

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDatabaseAdapter.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `rows` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `rows` property available on `ALNDatabaseResult`. |
| `count` | `NSUInteger` | `nonatomic, assign, readonly` | Public `count` property available on `ALNDatabaseResult`. |
| `columns` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `columns` property available on `ALNDatabaseResult`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `resultWithRows:` | `+ (instancetype)resultWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows;` | Perform `result with rows` for `ALNDatabaseResult`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `resultWithRows:orderedColumns:orderedValues:` | `+ (instancetype)resultWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows orderedColumns:(nullable NSArray<NSString *> *)orderedColumns orderedValues:(nullable NSArray<NSArray *> *)orderedValues;` | Perform `result with rows` for `ALNDatabaseResult`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDatabaseResult` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithRows:` | `- (instancetype)initWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows;` | Initialize and return a new `ALNDatabaseResult` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithRows:orderedColumns:orderedValues:` | `- (instancetype)initWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows orderedColumns:(nullable NSArray<NSString *> *)orderedColumns orderedValues:(nullable NSArray<NSArray *> *)orderedValues NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDatabaseResult` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `first` | `- (nullable ALNDatabaseRow *)first;` | Perform `first` for `ALNDatabaseResult`. | Read this value when you need current runtime/request state. |
| `rowAtIndex:` | `- (nullable ALNDatabaseRow *)rowAtIndex:(NSUInteger)index;` | Perform `row at index` for `ALNDatabaseResult`. | Capture the returned value and propagate errors/validation as needed. |
| `one:` | `- (nullable ALNDatabaseRow *)one:(NSError *_Nullable *_Nullable)error;` | Perform `one` for `ALNDatabaseResult`. | Capture the returned value and propagate errors/validation as needed. |
| `oneOrNil:` | `- (nullable ALNDatabaseRow *)oneOrNil:(NSError *_Nullable *_Nullable)error;` | Perform `one or nil` for `ALNDatabaseResult`. | Capture the returned value and propagate errors/validation as needed. |
| `scalarValueForColumn:error:` | `- (nullable id)scalarValueForColumn:(nullable NSString *)columnName error:(NSError *_Nullable *_Nullable)error;` | Perform `scalar value for column` for `ALNDatabaseResult`. | Pass `NSError **` and treat a `nil` result as failure. |
