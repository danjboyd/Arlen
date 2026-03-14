#ifndef ALN_MIGRATION_RUNNER_H
#define ALN_MIGRATION_RUNNER_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNMigrationRunnerErrorDomain;
extern NSString *const ALNMigrationRunnerDefaultDatabaseTarget;

@interface ALNMigrationRunner : NSObject

+ (nullable NSArray<NSString *> *)migrationFilesAtPath:(NSString *)migrationsPath
                                                 error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                                      database:(id<ALNDatabaseAdapter>)database
                                                databaseTarget:(nullable NSString *)databaseTarget
                                              versionNamespace:(nullable NSString *)versionNamespace
                                                         error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                                      database:(id<ALNDatabaseAdapter>)database
                                                databaseTarget:(nullable NSString *)databaseTarget
                                                         error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                                      database:(id<ALNDatabaseAdapter>)database
                                                         error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(id<ALNDatabaseAdapter>)database
               databaseTarget:(nullable NSString *)databaseTarget
             versionNamespace:(nullable NSString *)versionNamespace
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> *_Nullable *_Nullable)appliedFiles
                        error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(id<ALNDatabaseAdapter>)database
               databaseTarget:(nullable NSString *)databaseTarget
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> *_Nullable *_Nullable)appliedFiles
                        error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(id<ALNDatabaseAdapter>)database
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> *_Nullable *_Nullable)appliedFiles
                        error:(NSError *_Nullable *_Nullable)error;

+ (NSString *)versionForMigrationFile:(NSString *)filePath;
+ (NSString *)versionForMigrationFile:(NSString *)filePath
                     versionNamespace:(nullable NSString *)versionNamespace;

@end

NS_ASSUME_NONNULL_END

#endif
