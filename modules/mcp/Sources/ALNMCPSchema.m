#import "ALNMCPSchema.h"
#import <math.h>

BOOL ALNMCPFail(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"Arlen.MCP" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
  return NO;
}
static BOOL MCPIsBoolean(id value) {
  return [value isKindOfClass:[NSNumber class]] &&
      (strcmp([value objCType], @encode(BOOL)) == 0);
}
static NSDictionary *Normalize(id raw, BOOL route, NSUInteger depth, NSError **error) {
  if (depth > 32) { ALNMCPFail(error, @"MCP schema exceeds depth 32"); return nil; }
  if (route && [raw isKindOfClass:[NSString class]]) raw = @{ @"type": raw };
  if (![raw isKindOfClass:[NSDictionary class]]) {
    ALNMCPFail(error, @"MCP schema must be an object"); return nil;
  }
  NSMutableDictionary *schema = [raw mutableCopy];
  if (route) {
    [schema removeObjectForKey:@"source"];
    if (depth > 0 && MCPIsBoolean(schema[@"required"])) [schema removeObjectForKey:@"required"];
  }
  NSSet *allowed = [NSSet setWithArray:@[@"type", @"properties", @"required", @"additionalProperties",
      @"items", @"enum", @"description", @"title", @"minimum", @"maximum", @"minLength", @"maxLength",
      @"minItems", @"maxItems"]];
  for (id key in schema) {
    if (![allowed containsObject:key]) {
      ALNMCPFail(error, [NSString stringWithFormat:@"Unsupported MCP schema keyword: %@ (provide an explicit supported schema)", key]); return nil;
    }
  }
  NSString *type = schema[@"type"];
  if (route && !type && schema[@"properties"]) schema[@"type"] = type = @"object";
  if (![@[@"object", @"array", @"string", @"integer", @"number", @"boolean", @"null"] containsObject:type ?: @""]) {
    ALNMCPFail(error, @"MCP schema requires one supported type; unions/nullable/$ref are unsupported"); return nil;
  }
  for (NSString *key in @[@"description", @"title"]) {
    if (schema[key] && ![schema[key] isKindOfClass:[NSString class]]) {
      ALNMCPFail(error, @"Schema title/description must be strings"); return nil;
    }
  }
  for (NSString *key in @[@"minimum", @"maximum", @"minLength", @"maxLength", @"minItems", @"maxItems"]) {
    id bound = schema[key];
    if (!bound) continue;
    BOOL count = ![@[@"minimum", @"maximum"] containsObject:key];
    BOOL applicable = count ? ([key hasSuffix:@"Length"] ? [type isEqual:@"string"] : [type isEqual:@"array"])
                            : [@[@"integer", @"number"] containsObject:type];
    if (!applicable || ![bound isKindOfClass:[NSNumber class]] || MCPIsBoolean(bound) ||
        !isfinite([bound doubleValue]) || (count && ([bound doubleValue] < 0 || floor([bound doubleValue]) != [bound doubleValue]))) {
      ALNMCPFail(error, @"Invalid or inapplicable schema bound"); return nil;
    }
  }
  for (NSArray *pair in @[@[@"minimum", @"maximum"], @[@"minLength", @"maxLength"], @[@"minItems", @"maxItems"]]) {
    if (schema[pair[0]] && schema[pair[1]] && [schema[pair[0]] doubleValue] > [schema[pair[1]] doubleValue]) {
      ALNMCPFail(error, @"Schema minimum exceeds maximum"); return nil;
    }
  }
  if ([type isEqual:@"object"]) {
    id props = schema[@"properties"] ?: @{};
    if (![props isKindOfClass:[NSDictionary class]] || (schema[@"additionalProperties"] && !MCPIsBoolean(schema[@"additionalProperties"]))) {
      ALNMCPFail(error, @"properties must be an object; additionalProperties must be boolean"); return nil;
    }
    id req = schema[@"required"] ?: @[];
    if (![req isKindOfClass:[NSArray class]]) { ALNMCPFail(error, @"required must be an array"); return nil; }
    NSMutableArray *required = [req mutableCopy];
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    for (id key in props) {
      if (![key isKindOfClass:[NSString class]]) { ALNMCPFail(error, @"Invalid property name"); return nil; }
      id descriptor = props[key];
      if (route && [descriptor isKindOfClass:[NSDictionary class]] && MCPIsBoolean(descriptor[@"required"]) && [descriptor[@"required"] boolValue] && ![required containsObject:key]) [required addObject:key];
      NSDictionary *child = Normalize(descriptor, route, depth + 1, error);
      if (!child) return nil;
      properties[key] = child;
    }
    for (id key in required) {
      if (![key isKindOfClass:[NSString class]] || !properties[key]) { ALNMCPFail(error, @"required names must exist in properties"); return nil; }
    }
    if ([NSSet setWithArray:required].count != required.count) { ALNMCPFail(error, @"Duplicate required property"); return nil; }
    schema[@"properties"] = properties;
    schema[@"required"] = [required sortedArrayUsingSelector:@selector(compare:)];
    // Closing the object is deliberate and published, never silently discard arguments.
    schema[@"additionalProperties"] = schema[@"additionalProperties"] ?: @NO;
  } else if (schema[@"properties"] || schema[@"required"] || schema[@"additionalProperties"]) {
    ALNMCPFail(error, @"Object keywords on non-object schema"); return nil;
  }
  if ([type isEqual:@"array"]) {
    NSDictionary *items = Normalize(schema[@"items"], route, depth + 1, error);
    if (!items) return nil;
    schema[@"items"] = items;
  } else if (schema[@"items"]) { ALNMCPFail(error, @"items on non-array schema"); return nil; }
  if (schema[@"enum"]) {
    id values = schema[@"enum"];
    if (![values isKindOfClass:[NSArray class]] || ![values count]) { ALNMCPFail(error, @"enum must be nonempty array"); return nil; }
    NSMutableDictionary *withoutEnum = [schema mutableCopy];
    [withoutEnum removeObjectForKey:@"enum"];
    for (id value in values) if (!ALNMCPValidate(value, withoutEnum)) { ALNMCPFail(error, @"enum value violates schema"); return nil; }
  }
  return schema;
}
NSDictionary *ALNMCPSchema(id schema, BOOL route, NSError **error) {
  NSDictionary *result = Normalize(schema, route, 0, error);
  if (result && ![result[@"type"] isEqual:@"object"]) { ALNMCPFail(error, @"MCP root schema must be an object"); return nil; }
  return result;
}
BOOL ALNMCPValidate(id value, NSDictionary *schema) {
  NSString *type = schema[@"type"];
  if (schema[@"enum"] && ![schema[@"enum"] containsObject:value ?: [NSNull null]]) return NO;
  if ([type isEqual:@"object"]) {
    if (![value isKindOfClass:[NSDictionary class]]) return NO;
    for (NSString *key in schema[@"required"]) if (!value[key]) return NO;
    for (NSString *key in value) {
      NSDictionary *child = schema[@"properties"][key];
      if (child ? !ALNMCPValidate(value[key], child) : ![schema[@"additionalProperties"] boolValue]) return NO;
    }
  } else if ([type isEqual:@"array"]) {
    if (![value isKindOfClass:[NSArray class]]) return NO;
    if (schema[@"minItems"] && [value count] < [schema[@"minItems"] unsignedIntegerValue]) return NO;
    if (schema[@"maxItems"] && [value count] > [schema[@"maxItems"] unsignedIntegerValue]) return NO;
    for (id item in value) if (!ALNMCPValidate(item, schema[@"items"])) return NO;
  } else if ([type isEqual:@"string"]) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSUInteger length = [value lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding] / 4;
    if (schema[@"minLength"] && length < [schema[@"minLength"] unsignedIntegerValue]) return NO;
    if (schema[@"maxLength"] && length > [schema[@"maxLength"] unsignedIntegerValue]) return NO;
  } else if ([type isEqual:@"boolean"]) {
    if (!MCPIsBoolean(value)) return NO;
  } else if ([type isEqual:@"null"]) {
    if (value != [NSNull null]) return NO;
  } else {
    if (![value isKindOfClass:[NSNumber class]] || MCPIsBoolean(value)) return NO;
    double number = [value doubleValue];
    if (!isfinite(number) || ([type isEqual:@"integer"] && floor(number) != number)) return NO;
    if (schema[@"minimum"] && number < [schema[@"minimum"] doubleValue]) return NO;
    if (schema[@"maximum"] && number > [schema[@"maximum"] doubleValue]) return NO;
  }
  return YES;
}
