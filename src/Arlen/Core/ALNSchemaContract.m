#import "ALNSchemaContract.h"

#import "ALNRequest.h"
#import "ALNValueTransformers.h"

static void ALNAppendSchemaError(NSMutableArray *errors,
                                 NSString *field,
                                 NSString *code,
                                 NSString *message) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
    @"field" : field ?: @"",
    @"code" : code ?: @"invalid",
    @"message" : message ?: @"invalid value",
  }];
  [errors addObject:entry];
}

static void ALNAppendSchemaErrorWithMetadata(NSMutableArray *errors,
                                             NSString *field,
                                             NSString *code,
                                             NSString *message,
                                             NSDictionary *metadata) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
    @"field" : field ?: @"",
    @"code" : code ?: @"invalid",
    @"message" : message ?: @"invalid value",
  }];
  if ([metadata isKindOfClass:[NSDictionary class]] && [metadata count] > 0) {
    entry[@"meta"] = metadata;
  }
  [errors addObject:entry];
}

static NSDictionary *ALNSchemaDescriptorFromValue(id raw) {
  if ([raw isKindOfClass:[NSDictionary class]]) {
    return raw;
  }
  if ([raw isKindOfClass:[NSString class]]) {
    return @{ @"type" : [raw lowercaseString] };
  }
  return @{};
}

static NSDictionary *ALNSchemaProperties(NSDictionary *schema) {
  if (![schema isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  id explicitProperties = schema[@"properties"];
  if ([explicitProperties isKindOfClass:[NSDictionary class]]) {
    return explicitProperties;
  }

  NSMutableDictionary *properties = [NSMutableDictionary dictionary];
  NSSet *reserved = [NSSet setWithArray:@[
    @"type", @"required", @"description", @"title", @"items", @"enum", @"source",
    @"default", @"coerce", @"minimum", @"maximum", @"minLength", @"maxLength",
    @"transformer", @"transformers"
  ]];
  for (id key in schema) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    if ([reserved containsObject:key]) {
      continue;
    }
    id candidate = schema[key];
    if ([candidate isKindOfClass:[NSDictionary class]] ||
        [candidate isKindOfClass:[NSString class]]) {
      properties[key] = candidate;
    }
  }
  return properties;
}

static NSSet *ALNSchemaRequiredSet(NSDictionary *schema, NSDictionary *properties) {
  NSMutableSet *required = [NSMutableSet set];
  id explicitRequired = schema[@"required"];
  if ([explicitRequired isKindOfClass:[NSArray class]]) {
    for (id value in explicitRequired) {
      if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        [required addObject:value];
      }
    }
  }
  for (NSString *name in properties) {
    NSDictionary *descriptor = ALNSchemaDescriptorFromValue(properties[name]);
    if ([descriptor[@"required"] respondsToSelector:@selector(boolValue)] &&
        [descriptor[@"required"] boolValue]) {
      [required addObject:name];
    }
  }
  return required;
}

static NSString *ALNSchemaType(NSDictionary *descriptor) {
  NSString *type = [descriptor[@"type"] isKindOfClass:[NSString class]]
                       ? [descriptor[@"type"] lowercaseString]
                       : @"";
  if ([type length] > 0) {
    return type;
  }
  if ([[descriptor[@"properties"] allKeys] count] > 0) {
    return @"object";
  }
  if ([descriptor[@"items"] isKindOfClass:[NSDictionary class]] ||
      [descriptor[@"items"] isKindOfClass:[NSString class]]) {
    return @"array";
  }
  return @"string";
}

static NSArray *ALNSchemaTransformerNames(NSDictionary *descriptor) {
  NSMutableArray *names = [NSMutableArray array];

  NSString *single = [descriptor[@"transformer"] isKindOfClass:[NSString class]]
                         ? descriptor[@"transformer"]
                         : @"";
  if ([single length] > 0) {
    NSString *trimmed = [single stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] > 0) {
      [names addObject:trimmed];
    }
  }

  NSArray *multiple = [descriptor[@"transformers"] isKindOfClass:[NSArray class]]
                          ? descriptor[@"transformers"]
                          : @[];
  for (id value in multiple) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
                                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0 || [names containsObject:trimmed]) {
      continue;
    }
    [names addObject:trimmed];
  }

  return [NSArray arrayWithArray:names];
}

static NSDictionary *ALNSchemaReadinessDiagnostic(NSString *field,
                                                  NSString *severity,
                                                  NSString *code,
                                                  NSString *message,
                                                  NSDictionary *meta) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionary];
  entry[@"field"] = [field isKindOfClass:[NSString class]] ? field : @"";
  entry[@"severity"] = [severity isKindOfClass:[NSString class]] ? severity : @"error";
  entry[@"code"] = [code isKindOfClass:[NSString class]] ? code : @"invalid_schema";
  entry[@"message"] =
      [message isKindOfClass:[NSString class]] ? message : @"Invalid schema descriptor";
  if ([meta isKindOfClass:[NSDictionary class]] && [meta count] > 0) {
    entry[@"meta"] = meta;
  }
  return entry;
}

static NSSet *ALNSupportedSchemaTypes(void) {
  static NSSet *types = nil;
  if (types == nil) {
    types = [[NSSet alloc] initWithArray:@[
      @"string",
      @"integer",
      @"number",
      @"boolean",
      @"object",
      @"array",
    ]];
  }
  return types;
}

static NSString *ALNSchemaJoinFieldPath(NSString *base, NSString *segment) {
  NSString *lhs = [base isKindOfClass:[NSString class]] ? base : @"";
  NSString *rhs = [segment isKindOfClass:[NSString class]] ? segment : @"";
  if ([lhs length] == 0) {
    return rhs;
  }
  if ([rhs length] == 0) {
    return lhs;
  }
  return [NSString stringWithFormat:@"%@.%@", lhs, rhs];
}

static void ALNCollectSchemaReadinessDiagnosticsForDescriptor(id rawDescriptor,
                                                              NSString *fieldPath,
                                                              NSMutableArray *diagnostics) {
  NSString *path = [fieldPath isKindOfClass:[NSString class]] ? fieldPath : @"";
  if (rawDescriptor != nil &&
      ![rawDescriptor isKindOfClass:[NSDictionary class]] &&
      ![rawDescriptor isKindOfClass:[NSString class]]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                            path,
                            @"warning",
                            @"invalid_descriptor",
                            @"Descriptor should be a dictionary or type string",
                            @{ @"descriptor_class" : NSStringFromClass([rawDescriptor class]) ?: @"" })];
    return;
  }

  NSDictionary *descriptor = ALNSchemaDescriptorFromValue(rawDescriptor);
  NSString *declaredType = [descriptor[@"type"] isKindOfClass:[NSString class]]
                               ? [descriptor[@"type"] lowercaseString]
                               : @"";
  if ([declaredType length] > 0 &&
      ![ALNSupportedSchemaTypes() containsObject:declaredType]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(path,
                                                        @"error",
                                                        @"unsupported_type",
                                                        @"Schema type is not supported",
                                                        @{ @"type" : declaredType ?: @"" })];
  }

  id requiredValue = descriptor[@"required"];
  if (requiredValue != nil &&
      ![requiredValue isKindOfClass:[NSArray class]] &&
      ![requiredValue respondsToSelector:@selector(boolValue)]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                            path,
                            @"warning",
                            @"invalid_required_shape",
                            @"required should be an array or boolean",
                            @{ @"required_class" : NSStringFromClass([requiredValue class]) ?: @"" })];
  }

  id singleTransformer = descriptor[@"transformer"];
  if (singleTransformer != nil && ![singleTransformer isKindOfClass:[NSString class]]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                            path,
                            @"warning",
                            @"invalid_transformer_shape",
                            @"transformer should be a string",
                            @{ @"transformer_class" : NSStringFromClass([singleTransformer class]) ?: @"" })];
  }

  id multipleTransformers = descriptor[@"transformers"];
  if (multipleTransformers != nil && ![multipleTransformers isKindOfClass:[NSArray class]]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                            path,
                            @"warning",
                            @"invalid_transformers_shape",
                            @"transformers should be an array",
                            @{ @"transformers_class" : NSStringFromClass([multipleTransformers class]) ?: @"" })];
  } else if ([multipleTransformers isKindOfClass:[NSArray class]]) {
    NSArray *values = (NSArray *)multipleTransformers;
    for (NSUInteger idx = 0; idx < [values count]; idx++) {
      id value = values[idx];
      if ([value isKindOfClass:[NSString class]]) {
        continue;
      }
      [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                              path,
                              @"warning",
                              @"invalid_transformer_name",
                              @"transformers entries should be strings",
                              @{
                                @"index" : @(idx),
                                @"transformer_class" : NSStringFromClass([value class]) ?: @""
                              })];
    }
  }

  for (NSString *name in ALNSchemaTransformerNames(descriptor)) {
    if (ALNValueTransformerNamed(name) != nil) {
      continue;
    }
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(path,
                                                        @"error",
                                                        @"invalid_transformer",
                                                        [NSString
                                                            stringWithFormat:@"Unknown value transformer '%@'",
                                                                             name ?: @""],
                                                        @{ @"transformer" : name ?: @"" })];
  }

  id explicitProperties = descriptor[@"properties"];
  if (explicitProperties != nil && ![explicitProperties isKindOfClass:[NSDictionary class]]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                            path,
                            @"warning",
                            @"invalid_properties_shape",
                            @"properties should be a dictionary",
                            @{ @"properties_class" : NSStringFromClass([explicitProperties class]) ?: @"" })];
  }
  NSDictionary *properties = ALNSchemaProperties(descriptor);
  NSArray *propertyNames = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (id key in propertyNames) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *propertyPath = ALNSchemaJoinFieldPath(path, (NSString *)key);
    ALNCollectSchemaReadinessDiagnosticsForDescriptor(properties[key],
                                                      propertyPath,
                                                      diagnostics);
  }

  id items = descriptor[@"items"];
  if (items != nil &&
      ![items isKindOfClass:[NSDictionary class]] &&
      ![items isKindOfClass:[NSString class]]) {
    [diagnostics addObject:ALNSchemaReadinessDiagnostic(
                            path,
                            @"warning",
                            @"invalid_items_shape",
                            @"items should be a dictionary or type string",
                            @{ @"items_class" : NSStringFromClass([items class]) ?: @"" })];
  } else if (items != nil) {
    NSString *itemsPath = ([path length] > 0) ? [path stringByAppendingString:@"[]"] : @"[]";
    ALNCollectSchemaReadinessDiagnosticsForDescriptor(items, itemsPath, diagnostics);
  }
}

static BOOL ALNSchemaApplyDescriptorTransformers(id rawValue,
                                                 NSDictionary *descriptor,
                                                 NSString *fieldPath,
                                                 NSMutableArray *errors,
                                                 id *transformedOut) {
  NSArray *transformers = ALNSchemaTransformerNames(descriptor);
  if ([transformers count] == 0) {
    if (transformedOut != NULL) {
      *transformedOut = rawValue;
    }
    return YES;
  }

  id current = rawValue;
  for (NSString *name in transformers) {
    NSError *transformError = nil;
    id transformed = ALNApplyValueTransformerNamed(name, current, &transformError);
    if (transformError != nil) {
      NSString *code =
          (transformError.code == ALNValueTransformerErrorUnknownTransformer)
              ? @"invalid_transformer"
              : @"invalid_transform";
      NSMutableDictionary *meta = [NSMutableDictionary dictionary];
      meta[@"transformer"] = name ?: @"";
      if ([transformError.domain length] > 0) {
        meta[@"domain"] = transformError.domain;
      }
      meta[@"domain_code"] = @((NSInteger)transformError.code);
      ALNAppendSchemaErrorWithMetadata(errors,
                                       fieldPath,
                                       code,
                                       transformError.localizedDescription ?: @"invalid transform",
                                       meta);
      return NO;
    }
    current = transformed;
  }

  if (transformedOut != NULL) {
    *transformedOut = current;
  }
  return YES;
}

static BOOL ALNParseInteger(NSString *value, NSInteger *outValue) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  NSInteger parsed = 0;
  if (![scanner scanInteger:&parsed]) {
    return NO;
  }
  if (![scanner isAtEnd]) {
    return NO;
  }
  if (outValue != NULL) {
    *outValue = parsed;
  }
  return YES;
}

static BOOL ALNParseDouble(NSString *value, double *outValue) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  double parsed = 0.0;
  if (![scanner scanDouble:&parsed]) {
    return NO;
  }
  if (![scanner isAtEnd]) {
    return NO;
  }
  if (outValue != NULL) {
    *outValue = parsed;
  }
  return YES;
}

static NSNumber *ALNParseBoolean(id value) {
  if ([value isKindOfClass:[NSNumber class]]) {
    return @([value boolValue]);
  }
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *normalized = [[value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    return @(YES);
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    return @(NO);
  }
  return nil;
}

static BOOL ALNSchemaEnumContainsValue(NSArray *allowedValues, id value) {
  if (![allowedValues isKindOfClass:[NSArray class]] || [allowedValues count] == 0) {
    return YES;
  }
  for (id candidate in allowedValues) {
    if ((candidate == nil && value == nil) || [candidate isEqual:value]) {
      return YES;
    }
  }
  return NO;
}

static id ALNSchemaCoerceScalarValue(id rawValue,
                                     NSDictionary *descriptor,
                                     NSString *fieldPath,
                                     BOOL coerce,
                                     NSMutableArray *errors) {
  NSString *type = ALNSchemaType(descriptor);
  if ([type isEqualToString:@"string"]) {
    NSString *stringValue = nil;
    if ([rawValue isKindOfClass:[NSString class]]) {
      stringValue = rawValue;
    } else if (coerce && [rawValue respondsToSelector:@selector(description)]) {
      stringValue = [rawValue description];
    }
    if ([stringValue length] == 0 && ![rawValue isKindOfClass:[NSString class]]) {
      ALNAppendSchemaError(errors, fieldPath, @"invalid_type", @"must be a string");
      return nil;
    }

    id minLength = descriptor[@"minLength"];
    if ([minLength respondsToSelector:@selector(integerValue)] &&
        [stringValue length] < [minLength integerValue]) {
      ALNAppendSchemaError(errors, fieldPath, @"too_short", @"is shorter than minLength");
      return nil;
    }
    id maxLength = descriptor[@"maxLength"];
    if ([maxLength respondsToSelector:@selector(integerValue)] &&
        [stringValue length] > [maxLength integerValue]) {
      ALNAppendSchemaError(errors, fieldPath, @"too_long", @"is longer than maxLength");
      return nil;
    }
    return stringValue ?: @"";
  }

  if ([type isEqualToString:@"integer"]) {
    NSInteger parsed = 0;
    if ([rawValue isKindOfClass:[NSNumber class]]) {
      parsed = [rawValue integerValue];
    } else if (coerce && [rawValue isKindOfClass:[NSString class]] &&
               ALNParseInteger(rawValue, &parsed)) {
      // parsed from string
    } else {
      ALNAppendSchemaError(errors, fieldPath, @"invalid_type", @"must be an integer");
      return nil;
    }
    id minimum = descriptor[@"minimum"];
    if ([minimum respondsToSelector:@selector(doubleValue)] &&
        (double)parsed < [minimum doubleValue]) {
      ALNAppendSchemaError(errors, fieldPath, @"too_small", @"is lower than minimum");
      return nil;
    }
    id maximum = descriptor[@"maximum"];
    if ([maximum respondsToSelector:@selector(doubleValue)] &&
        (double)parsed > [maximum doubleValue]) {
      ALNAppendSchemaError(errors, fieldPath, @"too_large", @"is greater than maximum");
      return nil;
    }
    return @(parsed);
  }

  if ([type isEqualToString:@"number"]) {
    double parsed = 0.0;
    if ([rawValue isKindOfClass:[NSNumber class]]) {
      parsed = [rawValue doubleValue];
    } else if (coerce && [rawValue isKindOfClass:[NSString class]] &&
               ALNParseDouble(rawValue, &parsed)) {
      // parsed
    } else {
      ALNAppendSchemaError(errors, fieldPath, @"invalid_type", @"must be a number");
      return nil;
    }
    id minimum = descriptor[@"minimum"];
    if ([minimum respondsToSelector:@selector(doubleValue)] &&
        parsed < [minimum doubleValue]) {
      ALNAppendSchemaError(errors, fieldPath, @"too_small", @"is lower than minimum");
      return nil;
    }
    id maximum = descriptor[@"maximum"];
    if ([maximum respondsToSelector:@selector(doubleValue)] &&
        parsed > [maximum doubleValue]) {
      ALNAppendSchemaError(errors, fieldPath, @"too_large", @"is greater than maximum");
      return nil;
    }
    return @(parsed);
  }

  if ([type isEqualToString:@"boolean"]) {
    NSNumber *parsed = coerce ? ALNParseBoolean(rawValue) : ([rawValue isKindOfClass:[NSNumber class]] ? @([rawValue boolValue]) : nil);
    if (parsed == nil) {
      ALNAppendSchemaError(errors, fieldPath, @"invalid_type", @"must be a boolean");
      return nil;
    }
    return parsed;
  }

  if ([type isEqualToString:@"object"]) {
    if (![rawValue isKindOfClass:[NSDictionary class]]) {
      ALNAppendSchemaError(errors, fieldPath, @"invalid_type", @"must be an object");
      return nil;
    }
    return rawValue;
  }

  if ([type isEqualToString:@"array"]) {
    if (![rawValue isKindOfClass:[NSArray class]]) {
      ALNAppendSchemaError(errors, fieldPath, @"invalid_type", @"must be an array");
      return nil;
    }
    return rawValue;
  }

  ALNAppendSchemaError(errors, fieldPath, @"unsupported_type", @"unsupported schema type");
  return nil;
}

static BOOL ALNSchemaValidateValueRecursive(id value,
                                            NSDictionary *descriptor,
                                            NSString *fieldPath,
                                            BOOL coerce,
                                            NSMutableArray *errors,
                                            id *coercedOut) {
  if (descriptor == nil) {
    if (coercedOut != NULL) {
      *coercedOut = value;
    }
    return YES;
  }

  BOOL coerceValue = coerce;
  if ([descriptor[@"coerce"] respondsToSelector:@selector(boolValue)]) {
    coerceValue = [descriptor[@"coerce"] boolValue];
  }

  id transformedValue = value;
  if (!ALNSchemaApplyDescriptorTransformers(value,
                                            descriptor,
                                            fieldPath,
                                            errors,
                                            &transformedValue)) {
    return NO;
  }

  id coercedScalar =
      ALNSchemaCoerceScalarValue(transformedValue, descriptor, fieldPath, coerceValue, errors);
  if (coercedScalar == nil) {
    return NO;
  }

  NSString *type = ALNSchemaType(descriptor);
  if ([type isEqualToString:@"object"]) {
    NSDictionary *properties = ALNSchemaProperties(descriptor);
    NSSet *required = ALNSchemaRequiredSet(descriptor, properties);
    NSMutableDictionary *coercedObject = [NSMutableDictionary dictionary];
    NSDictionary *dictValue = [coercedScalar isKindOfClass:[NSDictionary class]] ? coercedScalar : @{};

    NSArray *propertyNames = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *propertyName in propertyNames) {
      NSDictionary *propertyDescriptor = ALNSchemaDescriptorFromValue(properties[propertyName]);
      id rawProperty = dictValue[propertyName];
      NSString *propertyPath = [NSString stringWithFormat:@"%@.%@", fieldPath ?: @"value", propertyName];
      if (rawProperty == nil || rawProperty == [NSNull null]) {
        if ([required containsObject:propertyName]) {
          ALNAppendSchemaError(errors, propertyPath, @"missing", @"is required");
        }
        continue;
      }

      id coercedProperty = nil;
      BOOL valid = ALNSchemaValidateValueRecursive(rawProperty,
                                                   propertyDescriptor,
                                                   propertyPath,
                                                   coerce,
                                                   errors,
                                                   &coercedProperty);
      if (!valid) {
        continue;
      }
      if (coercedProperty != nil) {
        coercedObject[propertyName] = coercedProperty;
      }
    }
    if (coercedOut != NULL) {
      *coercedOut = coercedObject;
    }
  } else if ([type isEqualToString:@"array"]) {
    NSArray *arrayValue = [coercedScalar isKindOfClass:[NSArray class]] ? coercedScalar : @[];
    NSDictionary *itemDescriptor = ALNSchemaDescriptorFromValue(descriptor[@"items"]);
    NSMutableArray *coercedArray = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < [arrayValue count]; idx++) {
      id itemValue = arrayValue[idx];
      id coercedItem = nil;
      NSString *itemPath = [NSString stringWithFormat:@"%@[%lu]", fieldPath ?: @"value", (unsigned long)idx];
      BOOL valid = ALNSchemaValidateValueRecursive(itemValue,
                                                   itemDescriptor,
                                                   itemPath,
                                                   coerce,
                                                   errors,
                                                   &coercedItem);
      if (!valid) {
        continue;
      }
      [coercedArray addObject:coercedItem ?: [NSNull null]];
    }
    if (coercedOut != NULL) {
      *coercedOut = coercedArray;
    }
  } else if (coercedOut != NULL) {
    *coercedOut = coercedScalar;
  }

  if (!ALNSchemaEnumContainsValue(descriptor[@"enum"], (coercedOut != NULL) ? *coercedOut : coercedScalar)) {
    ALNAppendSchemaError(errors, fieldPath, @"invalid_enum", @"must be one of the allowed values");
    return NO;
  }
  return YES;
}

static NSString *ALNSchemaSource(NSDictionary *descriptor) {
  NSString *source = [descriptor[@"source"] isKindOfClass:[NSString class]]
                         ? [descriptor[@"source"] lowercaseString]
                         : @"";
  if ([source length] == 0) {
    return @"param";
  }
  return source;
}

NSArray *ALNSchemaReadinessDiagnostics(NSDictionary *schema) {
  if (![schema isKindOfClass:[NSDictionary class]] || [schema count] == 0) {
    return @[];
  }

  NSMutableArray *diagnostics = [NSMutableArray array];
  ALNCollectSchemaReadinessDiagnosticsForDescriptor(schema, @"", diagnostics);
  return [NSArray arrayWithArray:diagnostics];
}

NSDictionary *ALNSchemaCoerceRequestValues(NSDictionary *schema,
                                          ALNRequest *request,
                                          NSDictionary *routeParams,
                                          NSArray **errors) {
  if (![schema isKindOfClass:[NSDictionary class]] || [schema count] == 0) {
    if (errors != NULL) {
      *errors = @[];
    }
    return @{};
  }

  NSDictionary *properties = ALNSchemaProperties(schema);
  NSSet *required = ALNSchemaRequiredSet(schema, properties);
  NSMutableDictionary *coercedValues = [NSMutableDictionary dictionary];
  NSMutableArray *validationErrors = [NSMutableArray array];

  BOOL needsBodyObject = NO;
  for (NSString *field in properties) {
    NSDictionary *descriptor = ALNSchemaDescriptorFromValue(properties[field]);
    if ([[ALNSchemaSource(descriptor) lowercaseString] isEqualToString:@"body"]) {
      needsBodyObject = YES;
      break;
    }
  }

  NSDictionary *bodyObject = nil;
  if (needsBodyObject && [request.body length] > 0) {
    NSError *bodyError = nil;
    id parsedBody = [NSJSONSerialization JSONObjectWithData:request.body
                                                    options:0
                                                      error:&bodyError];
    if (bodyError != nil || ![parsedBody isKindOfClass:[NSDictionary class]]) {
      ALNAppendSchemaError(validationErrors, @"body", @"invalid_json", @"must be a JSON object");
    } else {
      bodyObject = parsedBody;
    }
  }

  NSArray *fields = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *field in fields) {
    NSDictionary *descriptor = ALNSchemaDescriptorFromValue(properties[field]);
    NSString *source = ALNSchemaSource(descriptor);
    id rawValue = nil;
    if ([source isEqualToString:@"path"] || [source isEqualToString:@"route"] ||
        [source isEqualToString:@"param"]) {
      rawValue = routeParams[field];
      if (rawValue == nil && [source isEqualToString:@"param"]) {
        rawValue = request.queryParams[field];
      }
      if (rawValue == nil && ![source isEqualToString:@"param"]) {
        rawValue = request.queryParams[field];
      }
    } else if ([source isEqualToString:@"query"]) {
      rawValue = request.queryParams[field];
    } else if ([source isEqualToString:@"header"]) {
      rawValue = request.headers[[field lowercaseString]];
    } else if ([source isEqualToString:@"body"]) {
      rawValue = bodyObject[field];
    } else {
      rawValue = routeParams[field] ?: request.queryParams[field];
    }

    if ((rawValue == nil || rawValue == [NSNull null]) && descriptor[@"default"] != nil) {
      rawValue = descriptor[@"default"];
    }

    if (rawValue == nil || rawValue == [NSNull null]) {
      if ([required containsObject:field]) {
        ALNAppendSchemaError(validationErrors, field, @"missing", @"is required");
      }
      continue;
    }

    id coercedValue = nil;
    BOOL valid = ALNSchemaValidateValueRecursive(rawValue,
                                                 descriptor,
                                                 field,
                                                 YES,
                                                 validationErrors,
                                                 &coercedValue);
    if (!valid) {
      continue;
    }
    if (coercedValue != nil) {
      coercedValues[field] = coercedValue;
    }
  }

  if (errors != NULL) {
    *errors = [NSArray arrayWithArray:validationErrors];
  }
  if ([validationErrors count] > 0) {
    return nil;
  }
  return [NSDictionary dictionaryWithDictionary:coercedValues];
}

BOOL ALNSchemaValidateResponseValue(id value, NSDictionary *schema, NSArray **errors) {
  if (![schema isKindOfClass:[NSDictionary class]] || [schema count] == 0) {
    if (errors != NULL) {
      *errors = @[];
    }
    return YES;
  }

  NSMutableArray *validationErrors = [NSMutableArray array];
  NSDictionary *descriptor = schema;
  if (schema[@"properties"] == nil && schema[@"type"] == nil) {
    descriptor = @{
      @"type" : @"object",
      @"properties" : schema,
    };
  }

  id coercedValue = nil;
  BOOL valid = ALNSchemaValidateValueRecursive(value,
                                               descriptor,
                                               @"response",
                                               NO,
                                               validationErrors,
                                               &coercedValue);
  if (errors != NULL) {
    *errors = [NSArray arrayWithArray:validationErrors];
  }
  return valid && [validationErrors count] == 0;
}
