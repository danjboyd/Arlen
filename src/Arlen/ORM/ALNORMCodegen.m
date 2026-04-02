#import "ALNORMCodegen.h"

#import "ALNORMErrors.h"

typedef NS_ENUM(NSInteger, ALNORMFieldTypeKind) {
  ALNORMFieldTypeKindOther = 0,
  ALNORMFieldTypeKindArray = 1,
  ALNORMFieldTypeKindJSON = 2,
};

static NSString *ALNORMCodegenStringValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNORMCodegenBoolValue(id value, BOOL fallback) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *text = [[ALNORMCodegenStringValue(value) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text length] == 0) {
    return fallback;
  }
  if ([text isEqualToString:@"yes"] || [text isEqualToString:@"true"] || [text isEqualToString:@"1"] ||
      [text isEqualToString:@"t"] || [text isEqualToString:@"y"]) {
    return YES;
  }
  if ([text isEqualToString:@"no"] || [text isEqualToString:@"false"] || [text isEqualToString:@"0"] ||
      [text isEqualToString:@"f"] || [text isEqualToString:@"n"]) {
    return NO;
  }
  return fallback;
}

static NSInteger ALNORMCodegenIntegerValue(id value, NSInteger fallback) {
  return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

static BOOL ALNORMCodegenIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [value characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

static NSString *ALNORMCodegenPascalSuffix(NSString *identifier) {
  NSArray *parts = [identifier componentsSeparatedByString:@"_"];
  NSMutableString *suffix = [NSMutableString string];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSString *lower = [part lowercaseString];
    NSString *first = [[lower substringToIndex:1] uppercaseString];
    NSString *rest = ([lower length] > 1) ? [lower substringFromIndex:1] : @"";
    [suffix appendFormat:@"%@%@", first, rest];
  }
  if ([suffix length] == 0) {
    [suffix appendString:@"Value"];
  }
  unichar first = [suffix characterAtIndex:0];
  if (![[NSCharacterSet letterCharacterSet] characterIsMember:first] && first != '_') {
    [suffix insertString:@"N" atIndex:0];
  }
  return [NSString stringWithString:suffix];
}

static NSString *ALNORMCodegenCamelCase(NSString *identifier) {
  NSString *pascal = ALNORMCodegenPascalSuffix(identifier);
  if ([pascal length] == 0) {
    return @"value";
  }
  NSString *first = [[pascal substringToIndex:1] lowercaseString];
  NSString *rest = ([pascal length] > 1) ? [pascal substringFromIndex:1] : @"";
  return [NSString stringWithFormat:@"%@%@", first, rest];
}

static NSString *ALNORMCodegenSingularize(NSString *identifier) {
  NSString *value = [[identifier isKindOfClass:[NSString class]] ? identifier : @""
      lowercaseString];
  if ([value hasSuffix:@"ies"] && [value length] > 3) {
    return [[value substringToIndex:[value length] - 3] stringByAppendingString:@"y"];
  }
  if ([value hasSuffix:@"s"] && [value length] > 1) {
    return [value substringToIndex:[value length] - 1];
  }
  return value;
}

static NSString *ALNORMCodegenPluralize(NSString *identifier) {
  NSString *value = [[identifier isKindOfClass:[NSString class]] ? identifier : @""
      lowercaseString];
  if ([value hasSuffix:@"y"] && [value length] > 1) {
    unichar previous = [value characterAtIndex:[value length] - 2];
    if (![[NSCharacterSet characterSetWithCharactersInString:@"aeiou"] characterIsMember:previous]) {
      return [[value substringToIndex:[value length] - 1] stringByAppendingString:@"ies"];
    }
  }
  if ([value hasSuffix:@"s"]) {
    return value;
  }
  return [value stringByAppendingString:@"s"];
}

static NSString *ALNORMCodegenQualifiedEntityName(NSString *schema, NSString *table) {
  return [NSString stringWithFormat:@"%@.%@", schema ?: @"", table ?: @""];
}

static NSString *ALNORMCodegenQualifiedTableName(NSString *schema, NSString *table) {
  if ([[schema lowercaseString] isEqualToString:@"public"]) {
    return table ?: @"";
  }
  return ALNORMCodegenQualifiedEntityName(schema, table);
}

static NSArray<NSString *> *ALNORMCodegenNormalizedStringArray(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray *items = [NSMutableArray array];
  for (id rawItem in value) {
    NSString *string = ALNORMCodegenStringValue(rawItem);
    if ([string length] > 0) {
      [items addObject:string];
    }
  }
  return items;
}

static NSArray<NSString *> *ALNORMCodegenSortedUniqueStrings(NSArray<NSString *> *strings) {
  NSOrderedSet *ordered = [NSOrderedSet orderedSetWithArray:strings ?: @[]];
  return [[ordered array] sortedArrayUsingSelector:@selector(compare:)];
}

static NSDictionary<NSString *, NSString *> *ALNORMCodegenTypeDescriptor(NSString *dataType,
                                                                         ALNORMFieldTypeKind *kindOut) {
  NSString *normalized = [[ALNORMCodegenStringValue(dataType) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized hasSuffix:@"[]"]) {
    if (kindOut != NULL) {
      *kindOut = ALNORMFieldTypeKindArray;
    }
    return @{
      @"objcType" : @"NSArray *",
      @"runtimeClass" : @"NSArray",
      @"propertyAttribute" : @"copy",
    };
  }
  if ([normalized isEqualToString:@"smallint"] || [normalized isEqualToString:@"integer"] ||
      [normalized isEqualToString:@"bigint"] || [normalized isEqualToString:@"numeric"] ||
      [normalized isEqualToString:@"decimal"] || [normalized isEqualToString:@"real"] ||
      [normalized isEqualToString:@"double precision"] || [normalized isEqualToString:@"boolean"]) {
    if (kindOut != NULL) {
      *kindOut = ALNORMFieldTypeKindOther;
    }
    return @{
      @"objcType" : @"NSNumber *",
      @"runtimeClass" : @"NSNumber",
      @"propertyAttribute" : @"strong",
    };
  }
  if ([normalized isEqualToString:@"bytea"]) {
    if (kindOut != NULL) {
      *kindOut = ALNORMFieldTypeKindOther;
    }
    return @{
      @"objcType" : @"NSData *",
      @"runtimeClass" : @"NSData",
      @"propertyAttribute" : @"copy",
    };
  }
  if ([normalized isEqualToString:@"json"] || [normalized isEqualToString:@"jsonb"]) {
    if (kindOut != NULL) {
      *kindOut = ALNORMFieldTypeKindJSON;
    }
    return @{
      @"objcType" : @"id",
      @"runtimeClass" : @"",
      @"propertyAttribute" : @"strong",
    };
  }
  if ([normalized hasPrefix:@"timestamp"] || [normalized isEqualToString:@"date"]) {
    if (kindOut != NULL) {
      *kindOut = ALNORMFieldTypeKindOther;
    }
    return @{
      @"objcType" : @"NSDate *",
      @"runtimeClass" : @"NSDate",
      @"propertyAttribute" : @"copy",
    };
  }
  if ([normalized isEqualToString:@"uuid"] || [normalized isEqualToString:@"text"] ||
      [normalized hasPrefix:@"character"] || [normalized hasSuffix:@"time zone"] ||
      [normalized isEqualToString:@"time"] || [normalized isEqualToString:@"inet"] ||
      [normalized isEqualToString:@"cidr"] || [normalized isEqualToString:@"macaddr"]) {
    if (kindOut != NULL) {
      *kindOut = ALNORMFieldTypeKindOther;
    }
    return @{
      @"objcType" : @"NSString *",
      @"runtimeClass" : @"NSString",
      @"propertyAttribute" : @"copy",
    };
  }
  if (kindOut != NULL) {
    *kindOut = ALNORMFieldTypeKindOther;
  }
  return @{
    @"objcType" : @"id",
    @"runtimeClass" : @"",
    @"propertyAttribute" : @"strong",
  };
}

static NSString *ALNORMCodegenUniqueRelationName(NSString *baseName,
                                                 NSMutableSet<NSString *> *usedNames) {
  NSString *candidate = ([baseName length] > 0) ? baseName : @"relation";
  NSUInteger suffix = 2;
  while ([usedNames containsObject:candidate]) {
    candidate = [NSString stringWithFormat:@"%@%lu", baseName ?: @"relation", (unsigned long)suffix];
    suffix += 1;
  }
  [usedNames addObject:candidate];
  return candidate;
}

static NSString *ALNORMCodegenJSONEscape(NSString *value) {
  NSMutableString *escaped = [NSMutableString stringWithCapacity:[value length] + 8];
  for (NSUInteger idx = 0; idx < [value length]; idx++) {
    unichar ch = [value characterAtIndex:idx];
    switch (ch) {
      case '"':
        [escaped appendString:@"\\\""];
        break;
      case '\\':
        [escaped appendString:@"\\\\"];
        break;
      case '\n':
        [escaped appendString:@"\\n"];
        break;
      case '\r':
        [escaped appendString:@"\\r"];
        break;
      case '\t':
        [escaped appendString:@"\\t"];
        break;
      default:
        if (ch < 0x20) {
          [escaped appendFormat:@"\\u%04x", ch];
        } else {
          [escaped appendFormat:@"%C", ch];
        }
        break;
    }
  }
  return [NSString stringWithString:escaped];
}

static void ALNORMCodegenAppendJSONValue(NSMutableString *output, id value);

static void ALNORMCodegenAppendJSONArray(NSMutableString *output, NSArray *values) {
  [output appendString:@"["];
  for (NSUInteger idx = 0; idx < [values count]; idx++) {
    if (idx > 0) {
      [output appendString:@", "];
    }
    ALNORMCodegenAppendJSONValue(output, values[idx]);
  }
  [output appendString:@"]"];
}

static void ALNORMCodegenAppendJSONDictionary(NSMutableString *output, NSDictionary *dictionary) {
  NSArray *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
  [output appendString:@"{"];
  for (NSUInteger idx = 0; idx < [keys count]; idx++) {
    NSString *key = keys[idx];
    if (idx > 0) {
      [output appendString:@", "];
    }
    [output appendFormat:@"\"%@\": ", ALNORMCodegenJSONEscape(key)];
    ALNORMCodegenAppendJSONValue(output, dictionary[key]);
  }
  [output appendString:@"}"];
}

static void ALNORMCodegenAppendJSONValue(NSMutableString *output, id value) {
  if (value == nil || value == [NSNull null]) {
    [output appendString:@"null"];
    return;
  }
  if ([value isKindOfClass:[NSString class]]) {
    [output appendFormat:@"\"%@\"", ALNORMCodegenJSONEscape(value)];
    return;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    if (strcmp([(NSNumber *)value objCType], @encode(BOOL)) == 0) {
      [output appendString:[value boolValue] ? @"true" : @"false"];
    } else {
      [output appendString:[value stringValue]];
    }
    return;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    ALNORMCodegenAppendJSONArray(output, value);
    return;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    ALNORMCodegenAppendJSONDictionary(output, value);
    return;
  }
  [output appendFormat:@"\"%@\"", ALNORMCodegenJSONEscape([value description])];
}

static NSString *ALNORMCodegenObjectiveCStringLiteral(NSString *value) {
  return [NSString stringWithFormat:@"@\"%@\"", ALNORMCodegenJSONEscape(value ?: @"")];
}

static NSString *ALNORMCodegenObjectiveCStringArray(NSArray<NSString *> *values) {
  NSMutableArray *quoted = [NSMutableArray array];
  for (NSString *value in values ?: @[]) {
    [quoted addObject:ALNORMCodegenObjectiveCStringLiteral(value)];
  }
  return [NSString stringWithFormat:@"@[ %@ ]", [quoted componentsJoinedByString:@", "]];
}

@implementation ALNORMCodegen

+ (NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSchemaMetadata:(NSDictionary<NSString *,id> *)metadata
                                                            classPrefix:(NSString *)classPrefix
                                                                  error:(NSError **)error {
  return [self modelDescriptorsFromSchemaMetadata:metadata
                                      classPrefix:classPrefix
                                   databaseTarget:nil
                               descriptorOverrides:nil
                                            error:error];
}

+ (NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSchemaMetadata:(NSDictionary<NSString *,id> *)metadata
                                                            classPrefix:(NSString *)classPrefix
                                                         databaseTarget:(NSString *)databaseTarget
                                                     descriptorOverrides:(NSDictionary<NSString *,NSDictionary *> *)descriptorOverrides
                                                                  error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![metadata isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"schema metadata must be a dictionary",
                               nil);
    }
    return nil;
  }

  NSString *prefix = ALNORMCodegenStringValue(classPrefix);
  if ([prefix length] == 0) {
    prefix = @"ALNORM";
  }
  if (!ALNORMCodegenIdentifierIsSafe(prefix)) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"class prefix must be a valid identifier",
                               @{
                                 @"class_prefix" : prefix ?: @"",
                               });
    }
    return nil;
  }

  NSString *normalizedDatabaseTarget = [ALNORMCodegenStringValue(databaseTarget) lowercaseString];
  if ([normalizedDatabaseTarget length] > 0 && !ALNORMCodegenIdentifierIsSafe(normalizedDatabaseTarget)) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"database target must be a valid identifier",
                               @{
                                 @"database_target" : normalizedDatabaseTarget ?: @"",
                               });
    }
    return nil;
  }

  NSArray<NSDictionary *> *relationRows = [metadata[@"relations"] isKindOfClass:[NSArray class]] ? metadata[@"relations"] : @[];
  NSArray<NSDictionary *> *columnRows = [metadata[@"columns"] isKindOfClass:[NSArray class]] ? metadata[@"columns"] : @[];
  NSArray<NSDictionary *> *primaryKeyRows =
      [metadata[@"primary_keys"] isKindOfClass:[NSArray class]] ? metadata[@"primary_keys"] : @[];
  NSArray<NSDictionary *> *uniqueRows =
      [metadata[@"unique_constraints"] isKindOfClass:[NSArray class]] ? metadata[@"unique_constraints"] : @[];
  NSArray<NSDictionary *> *foreignKeyRows =
      [metadata[@"foreign_keys"] isKindOfClass:[NSArray class]] ? metadata[@"foreign_keys"] : @[];

  NSMutableDictionary<NSString *, NSMutableDictionary *> *entities = [NSMutableDictionary dictionary];
  NSMutableSet<NSString *> *usedClassNames = [NSMutableSet set];

  for (NSDictionary *relationRow in relationRows) {
    NSString *schema = ALNORMCodegenStringValue(relationRow[@"schema"]);
    NSString *table = ALNORMCodegenStringValue(relationRow[@"table"]);
    NSString *relationKind = [[ALNORMCodegenStringValue(relationRow[@"relation_kind"]) lowercaseString] copy];
    if ([relationKind length] == 0) {
      relationKind = @"table";
    }
    BOOL readOnly = ALNORMCodegenBoolValue(relationRow[@"read_only"], ![relationKind isEqualToString:@"table"]);
    if (!ALNORMCodegenIdentifierIsSafe(schema) || !ALNORMCodegenIdentifierIsSafe(table)) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"relation metadata contains unsafe identifiers",
                                 @{
                                   @"schema" : schema ?: @"",
                                   @"table" : table ?: @"",
                                 });
      }
      return nil;
    }
    NSString *entityName = ALNORMCodegenQualifiedEntityName(schema, table);
    NSString *className = [NSString stringWithFormat:@"%@%@%@Model",
                                                     prefix,
                                                     ALNORMCodegenPascalSuffix(schema),
                                                     ALNORMCodegenPascalSuffix(table)];
    NSDictionary *override = descriptorOverrides[entityName];
    if ([override[@"class_name"] isKindOfClass:[NSString class]] &&
        ALNORMCodegenIdentifierIsSafe(override[@"class_name"])) {
      className = override[@"class_name"];
    }
    if ([usedClassNames containsObject:className]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorIdentifierCollision,
                                 @"generated ORM class name collision",
                                 @{
                                   @"class_name" : className ?: @"",
                                 });
      }
      return nil;
    }
    [usedClassNames addObject:className];

    entities[entityName] = [@{
      @"entity_name" : entityName,
      @"schema_name" : schema,
      @"table_name" : table,
      @"qualified_table_name" : ALNORMCodegenQualifiedTableName(schema, table),
      @"class_name" : className,
      @"relation_kind" : relationKind,
      @"database_target" : normalizedDatabaseTarget ?: @"",
      @"read_only" : @(readOnly),
      @"fields" : [NSMutableArray array],
      @"field_names" : [NSMutableSet set],
      @"field_by_name" : [NSMutableDictionary dictionary],
      @"primary_keys" : [NSMutableArray array],
      @"unique_sets" : [NSMutableArray array],
      @"relations" : [NSMutableArray array],
      @"relation_names" : [NSMutableSet set],
      @"foreign_keys" : [NSMutableArray array],
    } mutableCopy];
  }

  for (NSDictionary *columnRow in columnRows) {
    NSString *schema = ALNORMCodegenStringValue(columnRow[@"schema"]);
    NSString *table = ALNORMCodegenStringValue(columnRow[@"table"]);
    NSString *column = ALNORMCodegenStringValue(columnRow[@"column"]);
    NSString *entityName = ALNORMCodegenQualifiedEntityName(schema, table);
    NSMutableDictionary *entity = entities[entityName];
    if (entity == nil) {
      continue;
    }
    if (!ALNORMCodegenIdentifierIsSafe(column)) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"column metadata contains unsafe identifiers",
                                 @{
                                   @"entity_name" : entityName ?: @"",
                                   @"column_name" : column ?: @"",
                                 });
      }
      return nil;
    }
    NSString *fieldName = ALNORMCodegenCamelCase(column);
    NSMutableSet *fieldNames = entity[@"field_names"];
    if ([fieldNames containsObject:fieldName]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorIdentifierCollision,
                                 @"generated ORM field name collision",
                                 @{
                                   @"entity_name" : entityName ?: @"",
                                   @"field_name" : fieldName ?: @"",
                                 });
      }
      return nil;
    }
    [fieldNames addObject:fieldName];

    ALNORMFieldTypeKind fieldTypeKind = ALNORMFieldTypeKindOther;
    NSDictionary<NSString *, NSString *> *typeDescriptor =
        ALNORMCodegenTypeDescriptor(columnRow[@"data_type"], &fieldTypeKind);
    ALNORMFieldDescriptor *field =
        [[ALNORMFieldDescriptor alloc] initWithName:fieldName
                                       propertyName:fieldName
                                         columnName:column
                                           dataType:ALNORMCodegenStringValue(columnRow[@"data_type"])
                                           objcType:typeDescriptor[@"objcType"] ?: @"id"
                                   runtimeClassName:typeDescriptor[@"runtimeClass"] ?: @""
                                  propertyAttribute:typeDescriptor[@"propertyAttribute"] ?: @"strong"
                                            ordinal:ALNORMCodegenIntegerValue(columnRow[@"ordinal"], 0)
                                           nullable:ALNORMCodegenBoolValue(columnRow[@"nullable"], YES)
                                         primaryKey:ALNORMCodegenBoolValue(columnRow[@"primary_key"], NO)
                                             unique:NO
                                         hasDefault:ALNORMCodegenBoolValue(columnRow[@"has_default"], NO)
                                           readOnly:ALNORMCodegenBoolValue(columnRow[@"read_only"],
                                                                           ALNORMCodegenBoolValue(entity[@"read_only"], NO))
                                  defaultValueShape:ALNORMCodegenStringValue(columnRow[@"default_value_shape"])];
    [entity[@"fields"] addObject:field];
    entity[@"field_by_name"][field.name] = field;
    entity[@"field_by_name"][field.columnName] = field;
  }

  for (NSDictionary *primaryKeyRow in primaryKeyRows) {
    NSString *entityName =
        ALNORMCodegenQualifiedEntityName(ALNORMCodegenStringValue(primaryKeyRow[@"schema"]),
                                         ALNORMCodegenStringValue(primaryKeyRow[@"table"]));
    NSMutableDictionary *entity = entities[entityName];
    if (entity == nil) {
      continue;
    }
    NSMutableArray *fieldNames = [NSMutableArray array];
    for (NSString *columnName in ALNORMCodegenNormalizedStringArray(primaryKeyRow[@"columns"])) {
      ALNORMFieldDescriptor *field = entity[@"field_by_name"][columnName];
      if (field != nil) {
        [fieldNames addObject:field.name];
      }
    }
    entity[@"primary_keys"] = ALNORMCodegenSortedUniqueStrings(fieldNames);
  }

  for (NSDictionary *uniqueRow in uniqueRows) {
    NSString *entityName =
        ALNORMCodegenQualifiedEntityName(ALNORMCodegenStringValue(uniqueRow[@"schema"]),
                                         ALNORMCodegenStringValue(uniqueRow[@"table"]));
    NSMutableDictionary *entity = entities[entityName];
    if (entity == nil) {
      continue;
    }
    NSMutableArray *fieldNames = [NSMutableArray array];
    for (NSString *columnName in ALNORMCodegenNormalizedStringArray(uniqueRow[@"columns"])) {
      ALNORMFieldDescriptor *field = entity[@"field_by_name"][columnName];
      if (field != nil) {
        [fieldNames addObject:field.name];
      }
    }
    NSArray *normalized = ALNORMCodegenSortedUniqueStrings(fieldNames);
    if ([normalized count] > 0) {
      [entity[@"unique_sets"] addObject:normalized];
    }
  }

  for (NSString *entityName in entities) {
    NSMutableDictionary *entity = entities[entityName];
    NSArray<ALNORMFieldDescriptor *> *fields =
        [entity[@"fields"] sortedArrayUsingComparator:^NSComparisonResult(ALNORMFieldDescriptor *left,
                                                                          ALNORMFieldDescriptor *right) {
          if (left.ordinal < right.ordinal) {
            return NSOrderedAscending;
          }
          if (left.ordinal > right.ordinal) {
            return NSOrderedDescending;
          }
          return [left.columnName compare:right.columnName];
        }];
    entity[@"fields"] = [fields mutableCopy];

    NSArray<NSString *> *primaryKeys = entity[@"primary_keys"];
    NSArray<NSArray<NSString *> *> *uniqueSets = entity[@"unique_sets"];
    NSMutableArray *rebuiltFields = [NSMutableArray arrayWithCapacity:[fields count]];
    entity[@"field_by_name"] = [NSMutableDictionary dictionary];
    for (ALNORMFieldDescriptor *field in fields) {
      BOOL unique = ([primaryKeys count] == 1 && [primaryKeys containsObject:field.name]);
      if (!unique) {
        for (NSArray<NSString *> *fieldSet in uniqueSets) {
          if ([fieldSet count] == 1 && [fieldSet containsObject:field.name]) {
            unique = YES;
            break;
          }
        }
      }
      ALNORMFieldDescriptor *updated =
          [[ALNORMFieldDescriptor alloc] initWithName:field.name
                                         propertyName:field.propertyName
                                           columnName:field.columnName
                                             dataType:field.dataType
                                             objcType:field.objcType
                                     runtimeClassName:field.runtimeClassName
                                    propertyAttribute:field.propertyAttribute
                                              ordinal:field.ordinal
                                             nullable:field.isNullable
                                           primaryKey:[primaryKeys containsObject:field.name]
                                               unique:unique
                                           hasDefault:field.hasDefaultValue
                                             readOnly:field.isReadOnly
                                    defaultValueShape:field.defaultValueShape];
      [rebuiltFields addObject:updated];
      entity[@"field_by_name"][updated.name] = updated;
      entity[@"field_by_name"][updated.columnName] = updated;
    }
    entity[@"fields"] = rebuiltFields;
  }

  for (NSDictionary *foreignKeyRow in foreignKeyRows) {
    NSString *sourceEntityName =
        ALNORMCodegenQualifiedEntityName(ALNORMCodegenStringValue(foreignKeyRow[@"schema"]),
                                         ALNORMCodegenStringValue(foreignKeyRow[@"table"]));
    NSString *targetEntityName =
        ALNORMCodegenQualifiedEntityName(ALNORMCodegenStringValue(foreignKeyRow[@"referenced_schema"]),
                                         ALNORMCodegenStringValue(foreignKeyRow[@"referenced_table"]));
    NSMutableDictionary *sourceEntity = entities[sourceEntityName];
    NSMutableDictionary *targetEntity = entities[targetEntityName];
    if (sourceEntity == nil || targetEntity == nil) {
      continue;
    }

    NSMutableArray *sourceFieldNames = [NSMutableArray array];
    for (NSString *columnName in ALNORMCodegenNormalizedStringArray(foreignKeyRow[@"columns"])) {
      ALNORMFieldDescriptor *field = sourceEntity[@"field_by_name"][columnName];
      if (field != nil) {
        [sourceFieldNames addObject:field.name];
      }
    }
    NSMutableArray *targetFieldNames = [NSMutableArray array];
    for (NSString *columnName in ALNORMCodegenNormalizedStringArray(foreignKeyRow[@"referenced_columns"])) {
      ALNORMFieldDescriptor *field = targetEntity[@"field_by_name"][columnName];
      if (field != nil) {
        [targetFieldNames addObject:field.name];
      }
    }

    NSArray *normalizedSourceFields = ALNORMCodegenSortedUniqueStrings(sourceFieldNames);
    NSArray *normalizedTargetFields = ALNORMCodegenSortedUniqueStrings(targetFieldNames);
    if ([normalizedSourceFields count] == 0 || [normalizedTargetFields count] == 0) {
      continue;
    }

    BOOL sourceUnique = [sourceEntity[@"primary_keys"] isEqualToArray:normalizedSourceFields];
    if (!sourceUnique) {
      for (NSArray<NSString *> *uniqueSet in sourceEntity[@"unique_sets"]) {
        if ([uniqueSet isEqualToArray:normalizedSourceFields]) {
          sourceUnique = YES;
          break;
        }
      }
    }

    NSString *belongsToBaseName = ([normalizedSourceFields count] == 1 && [normalizedSourceFields[0] hasSuffix:@"Id"])
                                      ? [normalizedSourceFields[0] substringToIndex:[normalizedSourceFields[0] length] - 2]
                                      : ALNORMCodegenSingularize(targetEntity[@"table_name"]);
    NSString *inverseBaseName = sourceUnique ? ALNORMCodegenSingularize(sourceEntity[@"table_name"])
                                             : ALNORMCodegenPluralize(sourceEntity[@"table_name"]);
    NSString *belongsToName =
        ALNORMCodegenUniqueRelationName(ALNORMCodegenCamelCase(belongsToBaseName),
                                        sourceEntity[@"relation_names"]);
    NSString *inverseName =
        ALNORMCodegenUniqueRelationName(ALNORMCodegenCamelCase(inverseBaseName),
                                        targetEntity[@"relation_names"]);

    ALNORMRelationDescriptor *belongsTo =
        [[ALNORMRelationDescriptor alloc] initWithKind:ALNORMRelationKindBelongsTo
                                                  name:belongsToName
                                      sourceEntityName:sourceEntityName
                                      targetEntityName:targetEntityName
                                       targetClassName:targetEntity[@"class_name"]
                                     throughEntityName:nil
                                      throughClassName:nil
                                      sourceFieldNames:normalizedSourceFields
                                      targetFieldNames:normalizedTargetFields
                               throughSourceFieldNames:nil
                               throughTargetFieldNames:nil
                                       pivotFieldNames:nil
                                              readOnly:(ALNORMCodegenBoolValue(sourceEntity[@"read_only"], NO) ||
                                                        ALNORMCodegenBoolValue(targetEntity[@"read_only"], NO))
                                              inferred:YES];
    [sourceEntity[@"relations"] addObject:belongsTo];

    ALNORMRelationDescriptor *inverse =
        [[ALNORMRelationDescriptor alloc] initWithKind:(sourceUnique ? ALNORMRelationKindHasOne
                                                                     : ALNORMRelationKindHasMany)
                                                  name:inverseName
                                      sourceEntityName:targetEntityName
                                      targetEntityName:sourceEntityName
                                       targetClassName:sourceEntity[@"class_name"]
                                     throughEntityName:nil
                                      throughClassName:nil
                                      sourceFieldNames:normalizedTargetFields
                                      targetFieldNames:normalizedSourceFields
                               throughSourceFieldNames:nil
                               throughTargetFieldNames:nil
                                       pivotFieldNames:nil
                                              readOnly:(ALNORMCodegenBoolValue(sourceEntity[@"read_only"], NO) ||
                                                        ALNORMCodegenBoolValue(targetEntity[@"read_only"], NO))
                                              inferred:YES];
    [targetEntity[@"relations"] addObject:inverse];

    [sourceEntity[@"foreign_keys"] addObject:@{
      @"target_entity_name" : targetEntityName,
      @"target_class_name" : targetEntity[@"class_name"],
      @"source_field_names" : normalizedSourceFields,
      @"target_field_names" : normalizedTargetFields,
    }];
  }

  for (NSString *entityName in entities) {
    NSMutableDictionary *throughEntity = entities[entityName];
    NSArray *foreignKeys = throughEntity[@"foreign_keys"];
    if ([foreignKeys count] != 2) {
      continue;
    }
    NSArray<NSString *> *combinedSourceFields =
        ALNORMCodegenSortedUniqueStrings([foreignKeys[0][@"source_field_names"] arrayByAddingObjectsFromArray:foreignKeys[1][@"source_field_names"]]);
    BOOL qualifiesAsJoinTable = [[throughEntity[@"primary_keys"] copy] isEqualToArray:combinedSourceFields];
    if (!qualifiesAsJoinTable) {
      for (NSArray<NSString *> *uniqueSet in throughEntity[@"unique_sets"]) {
        if ([uniqueSet isEqualToArray:combinedSourceFields]) {
          qualifiesAsJoinTable = YES;
          break;
        }
      }
    }
    if (!qualifiesAsJoinTable) {
      continue;
    }

    NSDictionary *leftForeignKey = foreignKeys[0];
    NSDictionary *rightForeignKey = foreignKeys[1];
    if ([leftForeignKey[@"target_entity_name"] isEqual:rightForeignKey[@"target_entity_name"]]) {
      continue;
    }

    NSMutableDictionary *leftEntity = entities[leftForeignKey[@"target_entity_name"]];
    NSMutableDictionary *rightEntity = entities[rightForeignKey[@"target_entity_name"]];
    if (leftEntity == nil || rightEntity == nil) {
      continue;
    }

    NSMutableSet *pivotFieldNames = [NSMutableSet set];
    for (ALNORMFieldDescriptor *field in throughEntity[@"fields"]) {
      [pivotFieldNames addObject:field.name];
    }
    [pivotFieldNames minusSet:[NSSet setWithArray:leftForeignKey[@"source_field_names"]]];
    [pivotFieldNames minusSet:[NSSet setWithArray:rightForeignKey[@"source_field_names"]]];

    NSString *leftRelationName =
        ALNORMCodegenUniqueRelationName(ALNORMCodegenCamelCase(ALNORMCodegenPluralize(rightEntity[@"table_name"])),
                                        leftEntity[@"relation_names"]);
    NSString *rightRelationName =
        ALNORMCodegenUniqueRelationName(ALNORMCodegenCamelCase(ALNORMCodegenPluralize(leftEntity[@"table_name"])),
                                        rightEntity[@"relation_names"]);

    ALNORMRelationDescriptor *leftRelation =
        [[ALNORMRelationDescriptor alloc] initWithKind:ALNORMRelationKindManyToMany
                                                  name:leftRelationName
                                      sourceEntityName:leftEntity[@"entity_name"]
                                      targetEntityName:rightEntity[@"entity_name"]
                                       targetClassName:rightEntity[@"class_name"]
                                     throughEntityName:throughEntity[@"entity_name"]
                                      throughClassName:throughEntity[@"class_name"]
                                      sourceFieldNames:leftForeignKey[@"target_field_names"]
                                      targetFieldNames:rightForeignKey[@"target_field_names"]
                               throughSourceFieldNames:leftForeignKey[@"source_field_names"]
                               throughTargetFieldNames:rightForeignKey[@"source_field_names"]
                                       pivotFieldNames:ALNORMCodegenSortedUniqueStrings([pivotFieldNames allObjects])
                                              readOnly:(ALNORMCodegenBoolValue(leftEntity[@"read_only"], NO) ||
                                                        ALNORMCodegenBoolValue(rightEntity[@"read_only"], NO) ||
                                                        ALNORMCodegenBoolValue(throughEntity[@"read_only"], NO))
                                              inferred:YES];
    [leftEntity[@"relations"] addObject:leftRelation];

    ALNORMRelationDescriptor *rightRelation =
        [[ALNORMRelationDescriptor alloc] initWithKind:ALNORMRelationKindManyToMany
                                                  name:rightRelationName
                                      sourceEntityName:rightEntity[@"entity_name"]
                                      targetEntityName:leftEntity[@"entity_name"]
                                       targetClassName:leftEntity[@"class_name"]
                                     throughEntityName:throughEntity[@"entity_name"]
                                      throughClassName:throughEntity[@"class_name"]
                                      sourceFieldNames:rightForeignKey[@"target_field_names"]
                                      targetFieldNames:leftForeignKey[@"target_field_names"]
                               throughSourceFieldNames:rightForeignKey[@"source_field_names"]
                               throughTargetFieldNames:leftForeignKey[@"source_field_names"]
                                       pivotFieldNames:ALNORMCodegenSortedUniqueStrings([pivotFieldNames allObjects])
                                              readOnly:(ALNORMCodegenBoolValue(leftEntity[@"read_only"], NO) ||
                                                        ALNORMCodegenBoolValue(rightEntity[@"read_only"], NO) ||
                                                        ALNORMCodegenBoolValue(throughEntity[@"read_only"], NO))
                                              inferred:YES];
    [rightEntity[@"relations"] addObject:rightRelation];
  }

  NSMutableArray<ALNORMModelDescriptor *> *descriptors = [NSMutableArray array];
  NSArray<NSString *> *sortedEntityNames = [[entities allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *entityName in sortedEntityNames) {
    NSMutableDictionary *entity = entities[entityName];
    NSArray<ALNORMRelationDescriptor *> *relations =
        [entity[@"relations"] sortedArrayUsingComparator:^NSComparisonResult(ALNORMRelationDescriptor *left,
                                                                             ALNORMRelationDescriptor *right) {
          NSComparisonResult nameOrder = [left.name compare:right.name];
          if (nameOrder != NSOrderedSame) {
            return nameOrder;
          }
          return [left.targetEntityName compare:right.targetEntityName];
        }];

    NSDictionary *override = descriptorOverrides[entityName];
    if ([override[@"relations"] isKindOfClass:[NSArray class]]) {
      NSMutableArray *customRelations = [NSMutableArray array];
      for (NSDictionary *relationDictionary in override[@"relations"]) {
        if (![relationDictionary isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        NSString *targetEntityName = ALNORMCodegenStringValue(relationDictionary[@"target_entity_name"]);
        NSMutableDictionary *targetEntity = entities[targetEntityName];
        NSString *targetClassName = ALNORMCodegenStringValue(relationDictionary[@"target_class_name"]);
        if ([targetClassName length] == 0 && targetEntity != nil) {
          targetClassName = targetEntity[@"class_name"];
        }
        ALNORMRelationDescriptor *relation =
            [[ALNORMRelationDescriptor alloc] initWithKind:ALNORMRelationKindFromString(relationDictionary[@"kind"])
                                                      name:ALNORMCodegenStringValue(relationDictionary[@"name"])
                                          sourceEntityName:entityName
                                          targetEntityName:targetEntityName
                                           targetClassName:targetClassName
                                         throughEntityName:ALNORMCodegenStringValue(relationDictionary[@"through_entity_name"])
                                          throughClassName:ALNORMCodegenStringValue(relationDictionary[@"through_class_name"])
                                          sourceFieldNames:ALNORMCodegenNormalizedStringArray(relationDictionary[@"source_field_names"])
                                          targetFieldNames:ALNORMCodegenNormalizedStringArray(relationDictionary[@"target_field_names"])
                                   throughSourceFieldNames:ALNORMCodegenNormalizedStringArray(relationDictionary[@"through_source_field_names"])
                                   throughTargetFieldNames:ALNORMCodegenNormalizedStringArray(relationDictionary[@"through_target_field_names"])
                                           pivotFieldNames:ALNORMCodegenNormalizedStringArray(relationDictionary[@"pivot_field_names"])
                                                  readOnly:ALNORMCodegenBoolValue(relationDictionary[@"read_only"], NO)
                                                  inferred:NO];
        [customRelations addObject:relation];
      }
      relations = customRelations;
    }

    ALNORMModelDescriptor *descriptor =
        [[ALNORMModelDescriptor alloc] initWithClassName:entity[@"class_name"]
                                              entityName:entity[@"entity_name"]
                                              schemaName:entity[@"schema_name"]
                                               tableName:entity[@"table_name"]
                                      qualifiedTableName:entity[@"qualified_table_name"]
                                            relationKind:entity[@"relation_kind"]
                                          databaseTarget:entity[@"database_target"]
                                                readOnly:ALNORMCodegenBoolValue(entity[@"read_only"], NO)
                                                  fields:entity[@"fields"]
                                    primaryKeyFieldNames:entity[@"primary_keys"]
                                 uniqueConstraintFieldSets:[entity[@"unique_sets"] copy]
                                               relations:relations];
    [descriptors addObject:descriptor];
  }

  return descriptors;
}

+ (NSDictionary<NSString *,id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *,id> *)metadata
                                                       classPrefix:(NSString *)classPrefix
                                                             error:(NSError **)error {
  return [self renderArtifactsFromSchemaMetadata:metadata
                                     classPrefix:classPrefix
                                  databaseTarget:nil
                              descriptorOverrides:nil
                                           error:error];
}

+ (NSDictionary<NSString *,id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *,id> *)metadata
                                                       classPrefix:(NSString *)classPrefix
                                                    databaseTarget:(NSString *)databaseTarget
                                                descriptorOverrides:(NSDictionary<NSString *,NSDictionary *> *)descriptorOverrides
                                                             error:(NSError **)error {
  NSArray<ALNORMModelDescriptor *> *descriptors =
      [self modelDescriptorsFromSchemaMetadata:metadata
                                   classPrefix:classPrefix
                                databaseTarget:databaseTarget
                            descriptorOverrides:descriptorOverrides
                                         error:error];
  if (descriptors == nil) {
    return nil;
  }

  NSString *prefix = [ALNORMCodegenStringValue(classPrefix) length] > 0 ? ALNORMCodegenStringValue(classPrefix) : @"ALNORM";
  NSString *baseName = [NSString stringWithFormat:@"%@GeneratedModels", prefix];
  NSMutableString *guard = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [baseName length]; idx++) {
    unichar ch = [baseName characterAtIndex:idx];
    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch] || ch == '_') {
      [guard appendFormat:@"%c", (char)toupper(ch)];
    } else {
      [guard appendString:@"_"];
    }
  }
  [guard appendString:@"_H"];

  NSUInteger totalFieldCount = 0;
  NSUInteger totalRelationCount = 0;
  NSMutableString *header = [NSMutableString string];
  [header appendString:@"// Generated by Arlen ORM codegen. Do not edit by hand.\n"];
  [header appendFormat:@"#ifndef %@\n", guard];
  [header appendFormat:@"#define %@\n\n", guard];
  [header appendString:@"#import <Foundation/Foundation.h>\n"];
  [header appendString:@"#import \"ArlenORM/ArlenORM.h\"\n\n"];
  [header appendString:@"NS_ASSUME_NONNULL_BEGIN\n\n"];

  NSMutableString *implementation = [NSMutableString string];
  [implementation appendString:@"// Generated by Arlen ORM codegen. Do not edit by hand.\n"];
  [implementation appendFormat:@"#import \"%@.h\"\n\n", baseName];

  for (ALNORMModelDescriptor *descriptor in descriptors) {
    totalFieldCount += [descriptor.fields count];
    totalRelationCount += [descriptor.relations count];

    [header appendFormat:@"@interface %@ : ALNORMModel\n", descriptor.className];
    for (ALNORMFieldDescriptor *field in descriptor.fields) {
      NSString *readonlyAttribute = (descriptor.isReadOnly || field.isReadOnly) ? @", readonly" : @"";
      [header appendFormat:@"@property(nonatomic, %@%@, %@) %@ %@;\n",
                           field.propertyAttribute ?: @"strong",
                           readonlyAttribute,
                           field.isNullable ? @"nullable" : @"nonnull",
                           field.objcType ?: @"id",
                           field.propertyName ?: @"value"];
    }
    [header appendString:@"+ (ALNORMModelDescriptor *)modelDescriptor;\n"];
    [header appendString:@"+ (NSString *)entityName;\n"];
    [header appendString:@"+ (NSString *)tableName;\n"];
    [header appendString:@"+ (NSString *)relationKind;\n"];
    [header appendString:@"+ (NSArray<NSString *> *)primaryKeyFieldNames;\n"];
    for (ALNORMFieldDescriptor *field in descriptor.fields) {
      [header appendFormat:@"+ (NSString *)field%@;\n", ALNORMCodegenPascalSuffix(field.name)];
    }
    for (ALNORMRelationDescriptor *relation in descriptor.relations) {
      [header appendFormat:@"+ (NSString *)relation%@;\n", ALNORMCodegenPascalSuffix(relation.name)];
    }
    [header appendString:@"@end\n\n"];

    [implementation appendFormat:@"@implementation %@\n\n", descriptor.className];
    for (ALNORMFieldDescriptor *field in descriptor.fields) {
      [implementation appendFormat:@"@dynamic %@;\n", field.propertyName];
    }
    [implementation appendString:@"\n"];
    [implementation appendString:@"+ (ALNORMModelDescriptor *)modelDescriptor {\n"];
    [implementation appendString:@"  static ALNORMModelDescriptor *descriptor = nil;\n"];
    [implementation appendString:@"  if (descriptor == nil) {\n"];
    [implementation appendFormat:@"    descriptor = [[ALNORMModelDescriptor alloc] initWithClassName:%@\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.className)];
    [implementation appendFormat:@"                                              entityName:%@\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.entityName)];
    [implementation appendFormat:@"                                              schemaName:%@\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.schemaName)];
    [implementation appendFormat:@"                                               tableName:%@\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.tableName)];
    [implementation appendFormat:@"                                      qualifiedTableName:%@\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.qualifiedTableName)];
    [implementation appendFormat:@"                                            relationKind:%@\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.relationKind)];
    [implementation appendFormat:@"                                          databaseTarget:%@\n",
                                 [descriptor.databaseTarget length] > 0
                                     ? ALNORMCodegenObjectiveCStringLiteral(descriptor.databaseTarget)
                                     : @"nil"];
    [implementation appendFormat:@"                                                readOnly:%@\n",
                                 descriptor.isReadOnly ? @"YES" : @"NO"];
    [implementation appendString:@"                                                  fields:@[\n"];
    for (ALNORMFieldDescriptor *field in descriptor.fields) {
      [implementation appendFormat:@"                                                    [[ALNORMFieldDescriptor alloc] initWithName:%@ propertyName:%@ columnName:%@ dataType:%@ objcType:%@ runtimeClassName:%@ propertyAttribute:%@ ordinal:%ld nullable:%@ primaryKey:%@ unique:%@ hasDefault:%@ readOnly:%@ defaultValueShape:%@],\n",
                                   ALNORMCodegenObjectiveCStringLiteral(field.name),
                                   ALNORMCodegenObjectiveCStringLiteral(field.propertyName),
                                   ALNORMCodegenObjectiveCStringLiteral(field.columnName),
                                   ALNORMCodegenObjectiveCStringLiteral(field.dataType),
                                   ALNORMCodegenObjectiveCStringLiteral(field.objcType),
                                   ALNORMCodegenObjectiveCStringLiteral(field.runtimeClassName),
                                   ALNORMCodegenObjectiveCStringLiteral(field.propertyAttribute),
                                   (long)field.ordinal,
                                   field.isNullable ? @"YES" : @"NO",
                                   field.isPrimaryKey ? @"YES" : @"NO",
                                   field.isUnique ? @"YES" : @"NO",
                                   field.hasDefaultValue ? @"YES" : @"NO",
                                   field.isReadOnly ? @"YES" : @"NO",
                                   ALNORMCodegenObjectiveCStringLiteral(field.defaultValueShape)];
    }
    [implementation appendString:@"                                                    ]\n"];
    [implementation appendFormat:@"                                    primaryKeyFieldNames:%@\n",
                                 ALNORMCodegenObjectiveCStringArray(descriptor.primaryKeyFieldNames)];
    NSMutableArray *uniqueSetLiterals = [NSMutableArray array];
    for (NSArray<NSString *> *uniqueSet in descriptor.uniqueConstraintFieldSets) {
      [uniqueSetLiterals addObject:ALNORMCodegenObjectiveCStringArray(uniqueSet)];
    }
    [implementation appendFormat:@"                                 uniqueConstraintFieldSets:@[ %@ ]\n",
                                 [uniqueSetLiterals componentsJoinedByString:@", "]];
    [implementation appendString:@"                                               relations:@[\n"];
    for (ALNORMRelationDescriptor *relation in descriptor.relations) {
      [implementation appendFormat:@"                                                    [[ALNORMRelationDescriptor alloc] initWithKind:%ld name:%@ sourceEntityName:%@ targetEntityName:%@ targetClassName:%@ throughEntityName:%@ throughClassName:%@ sourceFieldNames:%@ targetFieldNames:%@ throughSourceFieldNames:%@ throughTargetFieldNames:%@ pivotFieldNames:%@ readOnly:%@ inferred:%@],\n",
                                   (long)relation.kind,
                                   ALNORMCodegenObjectiveCStringLiteral(relation.name),
                                   ALNORMCodegenObjectiveCStringLiteral(relation.sourceEntityName),
                                   ALNORMCodegenObjectiveCStringLiteral(relation.targetEntityName),
                                   ALNORMCodegenObjectiveCStringLiteral(relation.targetClassName),
                                   [relation.throughEntityName length] > 0 ? ALNORMCodegenObjectiveCStringLiteral(relation.throughEntityName) : @"nil",
                                   [relation.throughClassName length] > 0 ? ALNORMCodegenObjectiveCStringLiteral(relation.throughClassName) : @"nil",
                                   ALNORMCodegenObjectiveCStringArray(relation.sourceFieldNames),
                                   ALNORMCodegenObjectiveCStringArray(relation.targetFieldNames),
                                   ALNORMCodegenObjectiveCStringArray(relation.throughSourceFieldNames),
                                   ALNORMCodegenObjectiveCStringArray(relation.throughTargetFieldNames),
                                   ALNORMCodegenObjectiveCStringArray(relation.pivotFieldNames),
                                   relation.isReadOnly ? @"YES" : @"NO",
                                   relation.isInferred ? @"YES" : @"NO"];
    }
    [implementation appendString:@"                                                    ]];\n"];
    [implementation appendString:@"  }\n"];
    [implementation appendString:@"  return descriptor;\n"];
    [implementation appendString:@"}\n\n"];
    [implementation appendFormat:@"+ (NSString *)entityName {\n  return %@;\n}\n\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.entityName)];
    [implementation appendFormat:@"+ (NSString *)tableName {\n  return %@;\n}\n\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.qualifiedTableName)];
    [implementation appendFormat:@"+ (NSString *)relationKind {\n  return %@;\n}\n\n",
                                 ALNORMCodegenObjectiveCStringLiteral(descriptor.relationKind)];
    [implementation appendFormat:@"+ (NSArray<NSString *> *)primaryKeyFieldNames {\n  return %@;\n}\n\n",
                                 ALNORMCodegenObjectiveCStringArray(descriptor.primaryKeyFieldNames)];

    for (ALNORMFieldDescriptor *field in descriptor.fields) {
      [implementation appendFormat:@"- (%@)%@ {\n  return (%@)[self objectForPropertyName:%@];\n}\n\n",
                                   field.objcType,
                                   field.propertyName,
                                   field.objcType,
                                   ALNORMCodegenObjectiveCStringLiteral(field.propertyName)];
      if (!descriptor.isReadOnly && !field.isReadOnly) {
        [implementation appendFormat:@"- (void)set%@:(%@)%@ {\n  [self setObject:%@ forPropertyName:%@ error:NULL];\n}\n\n",
                                     ALNORMCodegenPascalSuffix(field.propertyName),
                                     field.objcType,
                                     field.propertyName,
                                     field.propertyName,
                                     ALNORMCodegenObjectiveCStringLiteral(field.propertyName)];
      }
      [implementation appendFormat:@"+ (NSString *)field%@ {\n  return %@;\n}\n\n",
                                   ALNORMCodegenPascalSuffix(field.name),
                                   ALNORMCodegenObjectiveCStringLiteral(field.name)];
    }
    for (ALNORMRelationDescriptor *relation in descriptor.relations) {
      [implementation appendFormat:@"+ (NSString *)relation%@ {\n  return %@;\n}\n\n",
                                   ALNORMCodegenPascalSuffix(relation.name),
                                   ALNORMCodegenObjectiveCStringLiteral(relation.name)];
    }
    [implementation appendString:@"@end\n\n"];
  }

  [header appendString:@"NS_ASSUME_NONNULL_END\n\n#endif\n"];

  NSMutableArray *manifestModels = [NSMutableArray array];
  for (ALNORMModelDescriptor *descriptor in descriptors) {
    [manifestModels addObject:[descriptor dictionaryRepresentation]];
  }
  NSDictionary *manifestRoot = @{
    @"format" : @"arlen-orm-descriptor-v1",
    @"version" : @1,
    @"class_prefix" : prefix,
    @"database_target" : ALNORMCodegenStringValue(databaseTarget) ?: @"",
    @"model_count" : @([descriptors count]),
    @"field_count" : @(totalFieldCount),
    @"relation_count" : @(totalRelationCount),
    @"models" : manifestModels,
  };
  NSMutableString *manifest = [NSMutableString string];
  ALNORMCodegenAppendJSONDictionary(manifest, manifestRoot);
  [manifest appendString:@"\n"];

  return @{
    @"baseName" : baseName,
    @"header" : header,
    @"implementation" : implementation,
    @"manifest" : manifest,
    @"modelCount" : @([descriptors count]),
    @"fieldCount" : @(totalFieldCount),
    @"relationCount" : @(totalRelationCount),
    @"suggestedManifestPath" : @"db/schema/arlen_orm_manifest.json",
    @"suggestedHeaderPath" : [NSString stringWithFormat:@"src/Generated/%@.h", baseName],
    @"suggestedImplementationPath" : [NSString stringWithFormat:@"src/Generated/%@.m", baseName],
  };
}

@end
