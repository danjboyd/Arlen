#import "ALNDataverseMetadata.h"

#import "ALNDataverseQuery.h"

NSString *const ALNDataverseMetadataErrorDomain = @"Arlen.Data.Dataverse.Metadata.Error";

static NSString *ALNDataverseMetadataTrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNDataverseMetadataBoolValue(id value, BOOL fallback) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *text = [[ALNDataverseMetadataTrimmedString(value) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text isEqualToString:@"1"] || [text isEqualToString:@"true"] || [text isEqualToString:@"yes"] ||
      [text isEqualToString:@"y"] || [text isEqualToString:@"t"]) {
    return YES;
  }
  if ([text isEqualToString:@"0"] || [text isEqualToString:@"false"] || [text isEqualToString:@"no"] ||
      [text isEqualToString:@"n"] || [text isEqualToString:@"f"]) {
    return NO;
  }
  return fallback;
}

static NSString *ALNDataverseMetadataLocalizedLabel(NSDictionary *labelValue) {
  if (![labelValue isKindOfClass:[NSDictionary class]]) {
    return @"";
  }
  NSDictionary *userLabel =
      [labelValue[@"UserLocalizedLabel"] isKindOfClass:[NSDictionary class]] ? labelValue[@"UserLocalizedLabel"] : nil;
  NSString *label = ALNDataverseMetadataTrimmedString(userLabel[@"Label"]);
  if ([label length] > 0) {
    return label;
  }
  NSArray *localized = [labelValue[@"LocalizedLabels"] isKindOfClass:[NSArray class]] ? labelValue[@"LocalizedLabels"] : nil;
  for (NSDictionary *entry in localized) {
    NSString *candidate = ALNDataverseMetadataTrimmedString(entry[@"Label"]);
    if ([candidate length] > 0) {
      return candidate;
    }
  }
  return @"";
}

static NSString *ALNDataverseMetadataAttributeType(NSDictionary *attribute) {
  NSString *normalizedType = ALNDataverseMetadataTrimmedString(attribute[@"type"]);
  if ([normalizedType length] > 0) {
    return normalizedType;
  }
  NSDictionary *typeName =
      [attribute[@"AttributeTypeName"] isKindOfClass:[NSDictionary class]] ? attribute[@"AttributeTypeName"] : nil;
  NSString *typeValue = ALNDataverseMetadataTrimmedString(typeName[@"Value"]);
  if ([typeValue length] > 0) {
    return typeValue;
  }
  return ALNDataverseMetadataTrimmedString(attribute[@"AttributeType"]);
}

static BOOL ALNDataverseMetadataAttributeNullable(NSDictionary *attribute) {
  if (attribute[@"nullable"] != nil && attribute[@"nullable"] != [NSNull null]) {
    return ALNDataverseMetadataBoolValue(attribute[@"nullable"], YES);
  }
  NSDictionary *requiredLevel =
      [attribute[@"RequiredLevel"] isKindOfClass:[NSDictionary class]] ? attribute[@"RequiredLevel"] : nil;
  NSString *required = [[ALNDataverseMetadataTrimmedString(requiredLevel[@"Value"]) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([required isEqualToString:@"systemrequired"] || [required isEqualToString:@"applicationrequired"]) {
    return NO;
  }
  return YES;
}

static NSArray<NSDictionary<NSString *, id> *> *ALNDataverseMetadataNormalizeChoiceOptions(NSDictionary *attribute) {
  NSArray *normalizedChoices = [attribute[@"choices"] isKindOfClass:[NSArray class]] ? attribute[@"choices"] : nil;
  if ([normalizedChoices count] > 0) {
    NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [NSMutableArray arrayWithCapacity:[normalizedChoices count]];
    for (NSDictionary *option in normalizedChoices) {
      if (![option isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSNumber *value = [option[@"value"] respondsToSelector:@selector(integerValue)] ? option[@"value"] : nil;
      if (value == nil && [option[@"Value"] respondsToSelector:@selector(integerValue)]) {
        value = option[@"Value"];
      }
      if (value == nil) {
        continue;
      }
      NSString *label = ALNDataverseMetadataTrimmedString(option[@"label"]);
      if ([label length] == 0) {
        label = ALNDataverseMetadataLocalizedLabel(
            [option[@"Label"] isKindOfClass:[NSDictionary class]] ? option[@"Label"] : nil);
      }
      [normalized addObject:@{
        @"value" : value,
        @"label" : label ?: @"",
      }];
    }
    [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
      NSInteger leftValue = [((NSNumber *)left[@"value"]) integerValue];
      NSInteger rightValue = [((NSNumber *)right[@"value"]) integerValue];
      if (leftValue < rightValue) {
        return NSOrderedAscending;
      }
      if (leftValue > rightValue) {
        return NSOrderedDescending;
      }
      return [left[@"label"] compare:right[@"label"]];
    }];
    return [NSArray arrayWithArray:normalized];
  }

  NSDictionary *optionSet = [attribute[@"OptionSet"] isKindOfClass:[NSDictionary class]] ? attribute[@"OptionSet"] : nil;
  if (optionSet == nil) {
    optionSet = [attribute[@"GlobalOptionSet"] isKindOfClass:[NSDictionary class]] ? attribute[@"GlobalOptionSet"] : nil;
  }
  NSArray *options = [optionSet[@"Options"] isKindOfClass:[NSArray class]] ? optionSet[@"Options"] : nil;
  if ([options count] == 0) {
    return @[];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [NSMutableArray arrayWithCapacity:[options count]];
  for (NSDictionary *option in options) {
    if (![option isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSNumber *value = [option[@"Value"] respondsToSelector:@selector(integerValue)] ? option[@"Value"] : nil;
    if (value == nil) {
      continue;
    }
    NSString *label = ALNDataverseMetadataLocalizedLabel(
        [option[@"Label"] isKindOfClass:[NSDictionary class]] ? option[@"Label"] : nil);
    [normalized addObject:@{
      @"value" : value,
      @"label" : label ?: @"",
    }];
  }
  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSInteger leftValue = [((NSNumber *)left[@"value"]) integerValue];
    NSInteger rightValue = [((NSNumber *)right[@"value"]) integerValue];
    if (leftValue < rightValue) {
      return NSOrderedAscending;
    }
    if (leftValue > rightValue) {
      return NSOrderedDescending;
    }
    return [left[@"label"] compare:right[@"label"]];
  }];
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSString *> *ALNDataverseMetadataSortedTargets(NSDictionary *attribute) {
  NSArray *targets = nil;
  if ([attribute[@"Targets"] isKindOfClass:[NSArray class]]) {
    targets = attribute[@"Targets"];
  } else if ([attribute[@"targets"] isKindOfClass:[NSArray class]]) {
    targets = attribute[@"targets"];
  }
  return [targets count] > 0 ? [targets sortedArrayUsingSelector:@selector(compare:)] : @[];
}

static NSString *ALNDataverseMetadataAttributeOf(NSDictionary *attribute) {
  NSString *attributeOf = ALNDataverseMetadataTrimmedString(attribute[@"AttributeOf"]);
  if ([attributeOf length] == 0) {
    attributeOf = ALNDataverseMetadataTrimmedString(attribute[@"attribute_of"]);
  }
  return attributeOf;
}

static BOOL ALNDataverseMetadataAttributeODataSelectable(NSDictionary *attribute) {
  if (attribute[@"odata_selectable"] != nil && attribute[@"odata_selectable"] != [NSNull null]) {
    return ALNDataverseMetadataBoolValue(attribute[@"odata_selectable"], YES);
  }
  if (attribute[@"IsValidODataAttribute"] != nil && attribute[@"IsValidODataAttribute"] != [NSNull null]) {
    return ALNDataverseMetadataBoolValue(attribute[@"IsValidODataAttribute"], YES);
  }
  return ([ALNDataverseMetadataAttributeOf(attribute) length] == 0);
}

static NSDictionary<NSString *, id> *ALNDataverseMetadataNormalizeAttribute(NSDictionary *attribute,
                                                                            NSString *primaryIDAttribute,
                                                                            NSString *primaryNameAttribute) {
  NSString *logicalName = ALNDataverseMetadataTrimmedString(attribute[@"LogicalName"]);
  if ([logicalName length] == 0) {
    logicalName = ALNDataverseMetadataTrimmedString(attribute[@"logical_name"]);
  }
  NSString *schemaName = ALNDataverseMetadataTrimmedString(attribute[@"SchemaName"]);
  if ([schemaName length] == 0) {
    schemaName = ALNDataverseMetadataTrimmedString(attribute[@"schema_name"]);
  }
  NSString *displayName = ALNDataverseMetadataLocalizedLabel(
      [attribute[@"DisplayName"] isKindOfClass:[NSDictionary class]] ? attribute[@"DisplayName"] : nil);
  if ([displayName length] == 0) {
    displayName = ALNDataverseMetadataTrimmedString(attribute[@"display_name"]);
  }
  NSString *type = ALNDataverseMetadataAttributeType(attribute);
  NSArray *sortedTargets = ALNDataverseMetadataSortedTargets(attribute);
  NSString *attributeOf = ALNDataverseMetadataAttributeOf(attribute);
  BOOL primaryID = [logicalName isEqualToString:primaryIDAttribute] ||
                   ALNDataverseMetadataBoolValue((attribute[@"primary_id"] != nil ? attribute[@"primary_id"]
                                                                                  : attribute[@"IsPrimaryId"]),
                                                 NO);
  BOOL primaryName = [logicalName isEqualToString:primaryNameAttribute] ||
                     ALNDataverseMetadataBoolValue(attribute[@"primary_name"], NO);

  return @{
    @"logical_name" : logicalName ?: @"",
    @"schema_name" : schemaName ?: @"",
    @"display_name" : displayName ?: @"",
    @"type" : type ?: @"",
    @"nullable" : @(ALNDataverseMetadataAttributeNullable(attribute)),
    @"primary_id" : @(primaryID),
    @"primary_name" : @(primaryName),
    @"logical" : @(ALNDataverseMetadataBoolValue((attribute[@"logical"] != nil ? attribute[@"logical"] : attribute[@"IsLogical"]), NO)),
    @"readable" : @(ALNDataverseMetadataBoolValue((attribute[@"readable"] != nil ? attribute[@"readable"] : attribute[@"IsValidForRead"]), YES)),
    @"creatable" : @(ALNDataverseMetadataBoolValue((attribute[@"creatable"] != nil ? attribute[@"creatable"] : attribute[@"IsValidForCreate"]), YES)),
    @"updateable" : @(ALNDataverseMetadataBoolValue((attribute[@"updateable"] != nil ? attribute[@"updateable"] : attribute[@"IsValidForUpdate"]), YES)),
    @"attribute_of" : attributeOf ?: @"",
    @"odata_selectable" : @(ALNDataverseMetadataAttributeODataSelectable(attribute)),
    @"targets" : sortedTargets ?: @[],
    @"choices" : ALNDataverseMetadataNormalizeChoiceOptions(attribute) ?: @[],
  };
}

static NSDictionary<NSString *, id> *ALNDataverseMetadataNormalizeLookup(NSDictionary *relationship) {
  NSString *navigationPropertyName =
      ALNDataverseMetadataTrimmedString(relationship[@"ReferencingEntityNavigationPropertyName"]);
  if ([navigationPropertyName length] == 0) {
    navigationPropertyName = ALNDataverseMetadataTrimmedString(relationship[@"NavigationPropertyName"]);
  }
  if ([navigationPropertyName length] == 0) {
    navigationPropertyName = ALNDataverseMetadataTrimmedString(relationship[@"navigation_property_name"]);
  }
  if ([navigationPropertyName length] == 0) {
    navigationPropertyName = ALNDataverseMetadataTrimmedString(relationship[@"ReferencingAttribute"]);
  }
  NSString *schemaName = ALNDataverseMetadataTrimmedString(relationship[@"SchemaName"]);
  if ([schemaName length] == 0) {
    schemaName = ALNDataverseMetadataTrimmedString(relationship[@"schema_name"]);
  }
  NSString *referencingAttribute = ALNDataverseMetadataTrimmedString(relationship[@"ReferencingAttribute"]);
  if ([referencingAttribute length] == 0) {
    referencingAttribute = ALNDataverseMetadataTrimmedString(relationship[@"referencing_attribute"]);
  }
  NSString *referencedEntity = ALNDataverseMetadataTrimmedString(relationship[@"ReferencedEntity"]);
  if ([referencedEntity length] == 0) {
    referencedEntity = ALNDataverseMetadataTrimmedString(relationship[@"referenced_entity"]);
  }
  NSString *referencedAttribute = ALNDataverseMetadataTrimmedString(relationship[@"ReferencedAttribute"]);
  if ([referencedAttribute length] == 0) {
    referencedAttribute = ALNDataverseMetadataTrimmedString(relationship[@"referenced_attribute"]);
  }
  return @{
    @"schema_name" : schemaName ?: @"",
    @"referencing_attribute" : referencingAttribute ?: @"",
    @"navigation_property_name" : navigationPropertyName ?: @"",
    @"referenced_entity" : referencedEntity ?: @"",
    @"referenced_attribute" : referencedAttribute ?: @"",
  };
}

static NSDictionary<NSString *, id> *ALNDataverseMetadataNormalizeKey(NSDictionary *key) {
  NSArray *attributes = [key[@"KeyAttributes"] isKindOfClass:[NSArray class]] ? key[@"KeyAttributes"] : nil;
  if ([attributes count] == 0) {
    attributes = [key[@"key_attributes"] isKindOfClass:[NSArray class]] ? key[@"key_attributes"] : @[];
  }
  NSArray *sorted = [attributes sortedArrayUsingSelector:@selector(compare:)];
  NSString *logicalName = ALNDataverseMetadataTrimmedString(key[@"LogicalName"]);
  if ([logicalName length] == 0) {
    logicalName = ALNDataverseMetadataTrimmedString(key[@"logical_name"]);
  }
  return @{
    @"logical_name" : logicalName ?: @"",
    @"key_attributes" : sorted ?: @[],
  };
}

static NSDictionary<NSString *, id> *ALNDataverseMetadataNormalizeEntity(NSDictionary *entity) {
  NSString *logicalName = ALNDataverseMetadataTrimmedString(entity[@"LogicalName"]);
  if ([logicalName length] == 0) {
    logicalName = ALNDataverseMetadataTrimmedString(entity[@"logical_name"]);
  }
  NSString *schemaName = ALNDataverseMetadataTrimmedString(entity[@"SchemaName"]);
  if ([schemaName length] == 0) {
    schemaName = ALNDataverseMetadataTrimmedString(entity[@"schema_name"]);
  }
  NSString *entitySetName = ALNDataverseMetadataTrimmedString(entity[@"EntitySetName"]);
  if ([entitySetName length] == 0) {
    entitySetName = ALNDataverseMetadataTrimmedString(entity[@"entity_set_name"]);
  }
  NSString *primaryIDAttribute = ALNDataverseMetadataTrimmedString(entity[@"PrimaryIdAttribute"]);
  if ([primaryIDAttribute length] == 0) {
    primaryIDAttribute = ALNDataverseMetadataTrimmedString(entity[@"primary_id_attribute"]);
  }
  NSString *primaryNameAttribute = ALNDataverseMetadataTrimmedString(entity[@"PrimaryNameAttribute"]);
  if ([primaryNameAttribute length] == 0) {
    primaryNameAttribute = ALNDataverseMetadataTrimmedString(entity[@"primary_name_attribute"]);
  }
  NSString *displayName = ALNDataverseMetadataLocalizedLabel(
      [entity[@"DisplayName"] isKindOfClass:[NSDictionary class]] ? entity[@"DisplayName"] : nil);
  if ([displayName length] == 0) {
    displayName = ALNDataverseMetadataTrimmedString(entity[@"display_name"]);
  }

  NSArray *attributes = [entity[@"Attributes"] isKindOfClass:[NSArray class]] ? entity[@"Attributes"] : nil;
  if ([attributes count] == 0) {
    attributes = [entity[@"attributes"] isKindOfClass:[NSArray class]] ? entity[@"attributes"] : @[];
  }
  NSMutableArray<NSDictionary<NSString *, id> *> *normalizedAttributes =
      [NSMutableArray arrayWithCapacity:[attributes count]];
  for (NSDictionary *attribute in attributes) {
    if (![attribute isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary<NSString *, id> *normalized =
        ALNDataverseMetadataNormalizeAttribute(attribute, primaryIDAttribute, primaryNameAttribute);
    if ([ALNDataverseMetadataTrimmedString(normalized[@"logical_name"]) length] > 0) {
      [normalizedAttributes addObject:normalized];
    }
  }
  [normalizedAttributes sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"logical_name"] compare:right[@"logical_name"]];
  }];

  NSArray *lookups =
      [entity[@"ManyToOneRelationships"] isKindOfClass:[NSArray class]] ? entity[@"ManyToOneRelationships"] : nil;
  if ([lookups count] == 0) {
    lookups = [entity[@"lookups"] isKindOfClass:[NSArray class]] ? entity[@"lookups"] : @[];
  }
  NSMutableArray<NSDictionary<NSString *, id> *> *normalizedLookups =
      [NSMutableArray arrayWithCapacity:[lookups count]];
  for (NSDictionary *relationship in lookups) {
    if (![relationship isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary<NSString *, id> *normalized = ALNDataverseMetadataNormalizeLookup(relationship);
    if ([ALNDataverseMetadataTrimmedString(normalized[@"referencing_attribute"]) length] > 0) {
      [normalizedLookups addObject:normalized];
    }
  }
  [normalizedLookups sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSComparisonResult attributeOrder = [left[@"referencing_attribute"] compare:right[@"referencing_attribute"]];
    if (attributeOrder != NSOrderedSame) {
      return attributeOrder;
    }
    return [left[@"navigation_property_name"] compare:right[@"navigation_property_name"]];
  }];

  NSArray *keys = [entity[@"Keys"] isKindOfClass:[NSArray class]] ? entity[@"Keys"] : nil;
  if ([keys count] == 0) {
    keys = [entity[@"keys"] isKindOfClass:[NSArray class]] ? entity[@"keys"] : @[];
  }
  NSMutableArray<NSDictionary<NSString *, id> *> *normalizedKeys = [NSMutableArray arrayWithCapacity:[keys count]];
  for (NSDictionary *key in keys) {
    if (![key isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary<NSString *, id> *normalized = ALNDataverseMetadataNormalizeKey(key);
    if ([ALNDataverseMetadataTrimmedString(normalized[@"logical_name"]) length] > 0) {
      [normalizedKeys addObject:normalized];
    }
  }
  [normalizedKeys sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"logical_name"] compare:right[@"logical_name"]];
  }];

  return @{
    @"logical_name" : logicalName ?: @"",
    @"schema_name" : schemaName ?: @"",
    @"entity_set_name" : entitySetName ?: @"",
    @"display_name" : displayName ?: @"",
    @"primary_id_attribute" : primaryIDAttribute ?: @"",
    @"primary_name_attribute" : primaryNameAttribute ?: @"",
    @"attributes" : [NSArray arrayWithArray:normalizedAttributes],
    @"lookups" : [NSArray arrayWithArray:normalizedLookups],
    @"keys" : [NSArray arrayWithArray:normalizedKeys],
  };
}

static NSArray<NSDictionary<NSString *, id> *> *ALNDataverseMetadataEntityArrayFromPayload(id payload) {
  if ([payload isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictionary = (NSDictionary *)payload;
    if ([dictionary[@"entities"] isKindOfClass:[NSArray class]]) {
      return dictionary[@"entities"];
    }
    if ([dictionary[@"value"] isKindOfClass:[NSArray class]]) {
      return dictionary[@"value"];
    }
    if ([dictionary[@"LogicalName"] isKindOfClass:[NSString class]]) {
      return @[ dictionary ];
    }
  }
  if ([payload isKindOfClass:[NSArray class]]) {
    return payload;
  }
  return nil;
}

NSError *ALNDataverseMetadataMakeError(ALNDataverseMetadataErrorCode code,
                                       NSString *message,
                                       NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"Dataverse metadata error";
  return [NSError errorWithDomain:ALNDataverseMetadataErrorDomain code:code userInfo:details];
}

@implementation ALNDataverseMetadata

+ (NSDictionary<NSString *, id> *)normalizedMetadataFromPayload:(id)payload error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSArray<NSDictionary<NSString *, id> *> *entities = ALNDataverseMetadataEntityArrayFromPayload(payload);
  if (![entities isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNDataverseMetadataMakeError(ALNDataverseMetadataErrorInvalidResponse,
                                             @"Dataverse metadata payload must be an entity definition or an array/value wrapper",
                                             nil);
    }
    return nil;
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *normalized = [NSMutableArray arrayWithCapacity:[entities count]];
  for (NSDictionary *entity in entities) {
    if (![entity isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary<NSString *, id> *normalizedEntity = ALNDataverseMetadataNormalizeEntity(entity);
    if ([ALNDataverseMetadataTrimmedString(normalizedEntity[@"logical_name"]) length] > 0) {
      [normalized addObject:normalizedEntity];
    }
  }
  [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"logical_name"] compare:right[@"logical_name"]];
  }];

  NSUInteger attributeCount = 0;
  for (NSDictionary *entity in normalized) {
    NSArray *attributes = [entity[@"attributes"] isKindOfClass:[NSArray class]] ? entity[@"attributes"] : @[];
    attributeCount += [attributes count];
  }
  return @{
    @"entities" : [NSArray arrayWithArray:normalized],
    @"entity_count" : @([normalized count]),
    @"attribute_count" : @(attributeCount),
  };
}

+ (NSDictionary<NSString *, id> *)fetchNormalizedMetadataWithClient:(ALNDataverseClient *)client
                                                       logicalNames:(NSArray<NSString *> *)logicalNames
                                                              error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (client == nil) {
    if (error != NULL) {
      *error = ALNDataverseMetadataMakeError(ALNDataverseMetadataErrorInvalidArgument,
                                             @"Dataverse metadata fetch requires a client",
                                             nil);
    }
    return nil;
  }

  NSArray<NSString *> *requestedNames = nil;
  if ([logicalNames count] > 0) {
    NSMutableArray<NSString *> *normalizedNames = [NSMutableArray array];
    for (NSString *logicalName in logicalNames) {
      NSString *trimmed = [[ALNDataverseMetadataTrimmedString(logicalName) lowercaseString]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([trimmed length] > 0) {
        [normalizedNames addObject:trimmed];
      }
    }
    requestedNames = [normalizedNames sortedArrayUsingSelector:@selector(compare:)];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *entities = [NSMutableArray array];
  NSArray<NSString *> *namesToFetch = requestedNames;
  if ([namesToFetch count] == 0) {
    ALNDataverseResponse *response = [client performRequestWithMethod:@"GET"
                                                                 path:@"EntityDefinitions"
                                                                query:@{
                                                                  @"$select" : @"LogicalName,SchemaName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute,DisplayName",
                                                                }
                                                              headers:nil
                                                           bodyObject:nil
                                               includeFormattedValues:NO
                                                 returnRepresentation:NO
                                                     consistencyCount:NO
                                                                error:error];
    if (response == nil) {
      return nil;
    }
    NSError *jsonError = nil;
    NSDictionary *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                ? [response JSONObject:&jsonError]
                                : nil;
    if (payload == nil) {
      if (error != NULL) {
        *error = jsonError ?: ALNDataverseMetadataMakeError(ALNDataverseMetadataErrorInvalidResponse,
                                                            @"Dataverse metadata summary response payload must be a dictionary",
                                                            nil);
      }
      return nil;
    }
    NSArray *summaries = [payload[@"value"] isKindOfClass:[NSArray class]] ? payload[@"value"] : @[];
    NSMutableArray<NSString *> *discovered = [NSMutableArray arrayWithCapacity:[summaries count]];
    for (NSDictionary *summary in summaries) {
      NSString *logicalName = [[ALNDataverseMetadataTrimmedString(summary[@"LogicalName"]) lowercaseString]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([logicalName length] > 0) {
        [discovered addObject:logicalName];
      }
    }
    namesToFetch = [discovered sortedArrayUsingSelector:@selector(compare:)];
  }

  for (NSString *logicalName in namesToFetch) {
    NSString *detailPath = [NSString stringWithFormat:@"EntityDefinitions(LogicalName='%@')",
                                                      [logicalName stringByReplacingOccurrencesOfString:@"'"
                                                                                            withString:@"''"]];
    NSDictionary<NSString *, NSString *> *detailQuery = @{
      @"$select" : @"LogicalName,SchemaName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute,DisplayName",
      // `Targets` is not selectable on the base AttributeMetadata expand against live Dataverse.
      // Lookup/navigation metadata still comes from ManyToOneRelationships, and picklist enrichment
      // is fetched separately via a cast query below.
      @"$expand" : @"Attributes($select=LogicalName,SchemaName,DisplayName,AttributeType,AttributeTypeName,AttributeOf,IsPrimaryId,IsLogical,IsValidForCreate,IsValidForRead,IsValidForUpdate,IsValidODataAttribute,RequiredLevel),Keys($select=LogicalName,KeyAttributes),ManyToOneRelationships($select=SchemaName,ReferencingAttribute,ReferencedEntity,ReferencedAttribute,ReferencingEntityNavigationPropertyName)",
    };
    ALNDataverseResponse *response = [client performRequestWithMethod:@"GET"
                                                                 path:detailPath
                                                                query:detailQuery
                                                              headers:nil
                                                           bodyObject:nil
                                               includeFormattedValues:NO
                                                 returnRepresentation:NO
                                                     consistencyCount:NO
                                                                error:error];
    if (response == nil) {
      return nil;
    }
    NSError *jsonError = nil;
    NSDictionary<NSString *, id> *payload = [[response JSONObject:&jsonError] isKindOfClass:[NSDictionary class]]
                                                ? [response JSONObject:&jsonError]
                                                : nil;
    if (payload == nil) {
      if (error != NULL) {
        *error = jsonError ?: ALNDataverseMetadataMakeError(ALNDataverseMetadataErrorInvalidResponse,
                                                            @"Dataverse metadata detail response payload must be a dictionary",
                                                            @{ @"logical_name" : logicalName ?: @"" });
      }
      return nil;
    }

    // Best-effort picklist enrichment. Dataverse requires a separate cast query to expose OptionSet metadata.
    NSString *picklistPath = [NSString stringWithFormat:
                                  @"EntityDefinitions(LogicalName='%@')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
                                  [logicalName stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
    NSDictionary<NSString *, NSString *> *picklistQuery = @{
      @"$select" : @"LogicalName,DisplayName,SchemaName",
      @"$expand" : @"OptionSet,GlobalOptionSet",
    };
    NSError *picklistError = nil;
    ALNDataverseResponse *picklistResponse = [client performRequestWithMethod:@"GET"
                                                                         path:picklistPath
                                                                        query:picklistQuery
                                                                      headers:nil
                                                                   bodyObject:nil
                                                       includeFormattedValues:NO
                                                         returnRepresentation:NO
                                                             consistencyCount:NO
                                                                        error:&picklistError];
    if (picklistResponse != nil) {
      NSError *picklistJSONError = nil;
      NSDictionary<NSString *, id> *picklistPayload =
          [[picklistResponse JSONObject:&picklistJSONError] isKindOfClass:[NSDictionary class]]
              ? [picklistResponse JSONObject:&picklistJSONError]
              : nil;
      NSArray *picklistAttributes = [picklistPayload[@"value"] isKindOfClass:[NSArray class]] ? picklistPayload[@"value"] : nil;
      if ([picklistAttributes count] > 0) {
        NSMutableArray *mergedAttributes =
            [NSMutableArray arrayWithArray:[payload[@"Attributes"] isKindOfClass:[NSArray class]] ? payload[@"Attributes"] : @[]];
        NSMutableDictionary<NSString *, NSDictionary *> *picklistByName = [NSMutableDictionary dictionary];
        for (NSDictionary *entry in picklistAttributes) {
          NSString *attributeName = ALNDataverseMetadataTrimmedString(entry[@"LogicalName"]);
          if ([attributeName length] > 0) {
            picklistByName[attributeName] = entry;
          }
        }
        for (NSUInteger idx = 0; idx < [mergedAttributes count]; idx++) {
          NSDictionary *attribute = mergedAttributes[idx];
          NSString *attributeName = ALNDataverseMetadataTrimmedString(attribute[@"LogicalName"]);
          NSDictionary *picklist = picklistByName[attributeName];
          if (picklist == nil) {
            continue;
          }
          NSMutableDictionary *enriched = [NSMutableDictionary dictionaryWithDictionary:attribute];
          if ([picklist[@"OptionSet"] isKindOfClass:[NSDictionary class]]) {
            enriched[@"OptionSet"] = picklist[@"OptionSet"];
          }
          if ([picklist[@"GlobalOptionSet"] isKindOfClass:[NSDictionary class]]) {
            enriched[@"GlobalOptionSet"] = picklist[@"GlobalOptionSet"];
          }
          mergedAttributes[idx] = enriched;
        }
        NSMutableDictionary *enrichedPayload = [NSMutableDictionary dictionaryWithDictionary:payload];
        enrichedPayload[@"Attributes"] = mergedAttributes;
        payload = [enrichedPayload copy];
      }
    }

    [entities addObject:payload];
  }

  return [self normalizedMetadataFromPayload:@{ @"value" : entities } error:error];
}

@end
