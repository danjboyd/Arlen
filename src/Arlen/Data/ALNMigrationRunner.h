#ifndef ALN_MIGRATION_RUNNER_H
#define ALN_MIGRATION_RUNNER_H

#import <Foundation/Foundation.h>

@class ALNPg;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNMigrationRunnerErrorDomain;

@interface ALNMigrationRunner : NSObject

+ (nullable NSArray<NSString *> *)migrationFilesAtPath:(NSString *)migrationsPath
                                                 error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                                      database:(ALNPg *)database
                                                         error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(ALNPg *)database
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> *_Nullable *_Nullable)appliedFiles
                        error:(NSError *_Nullable *_Nullable)error;

+ (NSString *)versionForMigrationFile:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END

#endif
