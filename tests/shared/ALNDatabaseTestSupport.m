#import "ALNDatabaseTestSupport.h"

#import "../ALNTestRequirements.h"
#import "ALNTestSupport.h"

static NSString *const ALNDatabaseTestSupportErrorDomain = @"Arlen.DatabaseTestSupport.Error";

static NSError *ALNDatabaseTestSupportMakeError(NSString *message, NSDictionary *userInfo) {
  return [NSError errorWithDomain:ALNDatabaseTestSupportErrorDomain
                             code:1
                         userInfo:userInfo != nil
                                      ? userInfo
                                      : @{
                                          NSLocalizedDescriptionKey : message ?: @"database test support error",
                                        }];
}

NSString *ALNTestRequiredEnvironmentString(NSString *environmentName,
                                           NSString *suiteName,
                                           NSString *testName,
                                           NSString *reason) {
  NSString *value = ALNTestEnvironmentString(environmentName);
  if ([value length] > 0) {
    return value;
  }

  ALNTestRequireCondition(NO,
                          suiteName ?: @"UnknownSuite",
                          testName ?: @"unknownTest",
                          environmentName ?: @"missing_env",
                          reason ?: @"required test environment variable is unset");
  return nil;
}

NSString *ALNTestQuotedIdentifierForAdapterName(NSString *adapterName, NSString *identifier) {
  NSString *name = [identifier isKindOfClass:[NSString class]] ? identifier : @"";
  NSString *adapter = [[adapterName isKindOfClass:[NSString class]] ? adapterName : @""
      lowercaseString];
  if ([adapter isEqualToString:@"mssql"]) {
    return [NSString stringWithFormat:@"[%@]",
                                      [name stringByReplacingOccurrencesOfString:@"]"
                                                                      withString:@"]]"]];
  }
  return [NSString stringWithFormat:@"\"%@\"",
                                    [name stringByReplacingOccurrencesOfString:@"\""
                                                                    withString:@"\"\""]];
}

NSString *ALNTestMSSQLTemporaryTableName(NSString *prefix) {
  return [@"#" stringByAppendingString:ALNTestUniqueIdentifier(prefix)];
}

BOOL ALNTestWithDisposableSchema(id<ALNDatabaseAdapter> adapter,
                                 NSString *schemaPrefix,
                                 BOOL (^block)(NSString *schemaName, NSError **error),
                                 NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (adapter == nil || block == nil) {
    if (error != NULL) {
      *error = ALNDatabaseTestSupportMakeError(
          @"adapter and block are required",
          @{
            NSLocalizedDescriptionKey : @"adapter and block are required",
          });
    }
    return NO;
  }

  NSString *adapterName = [[adapter adapterName] lowercaseString];
  BOOL isPostgres = [adapterName isEqualToString:@"postgresql"];
  BOOL isMSSQL = [adapterName isEqualToString:@"mssql"];
  if (!isPostgres && !isMSSQL) {
    if (error != NULL) {
      *error = ALNDatabaseTestSupportMakeError(
          @"disposable schema harness only supports PostgreSQL and MSSQL adapters",
          @{
            NSLocalizedDescriptionKey :
                @"disposable schema harness only supports PostgreSQL and MSSQL adapters",
            @"adapter" : adapterName ?: @"",
          });
    }
    return NO;
  }

  NSString *schemaName = ALNTestUniqueIdentifier(schemaPrefix);
  NSString *quotedSchema = ALNTestQuotedIdentifierForAdapterName(adapterName, schemaName);
  NSString *createSQL = isMSSQL
                            ? [NSString stringWithFormat:@"CREATE SCHEMA %@ AUTHORIZATION dbo",
                                                         quotedSchema]
                            : [NSString stringWithFormat:@"CREATE SCHEMA %@", quotedSchema];
  NSString *dropSQL = isMSSQL
                          ? [NSString stringWithFormat:@"DROP SCHEMA %@", quotedSchema]
                          : [NSString stringWithFormat:@"DROP SCHEMA %@ CASCADE", quotedSchema];

  NSError *createError = nil;
  NSInteger createAffected = [adapter executeCommand:createSQL parameters:@[] error:&createError];
  if (createAffected < 0 || createError != nil) {
    if (error != NULL) {
      *error = createError;
    }
    return NO;
  }

  NSError *blockError = nil;
  BOOL success = block(schemaName, &blockError);

  NSError *dropError = nil;
  NSInteger dropAffected = [adapter executeCommand:dropSQL parameters:@[] error:&dropError];
  if (dropAffected < 0 && dropError == nil) {
    dropError = ALNDatabaseTestSupportMakeError(
        @"failed tearing down disposable schema",
        @{
          NSLocalizedDescriptionKey : @"failed tearing down disposable schema",
          @"schema" : schemaName ?: @"",
        });
  }

  if (!success) {
    if (error != NULL) {
      *error = blockError ?: dropError;
    }
    return NO;
  }
  if (dropError != nil) {
    if (error != NULL) {
      *error = dropError;
    }
    return NO;
  }
  return YES;
}
