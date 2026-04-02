#import "ALNORMRelationDescriptor.h"

static NSString *ALNORMRelationKindFallbackName(ALNORMRelationKind kind) {
  switch (kind) {
    case ALNORMRelationKindBelongsTo:
      return @"belongs_to";
    case ALNORMRelationKindHasOne:
      return @"has_one";
    case ALNORMRelationKindHasMany:
      return @"has_many";
    case ALNORMRelationKindManyToMany:
      return @"many_to_many";
  }
  return @"belongs_to";
}

NSString *ALNORMRelationKindName(ALNORMRelationKind kind) {
  return ALNORMRelationKindFallbackName(kind);
}

ALNORMRelationKind ALNORMRelationKindFromString(NSString *value) {
  NSString *normalized = [[value isKindOfClass:[NSString class]] ? value : @""
      lowercaseString];
  if ([normalized isEqualToString:@"belongs_to"]) {
    return ALNORMRelationKindBelongsTo;
  }
  if ([normalized isEqualToString:@"has_one"]) {
    return ALNORMRelationKindHasOne;
  }
  if ([normalized isEqualToString:@"has_many"]) {
    return ALNORMRelationKindHasMany;
  }
  if ([normalized isEqualToString:@"many_to_many"]) {
    return ALNORMRelationKindManyToMany;
  }
  return ALNORMRelationKindBelongsTo;
}

@implementation ALNORMRelationDescriptor

- (instancetype)init {
  return [self initWithKind:ALNORMRelationKindBelongsTo
                       name:@""
           sourceEntityName:@""
           targetEntityName:@""
            targetClassName:@""
          throughEntityName:nil
           throughClassName:nil
           sourceFieldNames:@[]
           targetFieldNames:@[]
    throughSourceFieldNames:nil
    throughTargetFieldNames:nil
            pivotFieldNames:nil
                   readOnly:NO
                   inferred:NO];
}

- (instancetype)initWithKind:(ALNORMRelationKind)kind
                        name:(NSString *)name
            sourceEntityName:(NSString *)sourceEntityName
            targetEntityName:(NSString *)targetEntityName
             targetClassName:(NSString *)targetClassName
           throughEntityName:(NSString *)throughEntityName
            throughClassName:(NSString *)throughClassName
            sourceFieldNames:(NSArray<NSString *> *)sourceFieldNames
            targetFieldNames:(NSArray<NSString *> *)targetFieldNames
     throughSourceFieldNames:(NSArray<NSString *> *)throughSourceFieldNames
     throughTargetFieldNames:(NSArray<NSString *> *)throughTargetFieldNames
             pivotFieldNames:(NSArray<NSString *> *)pivotFieldNames
                    readOnly:(BOOL)readOnly
                    inferred:(BOOL)inferred {
  self = [super init];
  if (self != nil) {
    _kind = kind;
    _name = [name copy] ?: @"";
    _sourceEntityName = [sourceEntityName copy] ?: @"";
    _targetEntityName = [targetEntityName copy] ?: @"";
    _targetClassName = [targetClassName copy] ?: @"";
    _throughEntityName = [throughEntityName copy] ?: @"";
    _throughClassName = [throughClassName copy] ?: @"";
    _sourceFieldNames = [sourceFieldNames copy] ?: @[];
    _targetFieldNames = [targetFieldNames copy] ?: @[];
    _throughSourceFieldNames = [throughSourceFieldNames copy] ?: @[];
    _throughTargetFieldNames = [throughTargetFieldNames copy] ?: @[];
    _pivotFieldNames = [pivotFieldNames copy] ?: @[];
    _readOnly = readOnly;
    _inferred = inferred;
  }
  return self;
}

- (NSString *)kindName {
  return ALNORMRelationKindName(self.kind);
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
  return @{
    @"kind" : [self kindName],
    @"name" : self.name ?: @"",
    @"source_entity_name" : self.sourceEntityName ?: @"",
    @"target_entity_name" : self.targetEntityName ?: @"",
    @"target_class_name" : self.targetClassName ?: @"",
    @"through_entity_name" : self.throughEntityName ?: @"",
    @"through_class_name" : self.throughClassName ?: @"",
    @"source_field_names" : self.sourceFieldNames ?: @[],
    @"target_field_names" : self.targetFieldNames ?: @[],
    @"through_source_field_names" : self.throughSourceFieldNames ?: @[],
    @"through_target_field_names" : self.throughTargetFieldNames ?: @[],
    @"pivot_field_names" : self.pivotFieldNames ?: @[],
    @"read_only" : @(self.isReadOnly),
    @"inferred" : @(self.isInferred),
  };
}

@end
