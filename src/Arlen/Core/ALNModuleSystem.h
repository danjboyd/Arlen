#ifndef ALN_MODULE_SYSTEM_H
#define ALN_MODULE_SYSTEM_H

#import <Foundation/Foundation.h>

@class ALNApplication;
@protocol ALNPlugin;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNModuleSystemErrorDomain;
extern NSString *const ALNModuleSystemFrameworkVersion;

@protocol ALNModule <NSObject>
- (NSString *)moduleIdentifier;
- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;
@optional
- (NSArray<id<ALNPlugin>> *)pluginsForApplication:(ALNApplication *)application;
@end

@protocol ALNModuleMigrationProvider <NSObject>
@end

@protocol ALNModuleAssetProvider <NSObject>
@end

@protocol ALNAuthProviderHook <NSObject>
@end

@protocol ALNAdminResourceProvider <NSObject>
@end

@interface ALNModuleDefinition : NSObject

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *version;
@property(nonatomic, copy, readonly) NSString *principalClassName;
@property(nonatomic, copy, readonly) NSString *rootPath;
@property(nonatomic, copy, readonly) NSString *manifestPath;
@property(nonatomic, copy, readonly) NSString *sourcePath;
@property(nonatomic, copy, readonly) NSString *templatePath;
@property(nonatomic, copy, readonly) NSString *publicPath;
@property(nonatomic, copy, readonly) NSString *localePath;
@property(nonatomic, copy, readonly) NSString *migrationPath;
@property(nonatomic, copy, readonly) NSString *migrationDatabaseTarget;
@property(nonatomic, copy, readonly) NSString *migrationNamespace;
@property(nonatomic, copy, readonly) NSString *compatibleArlenVersion;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *dependencies;
@property(nonatomic, copy, readonly) NSDictionary *configDefaults;
@property(nonatomic, copy, readonly) NSArray<NSString *> *requiredConfigKeys;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *publicMounts;
@property(nonatomic, copy, readonly) NSDictionary *manifest;

+ (nullable instancetype)definitionWithModuleRoot:(NSString *)moduleRoot
                                           error:(NSError *_Nullable *_Nullable)error;

- (NSDictionary *)dictionaryRepresentation;

@end

@interface ALNModuleSystem : NSObject

+ (NSString *)frameworkVersion;
+ (NSString *)modulesConfigRelativePath;
+ (nullable NSDictionary *)modulesLockDocumentAtAppRoot:(NSString *)appRoot
                                                  error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)writeModulesLockDocument:(NSDictionary *)document
                         appRoot:(NSString *)appRoot
                           error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<NSDictionary *> *)installedModuleRecordsAtAppRoot:(NSString *)appRoot
                                                                error:(NSError *_Nullable *_Nullable)error;
+ (nullable ALNModuleDefinition *)moduleDefinitionAtPath:(NSString *)moduleRoot
                                                   error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<ALNModuleDefinition *> *)moduleDefinitionsAtAppRoot:(NSString *)appRoot
                                                                  error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<ALNModuleDefinition *> *)sortedModuleDefinitionsAtAppRoot:(NSString *)appRoot
                                                                        error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary *)configByApplyingModuleDefaultsToConfig:(NSDictionary *)config
                                                          appRoot:(NSString *)appRoot
                                                           strict:(BOOL)strict
                                                      diagnostics:
                                                          (NSArray<NSDictionary *> *_Nullable *_Nullable)diagnostics
                                                           error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<NSDictionary *> *)doctorDiagnosticsAtAppRoot:(NSString *)appRoot
                                                          config:(NSDictionary *)config
                                                           error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<id<ALNModule>> *)loadModulesForApplication:(ALNApplication *)application
                                                         error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<NSDictionary *> *)migrationPlansAtAppRoot:(NSString *)appRoot
                                                       config:(nullable NSDictionary *)config
                                                        error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)stagePublicAssetsAtAppRoot:(NSString *)appRoot
                         outputDir:(NSString *)outputDir
                       stagedFiles:(NSArray<NSString *> *_Nullable *_Nullable)stagedFiles
                             error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
