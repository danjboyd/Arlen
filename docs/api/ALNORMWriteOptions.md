# ALNORMWriteOptions

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMWriteOptions.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `optimisticLockFieldName` | `NSString *` | `nonatomic, copy` | Public `optimisticLockFieldName` property available on `ALNORMWriteOptions`. |
| `createdAtFieldName` | `NSString *` | `nonatomic, copy` | Public `createdAtFieldName` property available on `ALNORMWriteOptions`. |
| `updatedAtFieldName` | `NSString *` | `nonatomic, copy` | Public `updatedAtFieldName` property available on `ALNORMWriteOptions`. |
| `conflictFieldNames` | `NSArray<NSString *> *` | `nonatomic, copy` | Public `conflictFieldNames` property available on `ALNORMWriteOptions`. |
| `saveRelatedRelationNames` | `NSArray<NSString *> *` | `nonatomic, copy` | Public `saveRelatedRelationNames` property available on `ALNORMWriteOptions`. |
| `timestampValue` | `NSDate *` | `nonatomic, strong, nullable` | Public `timestampValue` property available on `ALNORMWriteOptions`. |
| `overwriteAllFields` | `BOOL` | `nonatomic, assign` | Public `overwriteAllFields` property available on `ALNORMWriteOptions`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `options` | `+ (instancetype)options;` | Perform `options` for `ALNORMWriteOptions`. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
