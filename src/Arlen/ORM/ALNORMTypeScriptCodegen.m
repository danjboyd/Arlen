#import "ALNORMTypeScriptCodegen.h"

#import "ALNJSONSerialization.h"
#import "ALNORMCodegen.h"
#import "ALNORMErrors.h"

static NSString *const ALNORMTypeScriptManifestFormat = @"arlen-typescript-contract-v1";

typedef NS_ENUM(NSInteger, ALNORMTSOperationKind) {
  ALNORMTSOperationKindQuery = 1,
  ALNORMTSOperationKindMutation = 2,
};

static NSString *ALNORMTSStringValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNORMTSBoolValue(id value, BOOL fallback) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *normalized = [[ALNORMTSStringValue(value) lowercaseString] copy];
  if ([normalized length] == 0) {
    return fallback;
  }
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"y"] ||
      [normalized isEqualToString:@"t"]) {
    return YES;
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"n"] ||
      [normalized isEqualToString:@"f"]) {
    return NO;
  }
  return fallback;
}

static NSNumber *ALNORMTSBoolNumber(BOOL value) {
  return value ? @YES : @NO;
}

static NSInteger ALNORMTSIntegerValue(id value, NSInteger fallback) {
  return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

static NSArray<NSString *> *ALNORMTSNormalizedStringArray(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray<NSString *> *items = [NSMutableArray array];
  for (id rawItem in (NSArray *)value) {
    NSString *item = ALNORMTSStringValue(rawItem);
    if ([item length] == 0) {
      continue;
    }
    if (![items containsObject:item]) {
      [items addObject:item];
    }
  }
  return [NSArray arrayWithArray:items];
}

static NSDictionary<NSString *, id> *ALNORMTSDictionaryValue(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSSet<NSString *> *ALNORMTSReservedWords(void) {
  static NSSet<NSString *> *reservedWords = nil;
  if (reservedWords == nil) {
    reservedWords = [NSSet setWithArray:@[
      @"abstract", @"any", @"as", @"asserts", @"async", @"await", @"boolean", @"break",
      @"case", @"catch", @"class", @"const", @"constructor", @"continue", @"debugger",
      @"declare", @"default", @"delete", @"do", @"else", @"enum", @"export", @"extends",
      @"false", @"finally", @"for", @"from", @"function", @"get", @"if", @"implements",
      @"import", @"in", @"infer", @"instanceof", @"interface", @"is", @"keyof", @"let",
      @"module", @"namespace", @"never", @"new", @"null", @"number", @"object", @"of",
      @"package", @"private", @"protected", @"public", @"readonly", @"require", @"return",
      @"set", @"static", @"string", @"super", @"switch", @"symbol", @"this", @"throw",
      @"true", @"try", @"type", @"typeof", @"undefined", @"unique", @"unknown", @"var",
      @"void", @"while", @"with", @"yield",
    ]];
  }
  return reservedWords;
}

static NSArray<NSString *> *ALNORMTSIdentifierParts(NSString *value) {
  NSString *input = ALNORMTSStringValue(value);
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSMutableString *current = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [input length]; idx++) {
    unichar character = [input characterAtIndex:idx];
    BOOL isLower = (character >= 'a' && character <= 'z');
    BOOL isUpper = (character >= 'A' && character <= 'Z');
    BOOL isDigit = (character >= '0' && character <= '9');
    BOOL isAlphaNumeric = isLower || isUpper || isDigit;
    if (isAlphaNumeric) {
      if ([current length] > 0 && isUpper) {
        unichar previousCharacter = [input characterAtIndex:idx - 1];
        BOOL previousIsLower = (previousCharacter >= 'a' && previousCharacter <= 'z');
        BOOL previousIsDigit = (previousCharacter >= '0' && previousCharacter <= '9');
        BOOL previousIsUpper = (previousCharacter >= 'A' && previousCharacter <= 'Z');
        BOOL nextIsLower = NO;
        if (idx + 1 < [input length]) {
          unichar nextCharacter = [input characterAtIndex:idx + 1];
          nextIsLower = (nextCharacter >= 'a' && nextCharacter <= 'z');
        }
        if (previousIsLower || previousIsDigit || (previousIsUpper && nextIsLower)) {
          [parts addObject:[NSString stringWithString:current]];
          [current setString:@""];
        }
      }
      if (isUpper) {
        [current appendFormat:@"%C", (unichar)tolower((int)character)];
      } else {
        [current appendFormat:@"%C", character];
      }
      continue;
    }
    if ([current length] > 0) {
      [parts addObject:[NSString stringWithString:current]];
      [current setString:@""];
    }
  }
  if ([current length] > 0) {
    [parts addObject:[NSString stringWithString:current]];
  }
  return [NSArray arrayWithArray:parts];
}

static NSString *ALNORMTSCapitalizedPart(NSString *value) {
  NSString *part = [ALNORMTSStringValue(value) lowercaseString];
  if ([part length] == 0) {
    return @"";
  }
  NSString *first = [[part substringToIndex:1] uppercaseString];
  NSString *rest = ([part length] > 1) ? [part substringFromIndex:1] : @"";
  return [NSString stringWithFormat:@"%@%@", first, rest];
}

static NSString *ALNORMTSComposeIdentifier(NSString *value,
                                           NSString *fallback,
                                           BOOL capitalizeFirst) {
  NSArray<NSString *> *parts = ALNORMTSIdentifierParts(value);
  if ([parts count] == 0) {
    parts = ALNORMTSIdentifierParts(fallback);
  }
  NSMutableString *identifier = [NSMutableString string];
  for (NSString *part in parts) {
    [identifier appendString:ALNORMTSCapitalizedPart(part)];
  }
  if ([identifier length] == 0) {
    [identifier appendString:capitalizeFirst ? @"Value" : @"value"];
  }
  if (!capitalizeFirst && [identifier length] > 0) {
    NSString *first = [[identifier substringToIndex:1] lowercaseString];
    NSString *rest = ([identifier length] > 1) ? [identifier substringFromIndex:1] : @"";
    [identifier setString:[NSString stringWithFormat:@"%@%@", first, rest]];
  }
  unichar firstCharacter = [identifier characterAtIndex:0];
  if (!((firstCharacter >= 'A' && firstCharacter <= 'Z') || (firstCharacter >= 'a' && firstCharacter <= 'z') ||
        firstCharacter == '_')) {
    [identifier insertString:(capitalizeFirst ? @"N" : @"n") atIndex:0];
  }
  return [NSString stringWithString:identifier];
}

static NSString *ALNORMTSEnsureIdentifier(NSString *value,
                                          NSString *fallback,
                                          NSString *reservedPrefix,
                                          BOOL capitalizeFirst) {
  NSString *composed = ALNORMTSComposeIdentifier(value, fallback, capitalizeFirst);
  NSMutableString *identifier =
      [NSMutableString stringWithString:[composed length] > 0 ? composed : (capitalizeFirst ? @"Value" : @"value")];
  if ([ALNORMTSReservedWords() containsObject:[identifier lowercaseString]]) {
    [identifier insertString:[ALNORMTSStringValue(reservedPrefix) length] > 0
                                 ? reservedPrefix
                                 : (capitalizeFirst ? @"Arlen" : @"arlen")
                    atIndex:0];
  }
  return [NSString stringWithString:identifier];
}

static NSString *ALNORMTSPascalIdentifier(NSString *value, NSString *fallback) {
  return ALNORMTSEnsureIdentifier(value, fallback, @"Arlen", YES);
}

static NSString *ALNORMTSCamelIdentifier(NSString *value, NSString *fallback) {
  return ALNORMTSEnsureIdentifier(value, fallback, @"arlen", NO);
}

static BOOL ALNORMTSPropertyIdentifierIsSafe(NSString *value) {
  NSString *identifier = ALNORMTSStringValue(value);
  if ([identifier length] == 0 || [ALNORMTSReservedWords() containsObject:[identifier lowercaseString]]) {
    return NO;
  }
  unichar first = [identifier characterAtIndex:0];
  if (!((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z') || first == '_')) {
    return NO;
  }
  for (NSUInteger idx = 1; idx < [identifier length]; idx++) {
    unichar character = [identifier characterAtIndex:idx];
    BOOL allowed = ((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') ||
                    (character >= '0' && character <= '9') || character == '_');
    if (!allowed) {
      return NO;
    }
  }
  return YES;
}

static NSString *ALNORMTSEscapeSingleQuotedString(NSString *value) {
  NSMutableString *escaped = [NSMutableString string];
  NSString *input = [ALNORMTSStringValue(value) copy];
  for (NSUInteger idx = 0; idx < [input length]; idx++) {
    unichar character = [input characterAtIndex:idx];
    switch (character) {
      case '\\':
        [escaped appendString:@"\\\\"];
        break;
      case '\'':
        [escaped appendString:@"\\'"];
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
        if (character < 0x20) {
          [escaped appendFormat:@"\\u%04x", character];
        } else {
          [escaped appendFormat:@"%C", character];
        }
        break;
    }
  }
  return [NSString stringWithString:escaped];
}

static NSString *ALNORMTSSingleQuotedString(NSString *value) {
  return [NSString stringWithFormat:@"'%@'", ALNORMTSEscapeSingleQuotedString(value)];
}

static NSString *ALNORMTSQuotedPropertyName(NSString *value) {
  return ALNORMTSPropertyIdentifierIsSafe(value) ? ALNORMTSStringValue(value) : ALNORMTSSingleQuotedString(value);
}

static NSString *ALNORMTSIndent(NSUInteger depth) {
  NSMutableString *indent = [NSMutableString string];
  for (NSUInteger idx = 0; idx < depth; idx++) {
    [indent appendString:@"  "];
  }
  return [NSString stringWithString:indent];
}

static NSJSONWritingOptions ALNORMTSJSONWritingOptions(void) {
  NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
#ifdef NSJSONWritingSortedKeys
  options |= NSJSONWritingSortedKeys;
#endif
  return options;
}

static NSString *ALNORMTSJSONStringFromObject(id object, NSError **error) {
  NSData *jsonData = [ALNJSONSerialization dataWithJSONObject:object ?: @{}
                                                      options:ALNORMTSJSONWritingOptions()
                                                        error:error];
  if (jsonData == nil) {
    return nil;
  }
  return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

static NSString *ALNORMTSSingularize(NSString *value) {
  NSString *normalized = [[ALNORMTSStringValue(value) lowercaseString] copy];
  if ([normalized hasSuffix:@"ies"] && [normalized length] > 3) {
    return [[normalized substringToIndex:[normalized length] - 3] stringByAppendingString:@"y"];
  }
  if ([normalized hasSuffix:@"sses"] || [normalized hasSuffix:@"shes"] || [normalized hasSuffix:@"ches"]) {
    return [normalized substringToIndex:[normalized length] - 2];
  }
  if ([normalized hasSuffix:@"ses"] && [normalized length] > 3) {
    return [normalized substringToIndex:[normalized length] - 2];
  }
  if ([normalized hasSuffix:@"s"] && ![normalized hasSuffix:@"ss"] && [normalized length] > 1) {
    return [normalized substringToIndex:[normalized length] - 1];
  }
  return normalized;
}

static NSString *ALNORMTSTypeNameForDescriptor(ALNORMModelDescriptor *descriptor) {
  NSString *schemaPart = ALNORMTSComposeIdentifier(descriptor.schemaName, @"Schema", YES);
  NSString *tablePart = ALNORMTSComposeIdentifier(ALNORMTSSingularize(descriptor.tableName), @"Model", YES);
  NSString *candidate = [NSString stringWithFormat:@"%@%@", schemaPart, tablePart];
  if ([candidate length] > 0) {
    return ALNORMTSPascalIdentifier(candidate, @"Model");
  }
  NSString *fallback = descriptor.className;
  if ([fallback hasSuffix:@"Model"] && [fallback length] > 5) {
    fallback = [fallback substringToIndex:[fallback length] - 5];
  }
  return ALNORMTSPascalIdentifier(fallback, @"Model");
}

static NSString *ALNORMTSHumanizedLabel(NSString *value) {
  NSArray<NSString *> *parts = ALNORMTSIdentifierParts(value);
  if ([parts count] == 0) {
    return [ALNORMTSStringValue(value) length] > 0 ? ALNORMTSStringValue(value) : @"Field";
  }
  NSMutableArray<NSString *> *words = [NSMutableArray array];
  for (NSString *part in parts) {
    [words addObject:ALNORMTSCapitalizedPart(part)];
  }
  return [words componentsJoinedByString:@" "];
}

static NSString *ALNORMTSFieldTypeForDescriptor(ALNORMFieldDescriptor *field) {
  NSString *normalized = [[ALNORMTSStringValue(field.dataType) lowercaseString] copy];
  if ([normalized hasSuffix:@"[]"]) {
    NSString *base = [normalized substringToIndex:[normalized length] - 2];
    ALNORMFieldDescriptor *nested =
        [[ALNORMFieldDescriptor alloc] initWithName:field.name
                                       propertyName:field.propertyName
                                         columnName:field.columnName
                                           dataType:base
                                           objcType:field.objcType
                                   runtimeClassName:field.runtimeClassName
                                  propertyAttribute:field.propertyAttribute
                                            ordinal:field.ordinal
                                           nullable:NO
                                         primaryKey:field.isPrimaryKey
                                             unique:field.isUnique
                                         hasDefault:field.hasDefaultValue
                                           readOnly:field.isReadOnly
                                  defaultValueShape:field.defaultValueShape];
    return [NSString stringWithFormat:@"Array<%@>", ALNORMTSFieldTypeForDescriptor(nested)];
  }
  if ([normalized isEqualToString:@"smallint"] || [normalized isEqualToString:@"integer"] ||
      [normalized isEqualToString:@"bigint"] || [normalized isEqualToString:@"numeric"] ||
      [normalized isEqualToString:@"decimal"] || [normalized isEqualToString:@"real"] ||
      [normalized isEqualToString:@"double precision"]) {
    return @"number";
  }
  if ([normalized isEqualToString:@"boolean"]) {
    return @"boolean";
  }
  if ([normalized isEqualToString:@"json"] || [normalized isEqualToString:@"jsonb"]) {
    return @"ArlenJSONValue";
  }
  if ([normalized isEqualToString:@"bytea"]) {
    return @"string";
  }
  if ([normalized hasPrefix:@"timestamp"] || [normalized isEqualToString:@"date"] ||
      [normalized isEqualToString:@"time"] || [normalized hasSuffix:@"time zone"] ||
      [normalized isEqualToString:@"uuid"] || [normalized isEqualToString:@"text"] ||
      [normalized hasPrefix:@"character"] || [normalized isEqualToString:@"inet"] ||
      [normalized isEqualToString:@"cidr"] || [normalized isEqualToString:@"macaddr"]) {
    return @"string";
  }
  return @"unknown";
}

static NSString *ALNORMTSValidatorKindForDataType(NSString *dataType) {
  NSString *normalized = [[ALNORMTSStringValue(dataType) lowercaseString] copy];
  if ([normalized hasSuffix:@"[]"]) {
    return @"array";
  }
  if ([normalized isEqualToString:@"smallint"] || [normalized isEqualToString:@"integer"] ||
      [normalized isEqualToString:@"bigint"] || [normalized isEqualToString:@"numeric"] ||
      [normalized isEqualToString:@"decimal"] || [normalized isEqualToString:@"real"] ||
      [normalized isEqualToString:@"double precision"]) {
    return @"number";
  }
  if ([normalized isEqualToString:@"boolean"]) {
    return @"boolean";
  }
  if ([normalized isEqualToString:@"json"] || [normalized isEqualToString:@"jsonb"]) {
    return @"json";
  }
  if ([normalized isEqualToString:@"bytea"] || [normalized hasPrefix:@"timestamp"] ||
      [normalized isEqualToString:@"date"] || [normalized isEqualToString:@"time"] ||
      [normalized hasSuffix:@"time zone"] || [normalized isEqualToString:@"uuid"] ||
      [normalized isEqualToString:@"text"] || [normalized hasPrefix:@"character"] ||
      [normalized isEqualToString:@"inet"] || [normalized isEqualToString:@"cidr"] ||
      [normalized isEqualToString:@"macaddr"]) {
    return @"string";
  }
  return @"unknown";
}

static NSString *ALNORMTSFormatHintForDataType(NSString *dataType) {
  NSString *normalized = [[ALNORMTSStringValue(dataType) lowercaseString] copy];
  if ([normalized isEqualToString:@"uuid"]) {
    return @"uuid";
  }
  if ([normalized hasPrefix:@"timestamp"]) {
    return @"date-time";
  }
  if ([normalized isEqualToString:@"date"]) {
    return @"date";
  }
  if ([normalized isEqualToString:@"time"] || [normalized hasSuffix:@"time zone"]) {
    return @"time";
  }
  if ([normalized isEqualToString:@"json"] || [normalized isEqualToString:@"jsonb"]) {
    return @"json";
  }
  return @"";
}

static NSString *ALNORMTSFormInputKindForDataType(NSString *dataType) {
  NSString *normalized = [[ALNORMTSStringValue(dataType) lowercaseString] copy];
  if ([normalized hasSuffix:@"[]"] || [normalized isEqualToString:@"json"] || [normalized isEqualToString:@"jsonb"]) {
    return @"json";
  }
  if ([normalized isEqualToString:@"boolean"]) {
    return @"checkbox";
  }
  if ([normalized isEqualToString:@"smallint"] || [normalized isEqualToString:@"integer"] ||
      [normalized isEqualToString:@"bigint"] || [normalized isEqualToString:@"numeric"] ||
      [normalized isEqualToString:@"decimal"] || [normalized isEqualToString:@"real"] ||
      [normalized isEqualToString:@"double precision"]) {
    return @"number";
  }
  if ([normalized hasPrefix:@"timestamp"]) {
    return @"datetime";
  }
  if ([normalized isEqualToString:@"date"]) {
    return @"date";
  }
  if ([normalized isEqualToString:@"time"] || [normalized hasSuffix:@"time zone"]) {
    return @"time";
  }
  return @"text";
}

static NSString *ALNORMTSNullableType(NSString *typeName, BOOL nullable) {
  NSString *base = [ALNORMTSStringValue(typeName) length] > 0 ? typeName : @"unknown";
  return nullable ? [NSString stringWithFormat:@"%@ | null", base] : base;
}

static NSString *ALNORMTSStringArrayExpression(NSArray<NSString *> *values) {
  NSMutableArray<NSString *> *quoted = [NSMutableArray array];
  for (NSString *value in values ?: @[]) {
    [quoted addObject:ALNORMTSSingleQuotedString(value)];
  }
  return [NSString stringWithFormat:@"[%@]", [quoted componentsJoinedByString:@", "]];
}

static NSString *ALNORMTSStringUnionExpression(NSArray<NSString *> *values) {
  NSMutableArray<NSString *> *quoted = [NSMutableArray array];
  for (NSString *value in values ?: @[]) {
    [quoted addObject:ALNORMTSSingleQuotedString(value)];
  }
  if ([quoted count] == 0) {
    return @"never";
  }
  return [quoted componentsJoinedByString:@" | "];
}

static NSString *ALNORMTSFieldSetArrayExpression(NSArray<NSArray<NSString *> *> *fieldSets) {
  NSMutableArray<NSString *> *rendered = [NSMutableArray array];
  for (NSArray<NSString *> *fieldSet in fieldSets ?: @[]) {
    [rendered addObject:ALNORMTSStringArrayExpression(fieldSet)];
  }
  return [NSString stringWithFormat:@"[%@]", [rendered componentsJoinedByString:@", "]];
}

static NSString *ALNORMTSRenderObjectType(NSArray<NSDictionary<NSString *, id> *> *properties,
                                          NSUInteger depth) {
  NSArray<NSDictionary<NSString *, id> *> *rows = [properties isKindOfClass:[NSArray class]] ? properties : @[];
  if ([rows count] == 0) {
    return @"Record<string, never>";
  }

  NSMutableString *output = [NSMutableString string];
  [output appendString:@"{\n"];
  for (NSDictionary<NSString *, id> *row in rows) {
    NSString *name = ALNORMTSStringValue(row[@"name"]);
    NSString *type = [ALNORMTSStringValue(row[@"type"]) length] > 0 ? row[@"type"] : @"unknown";
    BOOL optional = ALNORMTSBoolValue(row[@"optional"], NO);
    BOOL readOnly = ALNORMTSBoolValue(row[@"readonly"], NO);
    [output appendFormat:@"%@%@%@%@: %@;\n",
                         ALNORMTSIndent(depth + 1),
                         readOnly ? @"readonly " : @"",
                         ALNORMTSQuotedPropertyName(name),
                         optional ? @"?" : @"",
                         type];
  }
  [output appendFormat:@"%@}", ALNORMTSIndent(depth)];
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSLiteralTypeForValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"null";
  }
  if ([value isKindOfClass:[NSString class]]) {
    return ALNORMTSSingleQuotedString(value);
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    if (strcmp([(NSNumber *)value objCType], @encode(BOOL)) == 0) {
      return [value boolValue] ? @"true" : @"false";
    }
    return [value stringValue];
  }
  return nil;
}

static id ALNORMTSResolveSchemaReference(id rawSchema,
                                         NSDictionary<NSString *, id> *rootSpec,
                                         NSError **error);

static NSString *ALNORMTSRenderSchemaType(id rawSchema,
                                          NSDictionary<NSString *, id> *rootSpec,
                                          NSUInteger depth,
                                          NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  id resolved = ALNORMTSResolveSchemaReference(rawSchema, rootSpec, error);
  if (resolved == nil) {
    return nil;
  }
  NSDictionary<NSString *, id> *schema = ALNORMTSDictionaryValue(resolved);

  id typeValue = schema[@"type"];
  BOOL nullable = ALNORMTSBoolValue(schema[@"nullable"], NO);
  NSMutableArray<NSString *> *types = [NSMutableArray array];
  if ([typeValue isKindOfClass:[NSArray class]]) {
    for (id rawType in (NSArray *)typeValue) {
      NSString *normalized = [[ALNORMTSStringValue(rawType) lowercaseString] copy];
      if ([normalized isEqualToString:@"null"]) {
        nullable = YES;
      } else if ([normalized length] > 0) {
        [types addObject:normalized];
      }
    }
  } else {
    NSString *normalized = [[ALNORMTSStringValue(typeValue) lowercaseString] copy];
    if ([normalized isEqualToString:@"null"]) {
      nullable = YES;
    } else if ([normalized length] > 0) {
      [types addObject:normalized];
    }
  }

  NSArray *enumValues = [schema[@"enum"] isKindOfClass:[NSArray class]] ? schema[@"enum"] : nil;
  if ([enumValues count] > 0) {
    NSMutableArray<NSString *> *literals = [NSMutableArray array];
    for (id value in enumValues) {
      NSString *literal = ALNORMTSLiteralTypeForValue(value);
      if ([literal length] == 0) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI enum contains unsupported literal value",
                                   nil);
        }
        return nil;
      }
      [literals addObject:literal];
    }
    NSString *enumType = [literals componentsJoinedByString:@" | "];
    return nullable ? [NSString stringWithFormat:@"%@ | null", enumType] : enumType;
  }

  NSArray *oneOf = [schema[@"oneOf"] isKindOfClass:[NSArray class]] ? schema[@"oneOf"] : nil;
  if ([oneOf count] > 0) {
    NSMutableArray<NSString *> *members = [NSMutableArray array];
    for (id member in oneOf) {
      NSString *rendered = ALNORMTSRenderSchemaType(member, rootSpec, depth, error);
      if ([rendered length] == 0) {
        return nil;
      }
      [members addObject:rendered];
    }
    NSString *unionType = [members componentsJoinedByString:@" | "];
    return nullable ? [NSString stringWithFormat:@"%@ | null", unionType] : unionType;
  }

  NSArray *anyOf = [schema[@"anyOf"] isKindOfClass:[NSArray class]] ? schema[@"anyOf"] : nil;
  if ([anyOf count] > 0) {
    NSMutableArray<NSString *> *members = [NSMutableArray array];
    for (id member in anyOf) {
      NSString *rendered = ALNORMTSRenderSchemaType(member, rootSpec, depth, error);
      if ([rendered length] == 0) {
        return nil;
      }
      [members addObject:rendered];
    }
    NSString *unionType = [members componentsJoinedByString:@" | "];
    return nullable ? [NSString stringWithFormat:@"%@ | null", unionType] : unionType;
  }

  NSArray *allOf = [schema[@"allOf"] isKindOfClass:[NSArray class]] ? schema[@"allOf"] : nil;
  if ([allOf count] > 0) {
    NSMutableArray<NSString *> *members = [NSMutableArray array];
    for (id member in allOf) {
      NSString *rendered = ALNORMTSRenderSchemaType(member, rootSpec, depth, error);
      if ([rendered length] == 0) {
        return nil;
      }
      [members addObject:rendered];
    }
    NSString *intersectionType = [members componentsJoinedByString:@" & "];
    return nullable ? [NSString stringWithFormat:@"%@ | null", intersectionType] : intersectionType;
  }

  NSString *rendered = @"unknown";
  NSString *primaryType = ([types count] > 0) ? types[0] : @"";
  NSDictionary<NSString *, id> *properties = ALNORMTSDictionaryValue(schema[@"properties"]);
  NSArray<NSString *> *requiredFields = ALNORMTSNormalizedStringArray(schema[@"required"]);

  if ([primaryType isEqualToString:@"string"]) {
    rendered = @"string";
  } else if ([primaryType isEqualToString:@"integer"] || [primaryType isEqualToString:@"number"]) {
    rendered = @"number";
  } else if ([primaryType isEqualToString:@"boolean"]) {
    rendered = @"boolean";
  } else if ([primaryType isEqualToString:@"array"]) {
    NSDictionary<NSString *, id> *items = ALNORMTSDictionaryValue(schema[@"items"]);
    NSString *itemType = ALNORMTSRenderSchemaType(items, rootSpec, depth, error);
    if ([itemType length] == 0) {
      return nil;
    }
    rendered = [NSString stringWithFormat:@"Array<%@>", itemType];
  } else if ([primaryType isEqualToString:@"object"] || [properties count] > 0) {
    if ([properties count] == 0) {
      id additionalProperties = schema[@"additionalProperties"];
      if ([additionalProperties isKindOfClass:[NSDictionary class]]) {
        NSString *valueType = ALNORMTSRenderSchemaType(additionalProperties, rootSpec, depth, error);
        if ([valueType length] == 0) {
          return nil;
        }
        rendered = [NSString stringWithFormat:@"Record<string, %@>", valueType];
      } else if (ALNORMTSBoolValue(additionalProperties, NO)) {
        rendered = @"Record<string, unknown>";
      } else {
        rendered = @"Record<string, unknown>";
      }
    } else {
      NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
      NSArray<NSString *> *sortedNames = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
      for (NSString *name in sortedNames) {
        NSString *type = ALNORMTSRenderSchemaType(properties[name], rootSpec, depth + 1, error);
        if ([type length] == 0) {
          return nil;
        }
        [rows addObject:@{
          @"name" : name,
          @"type" : type,
          @"optional" : ALNORMTSBoolNumber(![requiredFields containsObject:name]),
        }];
      }
      rendered = ALNORMTSRenderObjectType(rows, depth);
    }
  } else if ([primaryType isEqualToString:@"null"]) {
    rendered = @"null";
  }

  return nullable && ![rendered containsString:@"| null"]
             ? [NSString stringWithFormat:@"%@ | null", rendered]
             : rendered;
}

static id ALNORMTSResolveSchemaReference(id rawSchema,
                                         NSDictionary<NSString *, id> *rootSpec,
                                         NSError **error) {
  NSDictionary<NSString *, id> *schema = ALNORMTSDictionaryValue(rawSchema);
  NSString *reference = ALNORMTSStringValue(schema[@"$ref"]);
  if ([reference length] == 0) {
    return schema;
  }
  if (![reference hasPrefix:@"#/"]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                               @"OpenAPI schema reference must be local",
                               @{
                                 @"reference" : reference ?: @"",
                               });
    }
    return nil;
  }
  id cursor = rootSpec;
  NSArray<NSString *> *parts = [[reference substringFromIndex:2] componentsSeparatedByString:@"/"];
  for (NSString *part in parts) {
    NSString *decoded = [[part stringByReplacingOccurrencesOfString:@"~1" withString:@"/"]
        stringByReplacingOccurrencesOfString:@"~0"
                                  withString:@"~"];
    if (![cursor isKindOfClass:[NSDictionary class]]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI schema reference points at a non-object node",
                                 @{
                                   @"reference" : reference ?: @"",
                                 });
      }
      return nil;
    }
    cursor = ((NSDictionary *)cursor)[decoded];
    if (cursor == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI schema reference could not be resolved",
                                 @{
                                   @"reference" : reference ?: @"",
                                 });
      }
      return nil;
    }
  }
  return cursor;
}

static NSDictionary<NSString *, id> *ALNORMTSValidatorSchemaFromOpenAPISchema(id rawSchema,
                                                                               NSDictionary<NSString *, id> *rootSpec,
                                                                               NSError **error);

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSValidatorSchemaMembersFromSchemas(
    NSArray *schemas,
    NSDictionary<NSString *, id> *rootSpec,
    NSError **error) {
  NSMutableArray<NSDictionary<NSString *, id> *> *members = [NSMutableArray array];
  for (id rawMember in schemas ?: @[]) {
    NSDictionary<NSString *, id> *member = ALNORMTSValidatorSchemaFromOpenAPISchema(rawMember, rootSpec, error);
    if (member == nil) {
      return nil;
    }
    [members addObject:member];
  }
  return [NSArray arrayWithArray:members];
}

static NSDictionary<NSString *, id> *ALNORMTSValidatorSchemaFromOpenAPISchema(id rawSchema,
                                                                               NSDictionary<NSString *, id> *rootSpec,
                                                                               NSError **error) {
  if (error != NULL) {
    *error = nil;
  }

  id resolved = ALNORMTSResolveSchemaReference(rawSchema, rootSpec, error);
  if (resolved == nil) {
    return nil;
  }

  NSDictionary<NSString *, id> *schema = ALNORMTSDictionaryValue(resolved);
  NSMutableDictionary<NSString *, id> *validator = [NSMutableDictionary dictionary];

  BOOL nullable = ALNORMTSBoolValue(schema[@"nullable"], NO);
  NSMutableArray<NSString *> *types = [NSMutableArray array];
  id typeValue = schema[@"type"];
  if ([typeValue isKindOfClass:[NSArray class]]) {
    for (id rawType in (NSArray *)typeValue) {
      NSString *normalized = [[ALNORMTSStringValue(rawType) lowercaseString] copy];
      if ([normalized isEqualToString:@"null"]) {
        nullable = YES;
      } else if ([normalized length] > 0) {
        [types addObject:normalized];
      }
    }
  } else {
    NSString *normalized = [[ALNORMTSStringValue(typeValue) lowercaseString] copy];
    if ([normalized isEqualToString:@"null"]) {
      nullable = YES;
    } else if ([normalized length] > 0) {
      [types addObject:normalized];
    }
  }

  NSString *formatHint = ALNORMTSStringValue(schema[@"format"]);
  if ([formatHint length] > 0) {
    validator[@"formatHint"] = formatHint;
  }
  validator[@"nullable"] = @(nullable);

  NSArray *enumValues = [schema[@"enum"] isKindOfClass:[NSArray class]] ? schema[@"enum"] : nil;
  if ([enumValues count] > 0) {
    validator[@"kind"] = @"enum";
    validator[@"literalValues"] = enumValues;
    return [NSDictionary dictionaryWithDictionary:validator];
  }

  NSArray *oneOf = [schema[@"oneOf"] isKindOfClass:[NSArray class]] ? schema[@"oneOf"] : nil;
  if ([oneOf count] > 0) {
    NSArray<NSDictionary<NSString *, id> *> *members =
        ALNORMTSValidatorSchemaMembersFromSchemas(oneOf, rootSpec, error);
    if (members == nil) {
      return nil;
    }
    validator[@"kind"] = @"union";
    validator[@"members"] = members;
    return [NSDictionary dictionaryWithDictionary:validator];
  }

  NSArray *anyOf = [schema[@"anyOf"] isKindOfClass:[NSArray class]] ? schema[@"anyOf"] : nil;
  if ([anyOf count] > 0) {
    NSArray<NSDictionary<NSString *, id> *> *members =
        ALNORMTSValidatorSchemaMembersFromSchemas(anyOf, rootSpec, error);
    if (members == nil) {
      return nil;
    }
    validator[@"kind"] = @"union";
    validator[@"members"] = members;
    return [NSDictionary dictionaryWithDictionary:validator];
  }

  NSArray *allOf = [schema[@"allOf"] isKindOfClass:[NSArray class]] ? schema[@"allOf"] : nil;
  if ([allOf count] > 0) {
    NSArray<NSDictionary<NSString *, id> *> *members =
        ALNORMTSValidatorSchemaMembersFromSchemas(allOf, rootSpec, error);
    if (members == nil) {
      return nil;
    }
    validator[@"kind"] = @"intersection";
    validator[@"members"] = members;
    return [NSDictionary dictionaryWithDictionary:validator];
  }

  NSDictionary<NSString *, id> *properties = ALNORMTSDictionaryValue(schema[@"properties"]);
  NSArray<NSString *> *requiredFields = ALNORMTSNormalizedStringArray(schema[@"required"]);
  NSString *primaryType = ([types count] > 0) ? types[0] : @"";

  if ([primaryType isEqualToString:@"string"]) {
    validator[@"kind"] = @"string";
    return [NSDictionary dictionaryWithDictionary:validator];
  }
  if ([primaryType isEqualToString:@"integer"] || [primaryType isEqualToString:@"number"]) {
    validator[@"kind"] = @"number";
    return [NSDictionary dictionaryWithDictionary:validator];
  }
  if ([primaryType isEqualToString:@"boolean"]) {
    validator[@"kind"] = @"boolean";
    return [NSDictionary dictionaryWithDictionary:validator];
  }
  if ([primaryType isEqualToString:@"null"]) {
    validator[@"kind"] = @"null";
    validator[@"nullable"] = @YES;
    return [NSDictionary dictionaryWithDictionary:validator];
  }
  if ([primaryType isEqualToString:@"array"]) {
    validator[@"kind"] = @"array";
    NSDictionary<NSString *, id> *items = ALNORMTSDictionaryValue(schema[@"items"]);
    if ([items count] > 0) {
      NSDictionary<NSString *, id> *itemSchema = ALNORMTSValidatorSchemaFromOpenAPISchema(items, rootSpec, error);
      if (itemSchema == nil) {
        return nil;
      }
      validator[@"items"] = itemSchema;
    } else {
      validator[@"items"] = @{ @"kind" : @"unknown", @"nullable" : @NO };
    }
    return [NSDictionary dictionaryWithDictionary:validator];
  }
  if ([primaryType isEqualToString:@"object"] || [properties count] > 0) {
    validator[@"kind"] = @"object";
    NSMutableDictionary<NSString *, id> *validatorProperties = [NSMutableDictionary dictionary];
    NSArray<NSString *> *sortedPropertyNames = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in sortedPropertyNames) {
      NSDictionary<NSString *, id> *propertySchema =
          ALNORMTSValidatorSchemaFromOpenAPISchema(properties[name], rootSpec, error);
      if (propertySchema == nil) {
        return nil;
      }
      validatorProperties[name] = propertySchema;
    }
    validator[@"properties"] = validatorProperties;
    validator[@"requiredFields"] = requiredFields ?: @[];
    id additionalProperties = schema[@"additionalProperties"];
    if ([additionalProperties isKindOfClass:[NSDictionary class]]) {
      NSDictionary<NSString *, id> *additionalSchema =
          ALNORMTSValidatorSchemaFromOpenAPISchema(additionalProperties, rootSpec, error);
      if (additionalSchema == nil) {
        return nil;
      }
      validator[@"additionalProperties"] = additionalSchema;
    } else if (additionalProperties != nil) {
      validator[@"additionalProperties"] = @(ALNORMTSBoolValue(additionalProperties, NO));
    }
    return [NSDictionary dictionaryWithDictionary:validator];
  }

  validator[@"kind"] = @"unknown";
  return [NSDictionary dictionaryWithDictionary:validator];
}

static NSDictionary<NSString *, id> *ALNORMTSValidatorSchemaForFieldDescriptor(ALNORMFieldDescriptor *field) {
  NSString *dataType = ALNORMTSStringValue(field.dataType);
  NSString *kind = ALNORMTSValidatorKindForDataType(dataType);
  NSMutableDictionary<NSString *, id> *schema = [NSMutableDictionary dictionary];
  schema[@"kind"] = kind;
  schema[@"nullable"] = @(field.isNullable);
  NSString *formatHint = ALNORMTSFormatHintForDataType(dataType);
  if ([formatHint length] > 0) {
    schema[@"formatHint"] = formatHint;
  }
  if ([kind isEqualToString:@"array"]) {
    NSString *baseType = [dataType hasSuffix:@"[]"] ? [dataType substringToIndex:[dataType length] - 2] : @"";
    schema[@"items"] = @{
      @"kind" : ALNORMTSValidatorKindForDataType(baseType),
      @"nullable" : @NO,
      @"formatHint" : ALNORMTSFormatHintForDataType(baseType),
    };
  }
  return [NSDictionary dictionaryWithDictionary:schema];
}

static NSDictionary<NSString *, id> *ALNORMTSValidatorObjectSchema(NSArray<NSDictionary<NSString *, id> *> *rows,
                                                                   BOOL allowAdditionalProperties) {
  NSMutableDictionary<NSString *, id> *properties = [NSMutableDictionary dictionary];
  NSMutableArray<NSString *> *requiredFields = [NSMutableArray array];
  NSMutableArray<NSString *> *readonlyFields = [NSMutableArray array];
  NSMutableArray<NSString *> *writableFields = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
    NSString *name = ALNORMTSStringValue(row[@"name"]);
    NSDictionary<NSString *, id> *schema = ALNORMTSDictionaryValue(row[@"schema"]);
    if ([name length] == 0 || [schema count] == 0) {
      continue;
    }
    properties[name] = schema;
    if (ALNORMTSBoolValue(row[@"required"], NO)) {
      [requiredFields addObject:name];
    }
    if (ALNORMTSBoolValue(row[@"readOnly"], NO)) {
      [readonlyFields addObject:name];
    } else {
      [writableFields addObject:name];
    }
  }

  return @{
    @"kind" : @"object",
    @"nullable" : @NO,
    @"properties" : properties,
    @"requiredFields" : requiredFields,
    @"readonlyFields" : readonlyFields,
    @"writableFields" : writableFields,
    @"additionalProperties" : @(allowAdditionalProperties),
  };
}

static NSArray<NSString *> *ALNORMTSOrderedHTTPMethods(void) {
  return @[ @"delete", @"get", @"head", @"options", @"patch", @"post", @"put", @"trace" ];
}

static NSArray<NSString *> *ALNORMTSPathParameterNames(NSString *path) {
  NSString *input = ALNORMTSStringValue(path);
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  NSUInteger cursor = 0;
  while (cursor < [input length]) {
    NSRange openRange = [input rangeOfString:@"{" options:0 range:NSMakeRange(cursor, [input length] - cursor)];
    if (openRange.location == NSNotFound) {
      break;
    }
    NSRange closeRange = [input rangeOfString:@"}" options:0 range:NSMakeRange(NSMaxRange(openRange),
                                                                                [input length] - NSMaxRange(openRange))];
    if (closeRange.location == NSNotFound) {
      break;
    }
    NSString *name = [input substringWithRange:NSMakeRange(NSMaxRange(openRange),
                                                           closeRange.location - NSMaxRange(openRange))];
    name = ALNORMTSStringValue(name);
    if ([name length] > 0 && ![names containsObject:name]) {
      [names addObject:name];
    }
    cursor = NSMaxRange(closeRange);
  }
  return [NSArray arrayWithArray:names];
}

static NSArray<NSString *> *ALNORMTSDerivedOperationTags(NSString *path) {
  NSArray<NSString *> *segments = [ALNORMTSStringValue(path) componentsSeparatedByString:@"/"];
  NSMutableArray<NSString *> *tags = [NSMutableArray array];
  for (NSString *segment in segments) {
    NSString *value = ALNORMTSStringValue(segment);
    if ([value length] == 0 || [value hasPrefix:@"{"]) {
      continue;
    }
    if ([[value lowercaseString] isEqualToString:@"api"]) {
      continue;
    }
    [tags addObject:[value lowercaseString]];
    break;
  }
  if ([tags count] == 0) {
    [tags addObject:@"default"];
  }
  return [NSArray arrayWithArray:tags];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSMergedOperationParameters(
    NSDictionary<NSString *, id> *pathItem,
    NSDictionary<NSString *, id> *operation) {
  NSMutableArray<NSDictionary<NSString *, id> *> *parameters = [NSMutableArray array];
  NSArray *pathParameters = [pathItem[@"parameters"] isKindOfClass:[NSArray class]] ? pathItem[@"parameters"] : @[];
  NSArray *operationParameters =
      [operation[@"parameters"] isKindOfClass:[NSArray class]] ? operation[@"parameters"] : @[];
  for (id parameter in pathParameters) {
    if ([parameter isKindOfClass:[NSDictionary class]]) {
      [parameters addObject:parameter];
    }
  }
  for (id parameter in operationParameters) {
    if ([parameter isKindOfClass:[NSDictionary class]]) {
      [parameters addObject:parameter];
    }
  }
  return [NSArray arrayWithArray:parameters];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSOperationsFromOpenAPISpecification(
    NSDictionary<NSString *, id> *specification,
    NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (![specification isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"OpenAPI specification must be a dictionary",
                               nil);
    }
    return nil;
  }
  NSDictionary<NSString *, id> *paths = ALNORMTSDictionaryValue(specification[@"paths"]);
  NSMutableArray<NSDictionary<NSString *, id> *> *operations = [NSMutableArray array];
  NSMutableSet<NSString *> *usedMethodNames = [NSMutableSet set];
  NSMutableSet<NSString *> *usedTypeNames = [NSMutableSet set];

  NSArray<NSString *> *sortedPaths = [[paths allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSArray<NSString *> *orderedMethods = ALNORMTSOrderedHTTPMethods();
  for (NSString *path in sortedPaths) {
    NSDictionary<NSString *, id> *pathItem = ALNORMTSDictionaryValue(paths[path]);
    NSArray<NSString *> *requiredPathParams = ALNORMTSPathParameterNames(path);

    for (NSString *method in orderedMethods) {
      NSDictionary<NSString *, id> *operation = ALNORMTSDictionaryValue(pathItem[method]);
      if ([operation count] == 0) {
        continue;
      }

      NSString *operationID = ALNORMTSStringValue(operation[@"operationId"]);
      if ([operationID length] == 0) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI operation is missing a stable operationId",
                                   @{
                                     @"path" : path ?: @"",
                                     @"method" : [method uppercaseString],
                                   });
        }
        return nil;
      }

      NSString *typeName = ALNORMTSPascalIdentifier(operationID, @"Operation");
      NSString *methodName = ALNORMTSCamelIdentifier(operationID, @"operation");
      if ([usedTypeNames containsObject:typeName] || [usedMethodNames containsObject:methodName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorIdentifierCollision,
                                   @"OpenAPI operationId collides after TypeScript normalization",
                                   @{
                                     @"operation_id" : operationID ?: @"",
                                     @"type_name" : typeName ?: @"",
                                     @"method_name" : methodName ?: @"",
                                   });
        }
        return nil;
      }
      [usedTypeNames addObject:typeName];
      [usedMethodNames addObject:methodName];

      NSMutableArray<NSDictionary<NSString *, id> *> *pathProperties = [NSMutableArray array];
      NSMutableArray<NSDictionary<NSString *, id> *> *queryProperties = [NSMutableArray array];
      NSMutableArray<NSDictionary<NSString *, id> *> *headerProperties = [NSMutableArray array];
      NSMutableSet<NSString *> *seenPathNames = [NSMutableSet set];
      NSMutableSet<NSString *> *seenQueryNames = [NSMutableSet set];
      NSMutableSet<NSString *> *seenHeaderNames = [NSMutableSet set];

      for (NSDictionary<NSString *, id> *parameter in ALNORMTSMergedOperationParameters(pathItem, operation)) {
        NSString *name = ALNORMTSStringValue(parameter[@"name"]);
        NSString *location = [[ALNORMTSStringValue(parameter[@"in"]) lowercaseString] copy];
        NSDictionary<NSString *, id> *schema = ALNORMTSDictionaryValue(parameter[@"schema"]);
        if ([name length] == 0 || [location length] == 0 || [schema count] == 0) {
          if (error != NULL) {
            *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                     @"OpenAPI parameter is missing required fields",
                                     @{
                                       @"operation_id" : operationID ?: @"",
                                     });
          }
          return nil;
        }

        NSString *type = ALNORMTSRenderSchemaType(schema, specification, 2, error);
        if ([type length] == 0) {
          return nil;
        }
        BOOL required = ALNORMTSBoolValue(parameter[@"required"], [location isEqualToString:@"path"]);
        NSDictionary<NSString *, id> *row = @{
          @"name" : name,
          @"type" : type,
          @"optional" : ALNORMTSBoolNumber(!required),
          @"schema" : schema,
        };

        if ([location isEqualToString:@"path"]) {
          [seenPathNames addObject:name];
          [pathProperties addObject:row];
        } else if ([location isEqualToString:@"query"]) {
          if (![seenQueryNames containsObject:name]) {
            [seenQueryNames addObject:name];
            [queryProperties addObject:row];
          }
        } else if ([location isEqualToString:@"header"]) {
          if (![seenHeaderNames containsObject:name]) {
            [seenHeaderNames addObject:name];
            [headerProperties addObject:row];
          }
        } else {
          if (error != NULL) {
            *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                     @"OpenAPI parameter location is unsupported",
                                     @{
                                       @"operation_id" : operationID ?: @"",
                                       @"location" : location ?: @"",
                                     });
          }
          return nil;
        }
      }

      for (NSString *requiredPathParam in requiredPathParams) {
        if (![seenPathNames containsObject:requiredPathParam]) {
          if (error != NULL) {
            *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                     @"OpenAPI path parameter is missing from parameter list",
                                     @{
                                       @"operation_id" : operationID ?: @"",
                                       @"path_parameter" : requiredPathParam ?: @"",
                                     });
          }
          return nil;
        }
      }

      NSDictionary<NSString *, id> *requestBody = ALNORMTSDictionaryValue(operation[@"requestBody"]);
      NSDictionary<NSString *, id> *requestContent = ALNORMTSDictionaryValue(requestBody[@"content"]);
      NSDictionary<NSString *, id> *jsonRequestBody = ALNORMTSDictionaryValue(requestContent[@"application/json"]);
      NSString *bodyType = nil;
      BOOL bodyRequired = NO;
      NSDictionary<NSString *, id> *bodySchema = @{};
      if ([requestBody count] > 0) {
        bodySchema = ALNORMTSDictionaryValue(jsonRequestBody[@"schema"]);
        if ([bodySchema count] == 0) {
          if (error != NULL) {
            *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                     @"OpenAPI requestBody must define application/json schema",
                                     @{
                                       @"operation_id" : operationID ?: @"",
                                     });
          }
          return nil;
        }
        bodyType = ALNORMTSRenderSchemaType(bodySchema, specification, 1, error);
        if ([bodyType length] == 0) {
          return nil;
        }
        bodyRequired = ALNORMTSBoolValue(requestBody[@"required"], NO);
      }

      NSDictionary<NSString *, id> *responses = ALNORMTSDictionaryValue(operation[@"responses"]);
      if ([responses count] == 0) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI operation must declare responses",
                                   @{
                                     @"operation_id" : operationID ?: @"",
                                   });
        }
        return nil;
      }

      NSArray<NSString *> *responseCodes = [[responses allKeys] sortedArrayUsingSelector:@selector(compare:)];
      NSString *responseType = @"void";
      BOOL sawSuccessResponse = NO;
      for (NSString *code in responseCodes) {
        if (![code hasPrefix:@"2"]) {
          continue;
        }
        sawSuccessResponse = YES;
        NSDictionary<NSString *, id> *response = ALNORMTSDictionaryValue(responses[code]);
        NSDictionary<NSString *, id> *content = ALNORMTSDictionaryValue(response[@"content"]);
        NSDictionary<NSString *, id> *jsonContent = ALNORMTSDictionaryValue(content[@"application/json"]);
        NSDictionary<NSString *, id> *schema = ALNORMTSDictionaryValue(jsonContent[@"schema"]);
        if ([content count] == 0 || [jsonContent count] == 0 || [schema count] == 0) {
          responseType = @"void";
        } else {
          responseType = ALNORMTSRenderSchemaType(schema, specification, 0, error);
          if ([responseType length] == 0) {
            return nil;
          }
        }
        break;
      }
      if (!sawSuccessResponse) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI operation must define at least one 2xx response",
                                   @{
                                     @"operation_id" : operationID ?: @"",
                                   });
        }
        return nil;
      }

      NSArray<NSString *> *tags = [ALNORMTSNormalizedStringArray(operation[@"tags"]) count] > 0
                                      ? ALNORMTSNormalizedStringArray(operation[@"tags"])
                                      : ALNORMTSDerivedOperationTags(path);
      [operations addObject:@{
        @"operationId" : operationID,
        @"typeName" : typeName,
        @"methodName" : methodName,
        @"summary" : ALNORMTSStringValue(operation[@"summary"]) ?: @"",
        @"httpMethod" : [method uppercaseString],
        @"path" : path ?: @"/",
        @"tags" : tags ?: @[],
        @"kind" : @(([method isEqualToString:@"get"] || [method isEqualToString:@"head"])
                        ? ALNORMTSOperationKindQuery
                        : ALNORMTSOperationKindMutation),
        @"pathProperties" : pathProperties,
        @"queryProperties" : queryProperties,
        @"headerProperties" : headerProperties,
        @"bodyType" : bodyType ?: @"",
        @"bodySchema" : bodySchema ?: @{},
        @"bodyRequired" : @(bodyRequired),
        @"responseType" : responseType ?: @"void",
      }];
    }
  }
  return [NSArray arrayWithArray:operations];
}

static NSDictionary<NSString *, id> *ALNORMTSArlenExtensionRoot(NSDictionary<NSString *, id> *openAPISpecification) {
  return ALNORMTSDictionaryValue(openAPISpecification[@"x-arlen"]);
}

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSNormalizedExtensionEntries(id rawValue,
                                                                                    NSString *nameKey) {
  NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
  if ([rawValue isKindOfClass:[NSArray class]]) {
    for (id rawEntry in (NSArray *)rawValue) {
      NSDictionary<NSString *, id> *entry = ALNORMTSDictionaryValue(rawEntry);
      if ([entry count] > 0) {
        [entries addObject:entry];
      }
    }
    return [NSArray arrayWithArray:entries];
  }
  NSDictionary<NSString *, id> *dictionary = ALNORMTSDictionaryValue(rawValue);
  NSArray<NSString *> *sortedNames = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in sortedNames) {
    NSDictionary<NSString *, id> *entry = [dictionary[name] isKindOfClass:[NSDictionary class]] ? dictionary[name] : nil;
    if ([entry count] == 0) {
      continue;
    }
    NSMutableDictionary<NSString *, id> *normalized = [entry mutableCopy];
    if ([ALNORMTSStringValue(normalized[nameKey]) length] == 0) {
      normalized[nameKey] = name;
    }
    [entries addObject:normalized];
  }
  return [NSArray arrayWithArray:entries];
}

static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *ALNORMTSOperationsByID(
    NSArray<NSDictionary<NSString *, id> *> *operations) {
  NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *mapping = [NSMutableDictionary dictionary];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    NSString *operationID = ALNORMTSStringValue(operation[@"operationId"]);
    if ([operationID length] > 0) {
      mapping[operationID] = operation;
    }
  }
  return [NSDictionary dictionaryWithDictionary:mapping];
}

static ALNORMFieldDescriptor *ALNORMTSFieldDescriptorFromDictionary(NSDictionary<NSString *, id> *dictionary) {
  return [[ALNORMFieldDescriptor alloc] initWithName:ALNORMTSStringValue(dictionary[@"name"])
                                        propertyName:ALNORMTSStringValue(dictionary[@"property_name"])
                                          columnName:ALNORMTSStringValue(dictionary[@"column_name"])
                                            dataType:ALNORMTSStringValue(dictionary[@"data_type"])
                                            objcType:ALNORMTSStringValue(dictionary[@"objc_type"])
                                    runtimeClassName:ALNORMTSStringValue(dictionary[@"runtime_class_name"])
                                   propertyAttribute:ALNORMTSStringValue(dictionary[@"property_attribute"])
                                             ordinal:ALNORMTSIntegerValue(dictionary[@"ordinal"], 0)
                                            nullable:ALNORMTSBoolValue(dictionary[@"nullable"], YES)
                                          primaryKey:ALNORMTSBoolValue(dictionary[@"primary_key"], NO)
                                              unique:ALNORMTSBoolValue(dictionary[@"unique"], NO)
                                          hasDefault:ALNORMTSBoolValue(dictionary[@"has_default"], NO)
                                            readOnly:ALNORMTSBoolValue(dictionary[@"read_only"], NO)
                                   defaultValueShape:ALNORMTSStringValue(dictionary[@"default_value_shape"])];
}

static ALNORMRelationDescriptor *ALNORMTSRelationDescriptorFromDictionary(NSDictionary<NSString *, id> *dictionary) {
  return [[ALNORMRelationDescriptor alloc]
      initWithKind:ALNORMRelationKindFromString(ALNORMTSStringValue(dictionary[@"kind"]))
             name:ALNORMTSStringValue(dictionary[@"name"])
     sourceEntityName:ALNORMTSStringValue(dictionary[@"source_entity_name"])
     targetEntityName:ALNORMTSStringValue(dictionary[@"target_entity_name"])
      targetClassName:ALNORMTSStringValue(dictionary[@"target_class_name"])
    throughEntityName:ALNORMTSStringValue(dictionary[@"through_entity_name"])
     throughClassName:ALNORMTSStringValue(dictionary[@"through_class_name"])
     sourceFieldNames:ALNORMTSNormalizedStringArray(dictionary[@"source_field_names"])
     targetFieldNames:ALNORMTSNormalizedStringArray(dictionary[@"target_field_names"])
  throughSourceFieldNames:ALNORMTSNormalizedStringArray(dictionary[@"through_source_field_names"])
  throughTargetFieldNames:ALNORMTSNormalizedStringArray(dictionary[@"through_target_field_names"])
          pivotFieldNames:ALNORMTSNormalizedStringArray(dictionary[@"pivot_field_names"])
                 readOnly:ALNORMTSBoolValue(dictionary[@"read_only"], NO)
                 inferred:ALNORMTSBoolValue(dictionary[@"inferred"], NO)];
}

static NSArray<ALNORMModelDescriptor *> *ALNORMTSModelDescriptorsFromORMManifest(
    NSDictionary<NSString *, id> *manifest,
    NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (![manifest isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"ORM manifest must be a dictionary",
                               nil);
    }
    return nil;
  }

  NSArray *models = [manifest[@"models"] isKindOfClass:[NSArray class]] ? manifest[@"models"] : nil;
  if (models == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                               @"ORM manifest must define a models array",
                               nil);
    }
    return nil;
  }

  NSMutableArray<ALNORMModelDescriptor *> *descriptors = [NSMutableArray array];
  NSMutableSet<NSString *> *seenEntities = [NSMutableSet set];
  for (id rawModel in models) {
    NSDictionary<NSString *, id> *model = ALNORMTSDictionaryValue(rawModel);
    NSString *entityName = ALNORMTSStringValue(model[@"entity_name"]);
    if ([entityName length] == 0 || [seenEntities containsObject:entityName]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"ORM manifest contains invalid or duplicate entity_name",
                                 @{
                                   @"entity_name" : entityName ?: @"",
                                 });
      }
      return nil;
    }
    [seenEntities addObject:entityName];

    NSMutableArray<ALNORMFieldDescriptor *> *fields = [NSMutableArray array];
    for (id rawField in [model[@"fields"] isKindOfClass:[NSArray class]] ? model[@"fields"] : @[]) {
      [fields addObject:ALNORMTSFieldDescriptorFromDictionary(ALNORMTSDictionaryValue(rawField))];
    }

    NSMutableArray<ALNORMRelationDescriptor *> *relations = [NSMutableArray array];
    for (id rawRelation in [model[@"relations"] isKindOfClass:[NSArray class]] ? model[@"relations"] : @[]) {
      [relations addObject:ALNORMTSRelationDescriptorFromDictionary(ALNORMTSDictionaryValue(rawRelation))];
    }

    ALNORMModelDescriptor *descriptor =
        [[ALNORMModelDescriptor alloc] initWithClassName:ALNORMTSStringValue(model[@"class_name"])
                                             entityName:entityName
                                             schemaName:ALNORMTSStringValue(model[@"schema_name"])
                                              tableName:ALNORMTSStringValue(model[@"table_name"])
                                     qualifiedTableName:ALNORMTSStringValue(model[@"qualified_table_name"])
                                           relationKind:ALNORMTSStringValue(model[@"relation_kind"])
                                         databaseTarget:ALNORMTSStringValue(model[@"database_target"])
                                               readOnly:ALNORMTSBoolValue(model[@"read_only"], NO)
                                                 fields:fields
                                   primaryKeyFieldNames:ALNORMTSNormalizedStringArray(model[@"primary_key_field_names"])
                               uniqueConstraintFieldSets:
                                   ([model[@"unique_constraint_field_sets"] isKindOfClass:[NSArray class]]
                                        ? model[@"unique_constraint_field_sets"]
                                        : @[])
                                              relations:relations];
    [descriptors addObject:descriptor];
  }
  return [NSArray arrayWithArray:descriptors];
}

static NSDictionary<NSString *, NSString *> *ALNORMTSTypeNamesByEntity(
    NSArray<ALNORMModelDescriptor *> *descriptors,
    NSError **error) {
  NSMutableDictionary<NSString *, NSString *> *namesByEntity = [NSMutableDictionary dictionary];
  NSMutableSet<NSString *> *usedTypeNames = [NSMutableSet set];
  for (ALNORMModelDescriptor *descriptor in descriptors ?: @[]) {
    NSString *typeName = ALNORMTSTypeNameForDescriptor(descriptor);
    if ([usedTypeNames containsObject:typeName]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorIdentifierCollision,
                                 @"ORM descriptors collide after TypeScript type normalization",
                                 @{
                                   @"entity_name" : descriptor.entityName ?: @"",
                                   @"type_name" : typeName ?: @"",
                                 });
      }
      return nil;
    }
    [usedTypeNames addObject:typeName];
    namesByEntity[descriptor.entityName ?: @""] = typeName;
  }
  return [NSDictionary dictionaryWithDictionary:namesByEntity];
}

static NSDictionary<NSString *, ALNORMModelDescriptor *> *ALNORMTSDescriptorsByEntity(
    NSArray<ALNORMModelDescriptor *> *descriptors) {
  NSMutableDictionary<NSString *, ALNORMModelDescriptor *> *mapping = [NSMutableDictionary dictionary];
  for (ALNORMModelDescriptor *descriptor in descriptors ?: @[]) {
    NSString *entityName = ALNORMTSStringValue(descriptor.entityName);
    if ([entityName length] > 0) {
      mapping[entityName] = descriptor;
    }
  }
  return [NSDictionary dictionaryWithDictionary:mapping];
}

static BOOL ALNORMTSValidateOperationIDs(NSArray<NSString *> *operationIDs,
                                         NSDictionary<NSString *, NSDictionary<NSString *, id> *> *operationsByID,
                                         NSString *errorPrefix,
                                         NSError **error) {
  for (NSString *operationID in operationIDs ?: @[]) {
    if (operationsByID[operationID] == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 [NSString stringWithFormat:@"%@ references an unknown operationId", errorPrefix ?: @"Arlen metadata"],
                                 @{
                                   @"operation_id" : operationID ?: @"",
                                 });
      }
      return NO;
    }
  }
  return YES;
}

static NSArray<NSString *> *ALNORMTSSortedFieldNamesForDescriptor(ALNORMModelDescriptor *descriptor) {
  NSMutableArray<NSString *> *fieldNames = [NSMutableArray array];
  for (ALNORMFieldDescriptor *field in descriptor.fields ?: @[]) {
    if ([ALNORMTSStringValue(field.name) length] > 0) {
      [fieldNames addObject:field.name];
    }
  }
  return [fieldNames sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray<NSString *> *ALNORMTSSortedRelationNamesForDescriptor(ALNORMModelDescriptor *descriptor) {
  NSMutableArray<NSString *> *relationNames = [NSMutableArray array];
  for (ALNORMRelationDescriptor *relation in descriptor.relations ?: @[]) {
    if ([ALNORMTSStringValue(relation.name) length] > 0) {
      [relationNames addObject:relation.name];
    }
  }
  return [relationNames sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSNormalizedResourceMetadata(
    NSDictionary<NSString *, id> *openAPISpecification,
    NSArray<NSDictionary<NSString *, id> *> *operations,
    NSArray<ALNORMModelDescriptor *> *descriptors,
    NSDictionary<NSString *, NSString *> *typeNamesByEntity,
    NSError **error) {
  if (error != NULL) {
    *error = nil;
  }

  NSDictionary<NSString *, id> *rootExtension = ALNORMTSArlenExtensionRoot(openAPISpecification ?: @{});
  NSArray<NSDictionary<NSString *, id> *> *rawResources =
      ALNORMTSNormalizedExtensionEntries(rootExtension[@"resources"], @"name");
  NSDictionary<NSString *, ALNORMModelDescriptor *> *descriptorsByEntity = ALNORMTSDescriptorsByEntity(descriptors);
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *operationsByID = ALNORMTSOperationsByID(operations);
  NSMutableArray<NSDictionary<NSString *, id> *> *resources = [NSMutableArray array];
  NSMutableSet<NSString *> *usedNames = [NSMutableSet set];

  for (NSDictionary<NSString *, id> *rawResource in rawResources) {
    NSString *name = ALNORMTSStringValue(rawResource[@"name"]);
    if ([name length] == 0 || [usedNames containsObject:name]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI x-arlen resource metadata must define unique names",
                                 @{
                                   @"resource_name" : name ?: @"",
                                 });
      }
      return nil;
    }
    [usedNames addObject:name];

    NSString *entityName = ALNORMTSStringValue(rawResource[@"entity_name"]);
    ALNORMModelDescriptor *descriptor = ([entityName length] > 0) ? descriptorsByEntity[entityName] : nil;
    if ([entityName length] > 0 && descriptor == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI x-arlen resource references an unknown ORM entity",
                                 @{
                                   @"resource_name" : name ?: @"",
                                   @"entity_name" : entityName ?: @"",
                                 });
      }
      return nil;
    }

    NSArray<NSString *> *operationIDs =
        ALNORMTSNormalizedStringArray(rawResource[@"operation_ids"]);
    NSDictionary<NSString *, id> *operationMap = ALNORMTSDictionaryValue(rawResource[@"operations"]);
    for (id rawOperationID in [operationMap allValues]) {
      NSString *operationID = ALNORMTSStringValue(rawOperationID);
      if ([operationID length] > 0 && ![operationIDs containsObject:operationID]) {
        operationIDs = [operationIDs arrayByAddingObject:operationID];
      }
    }
    if (!ALNORMTSValidateOperationIDs(operationIDs,
                                      operationsByID,
                                      [NSString stringWithFormat:@"Resource %@", name ?: @""],
                                      error)) {
      return nil;
    }

    NSArray<NSString *> *fieldNames = descriptor != nil ? ALNORMTSSortedFieldNamesForDescriptor(descriptor) : @[];
    NSArray<NSString *> *relationNames = descriptor != nil ? ALNORMTSSortedRelationNamesForDescriptor(descriptor) : @[];

    NSDictionary<NSString *, id> *query = ALNORMTSDictionaryValue(rawResource[@"query"]);
    NSArray<NSString *> *allowedSelect = ALNORMTSNormalizedStringArray(query[@"allowed_select"]);
    NSArray<NSString *> *allowedInclude = ALNORMTSNormalizedStringArray(query[@"allowed_include"]);
    NSArray<NSString *> *sortableFields = ALNORMTSNormalizedStringArray(query[@"sortable_fields"]);
    NSArray<NSString *> *filterableFields = ALNORMTSNormalizedStringArray(query[@"filterable_fields"]);
    NSArray<NSString *> *defaultSort = ALNORMTSNormalizedStringArray(query[@"default_sort"]);
    for (NSString *fieldName in allowedSelect) {
      if (descriptor != nil && ![fieldNames containsObject:fieldName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen resource allowed_select references an unknown field",
                                   @{
                                     @"resource_name" : name ?: @"",
                                     @"field_name" : fieldName ?: @"",
                                   });
        }
        return nil;
      }
    }
    for (NSString *relationName in allowedInclude) {
      if (descriptor != nil && ![relationNames containsObject:relationName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen resource allowed_include references an unknown relation",
                                   @{
                                     @"resource_name" : name ?: @"",
                                     @"relation_name" : relationName ?: @"",
                                   });
        }
        return nil;
      }
    }
    for (NSString *fieldName in sortableFields) {
      if (descriptor != nil && ![fieldNames containsObject:fieldName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen resource sortable_fields references an unknown field",
                                   @{
                                     @"resource_name" : name ?: @"",
                                     @"field_name" : fieldName ?: @"",
                                   });
        }
        return nil;
      }
    }
    for (NSString *fieldName in filterableFields) {
      if (descriptor != nil && ![fieldNames containsObject:fieldName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen resource filterable_fields references an unknown field",
                                   @{
                                     @"resource_name" : name ?: @"",
                                     @"field_name" : fieldName ?: @"",
                                   });
        }
        return nil;
      }
    }
    for (NSString *fieldName in defaultSort) {
      if ([sortableFields count] > 0 && ![sortableFields containsObject:fieldName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen resource default_sort must be a subset of sortable_fields",
                                   @{
                                     @"resource_name" : name ?: @"",
                                     @"field_name" : fieldName ?: @"",
                                   });
        }
        return nil;
      }
    }

    NSDictionary<NSString *, id> *admin = ALNORMTSDictionaryValue(rawResource[@"admin"]);
    NSArray<NSString *> *defaultColumns = ALNORMTSNormalizedStringArray(admin[@"default_columns"]);
    NSArray<NSString *> *searchableFields = ALNORMTSNormalizedStringArray(admin[@"searchable_fields"]);
    NSString *titleField = ALNORMTSStringValue(admin[@"title_field"]);
    if (descriptor != nil) {
      for (NSString *fieldName in defaultColumns) {
        if (![fieldNames containsObject:fieldName]) {
          if (error != NULL) {
            *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                     @"OpenAPI x-arlen admin default_columns references an unknown field",
                                     @{
                                       @"resource_name" : name ?: @"",
                                       @"field_name" : fieldName ?: @"",
                                     });
          }
          return nil;
        }
      }
      for (NSString *fieldName in searchableFields) {
        if (![fieldNames containsObject:fieldName]) {
          if (error != NULL) {
            *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                     @"OpenAPI x-arlen admin searchable_fields references an unknown field",
                                     @{
                                       @"resource_name" : name ?: @"",
                                       @"field_name" : fieldName ?: @"",
                                     });
          }
          return nil;
        }
      }
      if ([titleField length] > 0 && ![fieldNames containsObject:titleField]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen admin title_field references an unknown field",
                                   @{
                                     @"resource_name" : name ?: @"",
                                     @"field_name" : titleField ?: @"",
                                   });
        }
        return nil;
      }
    }

    NSMutableDictionary<NSString *, id> *normalized = [NSMutableDictionary dictionary];
    normalized[@"name"] = name;
    normalized[@"entityName"] = entityName ?: @"";
    if ([entityName length] > 0) {
      normalized[@"modelTypeName"] = typeNamesByEntity[entityName] ?: @"";
    }
    normalized[@"tagNames"] = ALNORMTSNormalizedStringArray(rawResource[@"tag_names"]);
    normalized[@"operationIds"] = operationIDs ?: @[];
    normalized[@"operations"] = @{
      @"list" : ALNORMTSStringValue(operationMap[@"list"]) ?: @"",
      @"detail" : ALNORMTSStringValue(operationMap[@"detail"]) ?: @"",
      @"create" : ALNORMTSStringValue(operationMap[@"create"]) ?: @"",
      @"update" : ALNORMTSStringValue(operationMap[@"update"]) ?: @"",
      @"destroy" : ALNORMTSStringValue(operationMap[@"destroy"]) ?: @"",
    };
    normalized[@"query"] = @{
      @"allowedSelect" : allowedSelect ?: @[],
      @"allowedInclude" : allowedInclude ?: @[],
      @"sortableFields" : sortableFields ?: @[],
      @"filterableFields" : filterableFields ?: @[],
      @"defaultSort" : defaultSort ?: @[],
      @"selectParam" : [ALNORMTSStringValue(query[@"select_param"]) length] > 0 ? ALNORMTSStringValue(query[@"select_param"]) : @"fields",
      @"includeParam" : [ALNORMTSStringValue(query[@"include_param"]) length] > 0 ? ALNORMTSStringValue(query[@"include_param"]) : @"include",
      @"sortParam" : [ALNORMTSStringValue(query[@"sort_param"]) length] > 0 ? ALNORMTSStringValue(query[@"sort_param"]) : @"sort",
      @"filterPrefix" : [ALNORMTSStringValue(query[@"filter_prefix"]) length] > 0 ? ALNORMTSStringValue(query[@"filter_prefix"]) : @"filter.",
      @"cursorParam" : [ALNORMTSStringValue(query[@"cursor_param"]) length] > 0 ? ALNORMTSStringValue(query[@"cursor_param"]) : @"cursor",
      @"limitParam" : [ALNORMTSStringValue(query[@"limit_param"]) length] > 0 ? ALNORMTSStringValue(query[@"limit_param"]) : @"limit",
      @"defaultPageSize" : @(ALNORMTSIntegerValue(query[@"default_page_size"], 25)),
      @"maxPageSize" : @(ALNORMTSIntegerValue(query[@"max_page_size"], 100)),
    };
    normalized[@"admin"] = @{
      @"enabled" : @(ALNORMTSBoolValue(admin[@"enabled"], [admin count] > 0)),
      @"titleField" : titleField ?: @"",
      @"defaultColumns" : defaultColumns ?: @[],
      @"searchableFields" : searchableFields ?: @[],
      @"allowedActions" : ALNORMTSNormalizedStringArray(admin[@"allowed_actions"]),
      @"htmlPath" : ALNORMTSStringValue(admin[@"html_path"]) ?: @"",
      @"apiPath" : ALNORMTSStringValue(admin[@"api_path"]) ?: @"",
    };
    [resources addObject:normalized];
  }

  return [NSArray arrayWithArray:resources];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSNormalizedModuleMetadata(
    NSDictionary<NSString *, id> *openAPISpecification,
    NSArray<NSDictionary<NSString *, id> *> *operations,
    NSArray<NSDictionary<NSString *, id> *> *resources,
    NSError **error) {
  if (error != NULL) {
    *error = nil;
  }

  NSDictionary<NSString *, id> *rootExtension = ALNORMTSArlenExtensionRoot(openAPISpecification ?: @{});
  NSArray<NSDictionary<NSString *, id> *> *rawModules =
      ALNORMTSNormalizedExtensionEntries(rootExtension[@"modules"], @"name");
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *operationsByID = ALNORMTSOperationsByID(operations);
  NSMutableSet<NSString *> *resourceNames = [NSMutableSet set];
  for (NSDictionary<NSString *, id> *resource in resources ?: @[]) {
    NSString *resourceName = ALNORMTSStringValue(resource[@"name"]);
    if ([resourceName length] > 0) {
      [resourceNames addObject:resourceName];
    }
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *modules = [NSMutableArray array];
  NSMutableSet<NSString *> *usedNames = [NSMutableSet set];
  for (NSDictionary<NSString *, id> *rawModule in rawModules) {
    NSString *name = ALNORMTSStringValue(rawModule[@"name"]);
    if ([name length] == 0 || [usedNames containsObject:name]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI x-arlen modules must define unique names",
                                 @{
                                   @"module_name" : name ?: @"",
                                 });
      }
      return nil;
    }
    [usedNames addObject:name];

    NSMutableArray<NSString *> *operationIDs = [NSMutableArray arrayWithArray:ALNORMTSNormalizedStringArray(rawModule[@"operation_ids"])];
    for (NSString *specialKey in @[ @"bootstrap_operation_id", @"capability_operation_id", @"summary_operation_id" ]) {
      NSString *operationID = ALNORMTSStringValue(rawModule[specialKey]);
      if ([operationID length] > 0 && ![operationIDs containsObject:operationID]) {
        [operationIDs addObject:operationID];
      }
    }
    if (!ALNORMTSValidateOperationIDs(operationIDs,
                                      operationsByID,
                                      [NSString stringWithFormat:@"Module %@", name ?: @""],
                                      error)) {
      return nil;
    }

    NSArray<NSString *> *moduleResources = ALNORMTSNormalizedStringArray(rawModule[@"resources"]);
    for (NSString *resourceName in moduleResources) {
      if (![resourceNames containsObject:resourceName]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"OpenAPI x-arlen module references an unknown resource",
                                   @{
                                     @"module_name" : name ?: @"",
                                     @"resource_name" : resourceName ?: @"",
                                   });
        }
        return nil;
      }
    }

    [modules addObject:@{
      @"name" : name,
      @"kind" : [ALNORMTSStringValue(rawModule[@"kind"]) length] > 0 ? ALNORMTSStringValue(rawModule[@"kind"]) : @"generic",
      @"tagNames" : ALNORMTSNormalizedStringArray(rawModule[@"tag_names"]),
      @"operationIds" : operationIDs,
      @"resourceNames" : moduleResources ?: @[],
      @"bootstrapOperationId" : ALNORMTSStringValue(rawModule[@"bootstrap_operation_id"]) ?: @"",
      @"capabilityOperationId" : ALNORMTSStringValue(rawModule[@"capability_operation_id"]) ?: @"",
      @"summaryOperationId" : ALNORMTSStringValue(rawModule[@"summary_operation_id"]) ?: @"",
    }];
  }

  return [NSArray arrayWithArray:modules];
}

static NSDictionary<NSString *, id> *ALNORMTSWorkspaceHints(NSDictionary<NSString *, id> *openAPISpecification) {
  NSDictionary<NSString *, id> *rootExtension = ALNORMTSArlenExtensionRoot(openAPISpecification ?: @{});
  NSDictionary<NSString *, id> *workspace = ALNORMTSDictionaryValue(rootExtension[@"workspace"]);
  NSMutableDictionary<NSString *, id> *hints = [NSMutableDictionary dictionary];
  hints[@"packageManager"] = [ALNORMTSStringValue(workspace[@"package_manager"]) length] > 0
                                 ? ALNORMTSStringValue(workspace[@"package_manager"])
                                 : @"npm";
  hints[@"installCommand"] = [ALNORMTSStringValue(workspace[@"install_command"]) length] > 0
                                 ? ALNORMTSStringValue(workspace[@"install_command"])
                                 : @"npm install";
  hints[@"typecheckCommand"] = [ALNORMTSStringValue(workspace[@"typecheck_command"]) length] > 0
                                   ? ALNORMTSStringValue(workspace[@"typecheck_command"])
                                   : @"npm run typecheck";
  if ([ALNORMTSStringValue(workspace[@"dev_command"]) length] > 0) {
    hints[@"devCommand"] = ALNORMTSStringValue(workspace[@"dev_command"]);
  }
  hints[@"outputDir"] = @"frontend/generated/arlen";
  hints[@"manifestPath"] = @"db/schema/arlen_typescript.json";
  return [NSDictionary dictionaryWithDictionary:hints];
}

static NSString *ALNORMTSRelationTypeName(ALNORMRelationDescriptor *relation,
                                          NSDictionary<NSString *, NSString *> *typeNamesByEntity) {
  NSString *targetType = typeNamesByEntity[relation.targetEntityName ?: @""] ?: @"unknown";
  BOOL multiple = (relation.kind == ALNORMRelationKindHasMany || relation.kind == ALNORMRelationKindManyToMany);
  return multiple ? [NSString stringWithFormat:@"%@[]", targetType] : [NSString stringWithFormat:@"%@ | null", targetType];
}

static NSString *ALNORMTSRenderUniqueWhereType(ALNORMModelDescriptor *descriptor,
                                               NSError **error) {
  NSMutableArray<NSArray<NSString *> *> *candidateSets = [NSMutableArray array];
  if ([descriptor.primaryKeyFieldNames count] > 0) {
    [candidateSets addObject:descriptor.primaryKeyFieldNames];
  }
  for (NSArray<NSString *> *uniqueSet in descriptor.uniqueConstraintFieldSets ?: @[]) {
    if ([uniqueSet count] > 0) {
      [candidateSets addObject:uniqueSet];
    }
  }
  if ([candidateSets count] == 0) {
    return @"never";
  }

  NSMutableArray<NSString *> *variants = [NSMutableArray array];
  for (NSArray<NSString *> *fieldSet in candidateSets) {
    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    for (NSString *fieldName in fieldSet) {
      ALNORMFieldDescriptor *field = [descriptor fieldNamed:fieldName];
      if (field == nil) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                   @"ORM unique constraint references an unknown field",
                                   @{
                                     @"entity_name" : descriptor.entityName ?: @"",
                                     @"field_name" : fieldName ?: @"",
                                   });
        }
        return nil;
      }
      [rows addObject:@{
        @"name" : field.name ?: @"",
        @"type" : ALNORMTSNullableType(ALNORMTSFieldTypeForDescriptor(field), NO),
      }];
    }
    [variants addObject:ALNORMTSRenderObjectType(rows, 0)];
  }
  return [variants componentsJoinedByString:@" | "];
}

static NSString *ALNORMTSRenderModelsModule(NSArray<ALNORMModelDescriptor *> *descriptors,
                                            NSDictionary<NSString *, NSString *> *typeNamesByEntity,
                                            NSError **error) {
  if (error != NULL) {
    *error = nil;
  }

  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  [output appendString:@"export type ArlenScalar = string | number | boolean | null;\n"];
  [output appendString:@"export type ArlenJSONValue = ArlenScalar | { [key: string]: ArlenJSONValue } | Array<ArlenJSONValue>;\n"];
  [output appendString:@"export type ArlenRelationKind = 'belongs_to' | 'has_one' | 'has_many' | 'many_to_many';\n"];
  [output appendString:@"export interface ArlenResultEnvelope<T> {\n  data: T;\n  meta?: Record<string, unknown>;\n}\n\n"];
  [output appendString:@"export interface ArlenListEnvelope<T> {\n  items: T[];\n  totalCount?: number;\n  nextCursor?: string | null;\n  prevCursor?: string | null;\n  meta?: Record<string, unknown>;\n}\n\n"];
  [output appendString:@"export interface ArlenErrorEnvelope {\n  error: {\n    code?: string;\n    message: string;\n    details?: Record<string, unknown>;\n    fieldErrors?: Record<string, string[]>;\n  };\n}\n\n"];
  [output appendString:@"export interface ArlenRelationMeta {\n  kind: ArlenRelationKind;\n  targetEntityName: string;\n  targetTypeName: string;\n  cardinality: 'one' | 'many';\n  readOnly: boolean;\n}\n\n"];
  [output appendString:@"export interface ArlenModelMeta {\n  entityName: string;\n  schemaName: string;\n  tableName: string;\n  relationKind: string;\n  readOnly: boolean;\n  primaryKeyFieldNames: string[];\n  uniqueConstraintFieldSets: string[][];\n  readonlyFieldNames: string[];\n  writableFieldNames: string[];\n  relationNames: string[];\n  relations: Record<string, ArlenRelationMeta>;\n}\n\n"];

  NSMutableArray<NSString *> *entityNames = [NSMutableArray array];
  NSMutableArray<NSString *> *registryRows = [NSMutableArray array];
  NSArray<ALNORMModelDescriptor *> *sortedDescriptors =
      [descriptors sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"entityName"
                                                                                ascending:YES] ]];
  for (ALNORMModelDescriptor *descriptor in sortedDescriptors) {
    [entityNames addObject:descriptor.entityName ?: @""];
    NSString *typeName = typeNamesByEntity[descriptor.entityName ?: @""];
    NSString *metaConstName = [NSString stringWithFormat:@"%@Meta", ALNORMTSCamelIdentifier(typeName, @"model")];
    [registryRows addObject:[NSString stringWithFormat:@"  %@: %@,", ALNORMTSQuotedPropertyName(typeName), metaConstName]];

    NSMutableArray<NSDictionary<NSString *, id> *> *readModelRows = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *createRows = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *updateRows = [NSMutableArray array];
    NSMutableArray<NSString *> *readonlyFieldNames = [NSMutableArray array];
    NSMutableArray<NSString *> *writableFieldNames = [NSMutableArray array];

    for (ALNORMFieldDescriptor *field in descriptor.fields ?: @[]) {
      NSString *fieldType = ALNORMTSNullableType(ALNORMTSFieldTypeForDescriptor(field), field.isNullable);
      [readModelRows addObject:@{
        @"name" : field.name ?: @"",
        @"type" : fieldType,
        @"readonly" : @YES,
      }];
      if (field.isReadOnly || descriptor.isReadOnly) {
        [readonlyFieldNames addObject:field.name ?: @""];
        continue;
      }
      [writableFieldNames addObject:field.name ?: @""];
      [createRows addObject:@{
        @"name" : field.name ?: @"",
        @"type" : fieldType,
        @"optional" : @((field.isNullable || field.hasDefaultValue)),
      }];
      [updateRows addObject:@{
        @"name" : field.name ?: @"",
        @"type" : fieldType,
        @"optional" : @YES,
      }];
    }

    NSArray<ALNORMRelationDescriptor *> *sortedRelations =
        [descriptor.relations sortedArrayUsingDescriptors:@[
          [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]
        ]];
    NSMutableArray<NSString *> *relationNames = [NSMutableArray array];
    for (ALNORMRelationDescriptor *relation in sortedRelations) {
      [relationNames addObject:relation.name ?: @""];
      [readModelRows addObject:@{
        @"name" : relation.name ?: @"",
        @"type" : ALNORMTSRelationTypeName(relation, typeNamesByEntity),
        @"readonly" : @YES,
        @"optional" : @YES,
      }];
    }

    NSString *createInputName = [NSString stringWithFormat:@"%@CreateInput", typeName];
    NSString *updateInputName = [NSString stringWithFormat:@"%@UpdateInput", typeName];
    NSString *resultEnvelopeName = [NSString stringWithFormat:@"%@ResultEnvelope", typeName];
    NSString *listEnvelopeName = [NSString stringWithFormat:@"%@ListEnvelope", typeName];
    NSString *relationNameTypeName = [NSString stringWithFormat:@"%@RelationName", typeName];
    NSString *uniqueWhereName = [NSString stringWithFormat:@"%@UniqueWhere", typeName];

    [output appendFormat:@"export type %@ = %@;\n\n",
                         [NSString stringWithFormat:@"%@EntityName", typeName],
                         ALNORMTSSingleQuotedString(descriptor.entityName ?: @"")];
    [output appendFormat:@"export interface %@ {\n  readonly __entity: %@;\n",
                         typeName,
                         ALNORMTSSingleQuotedString(descriptor.entityName ?: @"")];
    for (NSDictionary<NSString *, id> *row in readModelRows) {
      [output appendFormat:@"  readonly %@%@: %@;\n",
                           ALNORMTSQuotedPropertyName(row[@"name"]),
                           ALNORMTSBoolValue(row[@"optional"], NO) ? @"?" : @"",
                           row[@"type"] ?: @"unknown"];
    }
    [output appendString:@"}\n\n"];

    if ([createRows count] == 0) {
      [output appendFormat:@"export type %@ = never;\n\n", createInputName];
    } else {
      [output appendFormat:@"export interface %@ {\n", createInputName];
      for (NSDictionary<NSString *, id> *row in createRows) {
        [output appendFormat:@"  %@%@: %@;\n",
                             ALNORMTSQuotedPropertyName(row[@"name"]),
                             ALNORMTSBoolValue(row[@"optional"], NO) ? @"?" : @"",
                             row[@"type"] ?: @"unknown"];
      }
      [output appendString:@"}\n\n"];
    }

    if ([updateRows count] == 0) {
      [output appendFormat:@"export type %@ = never;\n\n", updateInputName];
    } else {
      [output appendFormat:@"export interface %@ {\n", updateInputName];
      for (NSDictionary<NSString *, id> *row in updateRows) {
        [output appendFormat:@"  %@?: %@;\n",
                             ALNORMTSQuotedPropertyName(row[@"name"]),
                             row[@"type"] ?: @"unknown"];
      }
      [output appendString:@"}\n\n"];
    }

    NSString *uniqueWhereType = ALNORMTSRenderUniqueWhereType(descriptor, error);
    if ([uniqueWhereType length] == 0) {
      return nil;
    }
    [output appendFormat:@"export type %@ = %@;\n\n", uniqueWhereName, uniqueWhereType];
    [output appendFormat:@"export type %@ = %@;\n\n", relationNameTypeName, ALNORMTSStringUnionExpression(relationNames)];
    [output appendFormat:@"export interface %@ extends ArlenResultEnvelope<%@> {}\n\n",
                         resultEnvelopeName, typeName];
    [output appendFormat:@"export interface %@ extends ArlenListEnvelope<%@> {}\n\n",
                         listEnvelopeName, typeName];

    [output appendFormat:@"export const %@: ArlenModelMeta = {\n", metaConstName];
    [output appendFormat:@"  entityName: %@,\n", ALNORMTSSingleQuotedString(descriptor.entityName ?: @"")];
    [output appendFormat:@"  schemaName: %@,\n", ALNORMTSSingleQuotedString(descriptor.schemaName ?: @"")];
    [output appendFormat:@"  tableName: %@,\n", ALNORMTSSingleQuotedString(descriptor.tableName ?: @"")];
    [output appendFormat:@"  relationKind: %@,\n", ALNORMTSSingleQuotedString(descriptor.relationKind ?: @"table")];
    [output appendFormat:@"  readOnly: %@,\n", descriptor.isReadOnly ? @"true" : @"false"];
    [output appendFormat:@"  primaryKeyFieldNames: %@,\n", ALNORMTSStringArrayExpression(descriptor.primaryKeyFieldNames)];
    [output appendFormat:@"  uniqueConstraintFieldSets: %@,\n",
                         ALNORMTSFieldSetArrayExpression(descriptor.uniqueConstraintFieldSets)];
    [output appendFormat:@"  readonlyFieldNames: %@,\n", ALNORMTSStringArrayExpression(readonlyFieldNames)];
    [output appendFormat:@"  writableFieldNames: %@,\n", ALNORMTSStringArrayExpression(writableFieldNames)];
    [output appendFormat:@"  relationNames: %@,\n", ALNORMTSStringArrayExpression(relationNames)];
    [output appendString:@"  relations: {\n"];
    for (ALNORMRelationDescriptor *relation in sortedRelations) {
      NSString *cardinality = (relation.kind == ALNORMRelationKindHasMany ||
                               relation.kind == ALNORMRelationKindManyToMany)
                                  ? @"many"
                                  : @"one";
      NSString *targetType = typeNamesByEntity[relation.targetEntityName ?: @""] ?: @"unknown";
      [output appendFormat:@"    %@: {\n", ALNORMTSQuotedPropertyName(relation.name ?: @"")];
      [output appendFormat:@"      kind: %@,\n", ALNORMTSSingleQuotedString([relation kindName])];
      [output appendFormat:@"      targetEntityName: %@,\n", ALNORMTSSingleQuotedString(relation.targetEntityName ?: @"")];
      [output appendFormat:@"      targetTypeName: %@,\n", ALNORMTSSingleQuotedString(targetType)];
      [output appendFormat:@"      cardinality: %@,\n", ALNORMTSSingleQuotedString(cardinality)];
      [output appendFormat:@"      readOnly: %@,\n", relation.isReadOnly ? @"true" : @"false"];
      [output appendString:@"    },\n"];
    }
    [output appendString:@"  },\n"];
    [output appendString:@"};\n\n"];
  }

  [output appendFormat:@"export type ArlenEntityName = %@;\n\n", ALNORMTSStringUnionExpression(entityNames)];
  [output appendString:@"export const arlenModelRegistry: Record<string, ArlenModelMeta> = {\n"];
  for (NSString *row in registryRows) {
    [output appendFormat:@"%@\n", row];
  }
  [output appendString:@"};\n"];

  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderValidatorsModule(NSArray<ALNORMModelDescriptor *> *descriptors,
                                                NSDictionary<NSString *, NSString *> *typeNamesByEntity,
                                                NSDictionary<NSString *, id> *openAPISpecification,
                                                NSArray<NSDictionary<NSString *, id> *> *operations,
                                                NSError **error) {
  if (error != NULL) {
    *error = nil;
  }

  NSMutableArray<NSString *> *modelTypeImports = [NSMutableArray array];
  NSArray<ALNORMModelDescriptor *> *sortedDescriptors =
      [descriptors sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"entityName" ascending:YES] ]];
  for (ALNORMModelDescriptor *descriptor in sortedDescriptors) {
    NSString *typeName = typeNamesByEntity[descriptor.entityName ?: @""] ?: @"Model";
    [modelTypeImports addObject:[NSString stringWithFormat:@"type %@CreateInput", typeName]];
    [modelTypeImports addObject:[NSString stringWithFormat:@"type %@UpdateInput", typeName]];
  }

  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  if ([modelTypeImports count] > 0) {
    [output appendFormat:@"import { %@ } from './models';\n\n", [modelTypeImports componentsJoinedByString:@", "]];
  }
  [output appendString:@"export type ArlenValidatorKind = 'string' | 'number' | 'boolean' | 'object' | 'array' | 'enum' | 'union' | 'intersection' | 'json' | 'unknown' | 'null';\n"];
  [output appendString:@"export interface ArlenValidatorSchema {\n  kind: ArlenValidatorKind;\n  nullable?: boolean;\n  formatHint?: string;\n  literalValues?: Array<string | number | boolean | null>;\n  properties?: Record<string, ArlenValidatorSchema>;\n  requiredFields?: string[];\n  readonlyFields?: string[];\n  writableFields?: string[];\n  items?: ArlenValidatorSchema;\n  members?: ArlenValidatorSchema[];\n  additionalProperties?: boolean | ArlenValidatorSchema;\n}\n\n"];
  [output appendString:@"export interface ArlenValidationIssue {\n  path: string;\n  code: string;\n  message: string;\n}\n\n"];
  [output appendString:@"export type ArlenValidationResult<T> =\n  | { success: true; value: T }\n  | { success: false; errors: ArlenValidationIssue[] };\n\n"];
  [output appendString:@"export interface ArlenFormFieldAdapter {\n  name: string;\n  label: string;\n  inputKind: 'text' | 'number' | 'checkbox' | 'json' | 'date' | 'datetime' | 'time';\n  nullable: boolean;\n  required: boolean;\n  readOnly: boolean;\n  hasDefault: boolean;\n  defaultValueShape: string;\n  formatHint?: string;\n}\n\n"];
  [output appendString:@"function arlenIsPlainObject(value: unknown): value is Record<string, unknown> {\n  return typeof value === 'object' && value !== null && !Array.isArray(value);\n}\n\n"];
  [output appendString:@"function arlenIsJSONValue(value: unknown): boolean {\n  if (value === null) {\n    return true;\n  }\n  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {\n    return true;\n  }\n  if (Array.isArray(value)) {\n    return value.every((item) => arlenIsJSONValue(item));\n  }\n  if (arlenIsPlainObject(value)) {\n    return Object.values(value).every((item) => arlenIsJSONValue(item));\n  }\n  return false;\n}\n\n"];
  [output appendString:@"function arlenJoinPath(base: string, segment: string): string {\n  return base.length > 0 ? `${base}.${segment}` : segment;\n}\n\n"];
  [output appendString:@"function arlenValidateSchema(schema: ArlenValidatorSchema, value: unknown, path = ''): ArlenValidationIssue[] {\n  if (value === null) {\n    return schema.nullable || schema.kind === 'null'\n      ? []\n      : [{ path, code: 'required', message: 'Expected a non-null value' }];\n  }\n\n  switch (schema.kind) {\n    case 'string':\n      return typeof value === 'string' ? [] : [{ path, code: 'type', message: 'Expected a string' }];\n    case 'number':\n      return typeof value === 'number' && Number.isFinite(value)\n        ? []\n        : [{ path, code: 'type', message: 'Expected a finite number' }];\n    case 'boolean':\n      return typeof value === 'boolean' ? [] : [{ path, code: 'type', message: 'Expected a boolean' }];\n    case 'json':\n      return arlenIsJSONValue(value) ? [] : [{ path, code: 'type', message: 'Expected a JSON-compatible value' }];\n    case 'null':\n      return value === null ? [] : [{ path, code: 'type', message: 'Expected null' }];\n    case 'enum': {\n      const allowed = schema.literalValues ?? [];\n      return allowed.some((candidate) => candidate === value)\n        ? []\n        : [{ path, code: 'enum', message: `Expected one of ${allowed.join(', ')}` }];\n    }\n    case 'array': {\n      if (!Array.isArray(value)) {\n        return [{ path, code: 'type', message: 'Expected an array' }];\n      }\n      const issues: ArlenValidationIssue[] = [];\n      for (let index = 0; index < value.length; index += 1) {\n        issues.push(...arlenValidateSchema(schema.items ?? { kind: 'unknown' }, value[index], `${path}[${index}]`));\n      }\n      return issues;\n    }\n    case 'object': {\n      if (!arlenIsPlainObject(value)) {\n        return [{ path, code: 'type', message: 'Expected an object' }];\n      }\n      const issues: ArlenValidationIssue[] = [];\n      const properties = schema.properties ?? {};\n      const requiredFields = new Set(schema.requiredFields ?? []);\n      for (const fieldName of requiredFields) {\n        if (!(fieldName in value) || value[fieldName] === undefined) {\n          issues.push({ path: arlenJoinPath(path, fieldName), code: 'required', message: 'Field is required' });\n        }\n      }\n      for (const [fieldName, fieldSchema] of Object.entries(properties)) {\n        if (!(fieldName in value) || value[fieldName] === undefined) {\n          continue;\n        }\n        issues.push(...arlenValidateSchema(fieldSchema, value[fieldName], arlenJoinPath(path, fieldName)));\n      }\n      for (const [fieldName, fieldValue] of Object.entries(value)) {\n        if (fieldName in properties) {\n          continue;\n        }\n        if (schema.additionalProperties === false) {\n          issues.push({ path: arlenJoinPath(path, fieldName), code: 'unknown_field', message: 'Field is not allowed' });\n          continue;\n        }\n        if (schema.additionalProperties && typeof schema.additionalProperties === 'object' && !Array.isArray(schema.additionalProperties)) {\n          issues.push(...arlenValidateSchema(schema.additionalProperties, fieldValue, arlenJoinPath(path, fieldName)));\n        }\n      }\n      return issues;\n    }\n    case 'union': {\n      const members = schema.members ?? [];\n      if (members.some((member) => arlenValidateSchema(member, value, path).length === 0)) {\n        return [];\n      }\n      return [{ path, code: 'union', message: 'Value did not match any allowed schema member' }];\n    }\n    case 'intersection': {\n      const issues: ArlenValidationIssue[] = [];\n      for (const member of schema.members ?? []) {\n        issues.push(...arlenValidateSchema(member, value, path));\n      }\n      return issues;\n    }\n    case 'unknown':\n    default:\n      return [];\n  }\n}\n\n"];
  [output appendString:@"export function validateArlenValue<T>(schema: ArlenValidatorSchema, value: unknown): ArlenValidationResult<T> {\n  const errors = arlenValidateSchema(schema, value);\n  if (errors.length > 0) {\n    return { success: false, errors };\n  }\n  return { success: true, value: value as T };\n}\n\n"];

  NSMutableArray<NSString *> *modelRegistryRows = [NSMutableArray array];
  for (ALNORMModelDescriptor *descriptor in sortedDescriptors) {
    NSString *typeName = typeNamesByEntity[descriptor.entityName ?: @""] ?: @"Model";
    NSString *camelName = ALNORMTSCamelIdentifier(typeName, @"model");
    NSString *createSchemaConst = [NSString stringWithFormat:@"%@CreateInputSchema", camelName];
    NSString *updateSchemaConst = [NSString stringWithFormat:@"%@UpdateInputSchema", camelName];
    NSString *createFormConst = [NSString stringWithFormat:@"%@CreateFormFields", camelName];
    NSString *updateFormConst = [NSString stringWithFormat:@"%@UpdateFormFields", camelName];

    NSMutableArray<NSDictionary<NSString *, id> *> *createRows = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *updateRows = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *createFormFields = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *updateFormFields = [NSMutableArray array];
    for (ALNORMFieldDescriptor *field in descriptor.fields ?: @[]) {
      BOOL readOnly = (field.isReadOnly || descriptor.isReadOnly);
      NSDictionary<NSString *, id> *fieldSchema = ALNORMTSValidatorSchemaForFieldDescriptor(field);
      NSString *formatHint = ALNORMTSFormatHintForDataType(field.dataType);
      NSMutableDictionary<NSString *, id> *formField = [NSMutableDictionary dictionary];
      formField[@"name"] = field.name ?: @"";
      formField[@"label"] = ALNORMTSHumanizedLabel(field.name ?: @"");
      formField[@"inputKind"] = ALNORMTSFormInputKindForDataType(field.dataType);
      formField[@"nullable"] = @(field.isNullable);
      formField[@"required"] = ALNORMTSBoolNumber(!field.isNullable && !field.hasDefaultValue && !readOnly);
      formField[@"readOnly"] = @(readOnly);
      formField[@"hasDefault"] = @(field.hasDefaultValue);
      formField[@"defaultValueShape"] = field.defaultValueShape ?: @"none";
      if ([formatHint length] > 0) {
        formField[@"formatHint"] = formatHint;
      }

      if (readOnly) {
        continue;
      }
      [createRows addObject:@{
        @"name" : field.name ?: @"",
        @"schema" : fieldSchema,
        @"required" : ALNORMTSBoolNumber(!field.isNullable && !field.hasDefaultValue),
      }];
      [updateRows addObject:@{
        @"name" : field.name ?: @"",
        @"schema" : fieldSchema,
        @"required" : @NO,
      }];
      [createFormFields addObject:formField];
      NSMutableDictionary<NSString *, id> *updateFormField = [formField mutableCopy];
      updateFormField[@"required"] = @NO;
      [updateFormFields addObject:updateFormField];
    }

    NSString *createSchemaLiteral = ALNORMTSJSONStringFromObject(ALNORMTSValidatorObjectSchema(createRows, NO), error);
    if (createSchemaLiteral == nil) {
      return nil;
    }
    NSString *updateSchemaLiteral = ALNORMTSJSONStringFromObject(ALNORMTSValidatorObjectSchema(updateRows, NO), error);
    if (updateSchemaLiteral == nil) {
      return nil;
    }
    NSString *createFormLiteral = ALNORMTSJSONStringFromObject(createFormFields, error);
    if (createFormLiteral == nil) {
      return nil;
    }
    NSString *updateFormLiteral = ALNORMTSJSONStringFromObject(updateFormFields, error);
    if (updateFormLiteral == nil) {
      return nil;
    }

    [output appendFormat:@"export const %@: ArlenValidatorSchema = %@;\n\n", createSchemaConst, createSchemaLiteral];
    [output appendFormat:@"export const %@: ArlenValidatorSchema = %@;\n\n", updateSchemaConst, updateSchemaLiteral];
    [output appendFormat:@"export const %@: ArlenFormFieldAdapter[] = %@;\n\n", createFormConst, createFormLiteral];
    [output appendFormat:@"export const %@: ArlenFormFieldAdapter[] = %@;\n\n", updateFormConst, updateFormLiteral];
    [output appendFormat:@"export function validate%@CreateInput(value: unknown): ArlenValidationResult<%@CreateInput> {\n  return validateArlenValue<%@CreateInput>(%@, value);\n}\n\n",
                         typeName, typeName, typeName, createSchemaConst];
    [output appendFormat:@"export function validate%@UpdateInput(value: unknown): ArlenValidationResult<%@UpdateInput> {\n  return validateArlenValue<%@UpdateInput>(%@, value);\n}\n\n",
                         typeName, typeName, typeName, updateSchemaConst];

    [modelRegistryRows addObject:[NSString stringWithFormat:@"  %@: {\n    createInput: %@,\n    updateInput: %@,\n    createFormFields: %@,\n    updateFormFields: %@,\n  },",
                                 ALNORMTSQuotedPropertyName(typeName),
                                 createSchemaConst,
                                 updateSchemaConst,
                                 createFormConst,
                                 updateFormConst]];
  }

  NSMutableArray<NSString *> *operationRegistryRows = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    NSString *typeName = operation[@"typeName"] ?: @"Operation";
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    NSString *schemaConst = [NSString stringWithFormat:@"%@RequestSchema", methodName];

    NSMutableArray<NSDictionary<NSString *, id> *> *requestRows = [NSMutableArray array];
    NSArray<NSDictionary<NSString *, id> *> *pathProperties =
        [operation[@"pathProperties"] isKindOfClass:[NSArray class]] ? operation[@"pathProperties"] : @[];
    NSArray<NSDictionary<NSString *, id> *> *queryProperties =
        [operation[@"queryProperties"] isKindOfClass:[NSArray class]] ? operation[@"queryProperties"] : @[];
    NSArray<NSDictionary<NSString *, id> *> *headerProperties =
        [operation[@"headerProperties"] isKindOfClass:[NSArray class]] ? operation[@"headerProperties"] : @[];
    NSDictionary<NSString *, id> *bodySchema = ALNORMTSDictionaryValue(operation[@"bodySchema"]);

    if ([pathProperties count] > 0) {
      NSMutableArray<NSDictionary<NSString *, id> *> *pathRows = [NSMutableArray array];
      for (NSDictionary<NSString *, id> *property in pathProperties) {
        NSDictionary<NSString *, id> *schema =
            ALNORMTSValidatorSchemaFromOpenAPISchema(property[@"schema"], openAPISpecification ?: @{}, error);
        if (schema == nil) {
          return nil;
        }
        [pathRows addObject:@{
          @"name" : property[@"name"] ?: @"",
          @"schema" : schema,
          @"required" : ALNORMTSBoolNumber(!ALNORMTSBoolValue(property[@"optional"], NO)),
        }];
      }
      [requestRows addObject:@{
        @"name" : @"path",
        @"schema" : ALNORMTSValidatorObjectSchema(pathRows, NO),
        @"required" : @YES,
      }];
    }
    if ([queryProperties count] > 0) {
      NSMutableArray<NSDictionary<NSString *, id> *> *queryRows = [NSMutableArray array];
      for (NSDictionary<NSString *, id> *property in queryProperties) {
        NSDictionary<NSString *, id> *schema =
            ALNORMTSValidatorSchemaFromOpenAPISchema(property[@"schema"], openAPISpecification ?: @{}, error);
        if (schema == nil) {
          return nil;
        }
        [queryRows addObject:@{
          @"name" : property[@"name"] ?: @"",
          @"schema" : schema,
          @"required" : ALNORMTSBoolNumber(!ALNORMTSBoolValue(property[@"optional"], NO)),
        }];
      }
      [requestRows addObject:@{
        @"name" : @"query",
        @"schema" : ALNORMTSValidatorObjectSchema(queryRows, NO),
        @"required" : @NO,
      }];
    }
    if ([headerProperties count] > 0) {
      NSMutableArray<NSDictionary<NSString *, id> *> *headerRows = [NSMutableArray array];
      for (NSDictionary<NSString *, id> *property in headerProperties) {
        NSDictionary<NSString *, id> *schema =
            ALNORMTSValidatorSchemaFromOpenAPISchema(property[@"schema"], openAPISpecification ?: @{}, error);
        if (schema == nil) {
          return nil;
        }
        [headerRows addObject:@{
          @"name" : property[@"name"] ?: @"",
          @"schema" : schema,
          @"required" : ALNORMTSBoolNumber(!ALNORMTSBoolValue(property[@"optional"], NO)),
        }];
      }
      [requestRows addObject:@{
        @"name" : @"headers",
        @"schema" : ALNORMTSValidatorObjectSchema(headerRows, NO),
        @"required" : @NO,
      }];
    }
    if ([bodySchema count] > 0) {
      NSDictionary<NSString *, id> *validatorBodySchema =
          ALNORMTSValidatorSchemaFromOpenAPISchema(bodySchema, openAPISpecification ?: @{}, error);
      if (validatorBodySchema == nil) {
        return nil;
      }
      [requestRows addObject:@{
        @"name" : @"body",
        @"schema" : validatorBodySchema,
        @"required" : operation[@"bodyRequired"] ?: @NO,
      }];
    }

    NSString *requestSchemaLiteral = ALNORMTSJSONStringFromObject(ALNORMTSValidatorObjectSchema(requestRows, NO), error);
    if (requestSchemaLiteral == nil) {
      return nil;
    }
    [output appendFormat:@"export const %@: ArlenValidatorSchema = %@;\n\n", schemaConst, requestSchemaLiteral];
    [output appendFormat:@"export function validate%@Request(value: unknown): ArlenValidationResult<Record<string, unknown>> {\n  return validateArlenValue<Record<string, unknown>>(%@, value);\n}\n\n",
                         typeName,
                         schemaConst];
    [operationRegistryRows addObject:[NSString stringWithFormat:@"  %@: %@,", ALNORMTSQuotedPropertyName(methodName), schemaConst]];
  }

  [output appendString:@"export const arlenModelValidatorSchemas = {\n"];
  for (NSString *row in modelRegistryRows) {
    [output appendFormat:@"%@\n", row];
  }
  [output appendString:@"} as const;\n\n"];

  [output appendString:@"export const arlenOperationRequestSchemas = {\n"];
  for (NSString *row in operationRegistryRows) {
    [output appendFormat:@"%@\n", row];
  }
  [output appendString:@"} as const;\n"];
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderQueryModule(NSArray<ALNORMModelDescriptor *> *descriptors,
                                           NSDictionary<NSString *, NSString *> *typeNamesByEntity,
                                           NSArray<NSDictionary<NSString *, id> *> *resources) {
  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  [output appendString:@"export type ArlenSortDirection = 'asc' | 'desc';\n"];
  [output appendString:@"export type ArlenQueryFilterValue = string | number | boolean | null;\n"];
  [output appendString:@"export interface ArlenQuerySort<TField extends string = string> {\n  field: TField;\n  direction?: ArlenSortDirection;\n}\n\n"];
  [output appendString:@"export interface ArlenPaginationContract {\n  cursorParameterName: string;\n  limitParameterName: string;\n  defaultPageSize: number;\n  maxPageSize: number;\n}\n\n"];
  [output appendString:@"export interface ArlenRelationContract {\n  name: string;\n  kind: 'belongs_to' | 'has_one' | 'has_many' | 'many_to_many';\n  targetEntityName: string;\n  sourceFieldNames: string[];\n  targetFieldNames: string[];\n  throughEntityName?: string;\n  throughSourceFieldNames: string[];\n  throughTargetFieldNames: string[];\n  pivotFieldNames: string[];\n  readOnly: boolean;\n}\n\n"];
  [output appendString:@"export interface ArlenResourceQueryContract<TSelect extends string = string, TInclude extends string = string, TSort extends string = string, TFilter extends string = string> {\n  resourceName: string;\n  entityName?: string;\n  modelTypeName?: string;\n  operationIds: string[];\n  selectParameterName: string;\n  includeParameterName: string;\n  sortParameterName: string;\n  filterParameterPrefix: string;\n  pagination: ArlenPaginationContract;\n  allowedSelect: TSelect[];\n  allowedInclude: TInclude[];\n  sortableFields: TSort[];\n  filterableFields: TFilter[];\n  defaultSort: TSort[];\n}\n\n"];

  NSArray<ALNORMModelDescriptor *> *sortedDescriptors =
      [descriptors sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"entityName" ascending:YES] ]];
  for (ALNORMModelDescriptor *descriptor in sortedDescriptors) {
    NSString *typeName = typeNamesByEntity[descriptor.entityName ?: @""] ?: @"Model";
    NSString *camelName = ALNORMTSCamelIdentifier(typeName, @"model");
    NSArray<NSString *> *fieldNames = ALNORMTSSortedFieldNamesForDescriptor(descriptor);
    NSArray<NSString *> *relationNames = ALNORMTSSortedRelationNamesForDescriptor(descriptor);
    [output appendFormat:@"export type %@FieldName = %@;\n", typeName, ALNORMTSStringUnionExpression(fieldNames)];
    [output appendFormat:@"export const %@FieldNames = %@ as const;\n\n", camelName, ALNORMTSStringArrayExpression(fieldNames)];
    [output appendFormat:@"export const %@RelationContracts: Record<string, ArlenRelationContract> = {\n", camelName];
    NSArray<ALNORMRelationDescriptor *> *sortedRelations =
        [descriptor.relations sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
    for (ALNORMRelationDescriptor *relation in sortedRelations) {
      [output appendFormat:@"  %@: {\n", ALNORMTSQuotedPropertyName(relation.name ?: @"")];
      [output appendFormat:@"    name: %@,\n", ALNORMTSSingleQuotedString(relation.name ?: @"")];
      [output appendFormat:@"    kind: %@,\n", ALNORMTSSingleQuotedString([relation kindName])];
      [output appendFormat:@"    targetEntityName: %@,\n", ALNORMTSSingleQuotedString(relation.targetEntityName ?: @"")];
      [output appendFormat:@"    sourceFieldNames: %@,\n", ALNORMTSStringArrayExpression(relation.sourceFieldNames)];
      [output appendFormat:@"    targetFieldNames: %@,\n", ALNORMTSStringArrayExpression(relation.targetFieldNames)];
      if ([relation.throughEntityName length] > 0) {
        [output appendFormat:@"    throughEntityName: %@,\n", ALNORMTSSingleQuotedString(relation.throughEntityName)];
      }
      [output appendFormat:@"    throughSourceFieldNames: %@,\n", ALNORMTSStringArrayExpression(relation.throughSourceFieldNames)];
      [output appendFormat:@"    throughTargetFieldNames: %@,\n", ALNORMTSStringArrayExpression(relation.throughTargetFieldNames)];
      [output appendFormat:@"    pivotFieldNames: %@,\n", ALNORMTSStringArrayExpression(relation.pivotFieldNames)];
      [output appendFormat:@"    readOnly: %@,\n", relation.isReadOnly ? @"true" : @"false"];
      [output appendString:@"  },\n"];
    }
    [output appendString:@"} as const;\n\n"];
    [output appendFormat:@"export type %@AvailableInclude = %@;\n\n", typeName, ALNORMTSStringUnionExpression(relationNames)];
  }

  NSMutableArray<NSString *> *resourceRegistryRows = [NSMutableArray array];
  NSArray<NSDictionary<NSString *, id> *> *sortedResources =
      [resources sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
  for (NSDictionary<NSString *, id> *resource in sortedResources) {
    NSString *resourceName = ALNORMTSStringValue(resource[@"name"]);
    NSString *typeBase = [ALNORMTSStringValue(resource[@"modelTypeName"]) length] > 0
                             ? ALNORMTSStringValue(resource[@"modelTypeName"])
                             : ALNORMTSPascalIdentifier(resourceName, @"Resource");
    NSString *camelName = ALNORMTSCamelIdentifier(resourceName, @"resource");
    NSString *selectType = [NSString stringWithFormat:@"%@ResourceSelectField", typeBase];
    NSString *includeType = [NSString stringWithFormat:@"%@ResourceIncludeField", typeBase];
    NSString *sortType = [NSString stringWithFormat:@"%@ResourceSortField", typeBase];
    NSString *filterType = [NSString stringWithFormat:@"%@ResourceFilterField", typeBase];
    NSString *queryShapeType = [NSString stringWithFormat:@"%@ResourceQueryShape", typeBase];
    NSString *contractConst = [NSString stringWithFormat:@"%@ResourceQueryContract", camelName];
    NSDictionary<NSString *, id> *query = ALNORMTSDictionaryValue(resource[@"query"]);
    NSArray<NSString *> *allowedSelect = ALNORMTSNormalizedStringArray(query[@"allowedSelect"]);
    NSArray<NSString *> *allowedInclude = ALNORMTSNormalizedStringArray(query[@"allowedInclude"]);
    NSArray<NSString *> *sortableFields = ALNORMTSNormalizedStringArray(query[@"sortableFields"]);
    NSArray<NSString *> *filterableFields = ALNORMTSNormalizedStringArray(query[@"filterableFields"]);
    NSArray<NSString *> *defaultSort = ALNORMTSNormalizedStringArray(query[@"defaultSort"]);

    [output appendFormat:@"export type %@ = %@;\n", selectType, ALNORMTSStringUnionExpression(allowedSelect)];
    [output appendFormat:@"export type %@ = %@;\n", includeType, ALNORMTSStringUnionExpression(allowedInclude)];
    [output appendFormat:@"export type %@ = %@;\n", sortType, ALNORMTSStringUnionExpression(sortableFields)];
    [output appendFormat:@"export type %@ = %@;\n\n", filterType, ALNORMTSStringUnionExpression(filterableFields)];
    [output appendFormat:@"export interface %@ {\n  select?: %@[];\n  include?: %@[];\n  filter?: Partial<Record<%@, ArlenQueryFilterValue | ArlenQueryFilterValue[]>>;\n  sort?: Array<ArlenQuerySort<%@>>;\n  cursor?: string | null;\n  limit?: number;\n}\n\n",
                         queryShapeType,
                         selectType,
                         includeType,
                         filterType,
                         sortType];
    [output appendFormat:@"export const %@: ArlenResourceQueryContract<%@, %@, %@, %@> = {\n",
                         contractConst,
                         selectType,
                         includeType,
                         sortType,
                         filterType];
    [output appendFormat:@"  resourceName: %@,\n", ALNORMTSSingleQuotedString(resourceName)];
    if ([ALNORMTSStringValue(resource[@"entityName"]) length] > 0) {
      [output appendFormat:@"  entityName: %@,\n", ALNORMTSSingleQuotedString(resource[@"entityName"])];
    }
    if ([ALNORMTSStringValue(resource[@"modelTypeName"]) length] > 0) {
      [output appendFormat:@"  modelTypeName: %@,\n", ALNORMTSSingleQuotedString(resource[@"modelTypeName"])];
    }
    [output appendFormat:@"  operationIds: %@,\n", ALNORMTSStringArrayExpression(resource[@"operationIds"] ?: @[])];
    [output appendFormat:@"  selectParameterName: %@,\n", ALNORMTSSingleQuotedString(query[@"selectParam"] ?: @"fields")];
    [output appendFormat:@"  includeParameterName: %@,\n", ALNORMTSSingleQuotedString(query[@"includeParam"] ?: @"include")];
    [output appendFormat:@"  sortParameterName: %@,\n", ALNORMTSSingleQuotedString(query[@"sortParam"] ?: @"sort")];
    [output appendFormat:@"  filterParameterPrefix: %@,\n", ALNORMTSSingleQuotedString(query[@"filterPrefix"] ?: @"filter.")];
    [output appendString:@"  pagination: {\n"];
    [output appendFormat:@"    cursorParameterName: %@,\n", ALNORMTSSingleQuotedString(query[@"cursorParam"] ?: @"cursor")];
    [output appendFormat:@"    limitParameterName: %@,\n", ALNORMTSSingleQuotedString(query[@"limitParam"] ?: @"limit")];
    [output appendFormat:@"    defaultPageSize: %@,\n", [query[@"defaultPageSize"] stringValue] ?: @"25"];
    [output appendFormat:@"    maxPageSize: %@,\n", [query[@"maxPageSize"] stringValue] ?: @"100"];
    [output appendString:@"  },\n"];
    [output appendFormat:@"  allowedSelect: %@,\n", ALNORMTSStringArrayExpression(allowedSelect)];
    [output appendFormat:@"  allowedInclude: %@,\n", ALNORMTSStringArrayExpression(allowedInclude)];
    [output appendFormat:@"  sortableFields: %@,\n", ALNORMTSStringArrayExpression(sortableFields)];
    [output appendFormat:@"  filterableFields: %@,\n", ALNORMTSStringArrayExpression(filterableFields)];
    [output appendFormat:@"  defaultSort: %@,\n", ALNORMTSStringArrayExpression(defaultSort)];
    [output appendString:@"};\n\n"];
    [output appendFormat:@"export function build%@QueryParams(query: %@): Record<string, ArlenQueryFilterValue | ArlenQueryFilterValue[]> {\n",
                         ALNORMTSPascalIdentifier(resourceName, @"Resource"),
                         queryShapeType];
    [output appendString:@"  const params: Record<string, ArlenQueryFilterValue | ArlenQueryFilterValue[]> = {};\n"];
    [output appendFormat:@"  if (query.select && query.select.length > 0) {\n    params[%@] = query.select;\n  }\n",
                         ALNORMTSSingleQuotedString(query[@"selectParam"] ?: @"fields")];
    [output appendFormat:@"  if (query.include && query.include.length > 0) {\n    params[%@] = query.include;\n  }\n",
                         ALNORMTSSingleQuotedString(query[@"includeParam"] ?: @"include")];
    [output appendFormat:@"  if (query.sort && query.sort.length > 0) {\n    params[%@] = query.sort.map((item) => `${item.direction ?? 'asc'}:${item.field}`);\n  }\n",
                         ALNORMTSSingleQuotedString(query[@"sortParam"] ?: @"sort")];
    [output appendFormat:@"  if (query.cursor !== undefined) {\n    params[%@] = query.cursor;\n  }\n",
                         ALNORMTSSingleQuotedString(query[@"cursorParam"] ?: @"cursor")];
    [output appendFormat:@"  if (query.limit !== undefined) {\n    params[%@] = query.limit;\n  }\n",
                         ALNORMTSSingleQuotedString(query[@"limitParam"] ?: @"limit")];
    [output appendFormat:@"  for (const [field, rawValue] of Object.entries(query.filter ?? {})) {\n    params[%@ + field] = rawValue as ArlenQueryFilterValue | ArlenQueryFilterValue[];\n  }\n",
                         ALNORMTSSingleQuotedString(query[@"filterPrefix"] ?: @"filter.")];
    [output appendString:@"  return params;\n}\n\n"];
    [resourceRegistryRows addObject:[NSString stringWithFormat:@"  %@: %@,", ALNORMTSQuotedPropertyName(resourceName), contractConst]];
  }

  [output appendString:@"export const arlenResourceQueryContracts = {\n"];
  for (NSString *row in resourceRegistryRows) {
    [output appendFormat:@"%@\n", row];
  }
  [output appendString:@"} as const;\n"];
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderMetaModule(NSArray<NSDictionary<NSString *, id> *> *resources,
                                          NSArray<NSDictionary<NSString *, id> *> *modules,
                                          NSDictionary<NSString *, id> *workspaceHints) {
  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  NSMutableArray<NSString *> *queryImports = [NSMutableArray array];
  NSArray<NSDictionary<NSString *, id> *> *sortedResources =
      [resources sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
  for (NSDictionary<NSString *, id> *resource in sortedResources) {
    NSString *resourceName = ALNORMTSStringValue(resource[@"name"]);
    if ([resourceName length] > 0) {
      [queryImports addObject:[NSString stringWithFormat:@"%@ResourceQueryContract",
                               ALNORMTSCamelIdentifier(resourceName, @"resource")]];
    }
  }
  if ([queryImports count] > 0) {
    [output appendFormat:@"import { %@, type ArlenResourceQueryContract } from './query';\n\n",
                         [queryImports componentsJoinedByString:@", "]];
  } else {
    [output appendString:@"import type { ArlenResourceQueryContract } from './query';\n\n"];
  }

  [output appendString:@"export interface ArlenWorkspaceHints {\n  packageManager: string;\n  installCommand: string;\n  typecheckCommand: string;\n  devCommand?: string;\n  outputDir: string;\n  manifestPath: string;\n}\n\n"];
  [output appendString:@"export interface ArlenAdminResourceMeta {\n  enabled: boolean;\n  titleField?: string;\n  defaultColumns: string[];\n  searchableFields: string[];\n  allowedActions: string[];\n  htmlPath?: string;\n  apiPath?: string;\n}\n\n"];
  [output appendString:@"export interface ArlenResourceMeta {\n  name: string;\n  entityName?: string;\n  modelTypeName?: string;\n  tagNames: string[];\n  operationIds: string[];\n  operations: {\n    list?: string;\n    detail?: string;\n    create?: string;\n    update?: string;\n    destroy?: string;\n  };\n  query: ArlenResourceQueryContract | null;\n  admin: ArlenAdminResourceMeta | null;\n}\n\n"];
  [output appendString:@"export interface ArlenModuleMeta {\n  name: string;\n  kind: string;\n  tagNames: string[];\n  operationIds: string[];\n  resourceNames: string[];\n  bootstrapOperationId?: string;\n  capabilityOperationId?: string;\n  summaryOperationId?: string;\n}\n\n"];

  NSString *workspaceLiteral = ALNORMTSJSONStringFromObject(workspaceHints ?: @{}, NULL);
  [output appendFormat:@"export const arlenWorkspaceHints: ArlenWorkspaceHints = %@;\n\n", workspaceLiteral ?: @"{}"];

  NSMutableArray<NSString *> *resourceRows = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *resource in sortedResources) {
    NSString *resourceName = ALNORMTSStringValue(resource[@"name"]);
    NSString *queryConst = [NSString stringWithFormat:@"%@ResourceQueryContract",
                            ALNORMTSCamelIdentifier(resourceName, @"resource")];
    NSDictionary<NSString *, id> *operations = ALNORMTSDictionaryValue(resource[@"operations"]);
    NSDictionary<NSString *, id> *admin = ALNORMTSDictionaryValue(resource[@"admin"]);
    BOOL adminEnabled = ALNORMTSBoolValue(admin[@"enabled"], NO);
    NSMutableString *row = [NSMutableString string];
    [row appendFormat:@"  %@: {\n", ALNORMTSQuotedPropertyName(resourceName)];
    [row appendFormat:@"    name: %@,\n", ALNORMTSSingleQuotedString(resourceName)];
    if ([ALNORMTSStringValue(resource[@"entityName"]) length] > 0) {
      [row appendFormat:@"    entityName: %@,\n", ALNORMTSSingleQuotedString(resource[@"entityName"])];
    }
    if ([ALNORMTSStringValue(resource[@"modelTypeName"]) length] > 0) {
      [row appendFormat:@"    modelTypeName: %@,\n", ALNORMTSSingleQuotedString(resource[@"modelTypeName"])];
    }
    [row appendFormat:@"    tagNames: %@,\n", ALNORMTSStringArrayExpression(resource[@"tagNames"] ?: @[])];
    [row appendFormat:@"    operationIds: %@,\n", ALNORMTSStringArrayExpression(resource[@"operationIds"] ?: @[])];
    [row appendString:@"    operations: {\n"];
    for (NSString *key in @[ @"list", @"detail", @"create", @"update", @"destroy" ]) {
      NSString *value = ALNORMTSStringValue(operations[key]);
      if ([value length] > 0) {
        [row appendFormat:@"      %@: %@,\n", ALNORMTSQuotedPropertyName(key), ALNORMTSSingleQuotedString(value)];
      }
    }
    [row appendString:@"    },\n"];
    if ([queryImports count] > 0) {
      [row appendFormat:@"    query: %@,\n", queryConst];
    } else {
      [row appendString:@"    query: null,\n"];
    }
    if (adminEnabled) {
      [row appendString:@"    admin: {\n"];
      [row appendString:@"      enabled: true,\n"];
      if ([ALNORMTSStringValue(admin[@"titleField"]) length] > 0) {
        [row appendFormat:@"      titleField: %@,\n", ALNORMTSSingleQuotedString(admin[@"titleField"])];
      }
      [row appendFormat:@"      defaultColumns: %@,\n", ALNORMTSStringArrayExpression(admin[@"defaultColumns"] ?: @[])];
      [row appendFormat:@"      searchableFields: %@,\n", ALNORMTSStringArrayExpression(admin[@"searchableFields"] ?: @[])];
      [row appendFormat:@"      allowedActions: %@,\n", ALNORMTSStringArrayExpression(admin[@"allowedActions"] ?: @[])];
      if ([ALNORMTSStringValue(admin[@"htmlPath"]) length] > 0) {
        [row appendFormat:@"      htmlPath: %@,\n", ALNORMTSSingleQuotedString(admin[@"htmlPath"])];
      }
      if ([ALNORMTSStringValue(admin[@"apiPath"]) length] > 0) {
        [row appendFormat:@"      apiPath: %@,\n", ALNORMTSSingleQuotedString(admin[@"apiPath"])];
      }
      [row appendString:@"    },\n"];
    } else {
      [row appendString:@"    admin: null,\n"];
    }
    [row appendString:@"  },\n"];
    [resourceRows addObject:row];
  }

  [output appendString:@"export const arlenResourceRegistry = {\n"];
  for (NSString *row in resourceRows) {
    [output appendString:row];
  }
  [output appendString:@"} satisfies Record<string, ArlenResourceMeta>;\n\n"];

  [output appendString:@"export const arlenAdminResourceRegistry = {\n"];
  for (NSDictionary<NSString *, id> *resource in sortedResources) {
    NSDictionary<NSString *, id> *admin = ALNORMTSDictionaryValue(resource[@"admin"]);
    if (!ALNORMTSBoolValue(admin[@"enabled"], NO)) {
      continue;
    }
    NSString *resourceName = ALNORMTSStringValue(resource[@"name"]);
    [output appendFormat:@"  %@: arlenResourceRegistry.%@.admin,\n",
                         ALNORMTSQuotedPropertyName(resourceName),
                         ALNORMTSQuotedPropertyName(resourceName)];
  }
  [output appendString:@"} as const;\n\n"];

  [output appendString:@"export const arlenModuleRegistry = {\n"];
  NSArray<NSDictionary<NSString *, id> *> *sortedModules =
      [modules sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
  for (NSDictionary<NSString *, id> *module in sortedModules) {
    NSString *moduleName = ALNORMTSStringValue(module[@"name"]);
    [output appendFormat:@"  %@: {\n", ALNORMTSQuotedPropertyName(moduleName)];
    [output appendFormat:@"    name: %@,\n", ALNORMTSSingleQuotedString(moduleName)];
    [output appendFormat:@"    kind: %@,\n", ALNORMTSSingleQuotedString(module[@"kind"] ?: @"generic")];
    [output appendFormat:@"    tagNames: %@,\n", ALNORMTSStringArrayExpression(module[@"tagNames"] ?: @[])];
    [output appendFormat:@"    operationIds: %@,\n", ALNORMTSStringArrayExpression(module[@"operationIds"] ?: @[])];
    [output appendFormat:@"    resourceNames: %@,\n", ALNORMTSStringArrayExpression(module[@"resourceNames"] ?: @[])];
    if ([ALNORMTSStringValue(module[@"bootstrapOperationId"]) length] > 0) {
      [output appendFormat:@"    bootstrapOperationId: %@,\n", ALNORMTSSingleQuotedString(module[@"bootstrapOperationId"])];
    }
    if ([ALNORMTSStringValue(module[@"capabilityOperationId"]) length] > 0) {
      [output appendFormat:@"    capabilityOperationId: %@,\n", ALNORMTSSingleQuotedString(module[@"capabilityOperationId"])];
    }
    if ([ALNORMTSStringValue(module[@"summaryOperationId"]) length] > 0) {
      [output appendFormat:@"    summaryOperationId: %@,\n", ALNORMTSSingleQuotedString(module[@"summaryOperationId"])];
    }
    [output appendString:@"  },\n"];
  }
  [output appendString:@"} satisfies Record<string, ArlenModuleMeta>;\n"];
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderOperationRequestInterface(NSDictionary<NSString *, id> *operation) {
  NSString *interfaceName = [NSString stringWithFormat:@"%@Request", operation[@"typeName"] ?: @"Operation"];
  NSArray<NSDictionary<NSString *, id> *> *pathProperties =
      [operation[@"pathProperties"] isKindOfClass:[NSArray class]] ? operation[@"pathProperties"] : @[];
  NSArray<NSDictionary<NSString *, id> *> *queryProperties =
      [operation[@"queryProperties"] isKindOfClass:[NSArray class]] ? operation[@"queryProperties"] : @[];
  NSArray<NSDictionary<NSString *, id> *> *headerProperties =
      [operation[@"headerProperties"] isKindOfClass:[NSArray class]] ? operation[@"headerProperties"] : @[];
  NSString *bodyType = ALNORMTSStringValue(operation[@"bodyType"]);
  BOOL bodyRequired = ALNORMTSBoolValue(operation[@"bodyRequired"], NO);

  NSMutableString *output = [NSMutableString string];
  [output appendFormat:@"export interface %@ {\n", interfaceName];
  if ([pathProperties count] > 0) {
    [output appendFormat:@"  path: %@;\n", ALNORMTSRenderObjectType(pathProperties, 1)];
  }
  if ([queryProperties count] > 0) {
    [output appendFormat:@"  query?: %@;\n", ALNORMTSRenderObjectType(queryProperties, 1)];
  }
  if ([headerProperties count] > 0) {
    [output appendFormat:@"  headers?: %@;\n", ALNORMTSRenderObjectType(headerProperties, 1)];
  }
  if ([bodyType length] > 0) {
    [output appendFormat:@"  body%@: %@;\n", bodyRequired ? @"" : @"?", bodyType];
  }
  [output appendString:@"  signal?: unknown;\n"];
  [output appendString:@"}\n\n"];
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderClientModule(NSDictionary<NSString *, id> *openAPISpecification,
                                            NSArray<NSDictionary<NSString *, id> *> *operations) {
  NSString *defaultBaseURL = nil;
  NSArray *servers = [openAPISpecification[@"servers"] isKindOfClass:[NSArray class]] ? openAPISpecification[@"servers"] : @[];
  if ([servers count] > 0 && [servers[0] isKindOfClass:[NSDictionary class]]) {
    defaultBaseURL = ALNORMTSStringValue(servers[0][@"url"]);
  }
  if ([defaultBaseURL length] == 0) {
    defaultBaseURL = @"http://127.0.0.1:3000";
  }

  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  [output appendString:@"import type { ArlenErrorEnvelope } from './models';\n\n"];
  [output appendString:@"export type ArlenRequestHeaders = Record<string, string | null | undefined>;\n"];
  [output appendString:@"export type ArlenQueryValue = string | number | boolean | null | undefined | Array<string | number | boolean | null>;\n"];
  [output appendString:@"export type ArlenQueryParams = Record<string, ArlenQueryValue>;\n\n"];
  [output appendString:@"export interface ArlenClientOptions {\n  baseUrl?: string;\n  fetch?: typeof fetch;\n  headers?: ArlenRequestHeaders | (() => ArlenRequestHeaders | Promise<ArlenRequestHeaders>);\n}\n\n"];
  [output appendString:@"interface ArlenOperationRequest {\n  operationId: string;\n  method: string;\n  path: string;\n  pathParams?: Record<string, string | number | boolean> | undefined;\n  query?: ArlenQueryParams | undefined;\n  headers?: ArlenRequestHeaders | undefined;\n  body?: unknown;\n  signal?: unknown;\n}\n\n"];
  [output appendString:@"function arlenDefaultFetch(): typeof fetch {\n  if (typeof globalThis.fetch !== 'function') {\n    throw new Error('ArlenClient requires a fetch implementation');\n  }\n  return globalThis.fetch.bind(globalThis);\n}\n\n"];
  [output appendString:@"function arlenEncodePath(pathTemplate: string, pathParams: Record<string, string | number | boolean> = {}): string {\n  return pathTemplate.replace(/\\{([^}]+)\\}/g, (_match, rawName: string) => {\n    const value = pathParams[rawName];\n    if (value === undefined || value === null) {\n      throw new Error(`Missing path parameter ${rawName}`);\n    }\n    return encodeURIComponent(String(value));\n  });\n}\n\n"];
  [output appendString:@"function arlenAppendQuery(urlPath: string, query?: ArlenQueryParams): string {\n  if (!query) {\n    return urlPath;\n  }\n  const search = new URLSearchParams();\n  for (const [key, rawValue] of Object.entries(query)) {\n    if (rawValue === undefined) {\n      continue;\n    }\n    const values = Array.isArray(rawValue) ? rawValue : [rawValue];\n    for (const value of values) {\n      if (value === undefined) {\n        continue;\n      }\n      search.append(key, value === null ? 'null' : String(value));\n    }\n  }\n  const queryString = search.toString();\n  return queryString.length > 0 ? `${urlPath}?${queryString}` : urlPath;\n}\n\n"];
  [output appendString:@"function arlenBuildURL(baseUrl: string, path: string, pathParams?: Record<string, string | number | boolean>, query?: ArlenQueryParams): string {\n  const normalizedPath = arlenAppendQuery(arlenEncodePath(path, pathParams), query);\n  if (!baseUrl) {\n    return normalizedPath;\n  }\n  const trimmedBase = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;\n  return `${trimmedBase}${normalizedPath}`;\n}\n\n"];
  [output appendString:@"async function arlenResolveHeaders(source?: ArlenRequestHeaders | (() => ArlenRequestHeaders | Promise<ArlenRequestHeaders>)): Promise<Record<string, string>> {\n  if (!source) {\n    return {};\n  }\n  const resolved = typeof source === 'function' ? await source() : source;\n  const headers: Record<string, string> = {};\n  for (const [key, value] of Object.entries(resolved ?? {})) {\n    if (value === undefined || value === null) {\n      continue;\n    }\n    headers[key] = String(value);\n  }\n  return headers;\n}\n\n"];
  [output appendString:@"async function arlenParsePayload(response: Response): Promise<unknown> {\n  const rawText = await response.text();\n  if (rawText.length === 0) {\n    return undefined;\n  }\n  const contentType = response.headers.get('content-type') ?? '';\n  if (contentType.includes('json')) {\n    try {\n      return JSON.parse(rawText);\n    } catch (_error) {\n      return rawText;\n    }\n  }\n  return rawText;\n}\n\n"];
  [output appendString:@"export class ArlenClientError extends Error {\n  readonly status: number;\n  readonly operationId: string;\n  readonly payload: ArlenErrorEnvelope | unknown;\n\n  constructor(operationId: string, status: number, payload: ArlenErrorEnvelope | unknown) {\n    super(`Arlen request failed for ${operationId} (${status})`);\n    this.name = 'ArlenClientError';\n    this.status = status;\n    this.operationId = operationId;\n    this.payload = payload;\n  }\n}\n\n"];

  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    [output appendString:ALNORMTSRenderOperationRequestInterface(operation)];
    [output appendFormat:@"export type %@Response = %@;\n\n",
                         operation[@"typeName"] ?: @"Operation",
                         operation[@"responseType"] ?: @"void"];
  }

  [output appendString:@"export const arlenOperations = {\n"];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    NSString *kind = ([operation[@"kind"] integerValue] == ALNORMTSOperationKindQuery) ? @"query" : @"mutation";
    [output appendFormat:@"  %@: {\n", ALNORMTSQuotedPropertyName(methodName)];
    [output appendFormat:@"    operationId: %@,\n", ALNORMTSSingleQuotedString(operation[@"operationId"] ?: @"")];
    [output appendFormat:@"    method: %@,\n", ALNORMTSSingleQuotedString(operation[@"httpMethod"] ?: @"GET")];
    [output appendFormat:@"    path: %@,\n", ALNORMTSSingleQuotedString(operation[@"path"] ?: @"/")];
    [output appendFormat:@"    tags: %@,\n", ALNORMTSStringArrayExpression(operation[@"tags"] ?: @[])];
    [output appendFormat:@"    kind: %@,\n", ALNORMTSSingleQuotedString(kind)];
    [output appendString:@"  },\n"];
  }
  [output appendString:@"} as const;\n\n"];
  [output appendString:@"export class ArlenClient {\n"];
  [output appendString:@"  readonly baseUrl: string;\n  private readonly fetchImplementation: typeof fetch;\n  private readonly defaultHeaders?: ArlenClientOptions['headers'];\n\n"];
  [output appendFormat:@"  constructor(options: ArlenClientOptions = { baseUrl: %@ }) {\n", ALNORMTSSingleQuotedString(defaultBaseURL)];
  [output appendFormat:@"    this.baseUrl = options.baseUrl ?? %@;\n", ALNORMTSSingleQuotedString(defaultBaseURL)];
  [output appendString:@"    this.fetchImplementation = options.fetch ?? arlenDefaultFetch();\n    this.defaultHeaders = options.headers;\n  }\n\n"];
  [output appendString:@"  private async request<T>(request: ArlenOperationRequest): Promise<T> {\n    const mergedHeaders = {\n      ...(await arlenResolveHeaders(this.defaultHeaders)),\n      ...(await arlenResolveHeaders(request.headers)),\n    };\n    if (request.body !== undefined) {\n      if (!mergedHeaders['content-type']) {\n        mergedHeaders['content-type'] = 'application/json';\n      }\n    }\n    if (!mergedHeaders.accept) {\n      mergedHeaders.accept = 'application/json';\n    }\n\n    const requestInit: RequestInit = {\n      method: request.method,\n      headers: mergedHeaders,\n    };\n    if (request.body !== undefined) {\n      requestInit.body = JSON.stringify(request.body);\n    }\n    if (request.signal !== undefined) {\n      requestInit.signal = request.signal as AbortSignal;\n    }\n\n    const response = await this.fetchImplementation(\n      arlenBuildURL(this.baseUrl, request.path, request.pathParams, request.query),\n      requestInit\n    );\n    const payload = await arlenParsePayload(response);\n    if (!response.ok) {\n      throw new ArlenClientError(request.operationId, response.status, payload);\n    }\n    return payload as T;\n  }\n\n"];

  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    NSString *typeName = operation[@"typeName"] ?: @"Operation";
    NSArray *pathProperties = [operation[@"pathProperties"] isKindOfClass:[NSArray class]] ? operation[@"pathProperties"] : @[];
    NSArray *queryProperties = [operation[@"queryProperties"] isKindOfClass:[NSArray class]] ? operation[@"queryProperties"] : @[];
    NSArray *headerProperties =
        [operation[@"headerProperties"] isKindOfClass:[NSArray class]] ? operation[@"headerProperties"] : @[];
    NSString *bodyType = ALNORMTSStringValue(operation[@"bodyType"]);
    NSString *pathValue = ([pathProperties count] > 0) ? @"request.path" : @"undefined";
    NSString *queryValue = ([queryProperties count] > 0) ? @"request.query" : @"undefined";
    NSString *headersValue = ([headerProperties count] > 0) ? @"request.headers" : @"undefined";
    NSString *bodyValue = ([bodyType length] > 0) ? @"request.body" : @"undefined";
    [output appendFormat:@"  async %@(request: %@Request): Promise<%@Response> {\n",
                         methodName, typeName, typeName];
    [output appendFormat:@"    return this.request<%@Response>({\n", typeName];
    [output appendFormat:@"      operationId: %@,\n", ALNORMTSSingleQuotedString(operation[@"operationId"] ?: @"")];
    [output appendFormat:@"      method: %@,\n", ALNORMTSSingleQuotedString(operation[@"httpMethod"] ?: @"GET")];
    [output appendFormat:@"      path: %@,\n", ALNORMTSSingleQuotedString(operation[@"path"] ?: @"/")];
    [output appendFormat:@"      pathParams: %@,\n", pathValue];
    [output appendFormat:@"      query: %@,\n", queryValue];
    [output appendFormat:@"      headers: %@,\n", headersValue];
    [output appendFormat:@"      body: %@,\n", bodyValue];
    [output appendString:@"      signal: request.signal,\n"];
    [output appendString:@"    });\n  }\n\n"];
  }

  [output appendString:@"}\n"];
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSReactQueryKeyRootExpression(NSString *methodName) {
  return [NSString stringWithFormat:@"[%@] as const", ALNORMTSSingleQuotedString(methodName)];
}

static NSString *ALNORMTSReactQueryKeyExpression(NSDictionary<NSString *, id> *operation) {
  NSString *methodName = operation[@"methodName"] ?: @"operation";
  NSArray *pathProperties = [operation[@"pathProperties"] isKindOfClass:[NSArray class]] ? operation[@"pathProperties"] : @[];
  NSArray *queryProperties = [operation[@"queryProperties"] isKindOfClass:[NSArray class]] ? operation[@"queryProperties"] : @[];
  NSMutableArray<NSString *> *components = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"...arlenQueryKeyRoots.%@", methodName]];
  if ([pathProperties count] > 0) {
    [components addObject:@"request.path"];
  }
  if ([queryProperties count] > 0) {
    [components addObject:@"request.query ?? null"];
  }
  return [NSString stringWithFormat:@"[%@] as const", [components componentsJoinedByString:@", "]];
}

static NSArray<NSDictionary<NSString *, id> *> *ALNORMTSOperationsMatchingTags(
    NSArray<NSDictionary<NSString *, id> *> *operations,
    NSArray<NSString *> *tags,
    ALNORMTSOperationKind kind) {
  NSMutableArray<NSDictionary<NSString *, id> *> *matches = [NSMutableArray array];
  NSSet<NSString *> *tagSet = [NSSet setWithArray:tags ?: @[]];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    if ([operation[@"kind"] integerValue] != kind) {
      continue;
    }
    NSSet<NSString *> *candidateTags = [NSSet setWithArray:operation[@"tags"] ?: @[]];
    if ([tagSet intersectsSet:candidateTags]) {
      [matches addObject:operation];
    }
  }
  return [NSArray arrayWithArray:matches];
}

static NSString *ALNORMTSRenderReactModule(NSArray<NSDictionary<NSString *, id> *> *operations) {
  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  [output appendString:@"import { useMutation, useQuery } from '@tanstack/react-query';\n"];
  [output appendString:@"import type { QueryClient, UseMutationOptions, UseQueryOptions } from '@tanstack/react-query';\n"];
  [output appendString:@"import { ArlenClient, ArlenClientError } from './client';\n"];

  NSMutableArray<NSString *> *typeImports = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    NSString *typeName = operation[@"typeName"] ?: @"Operation";
    [typeImports addObject:[NSString stringWithFormat:@"type %@Request", typeName]];
    [typeImports addObject:[NSString stringWithFormat:@"type %@Response", typeName]];
  }
  if ([typeImports count] > 0) {
    [output appendFormat:@"import { %@ } from './client';\n\n", [typeImports componentsJoinedByString:@", "]];
  } else {
    [output appendString:@"\n"];
  }

  NSArray<NSDictionary<NSString *, id> *> *queryOperations =
      ALNORMTSOperationsMatchingTags(operations, @[], ALNORMTSOperationKindQuery);
  (void)queryOperations;

  [output appendString:@"export const arlenQueryKeyRoots = {\n"];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    if ([operation[@"kind"] integerValue] != ALNORMTSOperationKindQuery) {
      continue;
    }
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    [output appendFormat:@"  %@: %@,\n",
                         ALNORMTSQuotedPropertyName(methodName),
                         ALNORMTSReactQueryKeyRootExpression(methodName)];
  }
  [output appendString:@"} as const;\n\n"];

  [output appendString:@"export const arlenQueryKeys = {\n"];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    if ([operation[@"kind"] integerValue] != ALNORMTSOperationKindQuery) {
      continue;
    }
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    NSString *typeName = operation[@"typeName"] ?: @"Operation";
    [output appendFormat:@"  %@: (request: %@Request) => %@,\n",
                         ALNORMTSQuotedPropertyName(methodName),
                         typeName,
                         ALNORMTSReactQueryKeyExpression(operation)];
  }
  [output appendString:@"} as const;\n\n"];

  [output appendString:@"export const arlenMutationKeys = {\n"];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    if ([operation[@"kind"] integerValue] != ALNORMTSOperationKindMutation) {
      continue;
    }
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    [output appendFormat:@"  %@: %@,\n",
                         ALNORMTSQuotedPropertyName(methodName),
                         ALNORMTSReactQueryKeyRootExpression(methodName)];
  }
  [output appendString:@"} as const;\n\n"];

  [output appendString:@"export const arlenInvalidationHints = {\n"];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    if ([operation[@"kind"] integerValue] != ALNORMTSOperationKindMutation) {
      continue;
    }
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    NSArray<NSDictionary<NSString *, id> *> *affectedQueries =
        ALNORMTSOperationsMatchingTags(operations, operation[@"tags"] ?: @[], ALNORMTSOperationKindQuery);
    NSMutableArray<NSString *> *queryOperationNames = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *queryOperation in affectedQueries) {
      [queryOperationNames addObject:queryOperation[@"methodName"] ?: @"operation"];
    }
    [output appendFormat:@"  %@: {\n", ALNORMTSQuotedPropertyName(methodName)];
    [output appendFormat:@"    tags: %@,\n", ALNORMTSStringArrayExpression(operation[@"tags"] ?: @[])];
    [output appendFormat:@"    queryOperations: %@,\n", ALNORMTSStringArrayExpression(queryOperationNames)];
    [output appendString:@"  },\n"];
  }
  [output appendString:@"} as const;\n\n"];

  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    NSString *methodName = operation[@"methodName"] ?: @"operation";
    NSString *typeName = operation[@"typeName"] ?: @"Operation";
    NSString *helperBase = ALNORMTSPascalIdentifier(methodName, @"Operation");
    if ([operation[@"kind"] integerValue] == ALNORMTSOperationKindQuery) {
      [output appendFormat:@"export function %@QueryOptions(\n  client: ArlenClient,\n  request: %@Request,\n  options: Omit<UseQueryOptions<%@Response, ArlenClientError, %@Response, ReturnType<typeof arlenQueryKeys.%@>>, 'queryKey' | 'queryFn'> = {}\n) {\n",
                           methodName, typeName, typeName, typeName, methodName];
      [output appendFormat:@"  return {\n    ...options,\n    queryKey: arlenQueryKeys.%@(request),\n    queryFn: () => client.%@(request),\n  };\n}\n\n",
                           methodName, methodName];
      [output appendFormat:@"export function use%@Query(\n  client: ArlenClient,\n  request: %@Request,\n  options: Omit<UseQueryOptions<%@Response, ArlenClientError, %@Response, ReturnType<typeof arlenQueryKeys.%@>>, 'queryKey' | 'queryFn'> = {}\n) {\n  return useQuery(%@QueryOptions(client, request, options));\n}\n\n",
                           helperBase, typeName, typeName, typeName, methodName, methodName];
      continue;
    }

    NSArray<NSDictionary<NSString *, id> *> *affectedQueries =
        ALNORMTSOperationsMatchingTags(operations, operation[@"tags"] ?: @[], ALNORMTSOperationKindQuery);
    [output appendFormat:@"export function %@MutationOptions(\n  client: ArlenClient,\n  options: Omit<UseMutationOptions<%@Response, ArlenClientError, %@Request, unknown>, 'mutationFn' | 'mutationKey'> = {}\n) {\n",
                         methodName, typeName, typeName];
    [output appendFormat:@"  return {\n    ...options,\n    mutationKey: arlenMutationKeys.%@,\n    mutationFn: (request: %@Request) => client.%@(request),\n  };\n}\n\n",
                         methodName, typeName, methodName];
    [output appendFormat:@"export function use%@Mutation(\n  client: ArlenClient,\n  options: Omit<UseMutationOptions<%@Response, ArlenClientError, %@Request, unknown>, 'mutationFn' | 'mutationKey'> = {}\n) {\n  return useMutation(%@MutationOptions(client, options));\n}\n\n",
                         helperBase, typeName, typeName, methodName];
    [output appendFormat:@"export async function invalidateAfter%@(\n  queryClient: QueryClient\n): Promise<void> {\n",
                         helperBase];
    if ([affectedQueries count] == 0) {
      [output appendString:@"  return Promise.resolve();\n}\n\n"];
    } else {
      [output appendString:@"  await Promise.all([\n"];
      for (NSDictionary<NSString *, id> *queryOperation in affectedQueries) {
        NSString *queryMethodName = queryOperation[@"methodName"] ?: @"operation";
        [output appendFormat:@"    queryClient.invalidateQueries({ queryKey: arlenQueryKeyRoots.%@ }),\n",
                             queryMethodName];
      }
      [output appendString:@"  ]);\n}\n\n"];
    }
  }

  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderIndexModule(NSArray<NSString *> *targets) {
  NSMutableString *output = [NSMutableString string];
  [output appendString:@"// Generated by arlen typescript-codegen. Do not edit by hand.\n\n"];
  [output appendString:@"export * from './models';\n"];
  if ([targets containsObject:@"validators"]) {
    [output appendString:@"export * from './validators';\n"];
  }
  if ([targets containsObject:@"query"]) {
    [output appendString:@"export * from './query';\n"];
  }
  if ([targets containsObject:@"client"]) {
    [output appendString:@"export * from './client';\n"];
  }
  if ([targets containsObject:@"react"]) {
    [output appendString:@"export * from './react';\n"];
  }
  if ([targets containsObject:@"meta"]) {
    [output appendString:@"export * from './meta';\n"];
  }
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderReadme(NSString *packageName,
                                      NSArray<NSString *> *targets,
                                      NSInteger modelCount,
                                      NSInteger operationCount,
                                      NSInteger resourceCount,
                                      NSInteger moduleCount,
                                      NSDictionary<NSString *, id> *workspaceHints) {
  NSMutableString *output = [NSMutableString string];
  [output appendFormat:@"# %@\n\n", packageName ?: @"arlen-generated-client"];
  [output appendString:@"Generated by `arlen typescript-codegen`.\n\n"];
  [output appendString:@"This package is descriptor-first:\n\n"];
  [output appendString:@"- `src/models.ts`: TypeScript read/create/update contracts and model metadata\n"];
  if ([targets containsObject:@"validators"]) {
    [output appendString:@"- `src/validators.ts`: framework-neutral validation schemas and form adapters\n"];
  }
  if ([targets containsObject:@"query"]) {
    [output appendString:@"- `src/query.ts`: explicit relation metadata and resource query-shape contracts\n"];
  }
  if ([targets containsObject:@"client"]) {
    [output appendString:@"- `src/client.ts`: typed `fetch` transport client derived from OpenAPI metadata\n"];
  }
  if ([targets containsObject:@"react"]) {
    [output appendString:@"- `src/react.ts`: optional TanStack Query-oriented React helpers\n"];
  }
  if ([targets containsObject:@"meta"]) {
    [output appendString:@"- `src/meta.ts`: module/resource/admin metadata bridge plus workspace hints\n"];
  }
  [output appendString:@"\n"];
  [output appendFormat:@"Models: `%ld`\n\n", (long)modelCount];
  [output appendFormat:@"OpenAPI operations: `%ld`\n", (long)operationCount];
  [output appendFormat:@"Resources: `%ld`\n", (long)resourceCount];
  [output appendFormat:@"Modules: `%ld`\n\n", (long)moduleCount];
  [output appendString:@"Common adoption shapes:\n\n"];
  [output appendString:@"- app-local generated folder under `frontend/generated/arlen`\n"];
  [output appendString:@"- monorepo package imported via workspace aliases\n"];
  [output appendString:@"- publishable internal package with app-owned versioning\n\n"];
  [output appendString:@"Suggested workflow:\n\n"];
  [output appendFormat:@"- install: `%@`\n", workspaceHints[@"installCommand"] ?: @"npm install"];
  [output appendFormat:@"- typecheck: `%@`\n", workspaceHints[@"typecheckCommand"] ?: @"npm run typecheck"];
  if ([ALNORMTSStringValue(workspaceHints[@"devCommand"]) length] > 0) {
    [output appendFormat:@"- dev: `%@`\n", workspaceHints[@"devCommand"]];
  }
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderTSConfig(BOOL reactTarget, NSError **error) {
  NSDictionary<NSString *, id> *config = @{
    @"compilerOptions" : @{
      @"target" : @"ES2020",
      @"module" : @"ESNext",
      @"moduleResolution" : @"Bundler",
      @"strict" : @YES,
      @"declaration" : @YES,
      @"noEmit" : @YES,
      @"exactOptionalPropertyTypes" : @YES,
      @"isolatedModules" : @YES,
      @"jsx" : reactTarget ? @"react-jsx" : @"preserve",
      @"lib" : @[ @"ES2020", @"DOM" ],
    },
    @"include" : @[ @"src/**/*.ts" ],
  };
  return ALNORMTSJSONStringFromObject(config, error);
}

static NSString *ALNORMTSRenderPackageJSON(NSString *packageName,
                                           NSArray<NSString *> *targets,
                                           NSError **error) {
  NSMutableDictionary<NSString *, id> *exports = [NSMutableDictionary dictionary];
  exports[@"."] = @"./src/index.ts";
  exports[@"./models"] = @"./src/models.ts";
  if ([targets containsObject:@"validators"]) {
    exports[@"./validators"] = @"./src/validators.ts";
  }
  if ([targets containsObject:@"query"]) {
    exports[@"./query"] = @"./src/query.ts";
  }
  if ([targets containsObject:@"client"]) {
    exports[@"./client"] = @"./src/client.ts";
  }
  if ([targets containsObject:@"react"]) {
    exports[@"./react"] = @"./src/react.ts";
  }
  if ([targets containsObject:@"meta"]) {
    exports[@"./meta"] = @"./src/meta.ts";
  }

  NSMutableDictionary<NSString *, id> *packageJSON = [NSMutableDictionary dictionary];
  packageJSON[@"name"] = [ALNORMTSStringValue(packageName) length] > 0 ? packageName : @"arlen-generated-client";
  packageJSON[@"version"] = @"0.1.0";
  packageJSON[@"private"] = @YES;
  packageJSON[@"type"] = @"module";
  packageJSON[@"types"] = @"./src/index.ts";
  packageJSON[@"sideEffects"] = @NO;
  packageJSON[@"exports"] = exports;
  packageJSON[@"scripts"] = @{
    @"typecheck" : @"tsc --noEmit",
    @"check" : @"tsc --noEmit",
  };
  packageJSON[@"devDependencies"] = @{
    @"typescript" : @"^5.0.0",
  };
  if ([targets containsObject:@"react"]) {
    packageJSON[@"peerDependencies"] = @{
      @"@tanstack/react-query" : @"^5.0.0",
      @"react" : @"^18.0.0 || ^19.0.0",
    };
  }
  return ALNORMTSJSONStringFromObject(packageJSON, error);
}

static NSArray<NSString *> *ALNORMTSNormalizedTargets(NSArray<NSString *> *rawTargets,
                                                      NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSArray<NSString *> *inputs = ([rawTargets count] > 0) ? rawTargets : @[ @"all" ];
  NSMutableArray<NSString *> *targets = [NSMutableArray array];
  for (NSString *rawTarget in inputs) {
    NSArray<NSString *> *tokens = [[ALNORMTSStringValue(rawTarget) lowercaseString] componentsSeparatedByString:@","];
    for (NSString *rawToken in tokens) {
      NSString *token = ALNORMTSStringValue(rawToken);
      if ([token length] == 0) {
        continue;
      }
      if ([token isEqualToString:@"all"]) {
        for (NSString *expanded in @[ @"models", @"validators", @"query", @"client", @"react", @"meta" ]) {
          if (![targets containsObject:expanded]) {
            [targets addObject:expanded];
          }
        }
        continue;
      }
      if ([token isEqualToString:@"react"]) {
        if (![targets containsObject:@"models"]) {
          [targets addObject:@"models"];
        }
        if (![targets containsObject:@"client"]) {
          [targets addObject:@"client"];
        }
        if (![targets containsObject:@"react"]) {
          [targets addObject:@"react"];
        }
        continue;
      }
      if ([token isEqualToString:@"validators"] || [token isEqualToString:@"query"]) {
        if (![targets containsObject:@"models"]) {
          [targets addObject:@"models"];
        }
      }
      if ([token isEqualToString:@"meta"]) {
        if (![targets containsObject:@"models"]) {
          [targets addObject:@"models"];
        }
        if (![targets containsObject:@"query"]) {
          [targets addObject:@"query"];
        }
      }
      if (![token isEqualToString:@"models"] && ![token isEqualToString:@"client"] &&
          ![token isEqualToString:@"validators"] && ![token isEqualToString:@"query"] &&
          ![token isEqualToString:@"meta"]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                                   @"TypeScript codegen target is unsupported",
                                   @{
                                     @"target" : token ?: @"",
                                   });
        }
        return nil;
      }
      if (![targets containsObject:token]) {
        [targets addObject:token];
      }
    }
  }
  if ([targets count] == 0) {
    [targets addObjectsFromArray:@[ @"models", @"validators", @"query", @"client", @"react", @"meta" ]];
  }
  return [NSArray arrayWithArray:targets];
}

@implementation ALNORMTypeScriptCodegen

+ (NSDictionary<NSString *,id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *,id> *)metadata
                                                       classPrefix:(NSString *)classPrefix
                                                    databaseTarget:(NSString *)databaseTarget
                                                descriptorOverrides:(NSDictionary<NSString *,NSDictionary *> *)descriptorOverrides
                                               openAPISpecification:(NSDictionary<NSString *,id> *)openAPISpecification
                                                       packageName:(NSString *)packageName
                                                           targets:(NSArray<NSString *> *)targets
                                                             error:(NSError **)error {
  NSArray<ALNORMModelDescriptor *> *descriptors =
      [ALNORMCodegen modelDescriptorsFromSchemaMetadata:metadata
                                            classPrefix:classPrefix
                                         databaseTarget:databaseTarget
                                     descriptorOverrides:descriptorOverrides
                                                  error:error];
  if (descriptors == nil) {
    return nil;
  }
  return [self renderArtifactsFromModelDescriptors:descriptors
                               openAPISpecification:openAPISpecification
                                        packageName:packageName
                                            targets:targets
                                              error:error];
}

+ (NSDictionary<NSString *,id> *)renderArtifactsFromORMManifest:(NSDictionary<NSString *,id> *)manifest
                                            openAPISpecification:(NSDictionary<NSString *,id> *)openAPISpecification
                                                    packageName:(NSString *)packageName
                                                        targets:(NSArray<NSString *> *)targets
                                                          error:(NSError **)error {
  NSArray<ALNORMModelDescriptor *> *descriptors = ALNORMTSModelDescriptorsFromORMManifest(manifest, error);
  if (descriptors == nil) {
    return nil;
  }
  return [self renderArtifactsFromModelDescriptors:descriptors
                               openAPISpecification:openAPISpecification
                                        packageName:packageName
                                            targets:targets
                                              error:error];
}

+ (NSDictionary<NSString *,id> *)renderArtifactsFromModelDescriptors:(NSArray<ALNORMModelDescriptor *> *)descriptors
                                                 openAPISpecification:(NSDictionary<NSString *,id> *)openAPISpecification
                                                         packageName:(NSString *)packageName
                                                             targets:(NSArray<NSString *> *)targets
                                                               error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  NSArray<NSString *> *normalizedTargets = ALNORMTSNormalizedTargets(targets, error);
  if (normalizedTargets == nil) {
    return nil;
  }

  if ([normalizedTargets containsObject:@"models"] && [descriptors count] == 0) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"TypeScript model generation requires at least one ORM descriptor",
                               nil);
    }
    return nil;
  }

  NSDictionary<NSString *, NSString *> *typeNamesByEntity = @{};
  if ([descriptors count] > 0) {
    typeNamesByEntity = ALNORMTSTypeNamesByEntity(descriptors, error);
    if (typeNamesByEntity == nil) {
      return nil;
    }
  }

  NSArray<NSDictionary<NSString *, id> *> *operations = @[];
  NSArray<NSDictionary<NSString *, id> *> *resources = @[];
  NSArray<NSDictionary<NSString *, id> *> *modules = @[];
  NSDictionary<NSString *, id> *workspaceHints = ALNORMTSWorkspaceHints(openAPISpecification ?: @{});
  BOOL requiresOpenAPI = ([normalizedTargets containsObject:@"client"] || [normalizedTargets containsObject:@"react"]);
  BOOL hasOpenAPI = [openAPISpecification isKindOfClass:[NSDictionary class]];
  if (requiresOpenAPI && !hasOpenAPI) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"TypeScript client/react generation requires an OpenAPI specification",
                               nil);
    }
    return nil;
  }
  if (hasOpenAPI) {
    operations = ALNORMTSOperationsFromOpenAPISpecification(openAPISpecification, error);
    if (operations == nil) {
      return nil;
    }
    resources = ALNORMTSNormalizedResourceMetadata(openAPISpecification,
                                                   operations,
                                                   descriptors ?: @[],
                                                   typeNamesByEntity,
                                                   error);
    if (resources == nil) {
      return nil;
    }
    modules = ALNORMTSNormalizedModuleMetadata(openAPISpecification, operations, resources, error);
    if (modules == nil) {
      return nil;
    }
    if (requiresOpenAPI && [operations count] == 0) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI specification did not contain any operations",
                                 nil);
      }
      return nil;
    }
  }

  NSMutableDictionary<NSString *, NSString *> *files = [NSMutableDictionary dictionary];
  NSError *renderError = nil;

  NSString *modelsModule = ALNORMTSRenderModelsModule(descriptors ?: @[], typeNamesByEntity, &renderError);
  if (modelsModule == nil) {
    if (error != NULL) {
      *error = renderError;
    }
    return nil;
  }
  files[@"src/models.ts"] = modelsModule;
  if ([normalizedTargets containsObject:@"validators"]) {
    NSString *validatorsModule =
        ALNORMTSRenderValidatorsModule(descriptors ?: @[],
                                       typeNamesByEntity,
                                       openAPISpecification ?: @{},
                                       operations ?: @[],
                                       &renderError);
    if (validatorsModule == nil) {
      if (error != NULL) {
        *error = renderError;
      }
      return nil;
    }
    files[@"src/validators.ts"] = validatorsModule;
  }
  if ([normalizedTargets containsObject:@"query"]) {
    files[@"src/query.ts"] = ALNORMTSRenderQueryModule(descriptors ?: @[],
                                                       typeNamesByEntity,
                                                       resources ?: @[]);
  }

  if ([normalizedTargets containsObject:@"client"]) {
    files[@"src/client.ts"] = ALNORMTSRenderClientModule(openAPISpecification ?: @{}, operations ?: @[]);
  }
  if ([normalizedTargets containsObject:@"react"]) {
    files[@"src/react.ts"] = ALNORMTSRenderReactModule(operations ?: @[]);
  }
  if ([normalizedTargets containsObject:@"meta"]) {
    files[@"src/meta.ts"] = ALNORMTSRenderMetaModule(resources ?: @[],
                                                     modules ?: @[],
                                                     workspaceHints ?: @{});
  }
  files[@"src/index.ts"] = ALNORMTSRenderIndexModule(normalizedTargets);

  NSString *resolvedPackageName = [ALNORMTSStringValue(packageName) length] > 0 ? packageName : @"arlen-generated-client";
  NSString *packageJSON = ALNORMTSRenderPackageJSON(resolvedPackageName, normalizedTargets, &renderError);
  if (packageJSON == nil) {
    if (error != NULL) {
      *error = renderError;
    }
    return nil;
  }
  files[@"package.json"] = packageJSON;

  NSString *tsconfig = ALNORMTSRenderTSConfig([normalizedTargets containsObject:@"react"], &renderError);
  if (tsconfig == nil) {
    if (error != NULL) {
      *error = renderError;
    }
    return nil;
  }
  files[@"tsconfig.json"] = tsconfig;
  files[@"README.md"] =
      ALNORMTSRenderReadme(resolvedPackageName,
                           normalizedTargets,
                           [descriptors count],
                           [operations count],
                           [resources count],
                           [modules count],
                           workspaceHints ?: @{});

  NSMutableArray<NSDictionary<NSString *, id> *> *manifestFiles = [NSMutableArray array];
  NSArray<NSString *> *sortedFilePaths = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *path in sortedFilePaths) {
    NSString *kind = @"support";
    if ([path hasSuffix:@"models.ts"]) {
      kind = @"models";
    } else if ([path hasSuffix:@"validators.ts"]) {
      kind = @"validators";
    } else if ([path hasSuffix:@"query.ts"]) {
      kind = @"query";
    } else if ([path hasSuffix:@"client.ts"]) {
      kind = @"client";
    } else if ([path hasSuffix:@"react.ts"]) {
      kind = @"react";
    } else if ([path hasSuffix:@"meta.ts"]) {
      kind = @"meta";
    }
    [manifestFiles addObject:@{
      @"path" : path,
      @"kind" : kind,
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *manifestModels = [NSMutableArray array];
  NSArray<ALNORMModelDescriptor *> *sortedDescriptors =
      [descriptors sortedArrayUsingDescriptors:@[
        [NSSortDescriptor sortDescriptorWithKey:@"entityName" ascending:YES]
      ]];
  for (ALNORMModelDescriptor *descriptor in sortedDescriptors) {
    NSString *typeName = typeNamesByEntity[descriptor.entityName ?: @""] ?: @"Model";
    [manifestModels addObject:@{
      @"entity_name" : descriptor.entityName ?: @"",
      @"type_name" : typeName,
      @"create_input_name" : [NSString stringWithFormat:@"%@CreateInput", typeName],
      @"update_input_name" : [NSString stringWithFormat:@"%@UpdateInput", typeName],
      @"create_schema_name" : [NSString stringWithFormat:@"%@CreateInputSchema", ALNORMTSCamelIdentifier(typeName, @"model")],
      @"update_schema_name" : [NSString stringWithFormat:@"%@UpdateInputSchema", ALNORMTSCamelIdentifier(typeName, @"model")],
      @"field_name_type" : [NSString stringWithFormat:@"%@FieldName", typeName],
      @"relation_name_type" : [NSString stringWithFormat:@"%@RelationName", typeName],
      @"available_include_type" : [NSString stringWithFormat:@"%@AvailableInclude", typeName],
      @"read_only" : @(descriptor.isReadOnly),
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *manifestOperations = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *operation in operations ?: @[]) {
    [manifestOperations addObject:@{
      @"operation_id" : operation[@"operationId"] ?: @"",
      @"method_name" : operation[@"methodName"] ?: @"",
      @"request_type" : [NSString stringWithFormat:@"%@Request", operation[@"typeName"] ?: @"Operation"],
      @"response_type" : [NSString stringWithFormat:@"%@Response", operation[@"typeName"] ?: @"Operation"],
      @"request_schema_name" : [NSString stringWithFormat:@"%@RequestSchema", operation[@"methodName"] ?: @"operation"],
      @"http_method" : operation[@"httpMethod"] ?: @"GET",
      @"path" : operation[@"path"] ?: @"/",
      @"kind" : ([operation[@"kind"] integerValue] == ALNORMTSOperationKindQuery) ? @"query" : @"mutation",
      @"tags" : operation[@"tags"] ?: @[],
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *manifestResources = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *resource in resources ?: @[]) {
    NSString *resourceName = ALNORMTSStringValue(resource[@"name"]);
    [manifestResources addObject:@{
      @"name" : resourceName ?: @"",
      @"entity_name" : ALNORMTSStringValue(resource[@"entityName"]) ?: @"",
      @"model_type_name" : ALNORMTSStringValue(resource[@"modelTypeName"]) ?: @"",
      @"operation_ids" : resource[@"operationIds"] ?: @[],
      @"query_contract_name" : [NSString stringWithFormat:@"%@ResourceQueryContract",
                                                       ALNORMTSCamelIdentifier(resourceName, @"resource")],
      @"admin_enabled" : @(ALNORMTSBoolValue(ALNORMTSDictionaryValue(resource[@"admin"])[@"enabled"], NO)),
    }];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *manifestModules = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *module in modules ?: @[]) {
    [manifestModules addObject:@{
      @"name" : ALNORMTSStringValue(module[@"name"]) ?: @"",
      @"kind" : ALNORMTSStringValue(module[@"kind"]) ?: @"generic",
      @"operation_ids" : module[@"operationIds"] ?: @[],
      @"resource_names" : module[@"resourceNames"] ?: @[],
    }];
  }

  NSDictionary<NSString *, id> *manifestRoot = @{
    @"format" : ALNORMTypeScriptManifestFormat,
    @"version" : @1,
    @"package_name" : resolvedPackageName,
    @"targets" : normalizedTargets,
    @"model_count" : @([descriptors count]),
    @"operation_count" : @([operations count]),
    @"resource_count" : @([resources count]),
    @"module_count" : @([modules count]),
    @"files" : manifestFiles,
    @"models" : manifestModels,
    @"operations" : manifestOperations,
    @"resources" : manifestResources,
    @"modules" : manifestModules,
    @"workspace_hints" : workspaceHints ?: @{},
  };
  NSString *manifest = ALNORMTSJSONStringFromObject(manifestRoot, &renderError);
  if (manifest == nil) {
    if (error != NULL) {
      *error = renderError;
    }
    return nil;
  }

  return @{
    @"files" : files,
    @"manifest" : manifest,
    @"targets" : normalizedTargets,
    @"packageName" : resolvedPackageName,
    @"modelCount" : @([descriptors count]),
    @"operationCount" : @([operations count]),
    @"resourceCount" : @([resources count]),
    @"moduleCount" : @([modules count]),
    @"suggestedOutputDir" : @"frontend/generated/arlen",
    @"suggestedManifestPath" : @"db/schema/arlen_typescript.json",
  };
}

@end
