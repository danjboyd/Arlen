# ALNORMAdminResource

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMAdminResource.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `resourceName` | `NSString *` | `nonatomic, copy, readonly` | Public `resourceName` property available on `ALNORMAdminResource`. |
| `modelClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `modelClassName` property available on `ALNORMAdminResource`. |
| `entityName` | `NSString *` | `nonatomic, copy, readonly` | Public `entityName` property available on `ALNORMAdminResource`. |
| `titleFieldName` | `NSString *` | `nonatomic, copy, readonly` | Public `titleFieldName` property available on `ALNORMAdminResource`. |
| `searchableFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `searchableFieldNames` property available on `ALNORMAdminResource`. |
| `sortableFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `sortableFieldNames` property available on `ALNORMAdminResource`. |
| `readOnly` | `BOOL` | `nonatomic, assign, readonly, getter=isReadOnly` | Public `readOnly` property available on `ALNORMAdminResource`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMAdminResource` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `resourceForModelClass:` | `+ (nullable instancetype)resourceForModelClass:(Class)modelClass;` | Perform `resource for model class` for `ALNORMAdminResource`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithResourceName:modelClassName:entityName:titleFieldName:searchableFieldNames:sortableFieldNames:readOnly:` | `- (instancetype)initWithResourceName:(NSString *)resourceName modelClassName:(NSString *)modelClassName entityName:(NSString *)entityName titleFieldName:(NSString *)titleFieldName searchableFieldNames:(NSArray<NSString *> *)searchableFieldNames sortableFieldNames:(NSArray<NSString *> *)sortableFieldNames readOnly:(BOOL)readOnly NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMAdminResource` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
