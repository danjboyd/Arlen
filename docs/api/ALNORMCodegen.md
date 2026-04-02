# ALNORMCodegen

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMCodegen.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `modelDescriptorsFromSchemaMetadata:classPrefix:error:` | `+ (nullable NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix error:(NSError *_Nullable *_Nullable)error;` | Perform `model descriptors from schema metadata` for `ALNORMCodegen`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `modelDescriptorsFromSchemaMetadata:classPrefix:databaseTarget:descriptorOverrides:error:` | `+ (nullable NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix databaseTarget:(nullable NSString *)databaseTarget descriptorOverrides:(nullable NSDictionary<NSString *, NSDictionary *> *)descriptorOverrides error:(NSError *_Nullable *_Nullable)error;` | Perform `model descriptors from schema metadata` for `ALNORMCodegen`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `renderArtifactsFromSchemaMetadata:classPrefix:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
| `renderArtifactsFromSchemaMetadata:classPrefix:databaseTarget:descriptorOverrides:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix databaseTarget:(nullable NSString *)databaseTarget descriptorOverrides:(nullable NSDictionary<NSString *, NSDictionary *> *)descriptorOverrides error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
