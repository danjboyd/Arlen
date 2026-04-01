#import "ALNORMDescriptorSnapshot.h"

#import "ALNORMErrors.h"

static NSString *ALNORMDescriptorSnapshotStringValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNORMDescriptorSnapshotBoolValue(id value, BOOL fallback) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *text = [[ALNORMDescriptorSnapshotStringValue(value) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text isEqualToString:@"yes"] || [text isEqualToString:@"true"] || [text isEqualToString:@"1"]) {
    return YES;
  }
  if ([text isEqualToString:@"no"] || [text isEqualToString:@"false"] || [text isEqualToString:@"0"]) {
    return NO;
  }
  return fallback;
}

static NSInteger ALNORMDescriptorSnapshotIntegerValue(id value, NSInteger fallback) {
  return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

static NSArray<NSString *> *ALNORMDescriptorSnapshotStringArray(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray<NSString *> *items = [NSMutableArray array];
  for (id rawItem in (NSArray *)value) {
    NSString *item = ALNORMDescriptorSnapshotStringValue(rawItem);
    if ([item length] > 0) {
      [items addObject:item];
    }
  }
  return [NSArray arrayWithArray:items];
}

static NSArray<NSArray<NSString *> *> *ALNORMDescriptorSnapshotStringSetArray(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray<NSArray<NSString *> *> *items = [NSMutableArray array];
  for (id rawItem in (NSArray *)value) {
    [items addObject:ALNORMDescriptorSnapshotStringArray(rawItem)];
  }
  return [NSArray arrayWithArray:items];
}

static ALNORMFieldDescriptor *ALNORMDescriptorSnapshotFieldFromDictionary(NSDictionary<NSString *, id> *dictionary) {
  return [[ALNORMFieldDescriptor alloc] initWithName:ALNORMDescriptorSnapshotStringValue(dictionary[@"name"])
                                       propertyName:ALNORMDescriptorSnapshotStringValue(dictionary[@"property_name"])
                                         columnName:ALNORMDescriptorSnapshotStringValue(dictionary[@"column_name"])
                                           dataType:ALNORMDescriptorSnapshotStringValue(dictionary[@"data_type"])
                                           objcType:ALNORMDescriptorSnapshotStringValue(dictionary[@"objc_type"])
                                   runtimeClassName:ALNORMDescriptorSnapshotStringValue(dictionary[@"runtime_class_name"])
                                  propertyAttribute:ALNORMDescriptorSnapshotStringValue(dictionary[@"property_attribute"])
                                            ordinal:ALNORMDescriptorSnapshotIntegerValue(dictionary[@"ordinal"], 0)
                                           nullable:ALNORMDescriptorSnapshotBoolValue(dictionary[@"nullable"], YES)
                                         primaryKey:ALNORMDescriptorSnapshotBoolValue(dictionary[@"primary_key"], NO)
                                             unique:ALNORMDescriptorSnapshotBoolValue(dictionary[@"unique"], NO)
                                         hasDefault:ALNORMDescriptorSnapshotBoolValue(dictionary[@"has_default"], NO)
                                           readOnly:ALNORMDescriptorSnapshotBoolValue(dictionary[@"read_only"], NO)
                                  defaultValueShape:ALNORMDescriptorSnapshotStringValue(dictionary[@"default_value_shape"])];
}

static ALNORMRelationDescriptor *ALNORMDescriptorSnapshotRelationFromDictionary(NSDictionary<NSString *, id> *dictionary) {
  return [[ALNORMRelationDescriptor alloc]
      initWithKind:ALNORMRelationKindFromString(ALNORMDescriptorSnapshotStringValue(dictionary[@"kind"]))
              name:ALNORMDescriptorSnapshotStringValue(dictionary[@"name"])
  sourceEntityName:ALNORMDescriptorSnapshotStringValue(dictionary[@"source_entity_name"])
  targetEntityName:ALNORMDescriptorSnapshotStringValue(dictionary[@"target_entity_name"])
   targetClassName:ALNORMDescriptorSnapshotStringValue(dictionary[@"target_class_name"])
 throughEntityName:ALNORMDescriptorSnapshotStringValue(dictionary[@"through_entity_name"])
  throughClassName:ALNORMDescriptorSnapshotStringValue(dictionary[@"through_class_name"])
  sourceFieldNames:ALNORMDescriptorSnapshotStringArray(dictionary[@"source_field_names"])
  targetFieldNames:ALNORMDescriptorSnapshotStringArray(dictionary[@"target_field_names"])
throughSourceFieldNames:ALNORMDescriptorSnapshotStringArray(dictionary[@"through_source_field_names"])
throughTargetFieldNames:ALNORMDescriptorSnapshotStringArray(dictionary[@"through_target_field_names"])
      pivotFieldNames:ALNORMDescriptorSnapshotStringArray(dictionary[@"pivot_field_names"])
             readOnly:ALNORMDescriptorSnapshotBoolValue(dictionary[@"read_only"], NO)
             inferred:ALNORMDescriptorSnapshotBoolValue(dictionary[@"inferred"], NO)];
}

static ALNORMModelDescriptor *ALNORMDescriptorSnapshotModelFromDictionary(NSDictionary<NSString *, id> *dictionary) {
  NSMutableArray<ALNORMFieldDescriptor *> *fields = [NSMutableArray array];
  for (id rawField in ([dictionary[@"fields"] isKindOfClass:[NSArray class]] ? dictionary[@"fields"] : @[])) {
    if ([rawField isKindOfClass:[NSDictionary class]]) {
      [fields addObject:ALNORMDescriptorSnapshotFieldFromDictionary(rawField)];
    }
  }

  NSMutableArray<ALNORMRelationDescriptor *> *relations = [NSMutableArray array];
  for (id rawRelation in ([dictionary[@"relations"] isKindOfClass:[NSArray class]] ? dictionary[@"relations"] : @[])) {
    if ([rawRelation isKindOfClass:[NSDictionary class]]) {
      [relations addObject:ALNORMDescriptorSnapshotRelationFromDictionary(rawRelation)];
    }
  }

  return [[ALNORMModelDescriptor alloc]
      initWithClassName:ALNORMDescriptorSnapshotStringValue(dictionary[@"class_name"])
             entityName:ALNORMDescriptorSnapshotStringValue(dictionary[@"entity_name"])
             schemaName:ALNORMDescriptorSnapshotStringValue(dictionary[@"schema_name"])
              tableName:ALNORMDescriptorSnapshotStringValue(dictionary[@"table_name"])
     qualifiedTableName:ALNORMDescriptorSnapshotStringValue(dictionary[@"qualified_table_name"])
           relationKind:ALNORMDescriptorSnapshotStringValue(dictionary[@"relation_kind"])
         databaseTarget:ALNORMDescriptorSnapshotStringValue(dictionary[@"database_target"])
               readOnly:ALNORMDescriptorSnapshotBoolValue(dictionary[@"read_only"], NO)
                 fields:fields
   primaryKeyFieldNames:ALNORMDescriptorSnapshotStringArray(dictionary[@"primary_key_field_names"])
uniqueConstraintFieldSets:ALNORMDescriptorSnapshotStringSetArray(dictionary[@"unique_constraint_field_sets"])
              relations:relations];
}

@implementation ALNORMDescriptorSnapshot

+ (NSString *)formatVersion {
  return @"arlen-orm-descriptor-snapshot-v1";
}

+ (NSDictionary<NSString *, id> *)snapshotDocumentWithModelDescriptors:(NSArray<ALNORMModelDescriptor *> *)descriptors
                                                        databaseTarget:(NSString *)databaseTarget
                                                                 label:(NSString *)label {
  NSArray<ALNORMModelDescriptor *> *sortedDescriptors =
      [descriptors sortedArrayUsingComparator:^NSComparisonResult(ALNORMModelDescriptor *left,
                                                                  ALNORMModelDescriptor *right) {
        return [left.entityName compare:right.entityName];
      }];
  NSMutableArray<NSDictionary<NSString *, id> *> *rendered = [NSMutableArray array];
  for (ALNORMModelDescriptor *descriptor in sortedDescriptors) {
    [rendered addObject:[descriptor dictionaryRepresentation]];
  }
  return @{
    @"format" : [self formatVersion],
    @"label" : [label copy] ?: @"",
    @"database_target" : [databaseTarget copy] ?: @"",
    @"descriptor_count" : @([rendered count]),
    @"descriptors" : rendered,
  };
}

+ (NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSnapshotDocument:(NSDictionary<NSString *, id> *)document
                                                                     error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![document isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"descriptor snapshot must be a dictionary",
                               nil);
    }
    return nil;
  }
  NSString *format = ALNORMDescriptorSnapshotStringValue(document[@"format"]);
  if (![format isEqualToString:[self formatVersion]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                               @"descriptor snapshot format is not supported",
                               @{
                                 @"expected_format" : [self formatVersion],
                                 @"actual_format" : format ?: @"",
                               });
    }
    return nil;
  }

  NSArray *descriptorDictionaries = [document[@"descriptors"] isKindOfClass:[NSArray class]] ? document[@"descriptors"] : nil;
  if ([descriptorDictionaries count] == 0) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                               @"descriptor snapshot does not contain any descriptors",
                               nil);
    }
    return nil;
  }

  NSMutableArray<ALNORMModelDescriptor *> *descriptors = [NSMutableArray array];
  for (id rawDescriptor in descriptorDictionaries) {
    if (![rawDescriptor isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [descriptors addObject:ALNORMDescriptorSnapshotModelFromDictionary(rawDescriptor)];
  }
  return [NSArray arrayWithArray:descriptors];
}

@end
