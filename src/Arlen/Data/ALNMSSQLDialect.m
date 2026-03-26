#import "ALNMSSQLDialect.h"

#import "ALNPostgresSQLBuilder.h"
#import "ALNSQLBuilder.h"

#import <dispatch/dispatch.h>

@interface ALNSQLBuilder (ALNDefaultDialectCompile)
- (nullable NSDictionary *)aln_buildDefaultDialect:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)aln_buildDefaultDialectWithDialectContext:(nullable id<ALNSQLDialect>)dialect
                                                               error:(NSError *_Nullable *_Nullable)error;
@end

static NSError *ALNMSSQLDialectError(ALNSQLBuilderErrorCode code,
                                     NSString *message,
                                     NSString *feature) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"MSSQL SQL compilation failed";
  if ([feature length] > 0) {
    userInfo[@"feature"] = feature;
  }
  return [NSError errorWithDomain:ALNSQLBuilderErrorDomain code:code userInfo:userInfo];
}

static NSError *ALNMSSQLDialectMigrationError(NSString *message, NSString *identifier) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"MSSQL migration SQL generation failed";
  if ([identifier length] > 0) {
    userInfo[@"identifier"] = identifier;
  }
  return [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                             code:ALNSQLBuilderErrorInvalidIdentifier
                         userInfo:userInfo];
}

static NSString *ALNMSSQLTrimmedString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNMSSQLOrderClausesUseNullsDirective(NSArray *clauses) {
  for (NSDictionary *entry in ([clauses isKindOfClass:[NSArray class]] ? clauses : @[])) {
    NSString *nulls = ALNMSSQLTrimmedString(entry[@"nulls"]);
    if ([nulls length] > 0) {
      return YES;
    }
  }
  return NO;
}

static BOOL ALNMSSQLClausesContainOperator(NSArray *clauses, NSSet<NSString *> *operators) {
  for (NSDictionary *clause in ([clauses isKindOfClass:[NSArray class]] ? clauses : @[])) {
    if (![clause isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *kind = [clause[@"kind"] isKindOfClass:[NSString class]] ? clause[@"kind"] : @"";
    if ([kind isEqualToString:@"group"]) {
      NSArray *nested = [clause[@"clauses"] isKindOfClass:[NSArray class]] ? clause[@"clauses"] : @[];
      if (ALNMSSQLClausesContainOperator(nested, operators)) {
        return YES;
      }
      continue;
    }
    NSString *operatorName =
        [[clause[@"operator"] isKindOfClass:[NSString class]] ? clause[@"operator"] : @""
            uppercaseString];
    if ([operatorName length] > 0 && [operators containsObject:operatorName]) {
      return YES;
    }
  }
  return NO;
}

static BOOL ALNMSSQLJoinsContainUnsupportedFeatures(NSArray *joins, NSString **feature) {
  for (NSDictionary *join in ([joins isKindOfClass:[NSArray class]] ? joins : @[])) {
    if (![join isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    BOOL lateral = [join[@"lateral"] respondsToSelector:@selector(boolValue)] &&
                   [join[@"lateral"] boolValue];
    if (lateral) {
      if (feature != NULL) {
        *feature = @"lateral_join";
      }
      return YES;
    }
    NSString *conditionKind =
        [join[@"conditionKind"] isKindOfClass:[NSString class]] ? join[@"conditionKind"] : @"";
    if ([conditionKind isEqualToString:@"using-fields"]) {
      if (feature != NULL) {
        *feature = @"join_using";
      }
      return YES;
    }
  }
  return NO;
}

static BOOL ALNMSSQLBuilderUsesUnsupportedFeatures(ALNSQLBuilder *builder, NSError **error) {
  if (builder == nil) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorInvalidArgument,
                                    @"builder is required",
                                    @"builder");
    }
    return YES;
  }

  if ([builder isKindOfClass:[ALNPostgresSQLBuilder class]]) {
    NSInteger conflictMode = [[[builder valueForKey:@"conflictMode"] description] integerValue];
    if (conflictMode != 0) {
      if (error != NULL) {
        *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                      @"ON CONFLICT is not supported by the MSSQL dialect",
                                      @"on_conflict");
      }
      return YES;
    }
  }

  NSString *tableAlias = ALNMSSQLTrimmedString([builder valueForKey:@"tableAlias"]);
  if ([tableAlias length] > 0 && builder.kind != ALNSQLBuilderKindSelect) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL DML compilation does not support table aliases on the target table",
                                    @"dml_target_alias");
    }
    return YES;
  }

  NSArray *joins = [[builder valueForKey:@"joins"] isKindOfClass:[NSArray class]]
                       ? [builder valueForKey:@"joins"]
                       : @[];
  NSString *joinFeature = nil;
  if (ALNMSSQLJoinsContainUnsupportedFeatures(joins, &joinFeature)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL SQL compilation does not support this join construct",
                                    joinFeature);
    }
    return YES;
  }

  NSArray *orderByClauses = [[builder valueForKey:@"orderByClauses"] isKindOfClass:[NSArray class]]
                                ? [builder valueForKey:@"orderByClauses"]
                                : @[];
  if (ALNMSSQLOrderClausesUseNullsDirective(orderByClauses)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL SQL compilation does not support NULLS FIRST/LAST directives",
                                    @"nulls_directive");
    }
    return YES;
  }

  NSString *rowLockMode = ALNMSSQLTrimmedString([builder valueForKey:@"rowLockMode"]);
  BOOL skipLocked = [[builder valueForKey:@"rowLockSkipLocked"] respondsToSelector:@selector(boolValue)] &&
                    [[builder valueForKey:@"rowLockSkipLocked"] boolValue];
  if ([rowLockMode length] > 0 || skipLocked) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL SQL compilation does not support PostgreSQL-style FOR UPDATE locking clauses",
                                    @"row_locking");
    }
    return YES;
  }

  NSArray *whereClauses = [[builder valueForKey:@"whereClauses"] isKindOfClass:[NSArray class]]
                              ? [builder valueForKey:@"whereClauses"]
                              : @[];
  NSArray *havingClauses = [[builder valueForKey:@"havingClauses"] isKindOfClass:[NSArray class]]
                               ? [builder valueForKey:@"havingClauses"]
                               : @[];
  NSSet *unsupportedOperators = [NSSet setWithArray:@[ @"ILIKE", @"NOT ILIKE" ]];
  if (ALNMSSQLClausesContainOperator(whereClauses, unsupportedOperators) ||
      ALNMSSQLClausesContainOperator(havingClauses, unsupportedOperators)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL SQL compilation does not support PostgreSQL ILIKE operators; use an explicit trusted expression when required",
                                    @"ilike");
    }
    return YES;
  }

  BOOL hasLimit = [[builder valueForKey:@"hasLimit"] respondsToSelector:@selector(boolValue)] &&
                  [[builder valueForKey:@"hasLimit"] boolValue];
  BOOL hasOffset = [[builder valueForKey:@"hasOffset"] respondsToSelector:@selector(boolValue)] &&
                   [[builder valueForKey:@"hasOffset"] boolValue];
  NSArray *setOperations = [[builder valueForKey:@"setOperations"] isKindOfClass:[NSArray class]]
                               ? [builder valueForKey:@"setOperations"]
                               : @[];
  if ((hasLimit || hasOffset) && [setOperations count] > 0) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL SQL compilation does not currently support OFFSET/FETCH pagination on builders that also use UNION/INTERSECT/EXCEPT composition",
                                    @"set_operation_pagination");
    }
    return YES;
  }

  if ((hasLimit || hasOffset) && [orderByClauses count] == 0) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL pagination requires an explicit ORDER BY clause",
                                    @"pagination_order_by");
    }
    return YES;
  }

  return NO;
}

static NSString *ALNMSSQLStripTrailingReturningClause(NSString *sql) {
  NSRange returningRange = [sql rangeOfString:@" RETURNING " options:NSBackwardsSearch];
  if (returningRange.location == NSNotFound) {
    return sql ?: @"";
  }
  return [sql substringToIndex:returningRange.location];
}

static NSString *ALNMSSQLRemoveLimitOffsetSuffix(NSString *sql,
                                                 BOOL hasLimit,
                                                 BOOL hasOffset) {
  NSString *rewritten = sql ?: @"";
  if (hasOffset) {
    NSRange offsetRange = [rewritten rangeOfString:@" OFFSET " options:NSBackwardsSearch];
    if (offsetRange.location != NSNotFound) {
      rewritten = [rewritten substringToIndex:offsetRange.location];
    }
  }
  if (hasLimit) {
    NSRange limitRange = [rewritten rangeOfString:@" LIMIT " options:NSBackwardsSearch];
    if (limitRange.location != NSNotFound) {
      rewritten = [rewritten substringToIndex:limitRange.location];
    }
  }
  return rewritten;
}

static NSString *ALNMSSQLConvertPlaceholders(NSString *sql) {
  NSError *regexError = nil;
  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"\\$[0-9]+"
                                                options:0
                                                  error:&regexError];
  if (regex == nil || regexError != nil || [sql length] == 0) {
    return sql ?: @"";
  }
  return [regex stringByReplacingMatchesInString:sql
                                         options:0
                                           range:NSMakeRange(0, [sql length])
                                    withTemplate:@"?"];
}

static NSString *ALNMSSQLConvertQuotedIdentifiers(NSString *sql, NSError **error) {
  if (![sql isKindOfClass:[NSString class]] || [sql length] == 0) {
    return @"";
  }

  NSMutableString *rewritten = [NSMutableString stringWithCapacity:[sql length] + 16];
  NSUInteger index = 0;
  NSUInteger length = [sql length];
  BOOL inSingleQuote = NO;
  while (index < length) {
    unichar character = [sql characterAtIndex:index];
    if (character == '\'') {
      [rewritten appendFormat:@"%C", character];
      index += 1;
      if (inSingleQuote && index < length && [sql characterAtIndex:index] == '\'') {
        [rewritten appendString:@"'"];
        index += 1;
      } else {
        inSingleQuote = !inSingleQuote;
      }
      continue;
    }

    if (!inSingleQuote && character == '"') {
      NSUInteger end = index + 1;
      while (end < length && [sql characterAtIndex:end] != '"') {
        end += 1;
      }
      if (end >= length) {
        if (error != NULL) {
          *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                        @"encountered an unterminated quoted identifier while translating PostgreSQL SQL to MSSQL SQL",
                                        @"quoted_identifier_translation");
        }
        return nil;
      }
      NSString *identifier = [sql substringWithRange:NSMakeRange(index + 1, end - index - 1)];
      [rewritten appendString:ALNSQLDialectBracketQuoteIdentifier(identifier)];
      index = end + 1;
      continue;
    }

    [rewritten appendFormat:@"%C", character];
    index += 1;
  }
  return rewritten;
}

static NSString *ALNMSSQLReturningExpressionForField(NSString *field,
                                                     NSString *sourceAlias,
                                                     NSError **error) {
  NSString *trimmed = ALNMSSQLTrimmedString(field);
  if ([trimmed length] == 0) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorInvalidIdentifier,
                                    @"MSSQL RETURNING/OUTPUT fields must be non-empty",
                                    @"returning");
    }
    return nil;
  }
  if ([trimmed isEqualToString:@"*"] || [trimmed hasSuffix:@".*"]) {
    return [NSString stringWithFormat:@"%@.*", sourceAlias ?: @"INSERTED"];
  }

  NSArray<NSString *> *components = [trimmed componentsSeparatedByString:@"."];
  NSString *column = [components lastObject];
  if (!ALNSQLDialectIdentifierIsSafe(column)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorInvalidIdentifier,
                                    @"invalid OUTPUT field",
                                    trimmed);
    }
    return nil;
  }
  return [NSString stringWithFormat:@"%@.%@",
                                    sourceAlias ?: @"INSERTED",
                                    ALNSQLDialectBracketQuoteIdentifier(column)];
}

static NSString *ALNMSSQLCompileOutputClause(ALNSQLBuilder *builder,
                                             NSString *sourceAlias,
                                             NSError **error) {
  NSArray *returningColumns = [[builder valueForKey:@"returningColumns"] isKindOfClass:[NSArray class]]
                                  ? [builder valueForKey:@"returningColumns"]
                                  : @[];
  if ([returningColumns count] == 0) {
    return @"";
  }

  NSMutableArray<NSString *> *expressions = [NSMutableArray arrayWithCapacity:[returningColumns count]];
  for (NSString *field in returningColumns) {
    NSString *expression = ALNMSSQLReturningExpressionForField(field, sourceAlias, error);
    if (expression == nil) {
      return nil;
    }
    [expressions addObject:expression];
  }
  return [NSString stringWithFormat:@" OUTPUT %@",
                                    [expressions componentsJoinedByString:@", "]];
}

static NSString *ALNMSSQLApplyReturningClause(ALNSQLBuilder *builder,
                                              NSString *sql,
                                              NSError **error) {
  NSString *outputSource = nil;
  switch (builder.kind) {
  case ALNSQLBuilderKindInsert:
  case ALNSQLBuilderKindUpdate:
    outputSource = @"INSERTED";
    break;
  case ALNSQLBuilderKindDelete:
    outputSource = @"DELETED";
    break;
  default:
    return sql ?: @"";
  }

  NSString *outputClause = ALNMSSQLCompileOutputClause(builder, outputSource, error);
  if (outputClause == nil || [outputClause length] == 0) {
    return sql ?: @"";
  }

  NSString *rewritten = ALNMSSQLStripTrailingReturningClause(sql);
  if (builder.kind == ALNSQLBuilderKindInsert) {
    NSRange valuesRange = [rewritten rangeOfString:@" VALUES "];
    if (valuesRange.location == NSNotFound) {
      if (error != NULL) {
        *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                      @"failed to locate INSERT VALUES clause while translating RETURNING to OUTPUT",
                                      @"insert_output");
      }
      return nil;
    }
    NSString *prefix = [rewritten substringToIndex:valuesRange.location];
    NSString *suffix = [rewritten substringFromIndex:valuesRange.location];
    return [NSString stringWithFormat:@"%@%@%@", prefix, outputClause, suffix];
  }

  NSRange whereRange = [rewritten rangeOfString:@" WHERE " options:NSBackwardsSearch];
  if (whereRange.location == NSNotFound) {
    return [rewritten stringByAppendingString:outputClause];
  }
  NSString *prefix = [rewritten substringToIndex:whereRange.location];
  NSString *suffix = [rewritten substringFromIndex:whereRange.location];
  return [NSString stringWithFormat:@"%@%@%@", prefix, outputClause, suffix];
}

static NSString *ALNMSSQLApplyPagination(ALNSQLBuilder *builder,
                                         NSString *sql,
                                         NSError **error) {
  BOOL hasLimit = [[builder valueForKey:@"hasLimit"] respondsToSelector:@selector(boolValue)] &&
                  [[builder valueForKey:@"hasLimit"] boolValue];
  BOOL hasOffset = [[builder valueForKey:@"hasOffset"] respondsToSelector:@selector(boolValue)] &&
                   [[builder valueForKey:@"hasOffset"] boolValue];
  if (!hasLimit && !hasOffset) {
    return sql ?: @"";
  }

  if (builder.kind != ALNSQLBuilderKindSelect) {
    if (error != NULL) {
      *error = ALNMSSQLDialectError(ALNSQLBuilderErrorCompileFailed,
                                    @"MSSQL pagination translation only applies to SELECT builders",
                                    @"pagination");
    }
    return nil;
  }

  NSUInteger limitValue = [[[builder valueForKey:@"limitValue"] description] integerValue];
  NSUInteger offsetValue = [[[builder valueForKey:@"offsetValue"] description] integerValue];
  NSString *rewritten = ALNMSSQLRemoveLimitOffsetSuffix(sql, hasLimit, hasOffset);
  NSMutableString *composed = [NSMutableString stringWithString:rewritten ?: @""];
  [composed appendFormat:@" OFFSET %lu ROWS", (unsigned long)(hasOffset ? offsetValue : 0)];
  if (hasLimit) {
    [composed appendFormat:@" FETCH NEXT %lu ROWS ONLY", (unsigned long)limitValue];
  }
  return [NSString stringWithString:composed];
}

static NSDictionary *ALNMSSQLCompileBuilder(ALNSQLBuilder *builder,
                                            BOOL finalizeOutput,
                                            NSError **error) {
  if (ALNMSSQLBuilderUsesUnsupportedFeatures(builder, error)) {
    return nil;
  }

  NSError *baseError = nil;
  NSDictionary *base = [builder aln_buildDefaultDialectWithDialectContext:[ALNMSSQLDialect sharedDialect]
                                                                    error:&baseError];
  if (base == nil) {
    if (error != NULL) {
      *error = baseError;
    }
    return nil;
  }

  NSString *sql = [base[@"sql"] isKindOfClass:[NSString class]] ? base[@"sql"] : @"";
  NSArray *parameters = [base[@"parameters"] isKindOfClass:[NSArray class]] ? base[@"parameters"] : @[];

  if ([sql hasPrefix:@"WITH RECURSIVE "]) {
    sql = [@"WITH " stringByAppendingString:[sql substringFromIndex:[@"WITH RECURSIVE " length]]];
  }

  sql = ALNMSSQLApplyReturningClause(builder, sql, error);
  if (sql == nil) {
    return nil;
  }
  sql = ALNMSSQLApplyPagination(builder, sql, error);
  if (sql == nil) {
    return nil;
  }

  if (!finalizeOutput) {
    return @{
      @"sql" : sql ?: @"",
      @"parameters" : parameters ?: @[],
    };
  }

  NSError *quoteError = nil;
  NSString *quotedSQL = ALNMSSQLConvertQuotedIdentifiers(sql, &quoteError);
  if (quotedSQL == nil) {
    if (error != NULL) {
      *error = quoteError;
    }
    return nil;
  }

  return @{
    @"sql" : ALNMSSQLConvertPlaceholders(quotedSQL ?: @""),
    @"parameters" : parameters ?: @[],
  };
}

@implementation ALNMSSQLDialect

+ (instancetype)sharedDialect {
  static ALNMSSQLDialect *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[ALNMSSQLDialect alloc] init];
  });
  return shared;
}

- (NSString *)dialectName {
  return @"mssql";
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"dialect" : @"mssql",
    @"supports_transactions" : @YES,
    @"returning_mode" : @"output",
    @"pagination_syntax" : @"offset_fetch",
    @"supports_upsert" : @NO,
    @"conflict_resolution_mode" : @"unsupported",
    @"json_feature_family" : @"json_value_openjson",
    @"supports_cte" : @YES,
    @"supports_recursive_cte" : @YES,
    @"supports_set_operations" : @YES,
    @"supports_window_clauses" : @YES,
    @"supports_lateral_join" : @NO,
    @"supports_for_update" : @NO,
    @"supports_skip_locked" : @NO,
  };
}

- (NSDictionary *)compileBuilder:(ALNSQLBuilder *)builder error:(NSError **)error {
  return ALNMSSQLCompileBuilder(builder, YES, error);
}

- (NSDictionary *)aln_compileNestedBuilder:(ALNSQLBuilder *)builder error:(NSError **)error {
  return ALNMSSQLCompileBuilder(builder, NO, error);
}

- (NSString *)migrationStateTableCreateSQLForTableName:(NSString *)tableName
                                                 error:(NSError **)error {
  if (!ALNSQLDialectIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectMigrationError(@"invalid migration state table name", tableName);
    }
    return nil;
  }

  NSString *quotedTable = ALNSQLDialectBracketQuoteIdentifier(tableName);
  NSString *quotedVersion = ALNSQLDialectBracketQuoteIdentifier(@"version");
  NSString *quotedAppliedAt = ALNSQLDialectBracketQuoteIdentifier(@"applied_at");
  return [NSString stringWithFormat:
                      @"IF OBJECT_ID(N'%@', N'U') IS NULL "
                      @"CREATE TABLE %@ ("
                      @"%@ NVARCHAR(255) NOT NULL PRIMARY KEY,"
                      @"%@ DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()"
                      @")",
                    quotedTable,
                    quotedTable,
                    quotedVersion,
                    quotedAppliedAt];
}

- (NSString *)migrationVersionsSelectSQLForTableName:(NSString *)tableName
                                               error:(NSError **)error {
  if (!ALNSQLDialectIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectMigrationError(@"invalid migration state table name", tableName);
    }
    return nil;
  }
  NSString *quotedTable = ALNSQLDialectBracketQuoteIdentifier(tableName);
  NSString *quotedVersion = ALNSQLDialectBracketQuoteIdentifier(@"version");
  return [NSString stringWithFormat:@"SELECT %@ FROM %@ ORDER BY %@",
                                    quotedVersion,
                                    quotedTable,
                                    quotedVersion];
}

- (NSString *)migrationVersionInsertSQLForTableName:(NSString *)tableName
                                              error:(NSError **)error {
  if (!ALNSQLDialectIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNMSSQLDialectMigrationError(@"invalid migration state table name", tableName);
    }
    return nil;
  }
  NSString *quotedTable = ALNSQLDialectBracketQuoteIdentifier(tableName);
  NSString *quotedVersion = ALNSQLDialectBracketQuoteIdentifier(@"version");
  return [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (?)",
                                    quotedTable,
                                    quotedVersion];
}

@end
