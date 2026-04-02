# ALNORMModelDescriptor

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMModelDescriptor.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `className` | `NSString *` | `nonatomic, copy, readonly` | Public `className` property available on `ALNORMModelDescriptor`. |
| `entityName` | `NSString *` | `nonatomic, copy, readonly` | Public `entityName` property available on `ALNORMModelDescriptor`. |
| `schemaName` | `NSString *` | `nonatomic, copy, readonly` | Public `schemaName` property available on `ALNORMModelDescriptor`. |
| `tableName` | `NSString *` | `nonatomic, copy, readonly` | Public `tableName` property available on `ALNORMModelDescriptor`. |
| `qualifiedTableName` | `NSString *` | `nonatomic, copy, readonly` | Public `qualifiedTableName` property available on `ALNORMModelDescriptor`. |
| `relationKind` | `NSString *` | `nonatomic, copy, readonly` | Public `relationKind` property available on `ALNORMModelDescriptor`. |
| `databaseTarget` | `NSString *` | `nonatomic, copy, readonly` | Public `databaseTarget` property available on `ALNORMModelDescriptor`. |
| `readOnly` | `BOOL` | `nonatomic, assign, readonly, getter=isReadOnly` | Public `readOnly` property available on `ALNORMModelDescriptor`. |
| `fields` | `NSArray<ALNORMFieldDescriptor *> *` | `nonatomic, copy, readonly` | Public `fields` property available on `ALNORMModelDescriptor`. |
| `primaryKeyFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `primaryKeyFieldNames` property available on `ALNORMModelDescriptor`. |
| `uniqueConstraintFieldSets` | `NSArray<NSArray<NSString *> *> *` | `nonatomic, copy, readonly` | Public `uniqueConstraintFieldSets` property available on `ALNORMModelDescriptor`. |
| `relations` | `NSArray<ALNORMRelationDescriptor *> *` | `nonatomic, copy, readonly` | Public `relations` property available on `ALNORMModelDescriptor`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Initialize and return a new `ALNORMModelDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `initWithClassName:entityName:schemaName:tableName:qualifiedTableName:relationKind:databaseTarget:readOnly:fields:primaryKeyFieldNames:uniqueConstraintFieldSets:relations:` | `- (instancetype)initWithClassName:(NSString *)className entityName:(NSString *)entityName schemaName:(NSString *)schemaName tableName:(NSString *)tableName qualifiedTableName:(NSString *)qualifiedTableName relationKind:(NSString *)relationKind databaseTarget:(nullable NSString *)databaseTarget readOnly:(BOOL)readOnly fields:(NSArray<ALNORMFieldDescriptor *> *)fields primaryKeyFieldNames:(NSArray<NSString *> *)primaryKeyFieldNames uniqueConstraintFieldSets:(NSArray<NSArray<NSString *> *> *)uniqueConstraintFieldSets relations:(nullable NSArray<ALNORMRelationDescriptor *> *)relations NS_DESIGNATED_INITIALIZER;` | Initialize and return a new `ALNORMModelDescriptor` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `fieldNamed:` | `- (nullable ALNORMFieldDescriptor *)fieldNamed:(NSString *)fieldName;` | Perform `field named` for `ALNORMModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `fieldForPropertyName:` | `- (nullable ALNORMFieldDescriptor *)fieldForPropertyName:(NSString *)propertyName;` | Perform `field for property name` for `ALNORMModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `fieldForColumnName:` | `- (nullable ALNORMFieldDescriptor *)fieldForColumnName:(NSString *)columnName;` | Perform `field for column name` for `ALNORMModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `relationNamed:` | `- (nullable ALNORMRelationDescriptor *)relationNamed:(NSString *)relationName;` | Perform `relation named` for `ALNORMModelDescriptor`. | Capture the returned value and propagate errors/validation as needed. |
| `allFieldNames` | `- (NSArray<NSString *> *)allFieldNames;` | Perform `all field names` for `ALNORMModelDescriptor`. | Read this value when you need current runtime/request state. |
| `allColumnNames` | `- (NSArray<NSString *> *)allColumnNames;` | Perform `all column names` for `ALNORMModelDescriptor`. | Read this value when you need current runtime/request state. |
| `allQualifiedColumnNames` | `- (NSArray<NSString *> *)allQualifiedColumnNames;` | Perform `all qualified column names` for `ALNORMModelDescriptor`. | Read this value when you need current runtime/request state. |
| `hasUniqueConstraintForFieldSet:` | `- (BOOL)hasUniqueConstraintForFieldSet:(NSArray<NSString *> *)fieldNames;` | Return whether `ALNORMModelDescriptor` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `dictionaryRepresentation` | `- (NSDictionary<NSString *, id> *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
