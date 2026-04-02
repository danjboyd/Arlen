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
          @"optional" : @(![requiredFields containsObject:name]),
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
          @"optional" : @(!required),
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
      if ([requestBody count] > 0) {
        NSDictionary<NSString *, id> *bodySchema = ALNORMTSDictionaryValue(jsonRequestBody[@"schema"]);
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
        @"bodyRequired" : @(bodyRequired),
        @"responseType" : responseType ?: @"void",
      }];
    }
  }
  return [NSArray arrayWithArray:operations];
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
  [output appendString:@"interface ArlenOperationRequest {\n  operationId: string;\n  method: string;\n  path: string;\n  pathParams?: Record<string, string | number | boolean>;\n  query?: ArlenQueryParams;\n  headers?: ArlenRequestHeaders;\n  body?: unknown;\n  signal?: unknown;\n}\n\n"];
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
  [output appendString:@"  private async request<T>(request: ArlenOperationRequest): Promise<T> {\n    const mergedHeaders = {\n      ...(await arlenResolveHeaders(this.defaultHeaders)),\n      ...(await arlenResolveHeaders(request.headers)),\n    };\n    if (request.body !== undefined) {\n      if (!mergedHeaders['content-type']) {\n        mergedHeaders['content-type'] = 'application/json';\n      }\n    }\n    if (!mergedHeaders.accept) {\n      mergedHeaders.accept = 'application/json';\n    }\n\n    const response = await this.fetchImplementation(\n      arlenBuildURL(this.baseUrl, request.path, request.pathParams, request.query),\n      {\n        method: request.method,\n        headers: mergedHeaders,\n        body: request.body === undefined ? undefined : JSON.stringify(request.body),\n        signal: request.signal as AbortSignal | undefined,\n      }\n    );\n    const payload = await arlenParsePayload(response);\n    if (!response.ok) {\n      throw new ArlenClientError(request.operationId, response.status, payload);\n    }\n    return payload as T;\n  }\n\n"];

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
  if ([targets containsObject:@"client"]) {
    [output appendString:@"export * from './client';\n"];
  }
  if ([targets containsObject:@"react"]) {
    [output appendString:@"export * from './react';\n"];
  }
  return [NSString stringWithString:output];
}

static NSString *ALNORMTSRenderReadme(NSString *packageName,
                                      NSArray<NSString *> *targets,
                                      NSInteger modelCount,
                                      NSInteger operationCount) {
  NSMutableString *output = [NSMutableString string];
  [output appendFormat:@"# %@\n\n", packageName ?: @"arlen-generated-client"];
  [output appendString:@"Generated by `arlen typescript-codegen`.\n\n"];
  [output appendString:@"This package is descriptor-first:\n\n"];
  [output appendString:@"- `src/models.ts`: TypeScript read/create/update contracts and model metadata\n"];
  if ([targets containsObject:@"client"]) {
    [output appendString:@"- `src/client.ts`: typed `fetch` transport client derived from OpenAPI metadata\n"];
  }
  if ([targets containsObject:@"react"]) {
    [output appendString:@"- `src/react.ts`: optional TanStack Query-oriented React helpers\n"];
  }
  [output appendString:@"\n"];
  [output appendFormat:@"Models: `%ld`\n\n", (long)modelCount];
  [output appendFormat:@"OpenAPI operations: `%ld`\n", (long)operationCount];
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
  if ([targets containsObject:@"client"]) {
    exports[@"./client"] = @"./src/client.ts";
  }
  if ([targets containsObject:@"react"]) {
    exports[@"./react"] = @"./src/react.ts";
  }

  NSMutableDictionary<NSString *, id> *packageJSON = [NSMutableDictionary dictionary];
  packageJSON[@"name"] = [ALNORMTSStringValue(packageName) length] > 0 ? packageName : @"arlen-generated-client";
  packageJSON[@"version"] = @"0.1.0";
  packageJSON[@"private"] = @YES;
  packageJSON[@"type"] = @"module";
  packageJSON[@"sideEffects"] = @NO;
  packageJSON[@"exports"] = exports;
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
        for (NSString *expanded in @[ @"models", @"client", @"react" ]) {
          if (![targets containsObject:expanded]) {
            [targets addObject:expanded];
          }
        }
        continue;
      }
      if ([token isEqualToString:@"react"]) {
        if (![targets containsObject:@"client"]) {
          [targets addObject:@"client"];
        }
        if (![targets containsObject:@"react"]) {
          [targets addObject:@"react"];
        }
        continue;
      }
      if (![token isEqualToString:@"models"] && ![token isEqualToString:@"client"]) {
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
    [targets addObjectsFromArray:@[ @"models", @"client", @"react" ]];
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

  NSArray<NSDictionary<NSString *, id> *> *operations = @[];
  if ([normalizedTargets containsObject:@"client"] || [normalizedTargets containsObject:@"react"]) {
    if (![openAPISpecification isKindOfClass:[NSDictionary class]]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                                 @"TypeScript client/react generation requires an OpenAPI specification",
                                 nil);
      }
      return nil;
    }
    operations = ALNORMTSOperationsFromOpenAPISpecification(openAPISpecification, error);
    if (operations == nil) {
      return nil;
    }
    if ([operations count] == 0) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"OpenAPI specification did not contain any operations",
                                 nil);
      }
      return nil;
    }
  }

  NSDictionary<NSString *, NSString *> *typeNamesByEntity = @{};
  if ([descriptors count] > 0) {
    typeNamesByEntity = ALNORMTSTypeNamesByEntity(descriptors, error);
    if (typeNamesByEntity == nil) {
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

  if ([normalizedTargets containsObject:@"client"]) {
    files[@"src/client.ts"] = ALNORMTSRenderClientModule(openAPISpecification ?: @{}, operations ?: @[]);
  }
  if ([normalizedTargets containsObject:@"react"]) {
    files[@"src/react.ts"] = ALNORMTSRenderReactModule(operations ?: @[]);
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
      ALNORMTSRenderReadme(resolvedPackageName, normalizedTargets, [descriptors count], [operations count]);

  NSMutableArray<NSDictionary<NSString *, id> *> *manifestFiles = [NSMutableArray array];
  NSArray<NSString *> *sortedFilePaths = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *path in sortedFilePaths) {
    NSString *kind = @"support";
    if ([path hasSuffix:@"models.ts"]) {
      kind = @"models";
    } else if ([path hasSuffix:@"client.ts"]) {
      kind = @"client";
    } else if ([path hasSuffix:@"react.ts"]) {
      kind = @"react";
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
      @"relation_name_type" : [NSString stringWithFormat:@"%@RelationName", typeName],
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
      @"http_method" : operation[@"httpMethod"] ?: @"GET",
      @"path" : operation[@"path"] ?: @"/",
      @"kind" : ([operation[@"kind"] integerValue] == ALNORMTSOperationKindQuery) ? @"query" : @"mutation",
      @"tags" : operation[@"tags"] ?: @[],
    }];
  }

  NSDictionary<NSString *, id> *manifestRoot = @{
    @"format" : ALNORMTypeScriptManifestFormat,
    @"version" : @1,
    @"package_name" : resolvedPackageName,
    @"targets" : normalizedTargets,
    @"model_count" : @([descriptors count]),
    @"operation_count" : @([operations count]),
    @"files" : manifestFiles,
    @"models" : manifestModels,
    @"operations" : manifestOperations,
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
    @"suggestedOutputDir" : @"frontend/generated/arlen",
    @"suggestedManifestPath" : @"db/schema/arlen_typescript.json",
  };
}

@end
