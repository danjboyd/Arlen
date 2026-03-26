#import "ALNDatabaseAdapter.h"

#import "ALNMSSQL.h"
#import "ALNPg.h"

NSString *const ALNDatabaseAdapterErrorDomain = @"Arlen.Data.Adapter.Error";

@implementation ALNDatabaseJSONValue

+ (instancetype)valueWithObject:(id)object {
  return [[self alloc] initWithObject:object];
}

- (instancetype)init {
  return [self initWithObject:nil];
}

- (instancetype)initWithObject:(id)object {
  self = [super init];
  if (self != nil) {
    _object = object;
  }
  return self;
}

@end

@implementation ALNDatabaseArrayValue

+ (instancetype)valueWithItems:(NSArray *)items {
  return [[self alloc] initWithItems:items];
}

- (instancetype)init {
  return [self initWithItems:nil];
}

- (instancetype)initWithItems:(NSArray *)items {
  self = [super init];
  if (self != nil) {
    _items = [items copy] ?: @[];
  }
  return self;
}

@end

@implementation ALNDatabaseRow

+ (instancetype)rowWithDictionary:(NSDictionary<NSString *, id> *)dictionary {
  return [[self alloc] initWithDictionary:dictionary];
}

- (instancetype)init {
  return [self initWithDictionary:nil];
}

- (instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary {
  self = [super init];
  if (self != nil) {
    _dictionaryRepresentation = [dictionary isKindOfClass:[NSDictionary class]]
                                    ? [dictionary copy]
                                    : @{};
  }
  return self;
}

- (NSArray<NSString *> *)columns {
  return [[self.dictionaryRepresentation allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
}

- (id)objectForColumn:(NSString *)columnName {
  if (![columnName isKindOfClass:[NSString class]] || [columnName length] == 0) {
    return nil;
  }
  id value = self.dictionaryRepresentation[columnName];
  return (value == [NSNull null]) ? nil : value;
}

- (id)objectForKeyedSubscript:(NSString *)columnName {
  return [self objectForColumn:columnName];
}

@end

@implementation ALNDatabaseResult

+ (instancetype)resultWithRows:(NSArray<NSDictionary<NSString *, id> *> *)rows {
  return [[self alloc] initWithRows:rows];
}

- (instancetype)init {
  return [self initWithRows:nil];
}

- (instancetype)initWithRows:(NSArray<NSDictionary<NSString *, id> *> *)rows {
  self = [super init];
  if (self != nil) {
    _rows = [rows isKindOfClass:[NSArray class]] ? [rows copy] : @[];
  }
  return self;
}

- (NSUInteger)count {
  return [self.rows count];
}

- (ALNDatabaseRow *)first {
  return [self rowAtIndex:0];
}

- (ALNDatabaseRow *)rowAtIndex:(NSUInteger)index {
  if (index >= [self.rows count]) {
    return nil;
  }
  id row = self.rows[index];
  if (![row isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return [ALNDatabaseRow rowWithDictionary:row];
}

- (ALNDatabaseRow *)one:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if ([self.rows count] != 1) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(
          ALNDatabaseAdapterErrorInvalidResult,
          @"expected exactly one row in result",
          @{ @"row_count" : @([self.rows count]) });
    }
    return nil;
  }
  return [self rowAtIndex:0];
}

- (ALNDatabaseRow *)oneOrNil:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if ([self.rows count] == 0) {
    return nil;
  }
  return [self one:error];
}

- (id)scalarValueForColumn:(NSString *)columnName error:(NSError **)error {
  return ALNDatabaseScalarValueFromRows(self.rows, columnName, error);
}

@end

NSError *ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorCode code,
                                     NSString *message,
                                     NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"database adapter error";
  return [NSError errorWithDomain:ALNDatabaseAdapterErrorDomain
                             code:code
                         userInfo:details];
}

BOOL ALNDatabaseErrorIsConnectivityFailure(NSError *error) {
  if (![error isKindOfClass:[NSError class]]) {
    return NO;
  }

  NSError *underlying = [error.userInfo[NSUnderlyingErrorKey] isKindOfClass:[NSError class]]
                            ? error.userInfo[NSUnderlyingErrorKey]
                            : nil;
  if (underlying != nil && ALNDatabaseErrorIsConnectivityFailure(underlying)) {
    return YES;
  }

  if ([error.domain isEqualToString:ALNPgErrorDomain]) {
    return (error.code == ALNPgErrorConnectionFailed || error.code == ALNPgErrorPoolExhausted);
  }
  if ([error.domain isEqualToString:ALNMSSQLErrorDomain]) {
    return (error.code == ALNMSSQLErrorConnectionFailed || error.code == ALNMSSQLErrorPoolExhausted ||
            error.code == ALNMSSQLErrorTransportUnavailable);
  }

  NSString *sqlState = [error.userInfo[ALNPgErrorSQLStateKey] isKindOfClass:[NSString class]]
                           ? error.userInfo[ALNPgErrorSQLStateKey]
                           : @"";
  if ([sqlState hasPrefix:@"08"]) {
    return YES;
  }

  NSString *text = [[NSString stringWithFormat:@"%@ %@",
                                                error.localizedDescription ?: @"",
                                                [error.userInfo[@"detail"] description] ?: @""]
      lowercaseString];
  NSArray<NSString *> *hints = @[
    @"connection refused",
    @"connection reset",
    @"connect timeout",
    @"could not connect",
    @"network is unreachable",
    @"server closed the connection",
    @"transport unavailable",
    @"pool exhausted",
    @"broken pipe",
  ];
  for (NSString *hint in hints) {
    if ([text containsString:hint]) {
      return YES;
    }
  }
  return NO;
}

ALNDatabaseJSONValue *ALNDatabaseJSONParameter(id object) {
  return [ALNDatabaseJSONValue valueWithObject:object];
}

ALNDatabaseArrayValue *ALNDatabaseArrayParameter(NSArray *items) {
  return [ALNDatabaseArrayValue valueWithItems:items];
}

ALNDatabaseResult *ALNDatabaseResultFromRows(NSArray<NSDictionary *> *rows) {
  return [ALNDatabaseResult resultWithRows:rows];
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

ALNDatabaseResult *ALNDatabaseExecuteQueryResult(id<ALNDatabaseConnection> connection,
                                                 NSString *sql,
                                                 NSArray *parameters,
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

  if ([connection respondsToSelector:@selector(executeQueryResult:parameters:error:)]) {
    return [(id)connection executeQueryResult:sql parameters:parameters ?: @[] error:error];
  }

  NSArray<NSDictionary *> *rows =
      [connection executeQuery:sql parameters:parameters ?: @[] error:error];
  if (rows == nil) {
    return nil;
  }
  return ALNDatabaseResultFromRows(rows);
}

static NSArray<NSArray *> *ALNDatabaseNormalizedParameterSets(NSArray<NSArray *> *parameterSets,
                                                              NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (parameterSets == nil) {
    return @[];
  }
  if (![parameterSets isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                           @"batch parameter sets must be an array",
                                           nil);
    }
    return nil;
  }

  NSMutableArray<NSArray *> *normalized = [NSMutableArray arrayWithCapacity:[parameterSets count]];
  for (id item in parameterSets) {
    if (![item isKindOfClass:[NSArray class]]) {
      if (error != NULL) {
        *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                             @"each batch parameter set must be an array",
                                             nil);
      }
      return nil;
    }
    [normalized addObject:item];
  }
  return normalized;
}

NSInteger ALNDatabaseExecuteCommandBatch(id<ALNDatabaseConnection> connection,
                                         NSString *sql,
                                         NSArray<NSArray *> *parameterSets,
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
    return -1;
  }

  NSError *normalizeError = nil;
  NSArray<NSArray *> *normalized = ALNDatabaseNormalizedParameterSets(parameterSets, &normalizeError);
  if (normalized == nil) {
    if (error != NULL) {
      *error = normalizeError;
    }
    return -1;
  }

  if ([connection respondsToSelector:@selector(executeCommandBatch:parameterSets:error:)]) {
    return [(id)connection executeCommandBatch:sql parameterSets:normalized error:error];
  }

  NSInteger totalAffected = 0;
  for (NSArray *parameters in normalized) {
    NSInteger affected = [connection executeCommand:sql parameters:parameters error:error];
    if (affected < 0) {
      return -1;
    }
    totalAffected += affected;
  }
  return totalAffected;
}

BOOL ALNDatabaseConnectionSupportsSavepoints(id<ALNDatabaseConnection> connection) {
  return [connection respondsToSelector:@selector(createSavepointNamed:error:)] &&
         [connection respondsToSelector:@selector(rollbackToSavepointNamed:error:)] &&
         [connection respondsToSelector:@selector(releaseSavepointNamed:error:)];
}

BOOL ALNDatabaseCreateSavepoint(id<ALNDatabaseConnection> connection,
                                NSString *name,
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
    return NO;
  }
  if (![connection respondsToSelector:@selector(createSavepointNamed:error:)]) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorUnsupported,
                                           @"savepoints are not supported by this connection",
                                           nil);
    }
    return NO;
  }
  return [(id)connection createSavepointNamed:name error:error];
}

BOOL ALNDatabaseRollbackToSavepoint(id<ALNDatabaseConnection> connection,
                                    NSString *name,
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
    return NO;
  }
  if (![connection respondsToSelector:@selector(rollbackToSavepointNamed:error:)]) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorUnsupported,
                                           @"savepoints are not supported by this connection",
                                           nil);
    }
    return NO;
  }
  return [(id)connection rollbackToSavepointNamed:name error:error];
}

BOOL ALNDatabaseReleaseSavepoint(id<ALNDatabaseConnection> connection,
                                 NSString *name,
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
    return NO;
  }
  if (![connection respondsToSelector:@selector(releaseSavepointNamed:error:)]) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorUnsupported,
                                           @"savepoints are not supported by this connection",
                                           nil);
    }
    return NO;
  }
  return [(id)connection releaseSavepointNamed:name error:error];
}

BOOL ALNDatabaseWithSavepoint(id<ALNDatabaseConnection> connection,
                              NSString *name,
                              BOOL (^block)(NSError **error),
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
    return NO;
  }
  if (block == nil) {
    if (error != NULL) {
      *error = ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorInvalidArgument,
                                           @"savepoint block is required",
                                           nil);
    }
    return NO;
  }

  if ([connection respondsToSelector:@selector(withSavepointNamed:usingBlock:error:)]) {
    return [(id)connection withSavepointNamed:name usingBlock:block error:error];
  }

  if (!ALNDatabaseCreateSavepoint(connection, name, error)) {
    return NO;
  }

  NSError *blockError = nil;
  BOOL success = block(&blockError);
  if (success) {
    NSError *releaseError = nil;
    if (!ALNDatabaseReleaseSavepoint(connection, name, &releaseError)) {
      if (error != NULL) {
        *error = releaseError;
      }
      return NO;
    }
    return YES;
  }

  NSError *rollbackError = nil;
  (void)ALNDatabaseRollbackToSavepoint(connection, name, &rollbackError);
  if (error != NULL) {
    *error = blockError ?: rollbackError;
  }
  return NO;
}
