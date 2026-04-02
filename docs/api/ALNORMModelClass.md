# ALNORMModelClass

- Kind: `protocol`
- Header: `src/Arlen/ORM/ALNORMModel.h`

Protocol contract exported as part of the `ALNORMModelClass` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `modelDescriptor` | `+ (nullable ALNORMModelDescriptor *)modelDescriptor;` | Perform `model descriptor` for `ALNORMModelClass`. | Call on the class type, not on an instance. |
| `modelFromRow:error:` | `+ (nullable instancetype)modelFromRow:(NSDictionary<NSString *, id> *)row error:(NSError *_Nullable *_Nullable)error;` | Perform `model from row` for `ALNORMModelClass`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
