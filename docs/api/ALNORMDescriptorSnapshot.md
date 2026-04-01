# ALNORMDescriptorSnapshot

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDescriptorSnapshot.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `formatVersion` | `+ (NSString *)formatVersion;` | Perform `format version` for `ALNORMDescriptorSnapshot`. | Call on the class type, not on an instance. |
| `snapshotDocumentWithModelDescriptors:databaseTarget:label:` | `+ (NSDictionary<NSString *, id> *)snapshotDocumentWithModelDescriptors: (NSArray<ALNORMModelDescriptor *> *)descriptors databaseTarget:(nullable NSString *)databaseTarget label:(nullable NSString *)label;` | Return a point-in-time snapshot of current runtime state. | Call on the class type, not on an instance. |
| `modelDescriptorsFromSnapshotDocument:error:` | `+ (nullable NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSnapshotDocument: (NSDictionary<NSString *, id> *)document error: (NSError *_Nullable *_Nullable)error;` | Perform `model descriptors from snapshot document` for `ALNORMDescriptorSnapshot`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
