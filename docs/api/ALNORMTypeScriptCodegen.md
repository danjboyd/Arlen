# ALNORMTypeScriptCodegen

- Kind: `interface`
- Header: `src/Arlen/ORM/ALNORMTypeScriptCodegen.h`

Optional ORM APIs for reflected models, repositories, relations, and SQL-first code generation.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `renderArtifactsFromSchemaMetadata:classPrefix:databaseTarget:descriptorOverrides:openAPISpecification:packageName:targets:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata classPrefix:(NSString *)classPrefix databaseTarget:(nullable NSString *)databaseTarget descriptorOverrides: (nullable NSDictionary<NSString *, NSDictionary *> *)descriptorOverrides openAPISpecification: (nullable NSDictionary<NSString *, id> *)openAPISpecification packageName:(nullable NSString *)packageName targets:(NSArray<NSString *> *)targets error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
| `renderArtifactsFromORMManifest:openAPISpecification:packageName:targets:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromORMManifest:(NSDictionary<NSString *, id> *)manifest openAPISpecification: (nullable NSDictionary<NSString *, id> *)openAPISpecification packageName:(nullable NSString *)packageName targets:(NSArray<NSString *> *)targets error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
| `renderArtifactsFromModelDescriptors:openAPISpecification:packageName:targets:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromModelDescriptors: (NSArray<ALNORMModelDescriptor *> *)descriptors openAPISpecification: (nullable NSDictionary<NSString *, id> *)openAPISpecification packageName:(nullable NSString *)packageName targets:(NSArray<NSString *> *)targets error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
