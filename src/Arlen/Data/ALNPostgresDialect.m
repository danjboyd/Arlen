#import "ALNPostgresDialect.h"

#import "ALNSQLBuilder.h"

#import <dispatch/dispatch.h>

@interface ALNSQLBuilder (ALNDefaultDialectCompile)
- (nullable NSDictionary *)aln_buildDefaultDialect:(NSError *_Nullable *_Nullable)error;
@end

static NSError *ALNPostgresDialectMigrationError(NSString *message, NSString *identifier) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"PostgreSQL migration SQL generation failed";
  if ([identifier length] > 0) {
    userInfo[@"identifier"] = identifier;
  }
  return [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                             code:ALNSQLBuilderErrorInvalidIdentifier
                         userInfo:userInfo];
}

@implementation ALNPostgresDialect

+ (instancetype)sharedDialect {
  static ALNPostgresDialect *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[ALNPostgresDialect alloc] init];
  });
  return shared;
}

- (NSString *)dialectName {
  return @"postgresql";
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"dialect" : @"postgresql",
    @"supports_transactions" : @YES,
    @"returning_mode" : @"returning",
    @"pagination_syntax" : @"limit_offset",
    @"supports_upsert" : @YES,
    @"conflict_resolution_mode" : @"on_conflict",
    @"json_feature_family" : @"jsonb_ops",
    @"supports_cte" : @YES,
    @"supports_recursive_cte" : @YES,
    @"supports_set_operations" : @YES,
    @"supports_window_clauses" : @YES,
    @"supports_lateral_join" : @YES,
    @"supports_for_update" : @YES,
    @"supports_skip_locked" : @YES,
  };
}

- (NSDictionary *)compileBuilder:(ALNSQLBuilder *)builder error:(NSError **)error {
  if (builder == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                   code:ALNSQLBuilderErrorInvalidArgument
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"builder is required"
                               }];
    }
    return nil;
  }
  return [builder aln_buildDefaultDialect:error];
}

- (NSString *)migrationStateTableCreateSQLForTableName:(NSString *)tableName
                                                 error:(NSError **)error {
  if (!ALNSQLDialectIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNPostgresDialectMigrationError(@"invalid migration state table name", tableName);
    }
    return nil;
  }

  NSString *quotedTable = ALNSQLDialectDoubleQuoteIdentifier(tableName);
  NSString *quotedVersion = ALNSQLDialectDoubleQuoteIdentifier(@"version");
  NSString *quotedAppliedAt = ALNSQLDialectDoubleQuoteIdentifier(@"applied_at");
  return [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ ("
                                      "%@ TEXT PRIMARY KEY,"
                                      "%@ TIMESTAMPTZ NOT NULL DEFAULT NOW()"
                                      ")",
                                    quotedTable,
                                    quotedVersion,
                                    quotedAppliedAt];
}

- (NSString *)migrationVersionsSelectSQLForTableName:(NSString *)tableName
                                               error:(NSError **)error {
  if (!ALNSQLDialectIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNPostgresDialectMigrationError(@"invalid migration state table name", tableName);
    }
    return nil;
  }
  NSString *quotedTable = ALNSQLDialectDoubleQuoteIdentifier(tableName);
  NSString *quotedVersion = ALNSQLDialectDoubleQuoteIdentifier(@"version");
  return [NSString stringWithFormat:@"SELECT %@ FROM %@ ORDER BY %@",
                                    quotedVersion,
                                    quotedTable,
                                    quotedVersion];
}

- (NSString *)migrationVersionInsertSQLForTableName:(NSString *)tableName
                                              error:(NSError **)error {
  if (!ALNSQLDialectIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNPostgresDialectMigrationError(@"invalid migration state table name", tableName);
    }
    return nil;
  }
  NSString *quotedTable = ALNSQLDialectDoubleQuoteIdentifier(tableName);
  NSString *quotedVersion = ALNSQLDialectDoubleQuoteIdentifier(@"version");
  return [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES ($1)",
                                    quotedTable,
                                    quotedVersion];
}

@end
