# ALNORMDataverseModelClass

- Kind: `protocol`
- Header: `src/Arlen/ORM/ALNORMDataverseModel.h`

Protocol contract exported as part of the `ALNORMDataverseModelClass` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `dataverseModelDescriptor` | `+ (nullable ALNORMDataverseModelDescriptor *)dataverseModelDescriptor;` | Perform `dataverse model descriptor` for `ALNORMDataverseModelClass`. | Call on the class type, not on an instance. |
| `modelFromRecord:error:` | `+ (nullable instancetype)modelFromRecord:(ALNDataverseRecord *)record error:(NSError *_Nullable *_Nullable)error;` | Perform `model from record` for `ALNORMDataverseModelClass`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
