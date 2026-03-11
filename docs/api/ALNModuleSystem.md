# ALNModuleSystem

- Kind: `interface`
- Header: `src/Arlen/Core/ALNModuleSystem.h`

Core runtime API surface for application lifecycle, config, and contracts.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `frameworkVersion` | `+ (NSString *)frameworkVersion;` | Perform `framework version` for `ALNModuleSystem`. | Call on the class type, not on an instance. |
| `modulesConfigRelativePath` | `+ (NSString *)modulesConfigRelativePath;` | Perform `modules config relative path` for `ALNModuleSystem`. | Call on the class type, not on an instance. |
| `modulesLockDocumentAtAppRoot:error:` | `+ (nullable NSDictionary *)modulesLockDocumentAtAppRoot:(NSString *)appRoot error:(NSError *_Nullable *_Nullable)error;` | Perform `modules lock document at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `writeModulesLockDocument:appRoot:error:` | `+ (BOOL)writeModulesLockDocument:(NSDictionary *)document appRoot:(NSString *)appRoot error:(NSError *_Nullable *_Nullable)error;` | Write a serialized representation to disk. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `installedModuleRecordsAtAppRoot:error:` | `+ (nullable NSArray<NSDictionary *> *)installedModuleRecordsAtAppRoot:(NSString *)appRoot error:(NSError *_Nullable *_Nullable)error;` | Perform `installed module records at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `moduleDefinitionAtPath:error:` | `+ (nullable ALNModuleDefinition *)moduleDefinitionAtPath:(NSString *)moduleRoot error:(NSError *_Nullable *_Nullable)error;` | Perform `module definition at path` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `moduleDefinitionsAtAppRoot:error:` | `+ (nullable NSArray<ALNModuleDefinition *> *)moduleDefinitionsAtAppRoot:(NSString *)appRoot error:(NSError *_Nullable *_Nullable)error;` | Perform `module definitions at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `sortedModuleDefinitionsAtAppRoot:error:` | `+ (nullable NSArray<ALNModuleDefinition *> *)sortedModuleDefinitionsAtAppRoot:(NSString *)appRoot error:(NSError *_Nullable *_Nullable)error;` | Perform `sorted module definitions at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `configByApplyingModuleDefaultsToConfig:appRoot:strict:diagnostics:error:` | `+ (nullable NSDictionary *)configByApplyingModuleDefaultsToConfig:(NSDictionary *)config appRoot:(NSString *)appRoot strict:(BOOL)strict diagnostics: (NSArray<NSDictionary *> *_Nullable *_Nullable)diagnostics error:(NSError *_Nullable *_Nullable)error;` | Perform `config by applying module defaults to config` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `doctorDiagnosticsAtAppRoot:config:error:` | `+ (nullable NSArray<NSDictionary *> *)doctorDiagnosticsAtAppRoot:(NSString *)appRoot config:(NSDictionary *)config error:(NSError *_Nullable *_Nullable)error;` | Perform `doctor diagnostics at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `loadModulesForApplication:error:` | `+ (nullable NSArray<id<ALNModule>> *)loadModulesForApplication:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;` | Load and normalize configuration data. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `migrationPlansAtAppRoot:config:error:` | `+ (nullable NSArray<NSDictionary *> *)migrationPlansAtAppRoot:(NSString *)appRoot config:(nullable NSDictionary *)config error:(NSError *_Nullable *_Nullable)error;` | Perform `migration plans at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `stagePublicAssetsAtAppRoot:outputDir:stagedFiles:error:` | `+ (BOOL)stagePublicAssetsAtAppRoot:(NSString *)appRoot outputDir:(NSString *)outputDir stagedFiles:(NSArray<NSString *> *_Nullable *_Nullable)stagedFiles error:(NSError *_Nullable *_Nullable)error;` | Perform `stage public assets at app root` for `ALNModuleSystem`. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
