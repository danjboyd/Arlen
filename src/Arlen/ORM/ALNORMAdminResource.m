#import "ALNORMAdminResource.h"

#import "ALNORMFieldDescriptor.h"
#import "ALNORMModelDescriptor.h"

static NSArray<NSString *> *ALNORMAdminResourceSelectableFields(ALNORMModelDescriptor *descriptor,
                                                                BOOL includePrimaryKeyFallback) {
  NSMutableArray<NSString *> *fieldNames = [NSMutableArray array];
  for (ALNORMFieldDescriptor *field in descriptor.fields ?: @[]) {
    if ([field.runtimeClassName isEqualToString:@"NSString"] && !field.isReadOnly) {
      [fieldNames addObject:field.name ?: @""];
    }
  }
  if ([fieldNames count] == 0 && includePrimaryKeyFallback) {
    [fieldNames addObjectsFromArray:descriptor.primaryKeyFieldNames ?: @[]];
  }
  return [NSArray arrayWithArray:fieldNames];
}

@implementation ALNORMAdminResource

- (instancetype)init {
  return [self initWithResourceName:@""
                     modelClassName:@""
                         entityName:@""
                     titleFieldName:@""
               searchableFieldNames:@[]
                 sortableFieldNames:@[]
                           readOnly:NO];
}

+ (instancetype)resourceForModelClass:(Class)modelClass {
  if (modelClass == Nil || ![modelClass respondsToSelector:@selector(modelDescriptor)]) {
    return nil;
  }
  ALNORMModelDescriptor *descriptor = [modelClass modelDescriptor];
  if (![descriptor isKindOfClass:[ALNORMModelDescriptor class]]) {
    return nil;
  }

  NSString *titleFieldName = nil;
  for (ALNORMFieldDescriptor *field in descriptor.fields ?: @[]) {
    if ([field.name isEqualToString:@"name"] || [field.name isEqualToString:@"title"] ||
        [field.name isEqualToString:@"displayName"]) {
      titleFieldName = field.name;
      break;
    }
  }
  if ([titleFieldName length] == 0) {
    titleFieldName = [descriptor.primaryKeyFieldNames firstObject] ?: @"";
  }

  NSArray<NSString *> *searchable = ALNORMAdminResourceSelectableFields(descriptor, YES);
  NSArray<NSString *> *sortable = [descriptor allFieldNames];
  NSString *resourceName = [[descriptor.tableName length] > 0 ? descriptor.tableName : descriptor.entityName copy];
  return [[self alloc] initWithResourceName:resourceName
                             modelClassName:NSStringFromClass(modelClass) ?: @""
                                 entityName:descriptor.entityName ?: @""
                             titleFieldName:titleFieldName ?: @""
                       searchableFieldNames:searchable
                         sortableFieldNames:sortable
                                   readOnly:descriptor.isReadOnly];
}

- (instancetype)initWithResourceName:(NSString *)resourceName
                      modelClassName:(NSString *)modelClassName
                          entityName:(NSString *)entityName
                      titleFieldName:(NSString *)titleFieldName
                searchableFieldNames:(NSArray<NSString *> *)searchableFieldNames
                  sortableFieldNames:(NSArray<NSString *> *)sortableFieldNames
                            readOnly:(BOOL)readOnly {
  self = [super init];
  if (self != nil) {
    _resourceName = [resourceName copy] ?: @"";
    _modelClassName = [modelClassName copy] ?: @"";
    _entityName = [entityName copy] ?: @"";
    _titleFieldName = [titleFieldName copy] ?: @"";
    _searchableFieldNames = [searchableFieldNames copy] ?: @[];
    _sortableFieldNames = [sortableFieldNames copy] ?: @[];
    _readOnly = readOnly;
  }
  return self;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
  return @{
    @"resource_name" : self.resourceName ?: @"",
    @"model_class_name" : self.modelClassName ?: @"",
    @"entity_name" : self.entityName ?: @"",
    @"title_field_name" : self.titleFieldName ?: @"",
    @"searchable_field_names" : self.searchableFieldNames ?: @[],
    @"sortable_field_names" : self.sortableFieldNames ?: @[],
    @"read_only" : @(self.isReadOnly),
  };
}

@end
