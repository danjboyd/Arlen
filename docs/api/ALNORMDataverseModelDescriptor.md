# ALNORMDataverseModelDescriptor

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseModelDescriptor.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `className` | `NSString *` | `nonatomic, copy, readonly` | Public `className` property available on `ALNORMDataverseModelDescriptor`. |
| `logicalName` | `NSString *` | `nonatomic, copy, readonly` | Public `logicalName` property available on `ALNORMDataverseModelDescriptor`. |
| `entitySetName` | `NSString *` | `nonatomic, copy, readonly` | Public `entitySetName` property available on `ALNORMDataverseModelDescriptor`. |
| `primaryIDAttribute` | `NSString *` | `nonatomic, copy, readonly` | Public `primaryIDAttribute` property available on `ALNORMDataverseModelDescriptor`. |
| `primaryNameAttribute` | `NSString *` | `nonatomic, copy, readonly` | Public `primaryNameAttribute` property available on `ALNORMDataverseModelDescriptor`. |
| `dataverseTarget` | `NSString *` | `nonatomic, copy, readonly` | Public `dataverseTarget` property available on `ALNORMDataverseModelDescriptor`. |
| `readOnly` | `BOOL` | `nonatomic, assign, readonly, getter=isReadOnly` | Public `readOnly` property available on `ALNORMDataverseModelDescriptor`. |
| `fields` | `NSArray<ALNORMDataverseFieldDescriptor *> *` | `nonatomic, copy, readonly` | Public `fields` property available on `ALNORMDataverseModelDescriptor`. |
| `alternateKeyFieldSets` | `NSArray<NSArray<NSString *> *> *` | `nonatomic, copy, readonly` | Public `alternateKeyFieldSets` property available on `ALNORMDataverseModelDescriptor`. |
| `relations` | `NSArray<ALNORMDataverseRelationDescriptor *> *` | `nonatomic, copy, readonly` | Public `relations` property available on `ALNORMDataverseModelDescriptor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMDataverseModelDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithClassName:logicalName:entitySetName:primaryIDAttribute:primaryNameAttribute:dataverseTarget:readOnly:fields:alternateKeyFieldSets:relations:` | `- (instancetype)initWithClassName:(NSString *)className logicalName:(NSString *)logicalName entitySetName:(NSString *)entitySetName primaryIDAttribute:(NSString *)primaryIDAttribute primaryNameAttribute:(NSString *)primaryNameAttribute dataverseTarget:(nullable NSString *)dataverseTarget readOnly:(BOOL)readOnly fields:(NSArray<ALNORMDataverseFieldDescriptor *> *)fields alternateKeyFieldSets:(nullable NSArray<NSArray<NSString *> *> *)alternateKeyFieldSets relations:(nullable NSArray<ALNORMDataverseRelationDescriptor *> *)relations NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseModelDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `fieldNamed:` | `- (nullable ALNORMDataverseFieldDescriptor *)fieldNamed:(NSString *)fieldName;` | Perform `field named` for `ALNORMDataverseModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `fieldForReadKey:` | `- (nullable ALNORMDataverseFieldDescriptor *)fieldForReadKey:(NSString *)readKey;` | Perform `field for read key` for `ALNORMDataverseModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `relationNamed:` | `- (nullable ALNORMDataverseRelationDescriptor *)relationNamed:(NSString *)relationName;` | Perform `relation named` for `ALNORMDataverseModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
