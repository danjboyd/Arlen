#import "ALNMigrationStatus.h"

#import "ALNDatabaseAdapter.h"
#import "ALNGDL2Adapter.h"
#import "ALNMSSQL.h"
#import "ALNMigrationRunner.h"
#import "ALNModuleSystem.h"
#import "ALNPg.h"

static NSString *ALNMigrationStatusTrimmed(id value) {
  return [value isKindOfClass:[NSString class]]
             ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
             : @"";
}

static id<ALNDatabaseAdapter> ALNMigrationStatusAdapter(NSDictionary *database, NSString *dsn, NSError **error) {
  NSString *adapter = [ALNMigrationStatusTrimmed(database[@"adapter"]) lowercaseString];
  if ([adapter length] == 0 || [adapter isEqualToString:@"postgresql"]) {
    return [[ALNPg alloc] initWithConnectionString:dsn maxConnections:1 error:error];
  }
  if ([adapter isEqualToString:@"gdl2"]) {
    return [[ALNGDL2Adapter alloc] initWithConnectionString:dsn maxConnections:1 error:error];
  }
  if ([adapter isEqualToString:@"mssql"] || [adapter isEqualToString:@"sqlserver"]) {
    return [[ALNMSSQL alloc] initWithConnectionString:dsn maxConnections:1 error:error];
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:ALNDatabaseAdapterErrorDomain
                                 code:ALNDatabaseAdapterErrorUnsupported
                             userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"unsupported database adapter '%@'", adapter] }];
  }
  return nil;
}

@implementation ALNMigrationStatus

+ (NSDictionary *)statusAtAppRoot:(NSString *)appRoot config:(NSDictionary *)config {
  NSDictionary *database = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : @{};
  const char *envDSN = getenv("ARLEN_DATABASE_URL");
  NSString *dsn = (envDSN != NULL && envDSN[0] != '\0') ? [NSString stringWithUTF8String:envDSN]
                                                        : ALNMigrationStatusTrimmed(database[@"connectionString"]);
  if ([dsn length] == 0) {
    return @{ @"ok" : @YES, @"skipped" : @"no_database_configured", @"pending" : @[] };
  }

  // Versions this release ships: app migrations, then module migrations that
  // target the default database, versioned the way `arlen migrate` records them.
  NSMutableArray<NSString *> *shipped = [NSMutableArray array];
  NSError *error = nil;
  NSString *appMigrations = [appRoot stringByAppendingPathComponent:@"db/migrations"];
  BOOL isDirectory = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:appMigrations isDirectory:&isDirectory] && isDirectory) {
    NSArray *files = [ALNMigrationRunner migrationFilesAtPath:appMigrations error:&error];
    if (files == nil) {
      return @{ @"ok" : @NO, @"pending" : @[], @"error" : error.localizedDescription ?: @"could not list migrations" };
    }
    for (NSString *file in files) {
      [shipped addObject:[ALNMigrationRunner versionForMigrationFile:file]];
    }
  }
  NSArray<NSDictionary *> *plans = [ALNModuleSystem migrationPlansAtAppRoot:appRoot config:config error:&error] ?: @[];
  for (NSDictionary *plan in plans) {
    NSString *target = ALNMigrationStatusTrimmed(plan[@"databaseTarget"]);
    NSString *path = ALNMigrationStatusTrimmed(plan[@"path"]);
    if (([target length] > 0 && ![target isEqualToString:@"default"]) || [path length] == 0 ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
      continue;
    }
    for (NSString *file in [ALNMigrationRunner migrationFilesAtPath:path error:NULL] ?: @[]) {
      [shipped addObject:[ALNMigrationRunner versionForMigrationFile:file versionNamespace:plan[@"namespace"]]];
    }
  }
  if ([shipped count] == 0) {
    return @{ @"ok" : @YES, @"pending" : @[], @"total" : @0 };
  }

  id<ALNDatabaseAdapter> adapter = ALNMigrationStatusAdapter(database, dsn, &error);
  NSSet<NSString *> *applied =
      adapter != nil ? [ALNMigrationRunner appliedMigrationVersionsWithDatabase:adapter databaseTarget:nil error:&error] : nil;
  if (applied == nil) {
    return @{
      @"ok" : @NO,
      @"pending" : @[],
      @"total" : @([shipped count]),
      @"error" : error.localizedDescription ?: @"could not read arlen_schema_migrations",
    };
  }
  NSMutableArray<NSString *> *pending = [NSMutableArray array];
  for (NSString *version in shipped) {
    if (![applied containsObject:version]) {
      [pending addObject:version];
    }
  }
  return @{
    @"ok" : @([pending count] == 0),
    @"pending" : pending,
    @"total" : @([shipped count]),
    @"applied_count" : @([shipped count] - [pending count]),
  };
}

@end
