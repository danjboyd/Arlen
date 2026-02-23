#import "ALNMigrationRunner.h"

#import "ALNPg.h"

NSString *const ALNMigrationRunnerErrorDomain = @"Arlen.Data.MigrationRunner.Error";
NSString *const ALNMigrationRunnerDefaultDatabaseTarget = @"default";

static NSError *ALNMigrationError(NSString *message, NSString *detail) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"migration error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  return [NSError errorWithDomain:ALNMigrationRunnerErrorDomain code:1 userInfo:userInfo];
}

@implementation ALNMigrationRunner

+ (NSString *)normalizedDatabaseTarget:(NSString *)databaseTarget {
  NSString *normalized =
      [databaseTarget isKindOfClass:[NSString class]]
          ? [[databaseTarget stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                lowercaseString]
          : @"";
  if ([normalized length] == 0) {
    return ALNMigrationRunnerDefaultDatabaseTarget;
  }
  return normalized;
}

+ (BOOL)isSafeDatabaseTarget:(NSString *)databaseTarget {
  if (![databaseTarget isKindOfClass:[NSString class]] || [databaseTarget length] == 0) {
    return NO;
  }
  if ([databaseTarget length] > 32) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([[databaseTarget stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [databaseTarget characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

+ (nullable NSString *)migrationsTableNameForDatabaseTarget:(NSString *)databaseTarget
                                                     error:(NSError **)error {
  NSString *normalized = [self normalizedDatabaseTarget:databaseTarget];
  if (![self isSafeDatabaseTarget:normalized]) {
    if (error != NULL) {
      *error = ALNMigrationError(
          @"database target must match [a-z][a-z0-9_]* and be <= 32 characters", normalized);
    }
    return nil;
  }
  if ([normalized isEqualToString:ALNMigrationRunnerDefaultDatabaseTarget]) {
    return @"arlen_schema_migrations";
  }
  return [NSString stringWithFormat:@"arlen_schema_migrations__%@", normalized];
}

+ (NSArray<NSString *> *)migrationFilesAtPath:(NSString *)migrationsPath
                                        error:(NSError **)error {
  if ([migrationsPath length] == 0) {
    if (error != NULL) {
      *error = ALNMigrationError(@"migrations path is required", nil);
    }
    return nil;
  }

  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:migrationsPath isDirectory:&isDirectory] ||
      !isDirectory) {
    if (error != NULL) {
      *error = ALNMigrationError(@"migrations directory not found", migrationsPath);
    }
    return nil;
  }

  NSError *contentsError = nil;
  NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:migrationsPath
                                                                          error:&contentsError];
  if (entries == nil) {
    if (error != NULL) {
      *error = contentsError;
    }
    return nil;
  }

  NSMutableArray *files = [NSMutableArray array];
  for (NSString *entry in entries) {
    if (![[entry pathExtension] isEqualToString:@"sql"]) {
      continue;
    }
    NSString *fullPath = [migrationsPath stringByAppendingPathComponent:entry];
    BOOL childDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&childDirectory] &&
        !childDirectory) {
      [files addObject:fullPath];
    }
  }

  [files sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
    return [[left lastPathComponent] compare:[right lastPathComponent]];
  }];

  return files;
}

+ (NSString *)versionForMigrationFile:(NSString *)filePath {
  NSString *name = [[filePath lastPathComponent] stringByDeletingPathExtension];
  return [name copy] ?: @"";
}

+ (BOOL)ensureMigrationsTableWithDatabase:(ALNPg *)database
                                tableName:(NSString *)tableName
                                    error:(NSError **)error {
  NSString *sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ ("
                                              "version TEXT PRIMARY KEY,"
                                              "applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()"
                                              ")",
                                             tableName];
  NSInteger affected = [database executeCommand:sql parameters:@[] error:error];
  return (affected >= 0);
}

+ (nullable NSSet *)appliedVersionSetWithDatabase:(ALNPg *)database
                                         tableName:(NSString *)tableName
                                             error:(NSError **)error {
  NSString *sql = [NSString stringWithFormat:@"SELECT version FROM %@ ORDER BY version", tableName];
  NSArray *rows = [database executeQuery:sql parameters:@[] error:error];
  if (rows == nil) {
    return nil;
  }

  NSMutableSet *versions = [NSMutableSet setWithCapacity:[rows count]];
  for (NSDictionary *row in rows) {
    NSString *version = row[@"version"];
    if ([version isKindOfClass:[NSString class]] && [version length] > 0) {
      [versions addObject:version];
    }
  }
  return versions;
}

+ (NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                             database:(ALNPg *)database
                                       databaseTarget:(NSString *)databaseTarget
                                                error:(NSError **)error {
  NSArray *allMigrations = [self migrationFilesAtPath:migrationsPath error:error];
  if (allMigrations == nil) {
    return nil;
  }

  NSString *tableName = [self migrationsTableNameForDatabaseTarget:databaseTarget error:error];
  if ([tableName length] == 0) {
    return nil;
  }

  if (![self ensureMigrationsTableWithDatabase:database tableName:tableName error:error]) {
    return nil;
  }

  NSSet *applied = [self appliedVersionSetWithDatabase:database tableName:tableName error:error];
  if (applied == nil) {
    return nil;
  }

  NSMutableArray *pending = [NSMutableArray array];
  for (NSString *file in allMigrations) {
    NSString *version = [self versionForMigrationFile:file];
    if (![applied containsObject:version]) {
      [pending addObject:file];
    }
  }
  return pending;
}

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(ALNPg *)database
               databaseTarget:(NSString *)databaseTarget
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> **)appliedFiles
                        error:(NSError **)error {
  NSArray *pending = [self pendingMigrationFilesAtPath:migrationsPath
                                              database:database
                                        databaseTarget:databaseTarget
                                                 error:error];
  if (pending == nil) {
    return NO;
  }

  NSString *tableName = [self migrationsTableNameForDatabaseTarget:databaseTarget error:error];
  if ([tableName length] == 0) {
    return NO;
  }

  if (dryRun) {
    if (appliedFiles != NULL) {
      *appliedFiles = pending;
    }
    return YES;
  }

  NSMutableArray *applied = [NSMutableArray array];
  for (NSString *migrationPath in pending) {
    NSError *readError = nil;
    NSString *sql = [NSString stringWithContentsOfFile:migrationPath
                                              encoding:NSUTF8StringEncoding
                                                 error:&readError];
    if (sql == nil) {
      if (error != NULL) {
        *error = readError ?: ALNMigrationError(@"failed reading migration file", migrationPath);
      }
      return NO;
    }

    NSString *version = [self versionForMigrationFile:migrationPath];
    __block NSError *transactionError = nil;
    NSString *insertSQL = [NSString stringWithFormat:@"INSERT INTO %@ (version) VALUES ($1)", tableName];
    BOOL appliedOK = [database withTransaction:^BOOL(ALNPgConnection *connection, NSError **blockError) {
      NSInteger affected = [connection executeCommand:sql parameters:@[] error:blockError];
      if (affected < 0) {
        return NO;
      }

      NSInteger inserted = [connection executeCommand:insertSQL
                                           parameters:@[ version ]
                                                error:blockError];
      if (inserted < 0) {
        return NO;
      }
      return YES;
    } error:&transactionError];

    if (!appliedOK) {
      if (error != NULL) {
        *error = transactionError ?: ALNMigrationError(@"failed applying migration", migrationPath);
      }
      return NO;
    }
    [applied addObject:migrationPath];
  }

  if (appliedFiles != NULL) {
    *appliedFiles = applied;
  }
  return YES;
}

+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                                      database:(ALNPg *)database
                                                         error:(NSError **)error {
  return [self pendingMigrationFilesAtPath:migrationsPath
                                  database:database
                            databaseTarget:ALNMigrationRunnerDefaultDatabaseTarget
                                     error:error];
}

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(ALNPg *)database
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> **)appliedFiles
                        error:(NSError **)error {
  return [self applyMigrationsAtPath:migrationsPath
                            database:database
                      databaseTarget:ALNMigrationRunnerDefaultDatabaseTarget
                              dryRun:dryRun
                        appliedFiles:appliedFiles
                               error:error];
}

@end
