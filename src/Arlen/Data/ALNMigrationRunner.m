#import "ALNMigrationRunner.h"

#import "ALNPg.h"

NSString *const ALNMigrationRunnerErrorDomain = @"Arlen.Data.MigrationRunner.Error";

static NSError *ALNMigrationError(NSString *message, NSString *detail) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"migration error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  return [NSError errorWithDomain:ALNMigrationRunnerErrorDomain code:1 userInfo:userInfo];
}

@implementation ALNMigrationRunner

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

+ (BOOL)ensureMigrationsTableWithDatabase:(ALNPg *)database error:(NSError **)error {
  NSInteger affected =
      [database executeCommand:@"CREATE TABLE IF NOT EXISTS arlen_schema_migrations ("
                                "version TEXT PRIMARY KEY,"
                                "applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()"
                                ")"
                     parameters:@[]
                          error:error];
  return (affected >= 0);
}

+ (nullable NSSet *)appliedVersionSetWithDatabase:(ALNPg *)database error:(NSError **)error {
  NSArray *rows = [database executeQuery:@"SELECT version FROM arlen_schema_migrations"
                               parameters:@[]
                                    error:error];
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
                                                error:(NSError **)error {
  NSArray *allMigrations = [self migrationFilesAtPath:migrationsPath error:error];
  if (allMigrations == nil) {
    return nil;
  }

  if (![self ensureMigrationsTableWithDatabase:database error:error]) {
    return nil;
  }

  NSSet *applied = [self appliedVersionSetWithDatabase:database error:error];
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
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> **)appliedFiles
                        error:(NSError **)error {
  NSArray *pending = [self pendingMigrationFilesAtPath:migrationsPath database:database error:error];
  if (pending == nil) {
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
    BOOL appliedOK = [database withTransaction:^BOOL(ALNPgConnection *connection, NSError **blockError) {
      NSInteger affected = [connection executeCommand:sql parameters:@[] error:blockError];
      if (affected < 0) {
        return NO;
      }

      NSInteger inserted = [connection executeCommand:@"INSERT INTO arlen_schema_migrations (version) VALUES ($1)"
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

@end
