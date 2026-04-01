#import "ALNORMDataverseCodegen.h"

#import "ALNORMErrors.h"

static NSString *ALNORMDataverseCodegenStringValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNORMDataverseCodegenBoolValue(id value, BOOL fallback) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *text = [[ALNORMDataverseCodegenStringValue(value) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text isEqualToString:@"yes"] || [text isEqualToString:@"true"] || [text isEqualToString:@"1"]) {
    return YES;
  }
  if ([text isEqualToString:@"no"] || [text isEqualToString:@"false"] || [text isEqualToString:@"0"]) {
    return NO;
  }
  return fallback;
}

static NSString *ALNORMDataverseCodegenPascalCase(NSString *identifier) {
  NSMutableString *buffer = [NSMutableString string];
  BOOL uppercaseNext = YES;
  for (NSUInteger index = 0; index < [identifier length]; index++) {
    unichar character = [identifier characterAtIndex:index];
    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:character]) {
      NSString *piece = [[NSString stringWithFormat:@"%C", character] lowercaseString];
      [buffer appendString:(uppercaseNext ? [piece uppercaseString] : piece)];
      uppercaseNext = NO;
    } else {
      uppercaseNext = YES;
    }
  }
  if ([buffer length] == 0) {
    [buffer appendString:@"Value"];
  }
  return [NSString stringWithString:buffer];
}

static NSString *ALNORMDataverseCodegenPluralize(NSString *identifier) {
  NSString *value = [ALNORMDataverseCodegenStringValue(identifier) lowercaseString];
  if ([value hasSuffix:@"y"] && [value length] > 1) {
    return [[value substringToIndex:[value length] - 1] stringByAppendingString:@"ies"];
  }
  if ([value hasSuffix:@"s"]) {
    return value;
  }
  return [value stringByAppendingString:@"s"];
}

static NSDictionary<NSString *, NSString *> *ALNORMDataverseCodegenTypeInfo(NSString *attributeType) {
  NSString *type = [[ALNORMDataverseCodegenStringValue(attributeType) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([type isEqualToString:@"uniqueidentifier"] || [type isEqualToString:@"string"] ||
      [type isEqualToString:@"memo"] || [type isEqualToString:@"customer"] ||
      [type isEqualToString:@"owner"] || [type isEqualToString:@"lookup"]) {
    return @{
      @"objc_type" : @"NSString *",
      @"runtime_class_name" : @"NSString",
    };
  }
  if ([type isEqualToString:@"boolean"] || [type isEqualToString:@"picklist"] ||
      [type isEqualToString:@"state"] || [type isEqualToString:@"status"] ||
      [type isEqualToString:@"integer"] || [type isEqualToString:@"bigint"] ||
      [type isEqualToString:@"decimal"] || [type isEqualToString:@"double"] ||
      [type isEqualToString:@"money"]) {
    return @{
      @"objc_type" : @"NSNumber *",
      @"runtime_class_name" : @"NSNumber",
    };
  }
  if ([type isEqualToString:@"multiselectpicklist"]) {
    return @{
      @"objc_type" : @"NSArray *",
      @"runtime_class_name" : @"NSArray",
    };
  }
  if ([type isEqualToString:@"datetime"] || [type isEqualToString:@"date"]) {
    return @{
      @"objc_type" : @"NSDate *",
      @"runtime_class_name" : @"NSDate",
    };
  }
  return @{
    @"objc_type" : @"id",
    @"runtime_class_name" : @"",
  };
}

static NSString *ALNORMDataverseCodegenLookupReadKey(NSDictionary<NSString *, id> *attribute) {
  NSArray *targets = [attribute[@"targets"] isKindOfClass:[NSArray class]] ? attribute[@"targets"] : @[];
  NSString *logicalName = ALNORMDataverseCodegenStringValue(attribute[@"logical_name"]);
  if ([targets count] > 0 && [logicalName length] > 0) {
    return [NSString stringWithFormat:@"_%@_value", logicalName];
  }
  return logicalName;
}

@implementation ALNORMDataverseCodegen

+ (NSArray<ALNORMDataverseModelDescriptor *> *)modelDescriptorsFromMetadata:(NSDictionary<NSString *, id> *)metadata
                                                                classPrefix:(NSString *)classPrefix
                                                            dataverseTarget:(NSString *)dataverseTarget
                                                                      error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *entities =
      [metadata[@"entities"] isKindOfClass:[NSArray class]] ? metadata[@"entities"] : nil;
  NSString *prefix = ALNORMDataverseCodegenStringValue(classPrefix);
  if ([entities count] == 0 || [prefix length] == 0) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse ORM codegen requires non-empty metadata and a class prefix",
                               nil);
    }
    return nil;
  }

  NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *entitiesByLogicalName = [NSMutableDictionary dictionary];
  for (NSDictionary<NSString *, id> *entity in entities) {
    NSString *logicalName = ALNORMDataverseCodegenStringValue(entity[@"logical_name"]);
    if ([logicalName length] > 0) {
      entitiesByLogicalName[logicalName] = entity;
    }
  }

  NSMutableDictionary<NSString *, NSString *> *classNamesByLogicalName = [NSMutableDictionary dictionary];
  for (NSString *logicalName in entitiesByLogicalName) {
    classNamesByLogicalName[logicalName] =
        [NSString stringWithFormat:@"%@%@", prefix, ALNORMDataverseCodegenPascalCase(logicalName)];
  }

  NSMutableDictionary<NSString *, NSMutableArray<ALNORMDataverseRelationDescriptor *> *> *reverseRelations =
      [NSMutableDictionary dictionary];
  NSMutableArray<ALNORMDataverseModelDescriptor *> *descriptors = [NSMutableArray array];

  for (NSDictionary<NSString *, id> *entity in [entities sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left,
                                                                                                        NSDictionary *right) {
         return [ALNORMDataverseCodegenStringValue(left[@"logical_name"])
             compare:ALNORMDataverseCodegenStringValue(right[@"logical_name"])];
       }]) {
    NSString *logicalName = ALNORMDataverseCodegenStringValue(entity[@"logical_name"]);
    NSString *entitySetName = ALNORMDataverseCodegenStringValue(entity[@"entity_set_name"]);
    NSString *primaryIDAttribute = ALNORMDataverseCodegenStringValue(entity[@"primary_id_attribute"]);
    NSString *primaryNameAttribute = ALNORMDataverseCodegenStringValue(entity[@"primary_name_attribute"]);
    NSArray *attributes = [entity[@"attributes"] isKindOfClass:[NSArray class]] ? entity[@"attributes"] : @[];
    NSArray *lookups = [entity[@"lookups"] isKindOfClass:[NSArray class]] ? entity[@"lookups"] : @[];
    NSArray *keys = [entity[@"keys"] isKindOfClass:[NSArray class]] ? entity[@"keys"] : @[];

    NSMutableArray<ALNORMDataverseFieldDescriptor *> *fields = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *attribute in attributes) {
      NSString *attributeType = ALNORMDataverseCodegenStringValue(attribute[@"type"]);
      NSDictionary<NSString *, NSString *> *typeInfo = ALNORMDataverseCodegenTypeInfo(attributeType);
      [fields addObject:[[ALNORMDataverseFieldDescriptor alloc]
                            initWithLogicalName:ALNORMDataverseCodegenStringValue(attribute[@"logical_name"])
                                     schemaName:ALNORMDataverseCodegenStringValue(attribute[@"schema_name"])
                                    displayName:ALNORMDataverseCodegenStringValue(attribute[@"display_name"])
                                  attributeType:attributeType
                                        readKey:ALNORMDataverseCodegenLookupReadKey(attribute)
                                       objcType:typeInfo[@"objc_type"] ?: @"id"
                               runtimeClassName:typeInfo[@"runtime_class_name"] ?: @""
                                       nullable:ALNORMDataverseCodegenBoolValue(attribute[@"nullable"], YES)
                                      primaryID:ALNORMDataverseCodegenBoolValue(attribute[@"primary_id"], NO)
                                    primaryName:ALNORMDataverseCodegenBoolValue(attribute[@"primary_name"], NO)
                                        logical:ALNORMDataverseCodegenBoolValue(attribute[@"logical"], NO)
                                       readable:ALNORMDataverseCodegenBoolValue(attribute[@"readable"], YES)
                                      creatable:ALNORMDataverseCodegenBoolValue(attribute[@"creatable"], YES)
                                     updateable:ALNORMDataverseCodegenBoolValue(attribute[@"updateable"], YES)
                                        targets:[attribute[@"targets"] isKindOfClass:[NSArray class]] ? attribute[@"targets"] : @[]
                                        choices:[attribute[@"choices"] isKindOfClass:[NSArray class]] ? attribute[@"choices"] : @[]]];
    }

    NSMutableArray<ALNORMDataverseRelationDescriptor *> *relations = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *lookup in lookups) {
      NSString *relationName = ALNORMDataverseCodegenStringValue(lookup[@"navigation_property_name"]);
      NSString *targetLogicalName = ALNORMDataverseCodegenStringValue(lookup[@"referenced_entity"]);
      NSDictionary<NSString *, id> *targetEntity = entitiesByLogicalName[targetLogicalName];
      NSString *queryEntitySetName = ALNORMDataverseCodegenStringValue(targetEntity[@"entity_set_name"]);
      NSString *lookupFieldName = ALNORMDataverseCodegenStringValue(lookup[@"referencing_attribute"]);
      NSString *targetPrimaryID = ALNORMDataverseCodegenStringValue(targetEntity[@"primary_id_attribute"]);
      ALNORMDataverseRelationDescriptor *relation = [[ALNORMDataverseRelationDescriptor alloc]
          initWithName:relationName
          currentEntityLogicalName:logicalName
            queryEntityLogicalName:targetLogicalName
               queryEntitySetName:queryEntitySetName
                   targetClassName:classNamesByLogicalName[targetLogicalName] ?: @""
              sourceValueFieldName:lookupFieldName
                queryFieldLogicalName:targetPrimaryID
            navigationPropertyName:relationName
                         collection:NO
                           readOnly:NO
                           inferred:NO];
      [relations addObject:relation];

      if ([targetLogicalName length] > 0 && [targetPrimaryID length] > 0) {
        if (reverseRelations[targetLogicalName] == nil) {
          reverseRelations[targetLogicalName] = [NSMutableArray array];
        }
        NSString *reverseName = ALNORMDataverseCodegenPluralize(entitySetName);
        [reverseRelations[targetLogicalName]
            addObject:[[ALNORMDataverseRelationDescriptor alloc]
                          initWithName:reverseName
              currentEntityLogicalName:targetLogicalName
                queryEntityLogicalName:logicalName
                   queryEntitySetName:entitySetName
                       targetClassName:classNamesByLogicalName[logicalName] ?: @""
                  sourceValueFieldName:targetPrimaryID
                    queryFieldLogicalName:lookupFieldName
                navigationPropertyName:relationName
                             collection:YES
                               readOnly:YES
                               inferred:YES]];
      }
    }

    NSMutableArray<NSArray<NSString *> *> *alternateKeyFieldSets = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *key in keys) {
      NSArray *attributesForKey = [key[@"key_attributes"] isKindOfClass:[NSArray class]] ? key[@"key_attributes"] : @[];
      if ([attributesForKey count] > 0) {
        [alternateKeyFieldSets addObject:attributesForKey];
      }
    }

    [descriptors addObject:[[ALNORMDataverseModelDescriptor alloc]
                               initWithClassName:classNamesByLogicalName[logicalName] ?: @""
                                      logicalName:logicalName
                                    entitySetName:entitySetName
                               primaryIDAttribute:primaryIDAttribute
                             primaryNameAttribute:primaryNameAttribute
                                  dataverseTarget:dataverseTarget
                                         readOnly:NO
                                           fields:fields
                            alternateKeyFieldSets:alternateKeyFieldSets
                                        relations:relations]];
  }

  NSMutableArray<ALNORMDataverseModelDescriptor *> *resolved = [NSMutableArray array];
  for (ALNORMDataverseModelDescriptor *descriptor in descriptors) {
    NSMutableArray<ALNORMDataverseRelationDescriptor *> *relations =
        [NSMutableArray arrayWithArray:descriptor.relations ?: @[]];
    [relations addObjectsFromArray:reverseRelations[descriptor.logicalName] ?: @[]];
    [resolved addObject:[[ALNORMDataverseModelDescriptor alloc]
                            initWithClassName:descriptor.className
                                   logicalName:descriptor.logicalName
                                 entitySetName:descriptor.entitySetName
                            primaryIDAttribute:descriptor.primaryIDAttribute
                          primaryNameAttribute:descriptor.primaryNameAttribute
                               dataverseTarget:descriptor.dataverseTarget
                                      readOnly:descriptor.isReadOnly
                                        fields:descriptor.fields
                         alternateKeyFieldSets:descriptor.alternateKeyFieldSets
                                     relations:relations]];
  }
  return [NSArray arrayWithArray:resolved];
}

@end
