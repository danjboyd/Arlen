#import "ALNDatabaseInspector.h"

NSString *const ALNDatabaseInspectorErrorDomain = @"Arlen.Data.Inspector.Error";

static NSError *ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorCode code,
                                              NSString *message,
                                              NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"database inspector error";
  return [NSError errorWithDomain:ALNDatabaseInspectorErrorDomain
                             code:code
                         userInfo:details];
}

static NSString *ALNDatabaseInspectorTrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static NSInteger ALNDatabaseInspectorIntegerValue(id value, NSInteger fallback) {
  if ([value respondsToSelector:@selector(integerValue)]) {
    NSInteger parsed = [value integerValue];
    return (parsed > 0) ? parsed : fallback;
  }
  return fallback;
}

static BOOL ALNDatabaseInspectorBoolValue(id value, BOOL fallback) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }

  NSString *text = [[ALNDatabaseInspectorTrimmedString(value) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text length] == 0) {
    return fallback;
  }
  if ([text isEqualToString:@"1"] || [text isEqualToString:@"true"] || [text isEqualToString:@"t"] ||
      [text isEqualToString:@"yes"] || [text isEqualToString:@"y"]) {
    return YES;
  }
  if ([text isEqualToString:@"0"] || [text isEqualToString:@"false"] || [text isEqualToString:@"f"] ||
      [text isEqualToString:@"no"] || [text isEqualToString:@"n"]) {
    return NO;
  }
  return fallback;
}

static NSString *ALNPostgresInspectorDefaultValueShape(id value, BOOL hasDefault) {
  NSString *shape = [[ALNDatabaseInspectorTrimmedString(value) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([shape isEqualToString:@"literal"] || [shape isEqualToString:@"expression"] ||
      [shape isEqualToString:@"sequence"] || [shape isEqualToString:@"identity"]) {
    return shape;
  }
  return hasDefault ? @"expression" : @"none";
}

@implementation ALNDatabaseInspector

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)inspectSchemaColumnsForAdapter:(id<ALNDatabaseAdapter>)adapter
                                                                               error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (adapter == nil || ![adapter conformsToProtocol:@protocol(ALNDatabaseAdapter)]) {
    if (error != NULL) {
      *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidArgument,
                                             @"database adapter is required",
                                             nil);
    }
    return nil;
  }

  NSString *adapterName = [[adapter adapterName] lowercaseString];
  if ([adapterName isEqualToString:@"postgresql"]) {
    return [ALNPostgresInspector inspectSchemaColumnsWithAdapter:adapter error:error];
  }

  if ([adapter respondsToSelector:@selector(sqlDialect)]) {
    id dialect = [adapter sqlDialect];
    NSString *dialectClassName = NSStringFromClass([dialect class]) ?: @"";
    if ([dialectClassName isEqualToString:@"ALNPostgresDialect"]) {
      return [ALNPostgresInspector inspectSchemaColumnsWithAdapter:adapter error:error];
    }
  }

  if (error != NULL) {
    *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorUnsupportedAdapter,
                                           @"database inspector does not support this adapter",
                                           @{ @"adapter" : adapterName ?: @"" });
  }
  return nil;
}

@end

@implementation ALNPostgresInspector

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)inspectSchemaColumnsWithAdapter:(id<ALNDatabaseAdapter>)adapter
                                                                                error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (adapter == nil) {
    if (error != NULL) {
      *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidArgument,
                                             @"database adapter is required",
                                             nil);
    }
    return nil;
  }

  NSString *sql =
      @"SELECT c.table_schema AS schema, "
       "       c.table_name AS table, "
       "       c.column_name AS column, "
       "       c.ordinal_position AS ordinal, "
       "       c.data_type AS data_type, "
       "       CASE WHEN c.is_nullable = 'YES' THEN TRUE ELSE FALSE END AS nullable, "
       "       CASE WHEN pk.constraint_name IS NOT NULL THEN TRUE ELSE FALSE END AS primary_key, "
       "       CASE WHEN c.is_identity = 'YES' OR c.column_default IS NOT NULL THEN TRUE ELSE FALSE END AS has_default, "
       "       CASE "
       "         WHEN c.is_identity = 'YES' THEN 'identity' "
       "         WHEN c.column_default IS NULL THEN 'none' "
       "         WHEN c.column_default LIKE 'nextval(%' THEN 'sequence' "
       "         WHEN c.column_default ~ $$^[[:space:]]*[-+]?[0-9]+([.][0-9]+)?[[:space:]]*$$ "
       "           OR lower(c.column_default) IN ('true', 'false') "
       "           OR c.column_default ~ $$^'.*'(::[A-Za-z0-9_\". ]+)?$$ "
       "           THEN 'literal' "
       "         ELSE 'expression' "
       "       END AS default_value_shape "
       "FROM information_schema.columns c "
       "JOIN information_schema.tables t "
       "  ON t.table_schema = c.table_schema "
       " AND t.table_name = c.table_name "
       "LEFT JOIN ("
       "  SELECT kcu.table_schema, kcu.table_name, kcu.column_name, tc.constraint_name "
       "  FROM information_schema.table_constraints tc "
       "  JOIN information_schema.key_column_usage kcu "
       "    ON kcu.constraint_schema = tc.constraint_schema "
       "   AND kcu.constraint_name = tc.constraint_name "
       "   AND kcu.table_schema = tc.table_schema "
       "   AND kcu.table_name = tc.table_name "
       "  WHERE tc.constraint_type = 'PRIMARY KEY'"
       ") pk "
       "  ON pk.table_schema = c.table_schema "
       " AND pk.table_name = c.table_name "
       " AND pk.column_name = c.column_name "
       "WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema') "
       "  AND t.table_type IN ('BASE TABLE', 'VIEW') "
       "ORDER BY c.table_schema, c.table_name, c.ordinal_position, c.column_name";

  NSError *queryError = nil;
  NSArray<NSDictionary *> *rows = [adapter executeQuery:sql parameters:@[] error:&queryError];
  if (rows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"schema inspection query failed",
                                                           nil);
    }
    return nil;
  }

  return [self normalizedColumnsFromInspectionRows:rows error:error];
}

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)normalizedColumnsFromInspectionRows:(NSArray<NSDictionary *> *)rows
                                                                                     error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![rows isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidArgument,
                                             @"inspection rows must be an array",
                                             nil);
    }
    return nil;
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *normalized =
      [NSMutableArray arrayWithCapacity:[rows count]];
  NSInteger fallbackOrdinal = 1;
  for (id rawRow in rows) {
    if (![rawRow isKindOfClass:[NSDictionary class]]) {
      if (error != NULL) {
        *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidResult,
                                               @"inspection row must be a dictionary",
                                               @{ @"row" : [rawRow description] ?: @"" });
      }
      return nil;
    }

    NSDictionary *row = (NSDictionary *)rawRow;
    NSString *schema = ALNDatabaseInspectorTrimmedString(row[@"schema"]);
    NSString *table = ALNDatabaseInspectorTrimmedString(row[@"table"]);
    NSString *column = ALNDatabaseInspectorTrimmedString(row[@"column"]);
    NSString *dataType = ALNDatabaseInspectorTrimmedString(row[@"data_type"]);
    NSInteger ordinal = ALNDatabaseInspectorIntegerValue(row[@"ordinal"], fallbackOrdinal);
    fallbackOrdinal += 1;

    if ([schema length] == 0 || [table length] == 0 || [column length] == 0) {
      if (error != NULL) {
        *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidResult,
                                               @"inspection row is missing required identifiers",
                                               @{
                                                 @"schema" : schema ?: @"",
                                                 @"table" : table ?: @"",
                                                 @"column" : column ?: @"",
                                               });
      }
      return nil;
    }
    if ([dataType length] == 0) {
      dataType = @"text";
    }

    BOOL nullable = ALNDatabaseInspectorBoolValue(row[@"nullable"], YES);
    BOOL primaryKey = ALNDatabaseInspectorBoolValue(row[@"primary_key"], NO);
    BOOL hasDefault = ALNDatabaseInspectorBoolValue(row[@"has_default"], NO);
    NSString *defaultValueShape =
        ALNPostgresInspectorDefaultValueShape(row[@"default_value_shape"], hasDefault);

    [normalized addObject:@{
      @"schema" : schema,
      @"table" : table,
      @"column" : column,
      @"ordinal" : @(ordinal),
      @"data_type" : dataType,
      @"nullable" : @(nullable),
      @"primary_key" : @(primaryKey),
      @"has_default" : @(hasDefault),
      @"default_value_shape" : defaultValueShape,
    }];
  }

  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSComparisonResult schemaOrder = [left[@"schema"] compare:right[@"schema"]];
    if (schemaOrder != NSOrderedSame) {
      return schemaOrder;
    }
    NSComparisonResult tableOrder = [left[@"table"] compare:right[@"table"]];
    if (tableOrder != NSOrderedSame) {
      return tableOrder;
    }
    NSInteger leftOrdinal = [left[@"ordinal"] integerValue];
    NSInteger rightOrdinal = [right[@"ordinal"] integerValue];
    if (leftOrdinal < rightOrdinal) {
      return NSOrderedAscending;
    }
    if (leftOrdinal > rightOrdinal) {
      return NSOrderedDescending;
    }
    return [left[@"column"] compare:right[@"column"]];
  }];

  return [NSArray arrayWithArray:normalized];
}

@end
