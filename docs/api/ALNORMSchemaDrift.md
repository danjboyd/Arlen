# ALNORMSchemaDrift

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMSchemaDrift.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `diagnosticsByComparingSnapshotDocument:toModelDescriptors:` | `+ (NSArray<NSDictionary<NSString *, id> *> *)diagnosticsByComparingSnapshotDocument: (NSDictionary<NSString *, id> *)snapshotDocument toModelDescriptors: (NSArray<ALNORMModelDescriptor *> *)descriptors;` | Perform `diagnostics by comparing snapshot document` for `ALNORMSchemaDrift`. | Call on the class type, not on an instance. |
| `validateModelDescriptors:againstSnapshotDocument:diagnostics:error:` | `+ (BOOL)validateModelDescriptors:(NSArray<ALNORMModelDescriptor *> *)descriptors againstSnapshotDocument:(NSDictionary<NSString *, id> *)snapshotDocument diagnostics:(NSArray<NSDictionary<NSString *, id> *> *_Nullable *_Nullable)diagnostics error:(NSError *_Nullable *_Nullable)error;` | Perform `validate model descriptors` for `ALNORMSchemaDrift`. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
