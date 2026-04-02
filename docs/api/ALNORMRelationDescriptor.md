# ALNORMRelationDescriptor

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMRelationDescriptor.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `kind` | `ALNORMRelationKind` | `nonatomic, assign, readonly` | Public `kind` property available on `ALNORMRelationDescriptor`. |
| `name` | `NSString *` | `nonatomic, copy, readonly` | Public `name` property available on `ALNORMRelationDescriptor`. |
| `sourceEntityName` | `NSString *` | `nonatomic, copy, readonly` | Public `sourceEntityName` property available on `ALNORMRelationDescriptor`. |
| `targetEntityName` | `NSString *` | `nonatomic, copy, readonly` | Public `targetEntityName` property available on `ALNORMRelationDescriptor`. |
| `targetClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `targetClassName` property available on `ALNORMRelationDescriptor`. |
| `throughEntityName` | `NSString *` | `nonatomic, copy, readonly` | Public `throughEntityName` property available on `ALNORMRelationDescriptor`. |
| `throughClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `throughClassName` property available on `ALNORMRelationDescriptor`. |
| `sourceFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `sourceFieldNames` property available on `ALNORMRelationDescriptor`. |
| `targetFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `targetFieldNames` property available on `ALNORMRelationDescriptor`. |
| `throughSourceFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `throughSourceFieldNames` property available on `ALNORMRelationDescriptor`. |
| `throughTargetFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `throughTargetFieldNames` property available on `ALNORMRelationDescriptor`. |
| `pivotFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `pivotFieldNames` property available on `ALNORMRelationDescriptor`. |
| `readOnly` | `BOOL` | `nonatomic, assign, readonly, getter=isReadOnly` | Public `readOnly` property available on `ALNORMRelationDescriptor`. |
| `inferred` | `BOOL` | `nonatomic, assign, readonly, getter=isInferred` | Public `inferred` property available on `ALNORMRelationDescriptor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMRelationDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithKind:name:sourceEntityName:targetEntityName:targetClassName:throughEntityName:throughClassName:sourceFieldNames:targetFieldNames:throughSourceFieldNames:throughTargetFieldNames:pivotFieldNames:readOnly:inferred:` | `- (instancetype)initWithKind:(ALNORMRelationKind)kind name:(NSString *)name sourceEntityName:(NSString *)sourceEntityName targetEntityName:(NSString *)targetEntityName targetClassName:(NSString *)targetClassName throughEntityName:(nullable NSString *)throughEntityName throughClassName:(nullable NSString *)throughClassName sourceFieldNames:(NSArray<NSString *> *)sourceFieldNames targetFieldNames:(NSArray<NSString *> *)targetFieldNames throughSourceFieldNames:(nullable NSArray<NSString *> *)throughSourceFieldNames throughTargetFieldNames:(nullable NSArray<NSString *> *)throughTargetFieldNames pivotFieldNames:(nullable NSArray<NSString *> *)pivotFieldNames readOnly:(BOOL)readOnly inferred:(BOOL)inferred NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMRelationDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `kindName` | `- (NSString *)kindName;` | Perform `kind name` for `ALNORMRelationDescriptor`. | Read this value when you need current runtime/request state. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
