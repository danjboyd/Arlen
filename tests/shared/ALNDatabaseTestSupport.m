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

NSString *ALNTestWorkerOwnershipModeName(ALNTestWorkerOwnershipMode mode) {
  switch (mode) {
  case ALNTestWorkerOwnershipModeSharedOwner:
    return @"shared_owner";
  case ALNTestWorkerOwnershipModeExplicitBorrowed:
  default:
    return @"explicit_borrowed";
  }
}

NSDictionary<NSString *, id> *ALNTestWorkerOwnershipInfo(ALNTestWorkerOwnershipMode mode,
                                                         NSInteger workerIndex) {
  BOOL sharedOwner = (mode == ALNTestWorkerOwnershipModeSharedOwner);
  return @{
    @"mode" : @(mode),
    @"mode_name" : ALNTestWorkerOwnershipModeName(mode),
    @"worker_index" : @(workerIndex),
    @"shared_owner" : @(sharedOwner),
    @"borrowed_state_allowed" : @(sharedOwner ? NO : YES),
  };
}

BOOL ALNTestRunWorkerGroup(NSString *suiteName,
                           NSString *testName,
                           ALNTestWorkerOwnershipMode mode,
                           NSInteger workerCount,
                           NSTimeInterval timeoutSeconds,
                           ALNTestWorkerGroupBlock block,
                           NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (block == nil || workerCount <= 0) {
    if (error != NULL) {
      *error = ALNDatabaseTestSupportMakeError(
          @"worker group requires a positive worker count and block",
          @{
            NSLocalizedDescriptionKey : @"worker group requires a positive worker count and block",
          });
    }
    return NO;
  }

  NSOperationQueue *queue = [[NSOperationQueue alloc] init];
  queue.maxConcurrentOperationCount =
      (mode == ALNTestWorkerOwnershipModeSharedOwner) ? 1 : MAX(1, workerCount);

  NSCondition *condition = [[NSCondition alloc] init];
  __block NSInteger completed = 0;
  __block NSError *firstWorkerError = nil;

  for (NSInteger idx = 0; idx < workerCount; idx++) {
    NSInteger workerIndex = idx;
    [queue addOperationWithBlock:^{
      @autoreleasepool {
        NSDictionary<NSString *, id> *ownershipInfo =
            ALNTestWorkerOwnershipInfo(mode, workerIndex);
        NSError *workerError = nil;
        BOOL success = block(workerIndex, ownershipInfo, &workerError);
        [condition lock];
        @try {
          if (!success && firstWorkerError == nil) {
            firstWorkerError =
                workerError ?: ALNDatabaseTestSupportMakeError(
                                   @"worker group operation failed",
                                   @{
                                     NSLocalizedDescriptionKey :
                                         @"worker group operation failed",
                                     @"suite" : suiteName ?: @"UnknownSuite",
                                     @"test" : testName ?: @"unknownTest",
                                     @"mode_name" : ALNTestWorkerOwnershipModeName(mode),
                                     @"worker_index" : @(workerIndex),
                                   });
          }
          completed += 1;
          [condition signal];
        } @finally {
          [condition unlock];
        }
      }
    }];
  }

  NSDate *deadline =
      [NSDate dateWithTimeIntervalSinceNow:(timeoutSeconds > 0.0 ? timeoutSeconds : 10.0)];
  [condition lock];
  @try {
    while (completed < workerCount && [[NSDate date] compare:deadline] == NSOrderedAscending) {
      [condition waitUntilDate:deadline];
    }
  } @finally {
    [condition unlock];
  }

  if (completed < workerCount) {
    [queue cancelAllOperations];
    if (error != NULL) {
      *error = ALNDatabaseTestSupportMakeError(
          @"worker group timed out before all collaborators finished",
          @{
            NSLocalizedDescriptionKey :
                @"worker group timed out before all collaborators finished",
            @"suite" : suiteName ?: @"UnknownSuite",
            @"test" : testName ?: @"unknownTest",
            @"mode_name" : ALNTestWorkerOwnershipModeName(mode),
            @"completed" : @(completed),
            @"expected" : @(workerCount),
          });
    }
    return NO;
  }

  [queue waitUntilAllOperationsAreFinished];
  if (firstWorkerError != nil) {
    if (error != NULL) {
      *error = firstWorkerError;
    }
    return NO;
  }
  return YES;
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
