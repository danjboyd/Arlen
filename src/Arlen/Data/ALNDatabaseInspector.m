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

static NSString *ALNDatabaseInspectorRelationKind(id rawRelationKind, id rawTableType) {
  NSString *relationKind = [[ALNDatabaseInspectorTrimmedString(rawRelationKind) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([relationKind isEqualToString:@"table"] || [relationKind isEqualToString:@"view"] ||
      [relationKind isEqualToString:@"materialized_view"]) {
    return relationKind;
  }

  NSString *tableType = [[ALNDatabaseInspectorTrimmedString(rawTableType) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([tableType isEqualToString:@"base table"]) {
    return @"table";
  }
  if ([tableType isEqualToString:@"view"]) {
    return @"view";
  }
  return @"table";
}

static BOOL ALNDatabaseInspectorRelationReadOnly(NSString *relationKind, id rawReadOnly) {
  BOOL fallback = ![relationKind isEqualToString:@"table"];
  return ALNDatabaseInspectorBoolValue(rawReadOnly, fallback);
}

static NSString *ALNDatabaseInspectorConstraintName(id value, NSString *fallbackPrefix, NSDictionary *row) {
  NSString *name = ALNDatabaseInspectorTrimmedString(value);
  if ([name length] > 0) {
    return name;
  }
  NSString *schema = ALNDatabaseInspectorTrimmedString(row[@"schema"]);
  NSString *table = ALNDatabaseInspectorTrimmedString(row[@"table"]);
  return [NSString stringWithFormat:@"%@_%@_%@", fallbackPrefix ?: @"constraint", schema ?: @"", table ?: @""];
}

static NSComparisonResult ALNDatabaseInspectorSchemaTableCompare(NSDictionary *left, NSDictionary *right) {
  NSComparisonResult schemaOrder = [left[@"schema"] compare:right[@"schema"]];
  if (schemaOrder != NSOrderedSame) {
    return schemaOrder;
  }
  return [left[@"table"] compare:right[@"table"]];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNPostgresInspectorNormalizedRelationsFromInspectionRows(
    NSArray<NSDictionary *> *rows,
    NSError **error) {
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
    NSString *relationKind = ALNDatabaseInspectorRelationKind(row[@"relation_kind"], row[@"table_type"]);
    BOOL readOnly = ALNDatabaseInspectorRelationReadOnly(relationKind, row[@"read_only"]);
    if ([schema length] == 0 || [table length] == 0) {
      if (error != NULL) {
        *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidResult,
                                               @"relation inspection row is missing required identifiers",
                                               @{
                                                 @"schema" : schema ?: @"",
                                                 @"table" : table ?: @"",
                                               });
      }
      return nil;
    }

    [normalized addObject:@{
      @"schema" : schema,
      @"table" : table,
      @"relation_kind" : relationKind,
      @"read_only" : @(readOnly),
    }];
  }

  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSComparisonResult tableOrder = ALNDatabaseInspectorSchemaTableCompare(left, right);
    if (tableOrder != NSOrderedSame) {
      return tableOrder;
    }
    return [left[@"relation_kind"] compare:right[@"relation_kind"]];
  }];
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNPostgresInspectorGroupedColumnConstraints(
    NSArray<NSDictionary *> *rows,
    NSString *label,
    NSError **error) {
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

  NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *grouped = [NSMutableDictionary dictionary];
  NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
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
    NSString *constraintName = ALNDatabaseInspectorConstraintName(row[@"constraint_name"], label, row);
    NSString *column = ALNDatabaseInspectorTrimmedString(row[@"column"]);
    NSInteger ordinal = ALNDatabaseInspectorIntegerValue(row[@"ordinal"], [grouped count] + 1);
    if ([schema length] == 0 || [table length] == 0 || [column length] == 0) {
      if (error != NULL) {
        *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidResult,
                                               @"constraint inspection row is missing identifiers",
                                               @{
                                                 @"schema" : schema ?: @"",
                                                 @"table" : table ?: @"",
                                                 @"constraint_name" : constraintName ?: @"",
                                               });
      }
      return nil;
    }

    NSString *groupKey = [NSString stringWithFormat:@"%@.%@.%@", schema, table, constraintName];
    NSMutableDictionary<NSString *, id> *group = grouped[groupKey];
    if (group == nil) {
      group = [@{
        @"schema" : schema,
        @"table" : table,
        @"constraint_name" : constraintName,
        @"columns" : [NSMutableArray array],
      } mutableCopy];
      grouped[groupKey] = group;
      [groupOrder addObject:groupKey];
    }
    NSMutableArray *columns = group[@"columns"];
    [columns addObject:@{
      @"column" : column,
      @"ordinal" : @(ordinal),
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [NSMutableArray arrayWithCapacity:[groupOrder count]];
  for (NSString *groupKey in groupOrder) {
    NSMutableDictionary<NSString *, id> *group = grouped[groupKey];
    NSMutableArray *columns = group[@"columns"];
    [columns sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
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
    NSMutableArray<NSString *> *orderedColumns = [NSMutableArray arrayWithCapacity:[columns count]];
    for (NSDictionary *entry in columns) {
      [orderedColumns addObject:entry[@"column"]];
    }
    [normalized addObject:@{
      @"schema" : group[@"schema"] ?: @"",
      @"table" : group[@"table"] ?: @"",
      @"constraint_name" : group[@"constraint_name"] ?: @"",
      @"columns" : [NSArray arrayWithArray:orderedColumns],
    }];
  }

  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSComparisonResult tableOrder = ALNDatabaseInspectorSchemaTableCompare(left, right);
    if (tableOrder != NSOrderedSame) {
      return tableOrder;
    }
    return [left[@"constraint_name"] compare:right[@"constraint_name"]];
  }];
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNPostgresInspectorNormalizedForeignKeysFromInspectionRows(
    NSArray<NSDictionary *> *rows,
    NSError **error) {
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

  NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *grouped = [NSMutableDictionary dictionary];
  NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
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
    NSString *constraintName = ALNDatabaseInspectorConstraintName(row[@"constraint_name"], @"fk", row);
    NSString *column = ALNDatabaseInspectorTrimmedString(row[@"column"]);
    NSInteger ordinal = ALNDatabaseInspectorIntegerValue(row[@"ordinal"], [grouped count] + 1);
    NSString *referencedSchema = ALNDatabaseInspectorTrimmedString(row[@"referenced_schema"]);
    NSString *referencedTable = ALNDatabaseInspectorTrimmedString(row[@"referenced_table"]);
    NSString *referencedColumn = ALNDatabaseInspectorTrimmedString(row[@"referenced_column"]);

    if ([schema length] == 0 || [table length] == 0 || [column length] == 0 ||
        [referencedSchema length] == 0 || [referencedTable length] == 0 ||
        [referencedColumn length] == 0) {
      if (error != NULL) {
        *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidResult,
                                               @"foreign-key inspection row is missing identifiers",
                                               @{
                                                 @"schema" : schema ?: @"",
                                                 @"table" : table ?: @"",
                                                 @"constraint_name" : constraintName ?: @"",
                                               });
      }
      return nil;
    }

    NSString *groupKey = [NSString stringWithFormat:@"%@.%@.%@", schema, table, constraintName];
    NSMutableDictionary<NSString *, id> *group = grouped[groupKey];
    if (group == nil) {
      group = [@{
        @"schema" : schema,
        @"table" : table,
        @"constraint_name" : constraintName,
        @"referenced_schema" : referencedSchema,
        @"referenced_table" : referencedTable,
        @"column_pairs" : [NSMutableArray array],
      } mutableCopy];
      grouped[groupKey] = group;
      [groupOrder addObject:groupKey];
    }
    NSMutableArray *pairs = group[@"column_pairs"];
    [pairs addObject:@{
      @"column" : column,
      @"referenced_column" : referencedColumn,
      @"ordinal" : @(ordinal),
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [NSMutableArray arrayWithCapacity:[groupOrder count]];
  for (NSString *groupKey in groupOrder) {
    NSMutableDictionary<NSString *, id> *group = grouped[groupKey];
    NSMutableArray *pairs = group[@"column_pairs"];
    [pairs sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
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

    NSMutableArray<NSString *> *columns = [NSMutableArray arrayWithCapacity:[pairs count]];
    NSMutableArray<NSString *> *referencedColumns = [NSMutableArray arrayWithCapacity:[pairs count]];
    for (NSDictionary *pair in pairs) {
      [columns addObject:pair[@"column"]];
      [referencedColumns addObject:pair[@"referenced_column"]];
    }

    [normalized addObject:@{
      @"schema" : group[@"schema"] ?: @"",
      @"table" : group[@"table"] ?: @"",
      @"constraint_name" : group[@"constraint_name"] ?: @"",
      @"columns" : [NSArray arrayWithArray:columns],
      @"referenced_schema" : group[@"referenced_schema"] ?: @"",
      @"referenced_table" : group[@"referenced_table"] ?: @"",
      @"referenced_columns" : [NSArray arrayWithArray:referencedColumns],
    }];
  }

  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSComparisonResult tableOrder = ALNDatabaseInspectorSchemaTableCompare(left, right);
    if (tableOrder != NSOrderedSame) {
      return tableOrder;
    }
    return [left[@"constraint_name"] compare:right[@"constraint_name"]];
  }];
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNPostgresInspectorNormalizedIndexesFromInspectionRows(
    NSArray<NSDictionary *> *rows,
    NSError **error) {
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

  NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *grouped = [NSMutableDictionary dictionary];
  NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
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
    NSString *indexName = ALNDatabaseInspectorTrimmedString(row[@"index_name"]);
    NSString *column = ALNDatabaseInspectorTrimmedString(row[@"column"]);
    NSInteger ordinal = ALNDatabaseInspectorIntegerValue(row[@"ordinal"], [grouped count] + 1);
    BOOL unique = ALNDatabaseInspectorBoolValue(row[@"is_unique"], NO);
    BOOL primaryKey = ALNDatabaseInspectorBoolValue(row[@"is_primary"], NO);

    if ([schema length] == 0 || [table length] == 0 || [indexName length] == 0 || [column length] == 0) {
      if (error != NULL) {
        *error = ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInvalidResult,
                                               @"index inspection row is missing identifiers",
                                               @{
                                                 @"schema" : schema ?: @"",
                                                 @"table" : table ?: @"",
                                                 @"index_name" : indexName ?: @"",
                                               });
      }
      return nil;
    }

    NSString *groupKey = [NSString stringWithFormat:@"%@.%@.%@", schema, table, indexName];
    NSMutableDictionary<NSString *, id> *group = grouped[groupKey];
    if (group == nil) {
      group = [@{
        @"schema" : schema,
        @"table" : table,
        @"index_name" : indexName,
        @"is_unique" : @(unique),
        @"is_primary" : @(primaryKey),
        @"columns" : [NSMutableArray array],
      } mutableCopy];
      grouped[groupKey] = group;
      [groupOrder addObject:groupKey];
    }
    NSMutableArray *columns = group[@"columns"];
    [columns addObject:@{
      @"column" : column,
      @"ordinal" : @(ordinal),
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [NSMutableArray arrayWithCapacity:[groupOrder count]];
  for (NSString *groupKey in groupOrder) {
    NSMutableDictionary<NSString *, id> *group = grouped[groupKey];
    NSMutableArray *columns = group[@"columns"];
    [columns sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
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
    NSMutableArray<NSString *> *orderedColumns = [NSMutableArray arrayWithCapacity:[columns count]];
    for (NSDictionary *entry in columns) {
      [orderedColumns addObject:entry[@"column"]];
    }
    [normalized addObject:@{
      @"schema" : group[@"schema"] ?: @"",
      @"table" : group[@"table"] ?: @"",
      @"index_name" : group[@"index_name"] ?: @"",
      @"is_unique" : group[@"is_unique"] ?: @NO,
      @"is_primary" : group[@"is_primary"] ?: @NO,
      @"columns" : [NSArray arrayWithArray:orderedColumns],
    }];
  }

  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSComparisonResult tableOrder = ALNDatabaseInspectorSchemaTableCompare(left, right);
    if (tableOrder != NSOrderedSame) {
      return tableOrder;
    }
    return [left[@"index_name"] compare:right[@"index_name"]];
  }];
  return [NSArray arrayWithArray:normalized];
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

+ (nullable NSDictionary<NSString *, id> *)inspectSchemaMetadataForAdapter:(id<ALNDatabaseAdapter>)adapter
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
    return [ALNPostgresInspector inspectSchemaMetadataWithAdapter:adapter error:error];
  }

  if ([adapter respondsToSelector:@selector(sqlDialect)]) {
    id dialect = [adapter sqlDialect];
    NSString *dialectClassName = NSStringFromClass([dialect class]) ?: @"";
    if ([dialectClassName isEqualToString:@"ALNPostgresDialect"]) {
      return [ALNPostgresInspector inspectSchemaMetadataWithAdapter:adapter error:error];
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
      @"WITH relations AS ("
       "  SELECT n.nspname AS schema, "
       "         c.relname AS table_name, "
       "         CASE c.relkind "
       "           WHEN 'r' THEN 'table' "
       "           WHEN 'v' THEN 'view' "
       "           WHEN 'm' THEN 'materialized_view' "
       "           ELSE 'table' "
       "         END AS relation_kind, "
       "         CASE c.relkind WHEN 'r' THEN FALSE ELSE TRUE END AS read_only "
       "  FROM pg_catalog.pg_class c "
       "  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace "
       "  WHERE c.relkind IN ('r', 'v', 'm') "
       "    AND n.nspname NOT IN ('pg_catalog', 'information_schema')"
       ") "
       "SELECT c.table_schema AS schema, "
       "       c.table_name AS table, "
       "       relations.relation_kind AS relation_kind, "
       "       relations.read_only AS read_only, "
       "       c.column_name AS column, "
       "       c.ordinal_position AS ordinal, "
       "       CASE "
       "         WHEN c.data_type = 'ARRAY' THEN COALESCE(pg_catalog.format_type(a.atttypid, a.atttypmod), c.udt_name) "
       "         ELSE c.data_type "
       "       END AS data_type, "
       "       CASE WHEN c.is_nullable = 'YES' THEN TRUE ELSE FALSE END AS nullable, "
       "       CASE WHEN pk.constraint_name IS NOT NULL THEN TRUE ELSE FALSE END AS primary_key, "
       "       CASE WHEN c.is_identity = 'YES' OR c.column_default IS NOT NULL THEN TRUE ELSE FALSE END AS has_default, "
       "       CASE "
       "         WHEN c.is_identity = 'YES' THEN 'identity' "
       "         WHEN c.column_default IS NULL THEN 'none' "
       "         WHEN c.column_default LIKE 'nextval(%' THEN 'sequence' "
       "         WHEN c.column_default ~ $$^[[:space:]]*[-+]?[0-9]+([.][0-9]+)?[[:space:]]*$$ "
       "           OR lower(c.column_default) IN ('true', 'false') "
       "           OR c.column_default ~ $$^'.*'(::[A-Za-z0-9_\".\\[\\] ]+)?$$ "
       "           THEN 'literal' "
       "         ELSE 'expression' "
       "       END AS default_value_shape "
       "FROM information_schema.columns c "
       "JOIN relations "
       "  ON relations.schema = c.table_schema "
       " AND relations.table_name = c.table_name "
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
       "LEFT JOIN pg_catalog.pg_namespace nsp "
       "  ON nsp.nspname = c.table_schema "
       "LEFT JOIN pg_catalog.pg_class cls "
       "  ON cls.relnamespace = nsp.oid "
       " AND cls.relname = c.table_name "
       "LEFT JOIN pg_catalog.pg_attribute a "
       "  ON a.attrelid = cls.oid "
       " AND a.attname = c.column_name "
       " AND a.attnum > 0 "
       " AND NOT a.attisdropped "
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
    NSString *relationKind = ALNDatabaseInspectorRelationKind(row[@"relation_kind"], row[@"table_type"]);
    BOOL readOnly = ALNDatabaseInspectorRelationReadOnly(relationKind, row[@"read_only"]);
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
      @"relation_kind" : relationKind,
      @"read_only" : @(readOnly),
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
    NSComparisonResult tableOrder = ALNDatabaseInspectorSchemaTableCompare(left, right);
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

+ (nullable NSDictionary<NSString *, id> *)inspectSchemaMetadataWithAdapter:(id<ALNDatabaseAdapter>)adapter
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

  NSString *relationsSQL =
      @"SELECT n.nspname AS schema, "
       "       c.relname AS table, "
       "       CASE c.relkind "
       "         WHEN 'r' THEN 'table' "
       "         WHEN 'v' THEN 'view' "
       "         WHEN 'm' THEN 'materialized_view' "
       "         ELSE 'table' "
       "       END AS relation_kind, "
       "       CASE c.relkind WHEN 'r' THEN FALSE ELSE TRUE END AS read_only "
       "FROM pg_catalog.pg_class c "
       "JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace "
       "WHERE c.relkind IN ('r', 'v', 'm') "
       "  AND n.nspname NOT IN ('pg_catalog', 'information_schema') "
       "ORDER BY n.nspname, c.relname";

  NSString *primaryKeysSQL =
      @"SELECT tc.table_schema AS schema, "
       "       tc.table_name AS table, "
       "       tc.constraint_name AS constraint_name, "
       "       kcu.column_name AS column, "
       "       kcu.ordinal_position AS ordinal "
       "FROM information_schema.table_constraints tc "
       "JOIN information_schema.key_column_usage kcu "
       "  ON kcu.constraint_schema = tc.constraint_schema "
       " AND kcu.constraint_name = tc.constraint_name "
       " AND kcu.table_schema = tc.table_schema "
       " AND kcu.table_name = tc.table_name "
       "WHERE tc.constraint_type = 'PRIMARY KEY' "
       "  AND tc.table_schema NOT IN ('pg_catalog', 'information_schema') "
       "ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position, kcu.column_name";

  NSString *uniqueConstraintsSQL =
      @"SELECT tc.table_schema AS schema, "
       "       tc.table_name AS table, "
       "       tc.constraint_name AS constraint_name, "
       "       kcu.column_name AS column, "
       "       kcu.ordinal_position AS ordinal "
       "FROM information_schema.table_constraints tc "
       "JOIN information_schema.key_column_usage kcu "
       "  ON kcu.constraint_schema = tc.constraint_schema "
       " AND kcu.constraint_name = tc.constraint_name "
       " AND kcu.table_schema = tc.table_schema "
       " AND kcu.table_name = tc.table_name "
       "WHERE tc.constraint_type = 'UNIQUE' "
       "  AND tc.table_schema NOT IN ('pg_catalog', 'information_schema') "
       "ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position, kcu.column_name";

  NSString *foreignKeysSQL =
      @"SELECT src_ns.nspname AS schema, "
       "       src.relname AS table, "
       "       con.conname AS constraint_name, "
       "       src_att.attname AS column, "
       "       src_cols.ordinality AS ordinal, "
       "       ref_ns.nspname AS referenced_schema, "
       "       ref.relname AS referenced_table, "
       "       ref_att.attname AS referenced_column "
       "FROM pg_catalog.pg_constraint con "
       "JOIN pg_catalog.pg_class src ON src.oid = con.conrelid "
       "JOIN pg_catalog.pg_namespace src_ns ON src_ns.oid = src.relnamespace "
       "JOIN pg_catalog.pg_class ref ON ref.oid = con.confrelid "
       "JOIN pg_catalog.pg_namespace ref_ns ON ref_ns.oid = ref.relnamespace "
       "JOIN unnest(con.conkey) WITH ORDINALITY AS src_cols(attnum, ordinality) ON TRUE "
       "JOIN unnest(con.confkey) WITH ORDINALITY AS ref_cols(attnum, ordinality) "
       "  ON ref_cols.ordinality = src_cols.ordinality "
       "JOIN pg_catalog.pg_attribute src_att "
       "  ON src_att.attrelid = src.oid "
       " AND src_att.attnum = src_cols.attnum "
       "JOIN pg_catalog.pg_attribute ref_att "
       "  ON ref_att.attrelid = ref.oid "
       " AND ref_att.attnum = ref_cols.attnum "
       "WHERE con.contype = 'f' "
       "  AND src_ns.nspname NOT IN ('pg_catalog', 'information_schema') "
       "ORDER BY src_ns.nspname, src.relname, con.conname, src_cols.ordinality";

  NSString *indexesSQL =
      @"SELECT ns.nspname AS schema, "
       "       tbl.relname AS table, "
       "       idx.relname AS index_name, "
       "       i.indisunique AS is_unique, "
       "       i.indisprimary AS is_primary, "
       "       att.attname AS column, "
       "       cols.ordinality AS ordinal "
       "FROM pg_catalog.pg_index i "
       "JOIN pg_catalog.pg_class tbl ON tbl.oid = i.indrelid "
       "JOIN pg_catalog.pg_namespace ns ON ns.oid = tbl.relnamespace "
       "JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid "
       "JOIN unnest(i.indkey) WITH ORDINALITY AS cols(attnum, ordinality) ON cols.attnum > 0 "
       "JOIN pg_catalog.pg_attribute att "
       "  ON att.attrelid = tbl.oid "
       " AND att.attnum = cols.attnum "
       "WHERE ns.nspname NOT IN ('pg_catalog', 'information_schema') "
       "  AND tbl.relkind IN ('r', 'm', 'v') "
       "ORDER BY ns.nspname, tbl.relname, idx.relname, cols.ordinality";

  NSError *queryError = nil;
  NSArray<NSDictionary *> *relationRows = [adapter executeQuery:relationsSQL parameters:@[] error:&queryError];
  if (relationRows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"relation inspection query failed",
                                                           nil);
    }
    return nil;
  }

  NSArray<NSDictionary *> *columnRows = [self inspectSchemaColumnsWithAdapter:adapter error:&queryError];
  if (columnRows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"column inspection query failed",
                                                           nil);
    }
    return nil;
  }

  NSArray<NSDictionary *> *primaryKeyRows = [adapter executeQuery:primaryKeysSQL parameters:@[] error:&queryError];
  if (primaryKeyRows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"primary-key inspection query failed",
                                                           nil);
    }
    return nil;
  }

  NSArray<NSDictionary *> *uniqueConstraintRows =
      [adapter executeQuery:uniqueConstraintsSQL parameters:@[] error:&queryError];
  if (uniqueConstraintRows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"unique-constraint inspection query failed",
                                                           nil);
    }
    return nil;
  }

  NSArray<NSDictionary *> *foreignKeyRows = [adapter executeQuery:foreignKeysSQL parameters:@[] error:&queryError];
  if (foreignKeyRows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"foreign-key inspection query failed",
                                                           nil);
    }
    return nil;
  }

  NSArray<NSDictionary *> *indexRows = [adapter executeQuery:indexesSQL parameters:@[] error:&queryError];
  if (indexRows == nil) {
    if (error != NULL) {
      *error = queryError ?: ALNDatabaseInspectorMakeError(ALNDatabaseInspectorErrorInspectionFailed,
                                                           @"index inspection query failed",
                                                           nil);
    }
    return nil;
  }

  NSError *normalizeError = nil;
  NSArray<NSDictionary<NSString *, id> *> *relations =
      ALNPostgresInspectorNormalizedRelationsFromInspectionRows(relationRows, &normalizeError);
  if (relations == nil) {
    if (error != NULL) {
      *error = normalizeError;
    }
    return nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *primaryKeys =
      ALNPostgresInspectorGroupedColumnConstraints(primaryKeyRows, @"pk", &normalizeError);
  if (primaryKeys == nil) {
    if (error != NULL) {
      *error = normalizeError;
    }
    return nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *uniqueConstraints =
      ALNPostgresInspectorGroupedColumnConstraints(uniqueConstraintRows, @"uq", &normalizeError);
  if (uniqueConstraints == nil) {
    if (error != NULL) {
      *error = normalizeError;
    }
    return nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *foreignKeys =
      ALNPostgresInspectorNormalizedForeignKeysFromInspectionRows(foreignKeyRows, &normalizeError);
  if (foreignKeys == nil) {
    if (error != NULL) {
      *error = normalizeError;
    }
    return nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *indexes =
      ALNPostgresInspectorNormalizedIndexesFromInspectionRows(indexRows, &normalizeError);
  if (indexes == nil) {
    if (error != NULL) {
      *error = normalizeError;
    }
    return nil;
  }

  return @{
    @"reflection_contract_version" : @2,
    @"adapter" : @"postgresql",
    @"relations" : relations ?: @[],
    @"columns" : columnRows ?: @[],
    @"primary_keys" : primaryKeys ?: @[],
    @"unique_constraints" : uniqueConstraints ?: @[],
    @"foreign_keys" : foreignKeys ?: @[],
    @"indexes" : indexes ?: @[],
  };
}

@end
