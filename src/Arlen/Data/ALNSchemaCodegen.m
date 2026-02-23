#import "ALNSchemaCodegen.h"

#import <ctype.h>

NSString *const ALNSchemaCodegenErrorDomain = @"Arlen.Data.SchemaCodegen.Error";

static NSError *ALNSchemaCodegenError(ALNSchemaCodegenErrorCode code,
                                      NSString *message,
                                      NSString *detail) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"schema codegen error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  return [NSError errorWithDomain:ALNSchemaCodegenErrorDomain code:code userInfo:userInfo];
}

static NSString *ALNSchemaCodegenStringValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static NSInteger ALNSchemaCodegenOrdinalValue(id value, NSInteger fallback) {
  if ([value respondsToSelector:@selector(integerValue)]) {
    NSInteger parsed = [value integerValue];
    return (parsed > 0) ? parsed : fallback;
  }
  return fallback;
}

static BOOL ALNSchemaCodegenIdentifierIsSafe(NSString *value) {
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

static NSString *ALNSchemaCodegenPascalSuffix(NSString *identifier) {
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

static BOOL ALNSchemaCodegenIsNullableFromValue(id value) {
  NSString *text = [[ALNSchemaCodegenStringValue(value) lowercaseString] stringByTrimmingCharactersInSet:
                                                                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text isEqualToString:@"no"] || [text isEqualToString:@"false"] || [text isEqualToString:@"0"]) {
    return NO;
  }
  return YES;
}

static NSDictionary<NSString *, NSString *> *ALNSchemaCodegenTypeDescriptor(NSString *dataType) {
  NSString *normalized = [[ALNSchemaCodegenStringValue(dataType) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

  if ([normalized isEqualToString:@"smallint"] || [normalized isEqualToString:@"integer"] ||
      [normalized isEqualToString:@"bigint"] || [normalized isEqualToString:@"numeric"] ||
      [normalized isEqualToString:@"decimal"] || [normalized isEqualToString:@"real"] ||
      [normalized isEqualToString:@"double precision"] || [normalized isEqualToString:@"boolean"]) {
    return @{
      @"objcType" : @"NSNumber *",
      @"runtimeClass" : @"NSNumber",
      @"propertyAttribute" : @"strong",
      @"displayType" : ([normalized length] > 0 ? normalized : @"number"),
    };
  }
  if ([normalized isEqualToString:@"bytea"]) {
    return @{
      @"objcType" : @"NSData *",
      @"runtimeClass" : @"NSData",
      @"propertyAttribute" : @"copy",
      @"displayType" : @"bytea",
    };
  }
  if ([normalized isEqualToString:@"json"] || [normalized isEqualToString:@"jsonb"]) {
    return @{
      @"objcType" : @"id",
      @"runtimeClass" : @"",
      @"propertyAttribute" : @"strong",
      @"displayType" : normalized,
    };
  }
  if ([normalized isEqualToString:@"uuid"] || [normalized isEqualToString:@"text"] ||
      [normalized hasPrefix:@"character"] || [normalized hasSuffix:@"time zone"] ||
      [normalized hasPrefix:@"timestamp"] || [normalized isEqualToString:@"date"] ||
      [normalized isEqualToString:@"time"] || [normalized isEqualToString:@"inet"] ||
      [normalized isEqualToString:@"cidr"] || [normalized isEqualToString:@"macaddr"]) {
    return @{
      @"objcType" : @"NSString *",
      @"runtimeClass" : @"NSString",
      @"propertyAttribute" : @"copy",
      @"displayType" : ([normalized length] > 0 ? normalized : @"text"),
    };
  }
  return @{
    @"objcType" : @"id",
    @"runtimeClass" : @"",
    @"propertyAttribute" : @"strong",
    @"displayType" : ([normalized length] > 0 ? normalized : @"any"),
  };
}

static NSString *ALNSchemaCodegenQualifiedTableName(NSString *schema, NSString *table) {
  if ([schema isEqualToString:@"public"]) {
    return table;
  }
  return [NSString stringWithFormat:@"%@.%@", schema, table];
}

static NSString *ALNSchemaCodegenGuardName(NSString *baseName) {
  NSMutableString *guard = [NSMutableString stringWithCapacity:[baseName length] + 8];
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  for (NSUInteger idx = 0; idx < [baseName length]; idx++) {
    unichar ch = [baseName characterAtIndex:idx];
    if ([allowed characterIsMember:ch]) {
      [guard appendFormat:@"%c", (char)toupper(ch)];
    } else {
      [guard appendString:@"_"];
    }
  }
  if ([guard length] == 0) {
    [guard appendString:@"ALN_GENERATED_SCHEMA"];
  }
  if (![[NSCharacterSet letterCharacterSet] characterIsMember:[guard characterAtIndex:0]] &&
      [guard characterAtIndex:0] != '_') {
    [guard insertString:@"_" atIndex:0];
  }
  return [NSString stringWithFormat:@"%@_H", guard];
}

static NSString *ALNSchemaCodegenJSONEscape(NSString *value) {
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

@implementation ALNSchemaCodegen

+ (NSArray<NSDictionary<NSString *,id> *> *)normalizedColumnsFromRows:(NSArray<NSDictionary *> *)rows
                                                                 error:(NSError **)error {
  if (![rows isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNSchemaCodegenError(ALNSchemaCodegenErrorInvalidArgument,
                                     @"rows must be an array",
                                     @"");
    }
    return nil;
  }

  NSMutableArray *normalized = [NSMutableArray arrayWithCapacity:[rows count]];
  NSInteger fallbackOrdinal = 1;
  for (id rawRow in rows) {
    if (![rawRow isKindOfClass:[NSDictionary class]]) {
      if (error != NULL) {
        *error = ALNSchemaCodegenError(ALNSchemaCodegenErrorInvalidMetadata,
                                       @"schema row must be a dictionary",
                                       [rawRow description]);
      }
      return nil;
    }
    NSDictionary *row = rawRow;

    NSString *schema = ALNSchemaCodegenStringValue(row[@"schema"]);
    if ([schema length] == 0) {
      schema = ALNSchemaCodegenStringValue(row[@"table_schema"]);
    }
    NSString *table = ALNSchemaCodegenStringValue(row[@"table"]);
    if ([table length] == 0) {
      table = ALNSchemaCodegenStringValue(row[@"table_name"]);
    }
    NSString *column = ALNSchemaCodegenStringValue(row[@"column"]);
    if ([column length] == 0) {
      column = ALNSchemaCodegenStringValue(row[@"column_name"]);
    }
    NSString *dataType = ALNSchemaCodegenStringValue(row[@"data_type"]);
    if ([dataType length] == 0) {
      dataType = ALNSchemaCodegenStringValue(row[@"type"]);
    }
    if ([dataType length] == 0) {
      dataType = @"text";
    }
    BOOL nullable = ALNSchemaCodegenIsNullableFromValue(row[@"is_nullable"]);

    NSInteger ordinal =
        ALNSchemaCodegenOrdinalValue(row[@"ordinal"], ALNSchemaCodegenOrdinalValue(row[@"ordinal_position"], fallbackOrdinal));
    fallbackOrdinal += 1;

    if (!ALNSchemaCodegenIdentifierIsSafe(schema) ||
        !ALNSchemaCodegenIdentifierIsSafe(table) ||
        !ALNSchemaCodegenIdentifierIsSafe(column)) {
      if (error != NULL) {
        *error = ALNSchemaCodegenError(ALNSchemaCodegenErrorInvalidMetadata,
                                       @"schema metadata contains unsafe identifiers",
                                       [NSString stringWithFormat:@"%@.%@.%@", schema, table, column]);
      }
      return nil;
    }

    [normalized addObject:@{
      @"schema" : schema,
      @"table" : table,
      @"column" : column,
      @"ordinal" : @(ordinal),
      @"dataType" : dataType,
      @"nullable" : @(nullable),
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

+ (NSDictionary<NSString *,id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows
                                                 classPrefix:(NSString *)classPrefix
                                                       error:(NSError **)error {
  return [self renderArtifactsFromColumns:rows
                              classPrefix:classPrefix
                           databaseTarget:nil
                    includeTypedContracts:NO
                                    error:error];
}

+ (NSDictionary<NSString *,id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows
                                                 classPrefix:(NSString *)classPrefix
                                              databaseTarget:(NSString *)databaseTarget
                                                       error:(NSError **)error {
  return [self renderArtifactsFromColumns:rows
                              classPrefix:classPrefix
                           databaseTarget:databaseTarget
                   includeTypedContracts:NO
                                    error:error];
}

+ (NSDictionary<NSString *,id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows
                                                 classPrefix:(NSString *)classPrefix
                                              databaseTarget:(NSString *)databaseTarget
                                       includeTypedContracts:(BOOL)includeTypedContracts
                                                       error:(NSError **)error {
  NSString *prefix = ALNSchemaCodegenStringValue(classPrefix);
  if ([prefix length] == 0) {
    prefix = @"ALNDB";
  }
  if (!ALNSchemaCodegenIdentifierIsSafe(prefix)) {
    if (error != NULL) {
      *error = ALNSchemaCodegenError(ALNSchemaCodegenErrorInvalidArgument,
                                     @"class prefix must be a valid identifier",
                                     prefix);
    }
    return nil;
  }

  NSString *normalizedDatabaseTarget = [ALNSchemaCodegenStringValue(databaseTarget) lowercaseString];
  if ([normalizedDatabaseTarget length] > 0 &&
      !ALNSchemaCodegenIdentifierIsSafe(normalizedDatabaseTarget)) {
    if (error != NULL) {
      *error = ALNSchemaCodegenError(ALNSchemaCodegenErrorInvalidArgument,
                                     @"database target must be a valid identifier",
                                     normalizedDatabaseTarget);
    }
    return nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *normalized = [self normalizedColumnsFromRows:rows error:error];
  if (normalized == nil) {
    return nil;
  }

  NSMutableArray *tables = [NSMutableArray array];
  NSMutableDictionary *tableIndexByKey = [NSMutableDictionary dictionary];
  NSMutableSet *usedClassNames = [NSMutableSet set];
  NSUInteger totalColumns = 0;

  for (NSDictionary *entry in normalized) {
    NSString *schema = entry[@"schema"];
    NSString *table = entry[@"table"];
    NSString *column = entry[@"column"];
    NSString *tableKey = [NSString stringWithFormat:@"%@.%@", schema, table];

    NSNumber *existingIndex = tableIndexByKey[tableKey];
    NSMutableDictionary *tableDescriptor = nil;
    if (existingIndex == nil) {
      NSString *className =
          [NSString stringWithFormat:@"%@%@%@", prefix,
                                     ALNSchemaCodegenPascalSuffix(schema),
                                     ALNSchemaCodegenPascalSuffix(table)];
      if ([usedClassNames containsObject:className]) {
        if (error != NULL) {
          *error = ALNSchemaCodegenError(ALNSchemaCodegenErrorIdentifierCollision,
                                         @"generated class name collision",
                                         className);
        }
        return nil;
      }
      [usedClassNames addObject:className];

      tableDescriptor = [@{
        @"schema" : schema,
        @"table" : table,
        @"className" : className,
        @"columns" : [NSMutableArray array],
        @"usedColumnSuffixes" : [NSMutableSet set],
      } mutableCopy];
      [tables addObject:tableDescriptor];
      tableIndexByKey[tableKey] = @([tables count] - 1);
    } else {
      tableDescriptor = tables[[existingIndex unsignedIntegerValue]];
    }

    NSMutableArray *columns = tableDescriptor[@"columns"];
    NSMutableSet *usedSuffixes = tableDescriptor[@"usedColumnSuffixes"];
    NSString *baseSuffix = ALNSchemaCodegenPascalSuffix(column);
    NSString *suffix = baseSuffix;
    NSInteger counter = 2;
    while ([usedSuffixes containsObject:suffix]) {
      suffix = [NSString stringWithFormat:@"%@Col%ld", baseSuffix, (long)counter];
      counter += 1;
    }
    [usedSuffixes addObject:suffix];

    NSString *propertyName = [NSString stringWithFormat:@"column%@", suffix];
    NSDictionary<NSString *, NSString *> *typeDescriptor =
        ALNSchemaCodegenTypeDescriptor(entry[@"dataType"]);

    [columns addObject:@{
      @"name" : column,
      @"suffix" : suffix,
      @"propertyName" : propertyName,
      @"objcType" : typeDescriptor[@"objcType"] ?: @"id",
      @"runtimeClass" : typeDescriptor[@"runtimeClass"] ?: @"",
      @"propertyAttribute" : typeDescriptor[@"propertyAttribute"] ?: @"strong",
      @"dataType" : entry[@"dataType"] ?: @"text",
      @"displayType" : typeDescriptor[@"displayType"] ?: @"any",
      @"nullable" : [entry[@"nullable"] respondsToSelector:@selector(boolValue)] ? entry[@"nullable"] : @(YES),
    }];
    totalColumns += 1;
  }

  NSString *baseName = [NSString stringWithFormat:@"%@Schema", prefix];
  NSString *guard = ALNSchemaCodegenGuardName(baseName);

  NSMutableString *header = [NSMutableString string];
  [header appendString:@"// Generated by arlen schema-codegen. Do not edit by hand.\n"];
  [header appendFormat:@"#ifndef %@\n", guard];
  [header appendFormat:@"#define %@\n\n", guard];
  [header appendString:@"#import <Foundation/Foundation.h>\n"];
  [header appendString:@"#import \"ALNSQLBuilder.h\"\n\n"];
  [header appendString:@"NS_ASSUME_NONNULL_BEGIN\n\n"];

  NSMutableString *implementation = [NSMutableString string];
  [implementation appendString:@"// Generated by arlen schema-codegen. Do not edit by hand.\n"];
  [implementation appendFormat:@"#import \"%@.h\"\n\n", baseName];

  NSString *typedDecodeErrorEnumName = [NSString stringWithFormat:@"%@TypedDecodeErrorCode", baseName];
  NSString *typedDecodeErrorDomainName = [NSString stringWithFormat:@"%@TypedDecodeErrorDomain", baseName];
  NSString *typedDecodeErrorFunctionName = [NSString stringWithFormat:@"%@TypedDecodeError", baseName];
  if (includeTypedContracts) {
    [header appendFormat:@"typedef NS_ENUM(NSInteger, %@) {\n", typedDecodeErrorEnumName];
    [header appendFormat:@"  %@MissingField = 1,\n", typedDecodeErrorEnumName];
    [header appendFormat:@"  %@InvalidType = 2,\n", typedDecodeErrorEnumName];
    [header appendString:@"};\n\n"];
    [header appendFormat:@"FOUNDATION_EXPORT NSString *const %@;\n\n", typedDecodeErrorDomainName];

    [implementation appendFormat:@"NSString *const %@ = @\"Arlen.Data.SchemaCodegen.TypedDecode.%@\";\n\n",
                                 typedDecodeErrorDomainName,
                                 baseName];
    [implementation appendFormat:@"static NSError *%@( %@ code,\n",
                                 typedDecodeErrorFunctionName,
                                 typedDecodeErrorEnumName];
    [implementation appendString:@"                                  NSString *field,\n"];
    [implementation appendString:@"                                  NSString *expectedType,\n"];
    [implementation appendString:@"                                  NSString *detail) {\n"];
    [implementation appendString:@"  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];\n"];
    [implementation appendString:@"  userInfo[NSLocalizedDescriptionKey] = detail ?: @\"typed row decode failure\";\n"];
    [implementation appendString:@"  if ([field length] > 0) {\n"];
    [implementation appendString:@"    userInfo[@\"field\"] = field;\n"];
    [implementation appendString:@"  }\n"];
    [implementation appendString:@"  if ([expectedType length] > 0) {\n"];
    [implementation appendString:@"    userInfo[@\"expected_type\"] = expectedType;\n"];
    [implementation appendString:@"  }\n"];
    [implementation appendFormat:@"  return [NSError errorWithDomain:%@\n", typedDecodeErrorDomainName];
    [implementation appendString:@"                             code:code\n"];
    [implementation appendString:@"                         userInfo:userInfo];\n"];
    [implementation appendString:@"}\n\n"];
  }

  for (NSMutableDictionary *tableDescriptor in tables) {
    NSString *schema = tableDescriptor[@"schema"];
    NSString *table = tableDescriptor[@"table"];
    NSString *className = tableDescriptor[@"className"];
    NSArray *columns = tableDescriptor[@"columns"];
    NSString *qualifiedTable = ALNSchemaCodegenQualifiedTableName(schema, table);
    NSString *rowClassName = [NSString stringWithFormat:@"%@Row", className];
    NSString *insertClassName = [NSString stringWithFormat:@"%@Insert", className];
    NSString *updateClassName = [NSString stringWithFormat:@"%@Update", className];

    if (includeTypedContracts) {
      [header appendFormat:@"@interface %@ : NSObject\n", rowClassName];
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *propertyAttribute = column[@"propertyAttribute"];
        NSString *nullability =
            [column[@"nullable"] respondsToSelector:@selector(boolValue)] && [column[@"nullable"] boolValue]
                ? @"nullable"
                : @"nonnull";
        [header appendFormat:@"@property(nonatomic, %@, readonly, %@) %@ %@;\n",
                             propertyAttribute,
                             nullability,
                             objcType,
                             propertyName];
      }
      [header appendString:@"- (instancetype)init"];
      NSUInteger index = 0;
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *selectorPart = (index == 0)
                                     ? [NSString stringWithFormat:@"With%@:", ALNSchemaCodegenPascalSuffix(propertyName)]
                                     : [NSString stringWithFormat:@"%@:", propertyName];
        [header appendFormat:@"%@(%@)%@", selectorPart, objcType, propertyName];
        if (index + 1 < [columns count]) {
          [header appendString:@" "];
        }
        index += 1;
      }
      [header appendString:@" NS_DESIGNATED_INITIALIZER;\n"];
      [header appendString:@"- (instancetype)init NS_UNAVAILABLE;\n"];
      [header appendString:@"@end\n\n"];

      [header appendFormat:@"@interface %@ : NSObject\n", insertClassName];
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *propertyAttribute = column[@"propertyAttribute"];
        [header appendFormat:@"@property(nonatomic, %@, nullable) %@ %@;\n",
                             propertyAttribute,
                             objcType,
                             propertyName];
      }
      [header appendString:@"- (NSDictionary<NSString *, id> *)builderValues;\n"];
      [header appendString:@"@end\n\n"];

      [header appendFormat:@"@interface %@ : NSObject\n", updateClassName];
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *propertyAttribute = column[@"propertyAttribute"];
        [header appendFormat:@"@property(nonatomic, %@, nullable) %@ %@;\n",
                             propertyAttribute,
                             objcType,
                             propertyName];
      }
      [header appendString:@"- (NSDictionary<NSString *, id> *)builderValues;\n"];
      [header appendString:@"@end\n\n"];
    }

    [header appendFormat:@"@interface %@ : NSObject\n", className];
    [header appendString:@"+ (NSString *)tableName;\n"];
    [header appendString:@"+ (NSArray<NSString *> *)allColumns;\n"];
    [header appendString:@"+ (NSArray<NSString *> *)allQualifiedColumns;\n"];
    [header appendString:@"+ (ALNSQLBuilder *)selectAll;\n"];
    [header appendString:@"+ (ALNSQLBuilder *)selectColumns:(nullable NSArray<NSString *> *)columns;\n"];
    [header appendString:@"+ (ALNSQLBuilder *)insertValues:(NSDictionary<NSString *, id> *)values;\n"];
    [header appendString:@"+ (ALNSQLBuilder *)updateValues:(NSDictionary<NSString *, id> *)values;\n"];
    [header appendString:@"+ (ALNSQLBuilder *)deleteBuilder;\n"];
    if (includeTypedContracts) {
      [header appendFormat:@"+ (ALNSQLBuilder *)insertContract:(%@ *)contractValues;\n", insertClassName];
      [header appendFormat:@"+ (ALNSQLBuilder *)updateContract:(%@ *)contractValues;\n", updateClassName];
      [header appendFormat:@"+ (nullable %@ *)decodeTypedRow:(NSDictionary<NSString *, id> *)row\n",
                           rowClassName];
      [header appendString:@"                            error:(NSError *_Nullable *_Nullable)error;\n"];
      [header appendFormat:@"+ (nullable NSArray<%@ *> *)decodeTypedRows:(NSArray<NSDictionary<NSString *, id> *> *)rows\n",
                           rowClassName];
      [header appendString:@"                                      error:(NSError *_Nullable *_Nullable)error;\n"];
    }
    for (NSDictionary *column in columns) {
      NSString *suffix = column[@"suffix"];
      [header appendFormat:@"+ (NSString *)column%@;\n", suffix];
      [header appendFormat:@"+ (NSString *)qualifiedColumn%@;\n", suffix];
    }
    [header appendString:@"@end\n\n"];

    if (includeTypedContracts) {
      [implementation appendFormat:@"@implementation %@\n\n", rowClassName];
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *propertyAttribute = column[@"propertyAttribute"];
        [implementation appendFormat:@"@property(nonatomic, %@, readwrite) %@ %@;\n",
                                     propertyAttribute,
                                     objcType,
                                     propertyName];
      }
      [implementation appendString:@"\n"];
      [implementation appendString:@"- (instancetype)init"];
      NSUInteger initIndex = 0;
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *selectorPart = (initIndex == 0)
                                     ? [NSString stringWithFormat:@"With%@:", ALNSchemaCodegenPascalSuffix(propertyName)]
                                     : [NSString stringWithFormat:@"%@:", propertyName];
        [implementation appendFormat:@"%@(%@)%@", selectorPart, objcType, propertyName];
        if (initIndex + 1 < [columns count]) {
          [implementation appendString:@" "];
        }
        initIndex += 1;
      }
      [implementation appendString:@" {\n"];
      [implementation appendString:@"  self = [super init];\n"];
      [implementation appendString:@"  if (self == nil) {\n"];
      [implementation appendString:@"    return nil;\n"];
      [implementation appendString:@"  }\n"];
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        [implementation appendFormat:@"  _%@ = %@;\n", propertyName, propertyName];
      }
      [implementation appendString:@"  return self;\n"];
      [implementation appendString:@"}\n\n"];
      [implementation appendString:@"@end\n\n"];

      [implementation appendFormat:@"@implementation %@\n\n", insertClassName];
      [implementation appendString:@"- (NSDictionary<NSString *, id> *)builderValues {\n"];
      [implementation appendString:@"  NSMutableDictionary *values = [NSMutableDictionary dictionary];\n"];
      for (NSDictionary *column in columns) {
        NSString *name = column[@"name"];
        NSString *propertyName = column[@"propertyName"];
        [implementation appendFormat:@"  if (self.%@ != nil) {\n", propertyName];
        [implementation appendFormat:@"    values[@\"%@\"] = self.%@;\n", name, propertyName];
        [implementation appendString:@"  }\n"];
      }
      [implementation appendString:@"  return values;\n"];
      [implementation appendString:@"}\n\n"];
      [implementation appendString:@"@end\n\n"];

      [implementation appendFormat:@"@implementation %@\n\n", updateClassName];
      [implementation appendString:@"- (NSDictionary<NSString *, id> *)builderValues {\n"];
      [implementation appendString:@"  NSMutableDictionary *values = [NSMutableDictionary dictionary];\n"];
      for (NSDictionary *column in columns) {
        NSString *name = column[@"name"];
        NSString *propertyName = column[@"propertyName"];
        [implementation appendFormat:@"  if (self.%@ != nil) {\n", propertyName];
        [implementation appendFormat:@"    values[@\"%@\"] = self.%@;\n", name, propertyName];
        [implementation appendString:@"  }\n"];
      }
      [implementation appendString:@"  return values;\n"];
      [implementation appendString:@"}\n\n"];
      [implementation appendString:@"@end\n\n"];
    }

    [implementation appendFormat:@"@implementation %@\n\n", className];
    [implementation appendFormat:@"+ (NSString *)tableName {\n  return @\"%@\";\n}\n\n",
                                 qualifiedTable];

    NSMutableArray *rawColumns = [NSMutableArray arrayWithCapacity:[columns count]];
    NSMutableArray *qualifiedColumns = [NSMutableArray arrayWithCapacity:[columns count]];
    for (NSDictionary *column in columns) {
      NSString *name = column[@"name"];
      [rawColumns addObject:[NSString stringWithFormat:@"@\"%@\"", name]];
      [qualifiedColumns addObject:[NSString stringWithFormat:@"@\"%@.%@\"", qualifiedTable, name]];
    }

    [implementation appendFormat:@"+ (NSArray<NSString *> *)allColumns {\n  return @[ %@ ];\n}\n\n",
                                 [rawColumns componentsJoinedByString:@", "]];
    [implementation appendFormat:@"+ (NSArray<NSString *> *)allQualifiedColumns {\n  return @[ %@ ];\n}\n\n",
                                 [qualifiedColumns componentsJoinedByString:@", "]];
    [implementation appendString:@"+ (ALNSQLBuilder *)selectAll {\n"];
    [implementation appendString:@"  return [ALNSQLBuilder selectFrom:[self tableName] columns:[self allQualifiedColumns]];\n"];
    [implementation appendString:@"}\n\n"];
    [implementation appendString:@"+ (ALNSQLBuilder *)selectColumns:(NSArray<NSString *> *)columns {\n"];
    [implementation appendString:@"  if ([columns count] == 0) {\n"];
    [implementation appendString:@"    return [self selectAll];\n"];
    [implementation appendString:@"  }\n"];
    [implementation appendString:@"  return [ALNSQLBuilder selectFrom:[self tableName] columns:columns];\n"];
    [implementation appendString:@"}\n\n"];
    [implementation appendString:@"+ (ALNSQLBuilder *)insertValues:(NSDictionary<NSString *, id> *)values {\n"];
    [implementation appendString:@"  return [ALNSQLBuilder insertInto:[self tableName] values:values ?: @{}];\n"];
    [implementation appendString:@"}\n\n"];
    [implementation appendString:@"+ (ALNSQLBuilder *)updateValues:(NSDictionary<NSString *, id> *)values {\n"];
    [implementation appendString:@"  return [ALNSQLBuilder updateTable:[self tableName] values:values ?: @{}];\n"];
    [implementation appendString:@"}\n\n"];
    [implementation appendString:@"+ (ALNSQLBuilder *)deleteBuilder {\n"];
    [implementation appendString:@"  return [ALNSQLBuilder deleteFrom:[self tableName]];\n"];
    [implementation appendString:@"}\n\n"];

    if (includeTypedContracts) {
      [implementation appendFormat:@"+ (ALNSQLBuilder *)insertContract:(%@ *)contractValues {\n",
                                   insertClassName];
      [implementation appendString:@"  return [self insertValues:[contractValues builderValues]];\n"];
      [implementation appendString:@"}\n\n"];
      [implementation appendFormat:@"+ (ALNSQLBuilder *)updateContract:(%@ *)contractValues {\n",
                                   updateClassName];
      [implementation appendString:@"  return [self updateValues:[contractValues builderValues]];\n"];
      [implementation appendString:@"}\n\n"];
      [implementation appendFormat:@"+ (nullable %@ *)decodeTypedRow:(NSDictionary<NSString *, id> *)row\n",
                                   rowClassName];
      [implementation appendString:@"                            error:(NSError **)error {\n"];
      [implementation appendString:@"  if (![row isKindOfClass:[NSDictionary class]]) {\n"];
      [implementation appendFormat:@"    if (error != NULL) {\n"];
      [implementation appendFormat:@"      *error = %@( %@InvalidType, @\"row\", @\"NSDictionary\", @\"typed row must be a dictionary\");\n",
                                   typedDecodeErrorFunctionName,
                                   typedDecodeErrorEnumName];
      [implementation appendString:@"    }\n"];
      [implementation appendString:@"    return nil;\n"];
      [implementation appendString:@"  }\n"];
      for (NSDictionary *column in columns) {
        NSString *name = column[@"name"];
        NSString *propertyName = column[@"propertyName"];
        NSString *objcType = column[@"objcType"];
        NSString *runtimeClass = column[@"runtimeClass"];
        BOOL nullable = [column[@"nullable"] respondsToSelector:@selector(boolValue)] && [column[@"nullable"] boolValue];
        NSString *displayType = column[@"displayType"];
        [implementation appendFormat:@"  id raw%@ = row[@\"%@\"];\n",
                                     ALNSchemaCodegenPascalSuffix(propertyName),
                                     name];
        [implementation appendFormat:@"  if (raw%@ == [NSNull null]) {\n",
                                     ALNSchemaCodegenPascalSuffix(propertyName)];
        [implementation appendFormat:@"    raw%@ = nil;\n", ALNSchemaCodegenPascalSuffix(propertyName)];
        [implementation appendString:@"  }\n"];
        if (!nullable) {
          [implementation appendFormat:@"  if (raw%@ == nil) {\n", ALNSchemaCodegenPascalSuffix(propertyName)];
          [implementation appendString:@"    if (error != NULL) {\n"];
          [implementation appendFormat:@"      *error = %@( %@MissingField, @\"%@\", @\"%@\", @\"missing required field\");\n",
                                       typedDecodeErrorFunctionName,
                                       typedDecodeErrorEnumName,
                                       name,
                                       displayType];
          [implementation appendString:@"    }\n"];
          [implementation appendString:@"    return nil;\n"];
          [implementation appendString:@"  }\n"];
        }
        if ([runtimeClass length] > 0) {
          [implementation appendFormat:@"  if (raw%@ != nil && ![raw%@ isKindOfClass:[%@ class]]) {\n",
                                       ALNSchemaCodegenPascalSuffix(propertyName),
                                       ALNSchemaCodegenPascalSuffix(propertyName),
                                       runtimeClass];
          [implementation appendString:@"    if (error != NULL) {\n"];
          [implementation appendFormat:@"      *error = %@( %@InvalidType, @\"%@\", @\"%@\", @\"field has unexpected runtime type\");\n",
                                       typedDecodeErrorFunctionName,
                                       typedDecodeErrorEnumName,
                                       name,
                                       displayType];
          [implementation appendString:@"    }\n"];
          [implementation appendString:@"    return nil;\n"];
          [implementation appendString:@"  }\n"];
        }
        [implementation appendFormat:@"  %@ %@ = (%@)raw%@;\n",
                                     objcType,
                                     propertyName,
                                     objcType,
                                     ALNSchemaCodegenPascalSuffix(propertyName)];
      }
      [implementation appendString:@"  return [["];
      [implementation appendString:rowClassName];
      [implementation appendString:@" alloc] init"];
      NSUInteger decodeInitIndex = 0;
      for (NSDictionary *column in columns) {
        NSString *propertyName = column[@"propertyName"];
        NSString *selectorPart = (decodeInitIndex == 0)
                                     ? [NSString stringWithFormat:@"With%@:", ALNSchemaCodegenPascalSuffix(propertyName)]
                                     : [NSString stringWithFormat:@"%@:", propertyName];
        [implementation appendFormat:@"%@%@", selectorPart, propertyName];
        if (decodeInitIndex + 1 < [columns count]) {
          [implementation appendString:@" "];
        }
        decodeInitIndex += 1;
      }
      [implementation appendString:@"];\n"];
      [implementation appendString:@"}\n\n"];
      [implementation appendFormat:@"+ (nullable NSArray<%@ *> *)decodeTypedRows:(NSArray<NSDictionary<NSString *, id> *> *)rows\n",
                                   rowClassName];
      [implementation appendString:@"                                      error:(NSError **)error {\n"];
      [implementation appendString:@"  if (![rows isKindOfClass:[NSArray class]]) {\n"];
      [implementation appendString:@"    if (error != NULL) {\n"];
      [implementation appendFormat:@"      *error = %@( %@InvalidType, @\"rows\", @\"NSArray\", @\"typed rows must be an array\");\n",
                                   typedDecodeErrorFunctionName,
                                   typedDecodeErrorEnumName];
      [implementation appendString:@"    }\n"];
      [implementation appendString:@"    return nil;\n"];
      [implementation appendString:@"  }\n"];
      [implementation appendString:@"  NSMutableArray *decoded = [NSMutableArray arrayWithCapacity:[rows count]];\n"];
      [implementation appendString:@"  for (id rawRow in rows) {\n"];
      [implementation appendFormat:@"    %@ *typed = [self decodeTypedRow:rawRow error:error];\n", rowClassName];
      [implementation appendString:@"    if (typed == nil) {\n"];
      [implementation appendString:@"      return nil;\n"];
      [implementation appendString:@"    }\n"];
      [implementation appendString:@"    [decoded addObject:typed];\n"];
      [implementation appendString:@"  }\n"];
      [implementation appendString:@"  return decoded;\n"];
      [implementation appendString:@"}\n\n"];
    }

    for (NSDictionary *column in columns) {
      NSString *name = column[@"name"];
      NSString *suffix = column[@"suffix"];
      [implementation appendFormat:@"+ (NSString *)column%@ {\n  return @\"%@\";\n}\n\n",
                                   suffix,
                                   name];
      [implementation appendFormat:@"+ (NSString *)qualifiedColumn%@ {\n  return @\"%@.%@\";\n}\n\n",
                                   suffix,
                                   qualifiedTable,
                                   name];
    }
    [implementation appendString:@"@end\n\n"];
  }

  [header appendString:@"NS_ASSUME_NONNULL_END\n\n"];
  [header appendString:@"#endif\n"];

  NSMutableString *manifest = [NSMutableString string];
  [manifest appendString:@"{\n"];
  [manifest appendString:@"  \"version\": 1,\n"];
  [manifest appendFormat:@"  \"class_prefix\": \"%@\",\n", ALNSchemaCodegenJSONEscape(prefix)];
  [manifest appendFormat:@"  \"artifact_base_name\": \"%@\",\n", ALNSchemaCodegenJSONEscape(baseName)];
  [manifest appendFormat:@"  \"typed_contracts\": %@,\n", includeTypedContracts ? @"true" : @"false"];
  if ([normalizedDatabaseTarget length] > 0) {
    [manifest appendFormat:@"  \"database_target\": \"%@\",\n",
                           ALNSchemaCodegenJSONEscape(normalizedDatabaseTarget)];
  }
  [manifest appendString:@"  \"tables\": [\n"];
  for (NSUInteger index = 0; index < [tables count]; index++) {
    NSDictionary *tableDescriptor = tables[index];
    NSString *schema = tableDescriptor[@"schema"];
    NSString *table = tableDescriptor[@"table"];
    NSString *className = tableDescriptor[@"className"];
    NSString *rowClassName = [NSString stringWithFormat:@"%@Row", className];
    NSString *insertClassName = [NSString stringWithFormat:@"%@Insert", className];
    NSString *updateClassName = [NSString stringWithFormat:@"%@Update", className];
    NSArray *columns = tableDescriptor[@"columns"];

    [manifest appendString:@"    {\n"];
    [manifest appendFormat:@"      \"schema\": \"%@\",\n", ALNSchemaCodegenJSONEscape(schema)];
    [manifest appendFormat:@"      \"table\": \"%@\",\n", ALNSchemaCodegenJSONEscape(table)];
    [manifest appendFormat:@"      \"class_name\": \"%@\",\n", ALNSchemaCodegenJSONEscape(className)];
    if (includeTypedContracts) {
      [manifest appendFormat:@"      \"row_class_name\": \"%@\",\n", ALNSchemaCodegenJSONEscape(rowClassName)];
      [manifest appendFormat:@"      \"insert_class_name\": \"%@\",\n", ALNSchemaCodegenJSONEscape(insertClassName)];
      [manifest appendFormat:@"      \"update_class_name\": \"%@\",\n", ALNSchemaCodegenJSONEscape(updateClassName)];
    }
    [manifest appendString:@"      \"columns\": ["];
    for (NSUInteger columnIndex = 0; columnIndex < [columns count]; columnIndex++) {
      NSDictionary *column = columns[columnIndex];
      NSString *columnName = column[@"name"];
      [manifest appendFormat:@"\"%@\"", ALNSchemaCodegenJSONEscape(columnName)];
      if (columnIndex + 1 < [columns count]) {
        [manifest appendString:@", "];
      }
    }
    [manifest appendString:@"]\n"];
    [manifest appendString:@"    }"];
    if (index + 1 < [tables count]) {
      [manifest appendString:@","];
    }
    [manifest appendString:@"\n"];
  }
  [manifest appendString:@"  ]\n"];
  [manifest appendString:@"}\n"];

  return @{
    @"baseName" : baseName,
    @"header" : [NSString stringWithString:header],
    @"implementation" : [NSString stringWithString:implementation],
    @"manifest" : [NSString stringWithString:manifest],
    @"tableCount" : @([tables count]),
    @"columnCount" : @(totalColumns),
  };
}

@end
