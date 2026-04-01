#import "ALNORMContext.h"

#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMModel.h"
#import "ALNORMQuery.h"
#import "ALNORMRelationDescriptor.h"
#import "ALNORMRepository.h"

@interface ALNORMContext ()

@property(nonatomic, strong, readwrite) id<ALNDatabaseAdapter> adapter;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *capabilityMetadata;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ALNORMRepository *> *repositoryCache;

@end

@implementation ALNORMContext

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithAdapter:nil];
}
#pragma clang diagnostic pop

- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter {
  self = [super init];
  if (self != nil) {
    if (adapter == nil) {
      return nil;
    }
    _adapter = adapter;
    _capabilityMetadata = [[[self class] capabilityMetadataForAdapter:adapter] copy] ?: @{};
    _repositoryCache = [NSMutableDictionary dictionary];
  }
  return self;
}

+ (NSDictionary<NSString *,id> *)capabilityMetadataForAdapter:(id<ALNDatabaseAdapter>)adapter {
  NSString *adapterName = [[adapter respondsToSelector:@selector(adapterName)] ? [adapter adapterName] : @""
      lowercaseString];
  BOOL sqlRuntimeSupported =
      ([adapterName isEqualToString:@"postgresql"] ||
       [adapterName isEqualToString:@"postgres"] ||
       [adapterName isEqualToString:@"mssql"]);
  BOOL reflectionSupported =
      ([adapterName isEqualToString:@"postgresql"] || [adapterName isEqualToString:@"postgres"]);
  return @{
    @"adapter_name" : adapterName ?: @"",
    @"supports_sql_runtime" : @(sqlRuntimeSupported),
    @"supports_schema_reflection" : @(reflectionSupported),
    @"supports_generated_models" : @(reflectionSupported),
    @"supports_associations" : @(sqlRuntimeSupported),
    @"supports_many_to_many" : @(sqlRuntimeSupported),
    @"supports_dataverse_orm" : @NO,
    @"boundary_note" :
        reflectionSupported ? @"SQL ORM runtime is enabled; descriptor reflection currently follows PostgreSQL metadata contracts."
                           : @"SQL ORM runtime may be usable, but schema reflection/codegen is not yet available for this adapter.",
  };
}

- (ALNORMRepository *)repositoryForModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return nil;
  }
  NSString *className = NSStringFromClass(modelClass) ?: @"";
  ALNORMRepository *existing = self.repositoryCache[className];
  if (existing != nil) {
    return existing;
  }
  ALNORMRepository *repository = [[ALNORMRepository alloc] initWithContext:self modelClass:modelClass];
  if (repository != nil) {
    self.repositoryCache[className] = repository;
  }
  return repository;
}

- (ALNORMQuery *)queryForRelationNamed:(NSString *)relationName
                             fromModel:(ALNORMModel *)model
                                 error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  if (model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"relation queries require a source model",
                               nil);
    }
    return nil;
  }

  ALNORMRelationDescriptor *relation = [model.descriptor relationNamed:relationName];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"model does not define the requested relation",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : model.descriptor.entityName ?: @"",
                               });
    }
    return nil;
  }

  Class targetClass = NSClassFromString(relation.targetClassName);
  ALNORMRepository *targetRepository = [self repositoryForModelClass:targetClass];
  if (targetRepository == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                               @"relation target class is not available",
                               @{
                                 @"target_class_name" : relation.targetClassName ?: @"",
                               });
    }
    return nil;
  }

  ALNORMQuery *query = [targetRepository query];
  if (query == nil) {
    return nil;
  }

  if (relation.kind == ALNORMRelationKindManyToMany) {
    if ([relation.sourceFieldNames count] != 1 ||
        [relation.targetFieldNames count] != 1 ||
        [relation.throughSourceFieldNames count] != 1 ||
        [relation.throughTargetFieldNames count] != 1) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorUnsupportedQueryShape,
                                 @"many-to-many relation queries currently require single-column keys",
                                 @{
                                   @"relation_name" : relation.name ?: @"",
                                 });
      }
      return nil;
    }

    Class throughClass = NSClassFromString(relation.throughClassName);
    if (throughClass == Nil || ![throughClass respondsToSelector:@selector(modelDescriptor)]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                                 @"many-to-many relation is missing its through model class",
                                 @{
                                   @"through_class_name" : relation.throughClassName ?: @"",
                                 });
      }
      return nil;
    }

    ALNORMModelDescriptor *throughDescriptor = [throughClass modelDescriptor];
    ALNORMFieldDescriptor *targetField =
        [targetRepository.descriptor fieldNamed:relation.targetFieldNames[0]];
    ALNORMFieldDescriptor *throughTargetField =
        [throughDescriptor fieldNamed:relation.throughTargetFieldNames[0]];
    ALNORMFieldDescriptor *throughSourceField =
        [throughDescriptor fieldNamed:relation.throughSourceFieldNames[0]];
    id sourceValue = [model objectForFieldName:relation.sourceFieldNames[0]];
    if (targetField == nil || throughTargetField == nil || throughSourceField == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidMetadata,
                                 @"many-to-many relation metadata is incomplete",
                                 @{
                                   @"relation_name" : relation.name ?: @"",
                                 });
      }
      return nil;
    }

    ALNSQLBuilder *subquery =
        [ALNSQLBuilder selectFrom:throughDescriptor.qualifiedTableName
                          columns:@[
                            [NSString stringWithFormat:@"%@.%@",
                                                       throughDescriptor.qualifiedTableName ?: @"",
                                                       throughTargetField.columnName ?: @""]
                          ]];
    [subquery whereField:[NSString stringWithFormat:@"%@.%@",
                                                     throughDescriptor.qualifiedTableName ?: @"",
                                                     throughSourceField.columnName ?: @""]
                operator:@"="
                   value:sourceValue];

    [query whereField:targetField.name inSubquery:subquery];
    return query;
  }

  NSUInteger pairCount = MIN([relation.sourceFieldNames count], [relation.targetFieldNames count]);
  for (NSUInteger index = 0; index < pairCount; index++) {
    NSString *sourceFieldName = relation.sourceFieldNames[index];
    NSString *targetFieldName = relation.targetFieldNames[index];
    id sourceValue = [model objectForFieldName:sourceFieldName];
    [query whereField:targetFieldName equals:sourceValue];
  }
  return query;
}

- (NSArray *)allForRelationNamed:(NSString *)relationName
                       fromModel:(ALNORMModel *)model
                           error:(NSError **)error {
  ALNORMQuery *query = [self queryForRelationNamed:relationName fromModel:model error:error];
  if (query == nil) {
    return nil;
  }
  Class targetClass = NSClassFromString([[model.descriptor relationNamed:relationName] targetClassName]);
  ALNORMRepository *repository = [self repositoryForModelClass:targetClass];
  return [repository allMatchingQuery:query error:error];
}

@end
