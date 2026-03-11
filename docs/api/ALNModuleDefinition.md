# ALNModuleDefinition

- Kind: `interface`
- Header: `src/Arlen/Core/ALNModuleSystem.h`

Core runtime API surface for application lifecycle, config, and contracts.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `identifier` | `NSString *` | `nonatomic, copy, readonly` | Public `identifier` property available on `ALNModuleDefinition`. |
| `version` | `NSString *` | `nonatomic, copy, readonly` | Public `version` property available on `ALNModuleDefinition`. |
| `principalClassName` | `NSString *` | `nonatomic, copy, readonly` | Public `principalClassName` property available on `ALNModuleDefinition`. |
| `rootPath` | `NSString *` | `nonatomic, copy, readonly` | Public `rootPath` property available on `ALNModuleDefinition`. |
| `manifestPath` | `NSString *` | `nonatomic, copy, readonly` | Public `manifestPath` property available on `ALNModuleDefinition`. |
| `sourcePath` | `NSString *` | `nonatomic, copy, readonly` | Public `sourcePath` property available on `ALNModuleDefinition`. |
| `templatePath` | `NSString *` | `nonatomic, copy, readonly` | Public `templatePath` property available on `ALNModuleDefinition`. |
| `publicPath` | `NSString *` | `nonatomic, copy, readonly` | Public `publicPath` property available on `ALNModuleDefinition`. |
| `localePath` | `NSString *` | `nonatomic, copy, readonly` | Public `localePath` property available on `ALNModuleDefinition`. |
| `migrationPath` | `NSString *` | `nonatomic, copy, readonly` | Public `migrationPath` property available on `ALNModuleDefinition`. |
| `migrationDatabaseTarget` | `NSString *` | `nonatomic, copy, readonly` | Public `migrationDatabaseTarget` property available on `ALNModuleDefinition`. |
| `migrationNamespace` | `NSString *` | `nonatomic, copy, readonly` | Public `migrationNamespace` property available on `ALNModuleDefinition`. |
| `compatibleArlenVersion` | `NSString *` | `nonatomic, copy, readonly` | Public `compatibleArlenVersion` property available on `ALNModuleDefinition`. |
| `dependencies` | `NSArray<NSDictionary *> *` | `nonatomic, copy, readonly` | Public `dependencies` property available on `ALNModuleDefinition`. |
| `configDefaults` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `configDefaults` property available on `ALNModuleDefinition`. |
| `requiredConfigKeys` | `NSArray<NSString *> *` | `nonatomic, copy, readonly` | Public `requiredConfigKeys` property available on `ALNModuleDefinition`. |
| `publicMounts` | `NSArray<NSDictionary *> *` | `nonatomic, copy, readonly` | Public `publicMounts` property available on `ALNModuleDefinition`. |
| `manifest` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `manifest` property available on `ALNModuleDefinition`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `definitionWithModuleRoot:error:` | `+ (nullable instancetype)definitionWithModuleRoot:(NSString *)moduleRoot error:(NSError *_Nullable *_Nullable)error;` | Perform `definition with module root` for `ALNModuleDefinition`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |
