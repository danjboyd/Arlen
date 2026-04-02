#import "ALNDataverseCodegen.h"

#import <ctype.h>

#import "ALNJSONSerialization.h"

NSString *const ALNDataverseCodegenErrorDomain = @"Arlen.Data.Dataverse.Codegen.Error";

static NSString *ALNDataverseCodegenTrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNDataverseCodegenIdentifierIsSafe(NSString *value) {
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

static BOOL ALNDataverseCodegenTargetIsSafe(NSString *value) {
  NSString *target = ALNDataverseCodegenTrimmedString(value);
  if ([target length] == 0) {
    return YES;
  }
  if ([target length] > 32) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([[target stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [target characterAtIndex:0];
  return (first >= 'a' && first <= 'z');
}

static NSString *ALNDataverseCodegenJSONEscape(NSString *value) {
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
  return escaped;
}

static NSString *ALNDataverseCodegenPascalSuffix(NSString *identifier) {
  NSString *input = ALNDataverseCodegenTrimmedString(identifier);
  NSMutableString *buffer = [NSMutableString string];
  BOOL uppercaseNext = YES;
  for (NSUInteger idx = 0; idx < [input length]; idx++) {
    unichar ch = [input characterAtIndex:idx];
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
      NSString *character = [[NSString stringWithFormat:@"%C", ch] lowercaseString];
      if (uppercaseNext) {
        [buffer appendString:[character uppercaseString]];
      } else {
        [buffer appendString:character];
      }
      uppercaseNext = NO;
    } else {
      uppercaseNext = YES;
    }
  }
  if ([buffer length] == 0) {
    [buffer appendString:@"Value"];
  }
  unichar first = [buffer characterAtIndex:0];
  if (![[NSCharacterSet letterCharacterSet] characterIsMember:first] && first != '_') {
    [buffer insertString:@"N" atIndex:0];
  }
  return buffer;
}

static NSString *ALNDataverseCodegenNavigationMethodName(NSString *identifier) {
  return [NSString stringWithFormat:@"navigation%@",
                                    ALNDataverseCodegenPascalSuffix(identifier)];
}

static NSString *ALNDataverseCodegenFieldMethodNameForAttribute(NSDictionary<NSString *, id> *attribute) {
  NSString *attributeName = ALNDataverseCodegenTrimmedString(attribute[@"logical_name"]);
  NSString *methodSuffix = ALNDataverseCodegenPascalSuffix(attributeName);
  BOOL selectable = YES;
  if (attribute[@"odata_selectable"] != nil && attribute[@"odata_selectable"] != [NSNull null]) {
    selectable = [attribute[@"odata_selectable"] boolValue];
  }
  return [NSString stringWithFormat:@"%@%@",
                                     selectable ? @"field" : @"nonSelectableField",
                                     methodSuffix];
}

static NSString *ALNDataverseCodegenEnumCaseName(NSString *label, NSInteger fallbackValue) {
  NSString *suffix = ALNDataverseCodegenPascalSuffix(label);
  if ([suffix isEqualToString:@"Value"]) {
    suffix = [NSString stringWithFormat:@"Value%ld", (long)fallbackValue];
  }
  return suffix;
}

NSError *ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorCode code,
                                      NSString *message,
                                      NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"Dataverse codegen error";
  return [NSError errorWithDomain:ALNDataverseCodegenErrorDomain code:code userInfo:details];
}

@implementation ALNDataverseCodegen

+ (NSDictionary<NSString *, id> *)renderArtifactsFromMetadata:(NSDictionary<NSString *, id> *)metadata
                                                  classPrefix:(NSString *)classPrefix
                                              dataverseTarget:(NSString *)dataverseTarget
                                                        error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *prefix = ALNDataverseCodegenTrimmedString(classPrefix);
  NSString *target = [[ALNDataverseCodegenTrimmedString(dataverseTarget) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray<NSDictionary<NSString *, id> *> *entities =
      [metadata[@"entities"] isKindOfClass:[NSArray class]] ? metadata[@"entities"] : nil;
  if (!ALNDataverseCodegenIdentifierIsSafe(prefix) || [entities count] == 0 || !ALNDataverseCodegenTargetIsSafe(target)) {
    if (error != NULL) {
      *error = ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorInvalidArgument,
                                            @"Dataverse codegen requires a safe class prefix, safe target, and non-empty metadata",
                                            nil);
    }
    return nil;
  }

  NSString *baseName = [NSString stringWithFormat:@"%@DataverseSchema", prefix];
  NSString *guardName = [[baseName uppercaseString] stringByAppendingString:@"_H"];
  NSMutableString *header = [NSMutableString string];
  NSMutableString *implementation = [NSMutableString string];
  NSMutableArray<NSDictionary<NSString *, id> *> *manifestEntities = [NSMutableArray arrayWithCapacity:[entities count]];
  NSMutableSet<NSString *> *classNames = [NSMutableSet set];

  [header appendFormat:@"#ifndef %@\n", guardName];
  [header appendFormat:@"#define %@\n\n", guardName];
  [header appendString:@"#import <Foundation/Foundation.h>\n\n"];
  [header appendString:@"NS_ASSUME_NONNULL_BEGIN\n\n"];

  [implementation appendFormat:@"#import \"%@.h\"\n\n", baseName];

  NSUInteger attributeCount = 0;
  for (NSDictionary<NSString *, id> *entity in entities) {
    NSString *logicalName = ALNDataverseCodegenTrimmedString(entity[@"logical_name"]);
    NSString *entitySetName = ALNDataverseCodegenTrimmedString(entity[@"entity_set_name"]);
    NSString *primaryID = ALNDataverseCodegenTrimmedString(entity[@"primary_id_attribute"]);
    NSString *primaryName = ALNDataverseCodegenTrimmedString(entity[@"primary_name_attribute"]);
    NSArray<NSDictionary<NSString *, id> *> *attributes =
        [entity[@"attributes"] isKindOfClass:[NSArray class]] ? entity[@"attributes"] : @[];
    NSArray<NSDictionary<NSString *, id> *> *lookups =
        [entity[@"lookups"] isKindOfClass:[NSArray class]] ? entity[@"lookups"] : @[];
    NSArray<NSDictionary<NSString *, id> *> *keys =
        [entity[@"keys"] isKindOfClass:[NSArray class]] ? entity[@"keys"] : @[];

    if ([logicalName length] == 0 || [entitySetName length] == 0) {
      if (error != NULL) {
        *error = ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorInvalidMetadata,
                                              @"Dataverse metadata entity is missing logical or entity set names",
                                              @{ @"entity" : entity ?: @{} });
      }
      return nil;
    }

    NSString *className = [NSString stringWithFormat:@"%@%@", prefix, ALNDataverseCodegenPascalSuffix(logicalName)];
    if ([classNames containsObject:className]) {
      if (error != NULL) {
        *error = ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorIdentifierCollision,
                                              @"Dataverse codegen generated duplicate class names",
                                              @{ @"class_name" : className ?: @"" });
      }
      return nil;
    }
    [classNames addObject:className];

    [header appendFormat:@"@interface %@ : NSObject\n", className];
    [header appendString:@"+ (NSString *)logicalName;\n"];
    [header appendString:@"+ (NSString *)entitySetName;\n"];
    [header appendString:@"+ (NSString *)primaryIDAttribute;\n"];
    [header appendString:@"+ (NSString *)primaryNameAttribute;\n"];
    [header appendString:@"+ (NSArray<NSArray<NSString *> *> *)alternateKeys;\n"];
    [header appendString:@"+ (NSDictionary<NSString *, NSString *> *)lookupNavigationMap;\n"];
    [header appendString:@"+ (NSDictionary<NSString *, NSArray<NSString *> *> *)lookupNavigationTargetsMap;\n"];
    [header appendString:@"+ (NSArray<NSString *> *)selectableFields;\n"];
    [header appendString:@"+ (NSArray<NSString *> *)nonSelectableFields;\n"];

    NSMutableArray<NSDictionary<NSString *, id> *> *manifestAttributes = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *manifestChoices = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *manifestLookups = [NSMutableArray array];
    NSMutableSet<NSString *> *methodNames = [NSMutableSet set];
    NSMutableArray<NSDictionary<NSString *, id> *> *normalizedLookups = [NSMutableArray array];
    NSMutableSet<NSString *> *seenLookupPairs = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *lookupGroups =
        [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *lookupAttributeOrder = [NSMutableArray array];
    NSMutableArray<NSString *> *selectableAttributeExpressions = [NSMutableArray array];
    NSMutableArray<NSString *> *nonSelectableAttributeExpressions = [NSMutableArray array];
    attributeCount += [attributes count];
    for (NSDictionary<NSString *, id> *attribute in attributes) {
      NSString *attributeName = ALNDataverseCodegenTrimmedString(attribute[@"logical_name"]);
      if ([attributeName length] == 0) {
        continue;
      }
      BOOL selectable = YES;
      if (attribute[@"odata_selectable"] != nil && attribute[@"odata_selectable"] != [NSNull null]) {
        selectable = [attribute[@"odata_selectable"] boolValue];
      }
      NSString *attributeOf = ALNDataverseCodegenTrimmedString(attribute[@"attribute_of"]);
      NSString *methodSuffix = ALNDataverseCodegenPascalSuffix(attributeName);
      NSString *fieldMethod = ALNDataverseCodegenFieldMethodNameForAttribute(attribute);
      if ([methodNames containsObject:fieldMethod]) {
        if (error != NULL) {
          *error = ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorIdentifierCollision,
                                                @"Dataverse codegen generated duplicate field method names",
                                                @{
                                                  @"class_name" : className ?: @"",
                                                  @"method_name" : fieldMethod ?: @"",
                                                });
        }
        return nil;
      }
      [methodNames addObject:fieldMethod];
      [header appendFormat:@"+ (NSString *)%@;\n", fieldMethod];
      NSMutableDictionary<NSString *, id> *manifestAttribute = [NSMutableDictionary dictionary];
      manifestAttribute[@"logical_name"] = attributeName;
      manifestAttribute[@"method_name"] = fieldMethod;
      manifestAttribute[@"type"] = ALNDataverseCodegenTrimmedString(attribute[@"type"]) ?: @"";
      manifestAttribute[@"selectable"] = @(selectable);
      manifestAttribute[@"attribute_of"] = attributeOf ?: @"";
      [manifestAttributes addObject:manifestAttribute];
      if (selectable) {
        [selectableAttributeExpressions addObject:[NSString stringWithFormat:@"@\"%@\"",
                                                                             ALNDataverseCodegenJSONEscape(attributeName)]];
      } else {
        [nonSelectableAttributeExpressions addObject:[NSString stringWithFormat:@"@\"%@\"",
                                                                                ALNDataverseCodegenJSONEscape(attributeName)]];
      }

      NSArray<NSDictionary<NSString *, id> *> *choices =
          [attribute[@"choices"] isKindOfClass:[NSArray class]] ? attribute[@"choices"] : @[];
      if ([choices count] > 0) {
        NSString *enumName = [NSString stringWithFormat:@"%@%@Choice", className, methodSuffix];
        [header appendFormat:@"typedef NS_ENUM(NSInteger, %@) {\n", enumName];
        NSMutableSet<NSString *> *enumCases = [NSMutableSet set];
        NSMutableArray<NSDictionary<NSString *, id> *> *choiceEntries = [NSMutableArray array];
        for (NSDictionary<NSString *, id> *choice in choices) {
          NSInteger value = [choice[@"value"] integerValue];
          NSString *caseName = [NSString stringWithFormat:@"%@%@", enumName,
                                                          ALNDataverseCodegenEnumCaseName(choice[@"label"], value)];
          if ([enumCases containsObject:caseName]) {
            caseName = [NSString stringWithFormat:@"%@Value%ld", enumName, (long)value];
          }
          [enumCases addObject:caseName];
          [header appendFormat:@"  %@ = %ld,\n", caseName, (long)value];
          [choiceEntries addObject:@{
            @"name" : caseName,
            @"value" : @(value),
            @"label" : ALNDataverseCodegenTrimmedString(choice[@"label"]) ?: @"",
          }];
        }
        [header appendString:@"};\n"];
        NSString *choiceMethod = [NSString stringWithFormat:@"%@Choices", fieldMethod];
        [header appendFormat:@"+ (NSDictionary<NSNumber *, NSString *> *)%@;\n", choiceMethod];
        [manifestChoices addObject:@{
          @"attribute" : attributeName,
          @"enum_name" : enumName,
          @"method_name" : choiceMethod,
          @"options" : choiceEntries,
        }];
      }
    }

    for (NSDictionary<NSString *, id> *lookup in lookups) {
      NSString *attributeName = ALNDataverseCodegenTrimmedString(lookup[@"referencing_attribute"]);
      NSString *navigationName = ALNDataverseCodegenTrimmedString(lookup[@"navigation_property_name"]);
      if ([attributeName length] == 0 || [navigationName length] == 0) {
        continue;
      }

      NSString *pairKey = [NSString stringWithFormat:@"%@\n%@", attributeName, navigationName];
      if ([seenLookupPairs containsObject:pairKey]) {
        continue;
      }
      [seenLookupPairs addObject:pairKey];

      NSDictionary<NSString *, id> *normalizedLookup = @{
        @"schema_name" : ALNDataverseCodegenTrimmedString(lookup[@"schema_name"]) ?: @"",
        @"referencing_attribute" : attributeName,
        @"navigation_property_name" : navigationName,
        @"referenced_entity" : ALNDataverseCodegenTrimmedString(lookup[@"referenced_entity"]) ?: @"",
        @"referenced_attribute" : ALNDataverseCodegenTrimmedString(lookup[@"referenced_attribute"]) ?: @"",
      };
      [normalizedLookups addObject:normalizedLookup];

      if (lookupGroups[attributeName] == nil) {
        lookupGroups[attributeName] = [NSMutableArray array];
        [lookupAttributeOrder addObject:attributeName];
      }
      [lookupGroups[attributeName] addObject:normalizedLookup];
    }

    for (NSString *attributeName in lookupAttributeOrder) {
      NSArray<NSDictionary<NSString *, id> *> *lookupEntries = lookupGroups[attributeName] ?: @[];
      if ([lookupEntries count] == 0) {
        continue;
      }

      BOOL polymorphic = ([lookupEntries count] > 1);
      NSMutableArray<NSString *> *navigationTargets = [NSMutableArray arrayWithCapacity:[lookupEntries count]];
      NSMutableArray<NSString *> *methodNamesForLookup = [NSMutableArray arrayWithCapacity:[lookupEntries count]];
      NSMutableArray<NSString *> *referencedEntities = [NSMutableArray array];
      for (NSDictionary<NSString *, id> *lookup in lookupEntries) {
        NSString *navigationName = ALNDataverseCodegenTrimmedString(lookup[@"navigation_property_name"]);
        NSString *referencedEntity = ALNDataverseCodegenTrimmedString(lookup[@"referenced_entity"]);
        NSString *methodName = polymorphic ? ALNDataverseCodegenNavigationMethodName(navigationName)
                                           : ALNDataverseCodegenNavigationMethodName(attributeName);
        if ([methodNames containsObject:methodName]) {
          if (error != NULL) {
            *error = ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorIdentifierCollision,
                                                  @"Dataverse codegen generated duplicate lookup helper method names",
                                                  @{
                                                    @"class_name" : className ?: @"",
                                                    @"method_name" : methodName ?: @"",
                                                    @"attribute" : attributeName ?: @"",
                                                    @"navigation_property_name" : navigationName ?: @"",
                                                  });
          }
          return nil;
        }
        [methodNames addObject:methodName];
        [methodNamesForLookup addObject:methodName];
        [navigationTargets addObject:navigationName];
        if ([referencedEntity length] > 0) {
          [referencedEntities addObject:referencedEntity];
        }
        [header appendFormat:@"+ (NSString *)%@;\n", methodName];
      }

      NSMutableDictionary<NSString *, id> *manifestLookup = [NSMutableDictionary dictionary];
      manifestLookup[@"attribute"] = attributeName ?: @"";
      manifestLookup[@"polymorphic"] = @(polymorphic);
      manifestLookup[@"lookup_map_included"] = @(!polymorphic);
      manifestLookup[@"navigation_targets"] = [NSArray arrayWithArray:navigationTargets];
      manifestLookup[@"method_names"] = [NSArray arrayWithArray:methodNamesForLookup];
      if ([referencedEntities count] > 0) {
        manifestLookup[@"referenced_entities"] = [NSArray arrayWithArray:referencedEntities];
      }
      [manifestLookups addObject:manifestLookup];
    }
    [header appendString:@"@end\n\n"];

    [implementation appendFormat:@"@implementation %@\n\n", className];
    [implementation appendFormat:@"+ (NSString *)logicalName { return @\"%@\"; }\n",
                                 ALNDataverseCodegenJSONEscape(logicalName)];
    [implementation appendFormat:@"+ (NSString *)entitySetName { return @\"%@\"; }\n",
                                 ALNDataverseCodegenJSONEscape(entitySetName)];
    [implementation appendFormat:@"+ (NSString *)primaryIDAttribute { return @\"%@\"; }\n",
                                 ALNDataverseCodegenJSONEscape(primaryID)];
    [implementation appendFormat:@"+ (NSString *)primaryNameAttribute { return @\"%@\"; }\n",
                                 ALNDataverseCodegenJSONEscape(primaryName)];

    NSMutableArray<NSString *> *alternateKeyExpressions = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *key in keys) {
      NSArray<NSString *> *keyAttributes = [key[@"key_attributes"] isKindOfClass:[NSArray class]] ? key[@"key_attributes"] : @[];
      NSMutableArray<NSString *> *quoted = [NSMutableArray array];
      for (NSString *attributeName in keyAttributes) {
        [quoted addObject:[NSString stringWithFormat:@"@\"%@\"", ALNDataverseCodegenJSONEscape(attributeName)]];
      }
      [alternateKeyExpressions addObject:[NSString stringWithFormat:@"@[ %@ ]", [quoted componentsJoinedByString:@", "]]];
    }
    [implementation appendFormat:@"+ (NSArray<NSArray<NSString *> *> *)alternateKeys { return @[ %@ ]; }\n",
                                 [alternateKeyExpressions componentsJoinedByString:@", "]];
    [implementation appendFormat:@"+ (NSArray<NSString *> *)selectableFields { return @[ %@ ]; }\n",
                                 [selectableAttributeExpressions componentsJoinedByString:@", "]];
    [implementation appendFormat:@"+ (NSArray<NSString *> *)nonSelectableFields { return @[ %@ ]; }\n",
                                 [nonSelectableAttributeExpressions componentsJoinedByString:@", "]];

    NSMutableArray<NSString *> *lookupPairs = [NSMutableArray array];
    NSMutableArray<NSString *> *lookupTargetPairs = [NSMutableArray array];
    for (NSString *attributeName in lookupAttributeOrder) {
      NSArray<NSDictionary<NSString *, id> *> *lookupEntries = lookupGroups[attributeName] ?: @[];
      if ([lookupEntries count] == 0) {
        continue;
      }

      NSMutableArray<NSString *> *targetExpressions = [NSMutableArray arrayWithCapacity:[lookupEntries count]];
      for (NSDictionary<NSString *, id> *lookup in lookupEntries) {
        NSString *navigationName = ALNDataverseCodegenTrimmedString(lookup[@"navigation_property_name"]);
        [targetExpressions addObject:[NSString stringWithFormat:@"@\"%@\"",
                                                                ALNDataverseCodegenJSONEscape(navigationName)]];
      }
      [lookupTargetPairs addObject:[NSString stringWithFormat:@"@\"%@\": @[ %@ ]",
                                                              ALNDataverseCodegenJSONEscape(attributeName),
                                                              [targetExpressions componentsJoinedByString:@", "]]];

      if ([lookupEntries count] == 1) {
        NSString *navigationName = ALNDataverseCodegenTrimmedString(lookupEntries[0][@"navigation_property_name"]);
        [lookupPairs addObject:[NSString stringWithFormat:@"@\"%@\": @\"%@\"",
                                                          ALNDataverseCodegenJSONEscape(attributeName),
                                                          ALNDataverseCodegenJSONEscape(navigationName)]];
      }
    }
    [implementation appendFormat:@"+ (NSDictionary<NSString *, NSString *> *)lookupNavigationMap { return @{ %@ }; }\n",
                                 [lookupPairs componentsJoinedByString:@", "]];
    [implementation appendFormat:@"+ (NSDictionary<NSString *, NSArray<NSString *> *> *)lookupNavigationTargetsMap { return @{ %@ }; }\n",
                                 [lookupTargetPairs componentsJoinedByString:@", "]];

    for (NSDictionary<NSString *, id> *attribute in attributes) {
      NSString *attributeName = ALNDataverseCodegenTrimmedString(attribute[@"logical_name"]);
      if ([attributeName length] == 0) {
        continue;
      }
      NSString *fieldMethod = ALNDataverseCodegenFieldMethodNameForAttribute(attribute);
      [implementation appendFormat:@"+ (NSString *)%@ { return @\"%@\"; }\n",
                                   fieldMethod,
                                   ALNDataverseCodegenJSONEscape(attributeName)];

      NSArray<NSDictionary<NSString *, id> *> *choices =
          [attribute[@"choices"] isKindOfClass:[NSArray class]] ? attribute[@"choices"] : @[];
      if ([choices count] > 0) {
        NSString *choiceMethod = [NSString stringWithFormat:@"%@Choices", fieldMethod];
        NSMutableArray<NSString *> *choicePairs = [NSMutableArray array];
        for (NSDictionary<NSString *, id> *choice in choices) {
          NSInteger value = [choice[@"value"] integerValue];
          NSString *label = ALNDataverseCodegenTrimmedString(choice[@"label"]);
          [choicePairs addObject:[NSString stringWithFormat:@"@(%ld): @\"%@\"",
                                                            (long)value,
                                                            ALNDataverseCodegenJSONEscape(label)]];
        }
        [implementation appendFormat:@"+ (NSDictionary<NSNumber *, NSString *> *)%@ { return @{ %@ }; }\n",
                                     choiceMethod,
                                     [choicePairs componentsJoinedByString:@", "]];
      }
    }

    for (NSString *attributeName in lookupAttributeOrder) {
      NSArray<NSDictionary<NSString *, id> *> *lookupEntries = lookupGroups[attributeName] ?: @[];
      if ([lookupEntries count] == 0) {
        continue;
      }

      BOOL polymorphic = ([lookupEntries count] > 1);
      for (NSDictionary<NSString *, id> *lookup in lookupEntries) {
        NSString *navigationName = ALNDataverseCodegenTrimmedString(lookup[@"navigation_property_name"]);
        NSString *methodName = polymorphic ? ALNDataverseCodegenNavigationMethodName(navigationName)
                                           : ALNDataverseCodegenNavigationMethodName(attributeName);
        [implementation appendFormat:@"+ (NSString *)%@ { return @\"%@\"; }\n",
                                     methodName,
                                     ALNDataverseCodegenJSONEscape(navigationName)];
      }
    }
    [implementation appendString:@"@end\n\n"];

    [manifestEntities addObject:@{
      @"logical_name" : logicalName,
      @"entity_set_name" : entitySetName,
      @"class_name" : className,
      @"primary_id_attribute" : primaryID ?: @"",
      @"primary_name_attribute" : primaryName ?: @"",
      @"attributes" : manifestAttributes,
      @"choices" : manifestChoices,
      @"lookups" : manifestLookups,
      @"selectable_attribute_count" : @([selectableAttributeExpressions count]),
      @"non_selectable_attribute_count" : @([nonSelectableAttributeExpressions count]),
      @"lookup_count" : @([normalizedLookups count]),
      @"alternate_key_count" : @([keys count]),
    }];
  }

  [header appendString:@"NS_ASSUME_NONNULL_END\n\n"];
  [header appendString:@"#endif\n"];

  NSMutableDictionary<NSString *, id> *manifestObject = [NSMutableDictionary dictionary];
  manifestObject[@"class_prefix"] = prefix;
  manifestObject[@"base_name"] = baseName;
  if ([target length] > 0) {
    manifestObject[@"dataverse_target"] = target;
  }
  manifestObject[@"entity_count"] = @([manifestEntities count]);
  manifestObject[@"attribute_count"] = @(attributeCount);
  manifestObject[@"entities"] = manifestEntities;

  NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
#ifdef NSJSONWritingSortedKeys
  options |= NSJSONWritingSortedKeys;
#endif
  NSError *jsonError = nil;
  NSData *manifestData = [ALNJSONSerialization dataWithJSONObject:manifestObject options:options error:&jsonError];
  if (manifestData == nil) {
    if (error != NULL) {
      *error = jsonError ?: ALNDataverseCodegenMakeError(ALNDataverseCodegenErrorInvalidMetadata,
                                                         @"Dataverse codegen could not encode the manifest",
                                                         nil);
    }
    return nil;
  }
  NSString *manifest = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding] ?: @"{}";

  return @{
    @"baseName" : baseName,
    @"header" : header,
    @"implementation" : implementation,
    @"manifest" : manifest,
    @"entityCount" : @([manifestEntities count]),
    @"attributeCount" : @(attributeCount),
  };
}

@end
