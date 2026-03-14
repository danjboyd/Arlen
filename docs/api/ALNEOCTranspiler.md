# ALNEOCTranspiler

- Kind: `interface`
- Header: `src/Arlen/MVC/Template/ALNEOCTranspiler.h`

EOC template compiler/transpiler with lint diagnostics and deterministic symbol/path resolution.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `symbolNameForLogicalPath:` | `- (NSString *)symbolNameForLogicalPath:(NSString *)logicalPath;` | Convert template logical path to deterministic ObjC symbol name. | Capture the returned value and propagate errors/validation as needed. |
| `logicalPathForTemplatePath:templateRoot:` | `- (NSString *)logicalPathForTemplatePath:(NSString *)templatePath templateRoot:(nullable NSString *)templateRoot;` | Resolve logical template path from file path and template root. | Capture the returned value and propagate errors/validation as needed. |
| `logicalPathForTemplatePath:templateRoot:logicalPrefix:` | `- (NSString *)logicalPathForTemplatePath:(NSString *)templatePath templateRoot:(nullable NSString *)templateRoot logicalPrefix:(nullable NSString *)logicalPrefix;` | Perform `logical path for template path` for `ALNEOCTranspiler`. | Capture the returned value and propagate errors/validation as needed. |
| `lintDiagnosticsForTemplateString:logicalPath:error:` | `- (nullable NSArray<NSDictionary *> *)lintDiagnosticsForTemplateString:(NSString *)templateText logicalPath:(NSString *)logicalPath error: (NSError *_Nullable *_Nullable)error;` | Run template lint pass and return diagnostics payloads. | Pass `NSError **` and treat a `nil` result as failure. |
| `templateMetadataForTemplateString:logicalPath:error:` | `- (nullable NSDictionary *)templateMetadataForTemplateString:(NSString *)templateText logicalPath:(NSString *)logicalPath error: (NSError *_Nullable *_Nullable)error;` | Perform `template metadata for template string` for `ALNEOCTranspiler`. | Pass `NSError **` and treat a `nil` result as failure. |
| `transpiledSourceForTemplateString:logicalPath:error:` | `- (nullable NSString *)transpiledSourceForTemplateString:(NSString *)templateText logicalPath:(NSString *)logicalPath error: (NSError *_Nullable *_Nullable)error;` | Transpile template source text into Objective-C runtime source. | Pass `NSError **` and treat a `nil` result as failure. |
| `transpileTemplateAtPath:templateRoot:outputPath:error:` | `- (BOOL)transpileTemplateAtPath:(NSString *)templatePath templateRoot:(nullable NSString *)templateRoot outputPath:(NSString *)outputPath error:(NSError *_Nullable *_Nullable)error;` | Transpile one template file to generated Objective-C file. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `transpileTemplateAtPath:templateRoot:logicalPrefix:outputPath:error:` | `- (BOOL)transpileTemplateAtPath:(NSString *)templatePath templateRoot:(nullable NSString *)templateRoot logicalPrefix:(nullable NSString *)logicalPrefix outputPath:(NSString *)outputPath error:(NSError *_Nullable *_Nullable)error;` | Perform `transpile template at path` for `ALNEOCTranspiler`. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
