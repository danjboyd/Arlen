# ALNORMDataverseCodegen

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMDataverseCodegen.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `modelDescriptorsFromMetadata:classPrefix:dataverseTarget:error:` | `+ (nullable NSArray<ALNORMDataverseModelDescriptor *> *)modelDescriptorsFromMetadata: (NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix dataverseTarget:(nullable NSString *)dataverseTarget error: (NSError *_Nullable *_Nullable)error;` | Perform `model descriptors from metadata` for `ALNORMDataverseCodegen`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
