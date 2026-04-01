#import "ALNORMDataverseRelationDescriptor.h"

@implementation ALNORMDataverseRelationDescriptor

- (instancetype)init {
  return [self initWithName:@""
    currentEntityLogicalName:@""
      queryEntityLogicalName:@""
         queryEntitySetName:@""
             targetClassName:@""
        sourceValueFieldName:@""
      queryFieldLogicalName:@""
      navigationPropertyName:@""
                   collection:NO
                     readOnly:NO
                     inferred:NO];
}

- (instancetype)initWithName:(NSString *)name
    currentEntityLogicalName:(NSString *)currentEntityLogicalName
      queryEntityLogicalName:(NSString *)queryEntityLogicalName
         queryEntitySetName:(NSString *)queryEntitySetName
             targetClassName:(NSString *)targetClassName
        sourceValueFieldName:(NSString *)sourceValueFieldName
          queryFieldLogicalName:(NSString *)queryFieldLogicalName
      navigationPropertyName:(NSString *)navigationPropertyName
                   collection:(BOOL)collection
                     readOnly:(BOOL)readOnly
                     inferred:(BOOL)inferred {
  self = [super init];
  if (self != nil) {
    _name = [name copy] ?: @"";
    _currentEntityLogicalName = [currentEntityLogicalName copy] ?: @"";
    _queryEntityLogicalName = [queryEntityLogicalName copy] ?: @"";
    _queryEntitySetName = [queryEntitySetName copy] ?: @"";
    _targetClassName = [targetClassName copy] ?: @"";
    _sourceValueFieldName = [sourceValueFieldName copy] ?: @"";
    _queryFieldLogicalName = [queryFieldLogicalName copy] ?: @"";
    _navigationPropertyName = [navigationPropertyName copy] ?: @"";
    _collection = collection;
    _readOnly = readOnly;
    _inferred = inferred;
  }
  return self;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
  return @{
    @"name" : self.name ?: @"",
    @"current_entity_logical_name" : self.currentEntityLogicalName ?: @"",
    @"query_entity_logical_name" : self.queryEntityLogicalName ?: @"",
    @"query_entity_set_name" : self.queryEntitySetName ?: @"",
    @"target_class_name" : self.targetClassName ?: @"",
    @"source_value_field_name" : self.sourceValueFieldName ?: @"",
    @"query_field_logical_name" : self.queryFieldLogicalName ?: @"",
    @"navigation_property_name" : self.navigationPropertyName ?: @"",
    @"collection" : @(self.isCollection),
    @"read_only" : @(self.isReadOnly),
    @"inferred" : @(self.isInferred),
  };
}

@end
