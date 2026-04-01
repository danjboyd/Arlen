# ALNORMDataverseFieldDescriptor

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseFieldDescriptor.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `logicalName` | `NSString *` | `nonatomic, copy, readonly` | Public `logicalName` property available on `ALNORMDataverseFieldDescriptor`. |
| `schemaName` | `NSString *` | `nonatomic, copy, readonly` | Public `schemaName` property available on `ALNORMDataverseFieldDescriptor`. |
| `displayName` | `NSString *` | `nonatomic, copy, readonly` | Public `displayName` property available on `ALNORMDataverseFieldDescriptor`. |
| `attributeType` | `NSString *` | `nonatomic, copy, readonly` | Public `attributeType` property available on `ALNORMDataverseFieldDescriptor`. |
| `readKey` | `NSString *` | `nonatomic, copy, readonly` | Public `readKey` property available on `ALNORMDataverseFieldDescriptor`. |
| `objcType` | `NSString *` | `nonatomic, copy, readonly` | Public `objcType` property available on `ALNORMDataverseFieldDescriptor`. |
| `runtimeClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `runtimeClassName` property available on `ALNORMDataverseFieldDescriptor`. |
| `nullable` | `BOOL` | `nonatomic, assign, readonly, getter=isNullable` | Public `nullable` property available on `ALNORMDataverseFieldDescriptor`. |
| `primaryID` | `BOOL` | `nonatomic, assign, readonly, getter=isPrimaryID` | Public `primaryID` property available on `ALNORMDataverseFieldDescriptor`. |
| `primaryName` | `BOOL` | `nonatomic, assign, readonly, getter=isPrimaryName` | Public `primaryName` property available on `ALNORMDataverseFieldDescriptor`. |
| `logical` | `BOOL` | `nonatomic, assign, readonly, getter=isLogical` | Public `logical` property available on `ALNORMDataverseFieldDescriptor`. |
| `readable` | `BOOL` | `nonatomic, assign, readonly, getter=isReadable` | Public `readable` property available on `ALNORMDataverseFieldDescriptor`. |
| `creatable` | `BOOL` | `nonatomic, assign, readonly, getter=isCreatable` | Public `creatable` property available on `ALNORMDataverseFieldDescriptor`. |
| `updateable` | `BOOL` | `nonatomic, assign, readonly, getter=isUpdateable` | Public `updateable` property available on `ALNORMDataverseFieldDescriptor`. |
| `targets` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `targets` property available on `ALNORMDataverseFieldDescriptor`. |
| `choices` | `NSArray<NSDictionary<NSString *, id> *> *` | `nonatomic, copy, readonly` | Public `choices` property available on `ALNORMDataverseFieldDescriptor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMDataverseFieldDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithLogicalName:schemaName:displayName:attributeType:readKey:objcType:runtimeClassName:nullable:primaryID:primaryName:logical:readable:creatable:updateable:targets:choices:` | `- (instancetype)initWithLogicalName:(NSString *)logicalName schemaName:(NSString *)schemaName displayName:(NSString *)displayName attributeType:(NSString *)attributeType readKey:(NSString *)readKey objcType:(NSString *)objcType runtimeClassName:(NSString *)runtimeClassName nullable:(BOOL)nullable primaryID:(BOOL)primaryID primaryName:(BOOL)primaryName logical:(BOOL)logical readable:(BOOL)readable creatable:(BOOL)creatable updateable:(BOOL)updateable targets:(nullable NSArray<NSString *> *)targets choices:(nullable NSArray<NSDictionary<NSString *, id> *> *)choices NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMDataverseFieldDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `isLookup` | `- (BOOL)isLookup;` | Return whether `ALNORMDataverseFieldDescriptor` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
