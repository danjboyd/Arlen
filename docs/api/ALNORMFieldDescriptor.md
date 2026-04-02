# ALNORMFieldDescriptor

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMFieldDescriptor.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `name` | `NSString *` | `nonatomic, copy, readonly` | Public `name` property available on `ALNORMFieldDescriptor`. |
| `propertyName` | `NSString *` | `nonatomic, copy, readonly` | Public `propertyName` property available on `ALNORMFieldDescriptor`. |
| `columnName` | `NSString *` | `nonatomic, copy, readonly` | Public `columnName` property available on `ALNORMFieldDescriptor`. |
| `dataType` | `NSString *` | `nonatomic, copy, readonly` | Public `dataType` property available on `ALNORMFieldDescriptor`. |
| `objcType` | `NSString *` | `nonatomic, copy, readonly` | Public `objcType` property available on `ALNORMFieldDescriptor`. |
| `runtimeClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `runtimeClassName` property available on `ALNORMFieldDescriptor`. |
| `propertyAttribute` | `NSString *` | `nonatomic, copy, readonly` | Public `propertyAttribute` property available on `ALNORMFieldDescriptor`. |
| `ordinal` | `NSInteger` | `nonatomic, assign, readonly` | Public `ordinal` property available on `ALNORMFieldDescriptor`. |
| `nullable` | `BOOL` | `nonatomic, assign, readonly, getter=isNullable` | Public `nullable` property available on `ALNORMFieldDescriptor`. |
| `primaryKey` | `BOOL` | `nonatomic, assign, readonly, getter=isPrimaryKey` | Public `primaryKey` property available on `ALNORMFieldDescriptor`. |
| `unique` | `BOOL` | `nonatomic, assign, readonly, getter=isUnique` | Public `unique` property available on `ALNORMFieldDescriptor`. |
| `hasDefault` | `BOOL` | `nonatomic, assign, readonly, getter=hasDefaultValue` | Public `hasDefault` property available on `ALNORMFieldDescriptor`. |
| `readOnly` | `BOOL` | `nonatomic, assign, readonly, getter=isReadOnly` | Public `readOnly` property available on `ALNORMFieldDescriptor`. |
| `defaultValueShape` | `NSString *` | `nonatomic, copy, readonly` | Public `defaultValueShape` property available on `ALNORMFieldDescriptor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMFieldDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithName:propertyName:columnName:dataType:objcType:runtimeClassName:propertyAttribute:ordinal:nullable:primaryKey:unique:hasDefault:readOnly:defaultValueShape:` | `- (instancetype)initWithName:(NSString *)name propertyName:(NSString *)propertyName columnName:(NSString *)columnName dataType:(NSString *)dataType objcType:(NSString *)objcType runtimeClassName:(nullable NSString *)runtimeClassName propertyAttribute:(NSString *)propertyAttribute ordinal:(NSInteger)ordinal nullable:(BOOL)nullable primaryKey:(BOOL)primaryKey unique:(BOOL)unique hasDefault:(BOOL)hasDefault readOnly:(BOOL)readOnly defaultValueShape:(NSString *)defaultValueShape NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMFieldDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
