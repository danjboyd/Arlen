#ifndef ALN_MIGRATION_STATUS_H
#define ALN_MIGRATION_STATUS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Read-only comparison of an app's migrations (db/migrations plus module
// migrations for the default database target) with the versions recorded in
// arlen_schema_migrations (GitHub issue 90). Used by the /readyz
// schema_migrations check; it never creates tables or applies anything.
@interface ALNMigrationStatus : NSObject

// Returns @{ ok, pending (versions), applied_count, total }, or with `skipped`
// when no database is configured, or `ok = NO` with `error` when the database
// cannot be queried. The connection string comes from ARLEN_DATABASE_URL, else
// config.database.connectionString, as `arlen migrate` resolves it.
+ (NSDictionary *)statusAtAppRoot:(NSString *)appRoot config:(NSDictionary *)config;

@end

NS_ASSUME_NONNULL_END

#endif
