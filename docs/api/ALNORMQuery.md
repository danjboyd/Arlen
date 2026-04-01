# ALNORMQuery

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMQuery.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `modelClass` | `Class` | `nonatomic, assign, readonly` | Public `modelClass` property available on `ALNORMQuery`. |
| `descriptor` | `ALNORMModelDescriptor *` | `nonatomic, strong, readonly` | Public `descriptor` property available on `ALNORMQuery`. |
| `selectedFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `selectedFieldNames` property available on `ALNORMQuery`. |
| `joins` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `joins` property available on `ALNORMQuery`. |
| `predicates` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `predicates` property available on `ALNORMQuery`. |
| `orderings` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `orderings` property available on `ALNORMQuery`. |
| `hasLimit` | `BOOL` | `nonatomic, assign, readonly` | Public `hasLimit` property available on `ALNORMQuery`. |
| `limitValue` | `NSUInteger` | `nonatomic, assign, readonly` | Public `limitValue` property available on `ALNORMQuery`. |
| `hasOffset` | `BOOL` | `nonatomic, assign, readonly` | Public `hasOffset` property available on `ALNORMQuery`. |
| `offsetValue` | `NSUInteger` | `nonatomic, assign, readonly` | Public `offsetValue` property available on `ALNORMQuery`. |
| `relationLoadStrategies` | `NSDictionary<NSString *, NSNumber *> *` | `nonatomic, copy, readonly` | Public `relationLoadStrategies` property available on `ALNORMQuery`. |
| `strictLoadingEnabled` | `BOOL` | `nonatomic, assign, readonly, getter=isStrictLoadingEnabled` | Public `strictLoadingEnabled` property available on `ALNORMQuery`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `queryWithModelClass:` | `+ (nullable instancetype)queryWithModelClass:(Class)modelClass;` | Perform `query with model class` for `ALNORMQuery`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMQuery` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithModelClass:descriptor:` | `- (instancetype)initWithModelClass:(Class)modelClass descriptor:(ALNORMModelDescriptor *)descriptor NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMQuery` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `selectFields:` | `- (ALNORMQuery *)selectFields:(nullable NSArray<NSString *> *)fieldNames;` | Perform `select fields` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `selectProperties:` | `- (ALNORMQuery *)selectProperties:(nullable NSArray<NSString *> *)propertyNames;` | Perform `select properties` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereField:equals:` | `- (ALNORMQuery *)whereField:(NSString *)fieldName equals:(nullable id)value;` | Perform `where field` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereField:operator:value:` | `- (ALNORMQuery *)whereField:(NSString *)fieldName operator:(NSString *)operatorName value:(nullable id)value;` | Perform `where field` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereFieldIn:values:` | `- (ALNORMQuery *)whereFieldIn:(NSString *)fieldName values:(NSArray *)values;` | Perform `where field in` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereFieldNotIn:values:` | `- (ALNORMQuery *)whereFieldNotIn:(NSString *)fieldName values:(NSArray *)values;` | Perform `where field not in` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereQualifiedField:operator:value:` | `- (ALNORMQuery *)whereQualifiedField:(NSString *)qualifiedField operator:(NSString *)operatorName value:(nullable id)value;` | Perform `where qualified field` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereExpression:parameters:` | `- (ALNORMQuery *)whereExpression:(NSString *)expression parameters:(nullable NSArray *)parameters;` | Perform `where expression` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `whereField:inSubquery:` | `- (ALNORMQuery *)whereField:(NSString *)fieldName inSubquery:(ALNSQLBuilder *)subquery;` | Perform `where field` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `joinTable:onLeftField:operator:onRightField:` | `- (ALNORMQuery *)joinTable:(NSString *)tableName onLeftField:(NSString *)leftField operator:(NSString *)operatorName onRightField:(NSString *)rightField;` | Perform `join table` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `orderByField:descending:` | `- (ALNORMQuery *)orderByField:(NSString *)fieldName descending:(BOOL)descending;` | Perform `order by field` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `limit:` | `- (ALNORMQuery *)limit:(NSUInteger)limit;` | Perform `limit` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `offset:` | `- (ALNORMQuery *)offset:(NSUInteger)offset;` | Perform `offset` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `applyScope:` | `- (ALNORMQuery *)applyScope:(nullable ALNORMQueryScope)scope;` | Apply this helper to context and update response state. | Capture the returned value and propagate errors/validation as needed. |
| `withRelationNamed:loadStrategy:` | `- (ALNORMQuery *)withRelationNamed:(NSString *)relationName loadStrategy:(ALNORMRelationLoadStrategy)loadStrategy;` | Run a scoped callback with managed lifecycle semantics. | Capture the returned value and propagate errors/validation as needed. |
| `withJoinedRelationNamed:` | `- (ALNORMQuery *)withJoinedRelationNamed:(NSString *)relationName;` | Run a scoped callback with managed lifecycle semantics. | Capture the returned value and propagate errors/validation as needed. |
| `withSelectInRelationNamed:` | `- (ALNORMQuery *)withSelectInRelationNamed:(NSString *)relationName;` | Run a scoped callback with managed lifecycle semantics. | Capture the returned value and propagate errors/validation as needed. |
| `withNoLoadRelationNamed:` | `- (ALNORMQuery *)withNoLoadRelationNamed:(NSString *)relationName;` | Run a scoped callback with managed lifecycle semantics. | Capture the returned value and propagate errors/validation as needed. |
| `withRaiseOnAccessRelationNamed:` | `- (ALNORMQuery *)withRaiseOnAccessRelationNamed:(NSString *)relationName;` | Run a scoped callback with managed lifecycle semantics. | Capture the returned value and propagate errors/validation as needed. |
| `strictLoading:` | `- (ALNORMQuery *)strictLoading:(BOOL)enabled;` | Perform `strict loading` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
| `loadStrategyForRelationNamed:` | `- (ALNORMRelationLoadStrategy)loadStrategyForRelationNamed:(NSString *)relationName;` | Load and normalize configuration data. | Capture the returned value and propagate errors/validation as needed. |
| `selectBuilder:` | `- (nullable ALNSQLBuilder *)selectBuilder:(NSError *_Nullable *_Nullable)error;` | Perform `select builder` for `ALNORMQuery`. | Capture the returned value and propagate errors/validation as needed. |
