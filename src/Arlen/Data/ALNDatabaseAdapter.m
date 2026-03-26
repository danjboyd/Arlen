#import "ALNDatabaseAdapter.h"

NSString *const ALNDatabaseAdapterErrorDomain = @"Arlen.Data.Adapter.Error";

NSError *ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorCode code,
                                     NSString *message,
                                     NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"database adapter error";
  return [NSError errorWithDomain:ALNDatabaseAdapterErrorDomain
                             code:code
                         userInfo:details];
}

NSDictionary<NSString *, id> *ALNDatabaseFirstRow(NSArray<NSDictionary *> *rows) {
  if (![rows isKindOfClass:[NSArray class]] || [rows count] == 0) {
    return nil;
  }
  id first = rows[0];
  return [first isKindOfClass:[NSDictionary class]] ? first : nil;
}

id ALNDatabaseScalarValueFromRow(NSDictionary<NSString *, id> *row,
                                 NSString *columnName,
                                 NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (row == nil) {
    return nil;
  }
  if (![row isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidResult,
                                           @"scalar row must be a dictionary",
                                           nil);
    }
    return nil;
  }

  NSString *requestedColumn = [columnName isKindOfClass:[NSString class]]
                                  ? [columnName stringByTrimmingCharactersInSet:
                                                   [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                  : @"";
  if ([requestedColumn length] > 0) {
    if (row[requestedColumn] == nil) {
      if (error != NULL) {
        *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidResult,
                                             @"requested scalar column is missing from the row",
                                             @{ @"column" : requestedColumn });
      }
      return nil;
    }
    id value = row[requestedColumn];
    return (value == [NSNull null]) ? nil : value;
  }

  NSArray *keys = [row allKeys];
  if ([keys count] == 0) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidResult,
                                           @"cannot extract a scalar from an empty row",
                                           nil);
    }
    return nil;
  }
  if ([keys count] > 1) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(
          ALNDatabaseAdapterErrorInvalidResult,
          @"scalar extraction requires an explicit column name when the row has multiple columns",
          @{ @"columns" : keys });
    }
    return nil;
  }

  id value = row[keys[0]];
  return (value == [NSNull null]) ? nil : value;
}

id ALNDatabaseScalarValueFromRows(NSArray<NSDictionary *> *rows,
                                  NSString *columnName,
                                  NSError **error) {
  NSDictionary<NSString *, id> *row = ALNDatabaseFirstRow(rows);
  if (row == nil) {
    if (error != NULL) {
      *error = nil;
    }
    return nil;
  }
  return ALNDatabaseScalarValueFromRow(row, columnName, error);
}

id ALNDatabaseExecuteScalarQuery(id<ALNDatabaseConnection> connection,
                                 NSString *sql,
                                 NSArray *parameters,
                                 NSString *columnName,
                                 NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (connection == nil) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                           @"database connection is required",
                                           nil);
    }
    return nil;
  }

  NSDictionary *row = [connection executeQueryOne:sql parameters:parameters ?: @[] error:error];
  if (row == nil) {
    return nil;
  }
  return ALNDatabaseScalarValueFromRow(row, columnName, error);
}
