# ALNDataverseQuery

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDataverseQuery.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `entitySetName` | `NSString *` | `nonatomic, copy, readonly` | Public `entitySetName` property available on `ALNDataverseQuery`. |
| `selectFields` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `selectFields` property available on `ALNDataverseQuery`. |
| `predicate` | `id` | `nonatomic, strong, readonly, nullable` | Public `predicate` property available on `ALNDataverseQuery`. |
| `orderBy` | `id` | `nonatomic, strong, readonly, nullable` | Public `orderBy` property available on `ALNDataverseQuery`. |
| `top` | `NSNumber *` | `nonatomic, copy, readonly, nullable` | Public `top` property available on `ALNDataverseQuery`. |
| `skip` | `NSNumber *` | `nonatomic, copy, readonly, nullable` | Public `skip` property available on `ALNDataverseQuery`. |
| `expand` | `NSDictionary<NSString *, id> *` | `nonatomic, copy, readonly, nullable` | Public `expand` property available on `ALNDataverseQuery`. |
| `includeCount` | `BOOL` | `nonatomic, assign, readonly` | Public `includeCount` property available on `ALNDataverseQuery`. |
| `includeFormattedValues` | `BOOL` | `nonatomic, assign, readonly` | Public `includeFormattedValues` property available on `ALNDataverseQuery`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `queryWithEntitySetName:error:` | `+ (nullable instancetype)queryWithEntitySetName:(NSString *)entitySetName error:(NSError *_Nullable *_Nullable)error;` | Perform `query with entity set name` for `ALNDataverseQuery`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `filterStringFromPredicate:error:` | `+ (nullable NSString *)filterStringFromPredicate:(nullable id)predicate error:(NSError *_Nullable *_Nullable)error;` | Perform `filter string from predicate` for `ALNDataverseQuery`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `orderByStringFromSpec:error:` | `+ (nullable NSString *)orderByStringFromSpec:(nullable id)orderBy error:(NSError *_Nullable *_Nullable)error;` | Perform `order by string from spec` for `ALNDataverseQuery`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `expandStringFromSpec:error:` | `+ (nullable NSString *)expandStringFromSpec:(nullable NSDictionary<NSString *, id> *)expand error:(NSError *_Nullable *_Nullable)error;` | Perform `expand string from spec` for `ALNDataverseQuery`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `queryParametersWithSelectFields:where:orderBy:top:skip:countFlag:expand:error:` | `+ (nullable NSDictionary<NSString *, NSString *> *)queryParametersWithSelectFields: (nullable NSArray<NSString *> *)selectFields where:(nullable id)predicate orderBy:(nullable id)orderBy top:(nullable NSNumber *)top skip:(nullable NSNumber *)skip countFlag:(BOOL)countFlag expand:(nullable NSDictionary<NSString *, id> *)expand error:(NSError *_Nullable *_Nullable)error;` | Perform `query parameters with select fields` for `ALNDataverseQuery`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNDataverseQuery` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithEntitySetName:error:` | `- (nullable instancetype)initWithEntitySetName:(NSString *)entitySetName error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNDataverseQuery` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `queryBySettingSelectFields:` | `- (ALNDataverseQuery *)queryBySettingSelectFields:(nullable NSArray<NSString *> *)selectFields;` | Perform `query by setting select fields` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingPredicate:` | `- (ALNDataverseQuery *)queryBySettingPredicate:(nullable id)predicate;` | Perform `query by setting predicate` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingOrderBy:` | `- (ALNDataverseQuery *)queryBySettingOrderBy:(nullable id)orderBy;` | Perform `query by setting order by` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingTop:` | `- (ALNDataverseQuery *)queryBySettingTop:(nullable NSNumber *)top;` | Perform `query by setting top` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingSkip:` | `- (ALNDataverseQuery *)queryBySettingSkip:(nullable NSNumber *)skip;` | Perform `query by setting skip` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingExpand:` | `- (ALNDataverseQuery *)queryBySettingExpand:(nullable NSDictionary<NSString *, id> *)expand;` | Perform `query by setting expand` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingIncludeCount:` | `- (ALNDataverseQuery *)queryBySettingIncludeCount:(BOOL)includeCount;` | Perform `query by setting include count` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryBySettingIncludeFormattedValues:` | `- (ALNDataverseQuery *)queryBySettingIncludeFormattedValues:(BOOL)includeFormattedValues;` | Perform `query by setting include formatted values` for `ALNDataverseQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `queryParameters:` | `- (nullable NSDictionary<NSString *, NSString *> *)queryParameters:(NSError *_Nullable *_Nullable)error;` | Perform `query parameters` for `ALNDataverseQuery`. | Treat returned collection values as snapshots unless the API documents mutability. |
