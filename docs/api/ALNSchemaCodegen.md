# ALNSchemaCodegen

- Kind: `interface`
- Header: `src/Arlen/Data/ALNSchemaCodegen.h`

Schema artifact generator for typed table/column contracts and optional typed decode helpers.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `normalizedColumnsFromRows:error:` | `+ (nullable NSArray<NSDictionary<NSString *, id> *> *)normalizedColumnsFromRows:(NSArray<NSDictionary *> *)rows error:(NSError *_Nullable *_Nullable)error;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `renderArtifactsFromColumns:classPrefix:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows classPrefix:(NSString *)classPrefix error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
| `renderArtifactsFromColumns:classPrefix:databaseTarget:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows classPrefix:(NSString *)classPrefix databaseTarget:(nullable NSString *)databaseTarget error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
| `renderArtifactsFromColumns:classPrefix:databaseTarget:includeTypedContracts:error:` | `+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows classPrefix:(NSString *)classPrefix databaseTarget:(nullable NSString *)databaseTarget includeTypedContracts:(BOOL)includeTypedContracts error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
