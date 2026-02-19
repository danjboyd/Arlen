#import "ALNSQLBuilder.h"

NSString *const ALNSQLBuilderErrorDomain = @"Arlen.Data.SQLBuilder.Error";

static NSError *ALNSQLBuilderMakeError(ALNSQLBuilderErrorCode code,
                                       NSString *message,
                                       NSString *identifier) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"sql builder error";
  if ([identifier length] > 0) {
    userInfo[@"identifier"] = identifier;
  }
  return [NSError errorWithDomain:ALNSQLBuilderErrorDomain code:code userInfo:userInfo];
}

static BOOL ALNSQLBuilderIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  NSArray *parts = [value componentsSeparatedByString:@"."];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      return NO;
    }
    unichar first = [part characterAtIndex:0];
    BOOL validStart = [[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_';
    if (!validStart) {
      return NO;
    }
  }
  return YES;
}

static NSString *ALNSQLBuilderQuoteIdentifier(NSString *value) {
  NSArray *parts = [value componentsSeparatedByString:@"."];
  NSMutableArray *quoted = [NSMutableArray arrayWithCapacity:[parts count]];
  for (NSString *part in parts) {
    [quoted addObject:[NSString stringWithFormat:@"\"%@\"", part]];
  }
  return [quoted componentsJoinedByString:@"."];
}

static NSArray *ALNSQLBuilderSortedDictionaryKeys(NSDictionary *dictionary) {
  NSArray *keys = [dictionary allKeys];
  return [keys sortedArrayUsingSelector:@selector(compare:)];
}

@interface ALNSQLBuilder ()

@property(nonatomic, assign, readwrite) ALNSQLBuilderKind kind;
@property(nonatomic, copy, readwrite) NSString *tableName;
@property(nonatomic, copy) NSArray *selectColumns;
@property(nonatomic, copy) NSDictionary *values;
@property(nonatomic, strong) NSMutableArray *whereClauses;
@property(nonatomic, strong) NSMutableArray *orderByClauses;
@property(nonatomic, assign) NSUInteger limitValue;
@property(nonatomic, assign) NSUInteger offsetValue;
@property(nonatomic, assign) BOOL hasLimit;
@property(nonatomic, assign) BOOL hasOffset;

@end

@implementation ALNSQLBuilder

+ (instancetype)selectFrom:(NSString *)tableName
                   columns:(NSArray<NSString *> *)columns {
  ALNSQLBuilder *builder = [[ALNSQLBuilder alloc] init];
  builder.kind = ALNSQLBuilderKindSelect;
  builder.tableName = [tableName copy] ?: @"";
  builder.selectColumns = ([columns count] > 0) ? [columns copy] : @[ @"*" ];
  return builder;
}

+ (instancetype)insertInto:(NSString *)tableName
                    values:(NSDictionary<NSString *,id> *)values {
  ALNSQLBuilder *builder = [[ALNSQLBuilder alloc] init];
  builder.kind = ALNSQLBuilderKindInsert;
  builder.tableName = [tableName copy] ?: @"";
  builder.values = [values copy] ?: @{};
  return builder;
}

+ (instancetype)updateTable:(NSString *)tableName
                     values:(NSDictionary<NSString *,id> *)values {
  ALNSQLBuilder *builder = [[ALNSQLBuilder alloc] init];
  builder.kind = ALNSQLBuilderKindUpdate;
  builder.tableName = [tableName copy] ?: @"";
  builder.values = [values copy] ?: @{};
  return builder;
}

+ (instancetype)deleteFrom:(NSString *)tableName {
  ALNSQLBuilder *builder = [[ALNSQLBuilder alloc] init];
  builder.kind = ALNSQLBuilderKindDelete;
  builder.tableName = [tableName copy] ?: @"";
  return builder;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _selectColumns = @[ @"*" ];
    _values = @{};
    _whereClauses = [NSMutableArray array];
    _orderByClauses = [NSMutableArray array];
    _hasLimit = NO;
    _hasOffset = NO;
  }
  return self;
}

- (instancetype)whereField:(NSString *)field equals:(id)value {
  return [self whereField:field operator:@"=" value:value];
}

- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
                     value:(id)value {
  NSString *normalized = [[operatorName ?: @"=" uppercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"operator" : normalized,
    @"value" : value ?: [NSNull null],
    @"kind" : @"operator"
  }];
  return self;
}

- (instancetype)whereFieldIn:(NSString *)field
                      values:(NSArray *)values {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"values" : values ?: @[],
    @"kind" : @"in"
  }];
  return self;
}

- (instancetype)orderByField:(NSString *)field descending:(BOOL)descending {
  [self.orderByClauses addObject:@{
    @"field" : field ?: @"",
    @"descending" : @(descending)
  }];
  return self;
}

- (instancetype)limit:(NSUInteger)limit {
  self.limitValue = limit;
  self.hasLimit = YES;
  return self;
}

- (instancetype)offset:(NSUInteger)offset {
  self.offsetValue = offset;
  self.hasOffset = YES;
  return self;
}

- (BOOL)validateTableName:(NSError **)error {
  if (!ALNSQLBuilderIdentifierIsSafe(self.tableName)) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                      @"invalid table name",
                                      self.tableName);
    }
    return NO;
  }
  return YES;
}

- (nullable NSString *)compileColumns:(NSError **)error {
  NSMutableArray *columns = [NSMutableArray array];
  for (id value in self.selectColumns ?: @[]) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
      continue;
    }
    NSString *column = value;
    if ([column isEqualToString:@"*"]) {
      [columns addObject:@"*"];
      continue;
    }
    if (!ALNSQLBuilderIdentifierIsSafe(column)) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid select column",
                                        column);
      }
      return nil;
    }
    [columns addObject:ALNSQLBuilderQuoteIdentifier(column)];
  }
  if ([columns count] == 0) {
    [columns addObject:@"*"];
  }
  return [columns componentsJoinedByString:@", "];
}

- (BOOL)appendWhereClauseSQLTo:(NSMutableString *)sql
                    parameters:(NSMutableArray *)parameters
                         error:(NSError **)error {
  if ([self.whereClauses count] == 0) {
    return YES;
  }

  NSMutableArray *fragments = [NSMutableArray arrayWithCapacity:[self.whereClauses count]];
  NSSet *allowedOperators = [NSSet setWithArray:@[
    @"=",
    @"!=",
    @">",
    @"<",
    @">=",
    @"<=",
    @"LIKE",
    @"ILIKE"
  ]];

  for (NSDictionary *clause in self.whereClauses) {
    NSString *kind = clause[@"kind"];
    NSString *field = [clause[@"field"] isKindOfClass:[NSString class]] ? clause[@"field"] : @"";
    if (!ALNSQLBuilderIdentifierIsSafe(field)) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid where field",
                                        field);
      }
      return NO;
    }
    NSString *quotedField = ALNSQLBuilderQuoteIdentifier(field);

    if ([kind isEqualToString:@"in"]) {
      NSArray *values = [clause[@"values"] isKindOfClass:[NSArray class]] ? clause[@"values"] : @[];
      if ([values count] == 0) {
        [fragments addObject:@"1=0"];
        continue;
      }
      NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:[values count]];
      for (id value in values) {
        [parameters addObject:value ?: [NSNull null]];
        [placeholders addObject:[NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]]];
      }
      [fragments addObject:[NSString stringWithFormat:@"%@ IN (%@)",
                                                       quotedField,
                                                       [placeholders componentsJoinedByString:@", "]]];
      continue;
    }

    NSString *operatorName = [clause[@"operator"] isKindOfClass:[NSString class]]
                                 ? [clause[@"operator"] uppercaseString]
                                 : @"=";
    if (![allowedOperators containsObject:operatorName]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorUnsupportedOperator,
                                        @"unsupported where operator",
                                        operatorName);
      }
      return NO;
    }

    id value = clause[@"value"];
    if (value == nil || value == [NSNull null]) {
      if ([operatorName isEqualToString:@"="]) {
        [fragments addObject:[NSString stringWithFormat:@"%@ IS NULL", quotedField]];
      } else if ([operatorName isEqualToString:@"!="]) {
        [fragments addObject:[NSString stringWithFormat:@"%@ IS NOT NULL", quotedField]];
      } else {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"NULL values only support '=' and '!=' operators",
                                          field);
        }
        return NO;
      }
      continue;
    }

    [parameters addObject:value];
    NSString *placeholder = [NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]];
    [fragments addObject:[NSString stringWithFormat:@"%@ %@ %@", quotedField, operatorName, placeholder]];
  }

  if ([fragments count] > 0) {
    [sql appendFormat:@" WHERE %@", [fragments componentsJoinedByString:@" AND "]];
  }
  return YES;
}

- (BOOL)appendOrderBySQLTo:(NSMutableString *)sql error:(NSError **)error {
  if ([self.orderByClauses count] == 0) {
    return YES;
  }

  NSMutableArray *fragments = [NSMutableArray arrayWithCapacity:[self.orderByClauses count]];
  for (NSDictionary *entry in self.orderByClauses) {
    NSString *field = [entry[@"field"] isKindOfClass:[NSString class]] ? entry[@"field"] : @"";
    if (!ALNSQLBuilderIdentifierIsSafe(field)) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid order field",
                                        field);
      }
      return NO;
    }
    BOOL descending = [entry[@"descending"] boolValue];
    [fragments addObject:[NSString stringWithFormat:@"%@ %@",
                                                    ALNSQLBuilderQuoteIdentifier(field),
                                                    descending ? @"DESC" : @"ASC"]];
  }

  if ([fragments count] > 0) {
    [sql appendFormat:@" ORDER BY %@", [fragments componentsJoinedByString:@", "]];
  }
  return YES;
}

- (nullable NSDictionary *)build:(NSError **)error {
  if (![self validateTableName:error]) {
    return nil;
  }

  NSMutableArray *parameters = [NSMutableArray array];
  NSMutableString *sql = [NSMutableString string];
  NSString *quotedTable = ALNSQLBuilderQuoteIdentifier(self.tableName);

  switch (self.kind) {
    case ALNSQLBuilderKindSelect: {
      NSString *columns = [self compileColumns:error];
      if (columns == nil) {
        return nil;
      }
      [sql appendFormat:@"SELECT %@ FROM %@", columns, quotedTable];
      if (![self appendWhereClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if (![self appendOrderBySQLTo:sql error:error]) {
        return nil;
      }
      if (self.hasLimit) {
        [sql appendFormat:@" LIMIT %lu", (unsigned long)self.limitValue];
      }
      if (self.hasOffset) {
        [sql appendFormat:@" OFFSET %lu", (unsigned long)self.offsetValue];
      }
      break;
    }
    case ALNSQLBuilderKindInsert: {
      if ([self.values count] == 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"insert requires at least one value",
                                          self.tableName);
        }
        return nil;
      }
      NSArray *keys = ALNSQLBuilderSortedDictionaryKeys(self.values);
      NSMutableArray *quotedColumns = [NSMutableArray arrayWithCapacity:[keys count]];
      NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:[keys count]];
      for (NSString *key in keys) {
        if (!ALNSQLBuilderIdentifierIsSafe(key)) {
          if (error != NULL) {
            *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                            @"invalid insert field",
                                            key);
          }
          return nil;
        }
        [quotedColumns addObject:ALNSQLBuilderQuoteIdentifier(key)];
        [parameters addObject:self.values[key] ?: [NSNull null]];
        [placeholders addObject:[NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]]];
      }
      [sql appendFormat:@"INSERT INTO %@ (%@) VALUES (%@)",
                        quotedTable,
                        [quotedColumns componentsJoinedByString:@", "],
                        [placeholders componentsJoinedByString:@", "]];
      break;
    }
    case ALNSQLBuilderKindUpdate: {
      if ([self.values count] == 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"update requires at least one value",
                                          self.tableName);
        }
        return nil;
      }
      NSArray *keys = ALNSQLBuilderSortedDictionaryKeys(self.values);
      NSMutableArray *assignments = [NSMutableArray arrayWithCapacity:[keys count]];
      for (NSString *key in keys) {
        if (!ALNSQLBuilderIdentifierIsSafe(key)) {
          if (error != NULL) {
            *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                            @"invalid update field",
                                            key);
          }
          return nil;
        }
        [parameters addObject:self.values[key] ?: [NSNull null]];
        NSString *placeholder = [NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]];
        [assignments addObject:[NSString stringWithFormat:@"%@ = %@",
                                                          ALNSQLBuilderQuoteIdentifier(key),
                                                          placeholder]];
      }
      [sql appendFormat:@"UPDATE %@ SET %@", quotedTable, [assignments componentsJoinedByString:@", "]];
      if (![self appendWhereClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      break;
    }
    case ALNSQLBuilderKindDelete: {
      [sql appendFormat:@"DELETE FROM %@", quotedTable];
      if (![self appendWhereClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      break;
    }
    default: {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorCompileFailed,
                                        @"unknown builder kind",
                                        self.tableName);
      }
      return nil;
    }
  }

  return @{
    @"sql" : [NSString stringWithString:sql],
    @"parameters" : [NSArray arrayWithArray:parameters]
  };
}

- (NSString *)buildSQL:(NSError **)error {
  NSDictionary *built = [self build:error];
  return [built[@"sql"] isKindOfClass:[NSString class]] ? built[@"sql"] : nil;
}

- (NSArray *)buildParameters:(NSError **)error {
  NSDictionary *built = [self build:error];
  return [built[@"parameters"] isKindOfClass:[NSArray class]] ? built[@"parameters"] : @[];
}

@end
