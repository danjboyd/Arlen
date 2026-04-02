# ALNORMDataverseRelationDescriptor

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseRelationDescriptor.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `name` | `NSString *` | `nonatomic, copy, readonly` | Public `name` property available on `ALNORMDataverseRelationDescriptor`. |
| `currentEntityLogicalName` | `NSString *` | `nonatomic, copy, readonly` | Public `currentEntityLogicalName` property available on `ALNORMDataverseRelationDescriptor`. |
| `queryEntityLogicalName` | `NSString *` | `nonatomic, copy, readonly` | Public `queryEntityLogicalName` property available on `ALNORMDataverseRelationDescriptor`. |
| `queryEntitySetName` | `NSString *` | `nonatomic, copy, readonly` | Public `queryEntitySetName` property available on `ALNORMDataverseRelationDescriptor`. |
| `targetClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `targetClassName` property available on `ALNORMDataverseRelationDescriptor`. |
| `sourceValueFieldName` | `NSString *` | `nonatomic, copy, readonly` | Public `sourceValueFieldName` property available on `ALNORMDataverseRelationDescriptor`. |
| `queryFieldLogicalName` | `NSString *` | `nonatomic, copy, readonly` | Public `queryFieldLogicalName` property available on `ALNORMDataverseRelationDescriptor`. |
| `navigationPropertyName` | `NSString *` | `nonatomic, copy, readonly` | Public `navigationPropertyName` property available on `ALNORMDataverseRelationDescriptor`. |
| `collection` | `BOOL` | `nonatomic, assign, readonly, getter=isCollection` | Public `collection` property available on `ALNORMDataverseRelationDescriptor`. |
| `readOnly` | `BOOL` | `nonatomic, assign, readonly, getter=isReadOnly` | Public `readOnly` property available on `ALNORMDataverseRelationDescriptor`. |
| `inferred` | `BOOL` | `nonatomic, assign, readonly, getter=isInferred` | Public `inferred` property available on `ALNORMDataverseRelationDescriptor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMDataverseRelationDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithName:currentEntityLogicalName:queryEntityLogicalName:queryEntitySetName:targetClassName:sourceValueFieldName:queryFieldLogicalName:navigationPropertyName:collection:readOnly:inferred:` | `- (instancetype)initWithName:(NSString *)name currentEntityLogicalName:(NSString *)currentEntityLogicalName queryEntityLogicalName:(NSString *)queryEntityLogicalName queryEntitySetName:(NSString *)queryEntitySetName targetClassName:(NSString *)targetClassName sourceValueFieldName:(NSString *)sourceValueFieldName queryFieldLogicalName:(NSString *)queryFieldLogicalName navigationPropertyName:(NSString *)navigationPropertyName collection:(BOOL)collection readOnly:(BOOL)readOnly inferred:(BOOL)inferred NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseRelationDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
