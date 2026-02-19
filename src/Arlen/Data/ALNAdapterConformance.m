#import "ALNAdapterConformance.h"

#import <stdlib.h>

NSString *const ALNAdapterConformanceErrorDomain = @"Arlen.Data.AdapterConformance.Error";

static NSString *ALNConformanceUniqueTableName(void) {
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"aln_adapter_%@", uuid];
}

static NSError *ALNConformanceStepError(NSString *step,
                                        NSString *adapterName,
                                        NSError *underlying) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"adapter conformance failed at step '%@'", step ?: @""];
  userInfo[@"step"] = step ?: @"";
  userInfo[@"adapter"] = adapterName ?: @"";
  if (underlying != nil) {
    userInfo[NSUnderlyingErrorKey] = underlying;
  }
  return [NSError errorWithDomain:ALNAdapterConformanceErrorDomain
                             code:ALNAdapterConformanceErrorStepFailed
                         userInfo:userInfo];
}

NSDictionary *_Nullable ALNAdapterConformanceReport(id<ALNDatabaseAdapter> adapter,
                                                     NSError **error) {
  if (adapter == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNAdapterConformanceErrorDomain
                                   code:ALNAdapterConformanceErrorInvalidAdapter
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"adapter is required"
                               }];
    }
    return nil;
  }

  NSString *adapterName = [adapter adapterName] ?: @"";
  NSString *table = ALNConformanceUniqueTableName();
  NSMutableDictionary *report = [NSMutableDictionary dictionary];
  report[@"adapter"] = adapterName;
  report[@"table"] = table;

  NSError *stepError = nil;
  NSString *createSQL =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, name TEXT NOT NULL)", table];
  NSInteger createResult = [adapter executeCommand:createSQL parameters:@[] error:&stepError];
  if (createResult < 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"create_table", adapterName, stepError);
    }
    return nil;
  }
  report[@"create_table"] = @"ok";

  __block NSString *insertedName = @"hank";
  BOOL insertCommitted = [adapter withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection,
                                                                   NSError **blockError) {
    NSInteger inserted = [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES ($1)", table]
                                         parameters:@[ insertedName ]
                                              error:blockError];
    return (inserted >= 0);
  } error:&stepError];
  if (!insertCommitted) {
    (void)[adapter executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                       parameters:@[]
                            error:nil];
    if (error != NULL) {
      *error = ALNConformanceStepError(@"transaction_commit", adapterName, stepError);
    }
    return nil;
  }
  report[@"transaction_commit"] = @"ok";

  NSArray *rows = [adapter executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@", table]
                             parameters:@[]
                                  error:&stepError];
  NSString *count = [[rows firstObject][@"count"] description];
  if (rows == nil || ![count isEqualToString:@"1"]) {
    (void)[adapter executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                       parameters:@[]
                            error:nil];
    if (error != NULL) {
      *error = ALNConformanceStepError(@"count_after_commit", adapterName, stepError);
    }
    return nil;
  }
  report[@"count_after_commit"] = count ?: @"";

  NSError *expectedRollback = [NSError errorWithDomain:ALNAdapterConformanceErrorDomain
                                                  code:999
                                              userInfo:@{
                                                NSLocalizedDescriptionKey : @"rollback sentinel"
                                              }];
  BOOL rollbackResult = [adapter withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection,
                                                                  NSError **blockError) {
    NSInteger inserted = [connection executeCommand:[NSString stringWithFormat:@"INSERT INTO %@ (name) VALUES ($1)", table]
                                         parameters:@[ @"rollback-me" ]
                                              error:blockError];
    if (inserted < 0) {
      return NO;
    }
    if (blockError != NULL) {
      *blockError = expectedRollback;
    }
    return NO;
  } error:&stepError];
  if (rollbackResult || ![stepError.domain isEqualToString:ALNAdapterConformanceErrorDomain] ||
      stepError.code != 999) {
    (void)[adapter executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                       parameters:@[]
                            error:nil];
    if (error != NULL) {
      *error = ALNConformanceStepError(@"transaction_rollback", adapterName, stepError);
    }
    return nil;
  }
  report[@"transaction_rollback"] = @"ok";

  rows = [adapter executeQuery:[NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@", table]
                    parameters:@[]
                         error:&stepError];
  count = [[rows firstObject][@"count"] description];
  if (rows == nil || ![count isEqualToString:@"1"]) {
    (void)[adapter executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                       parameters:@[]
                            error:nil];
    if (error != NULL) {
      *error = ALNConformanceStepError(@"count_after_rollback", adapterName, stepError);
    }
    return nil;
  }
  report[@"count_after_rollback"] = count ?: @"";

  NSInteger dropResult =
      [adapter executeCommand:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table]
                   parameters:@[]
                        error:&stepError];
  if (dropResult < 0) {
    if (error != NULL) {
      *error = ALNConformanceStepError(@"drop_table", adapterName, stepError);
    }
    return nil;
  }
  report[@"drop_table"] = @"ok";
  report[@"success"] = @(YES);
  return report;
}

BOOL ALNRunAdapterConformanceSuite(id<ALNDatabaseAdapter> adapter,
                                   NSError **error) {
  NSDictionary *report = ALNAdapterConformanceReport(adapter, error);
  return (report != nil);
}
