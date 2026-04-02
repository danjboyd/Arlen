#import "ALNORMRepository.h"

#import "../Data/ALNPostgresSQLBuilder.h"
#import "ALNORMContext.h"
#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMModel.h"
#import "ALNORMRelationDescriptor.h"

static NSDictionary<NSString *, id> *ALNORMRepositoryCompileBuilder(id<ALNDatabaseAdapter> adapter,
                                                                    ALNSQLBuilder *builder,
                                                                    NSError **error) {
  if (builder == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                               @"repository was given a nil SQL builder",
                               nil);
    }
    return nil;
  }
  if ([adapter respondsToSelector:@selector(sqlDialect)]) {
    id<ALNSQLDialect> dialect = [adapter sqlDialect];
    if (dialect != nil) {
      return [builder buildWithDialect:dialect error:error];
    }
  }
  return [builder build:error];
}

static NSString *ALNORMRepositorySafeIdentifierFragment(NSString *value) {
  NSMutableString *fragment = [NSMutableString string];
  for (NSUInteger index = 0; index < [value length]; index++) {
    unichar character = [value characterAtIndex:index];
    BOOL allowed = [[NSCharacterSet alphanumericCharacterSet] characterIsMember:character] || character == '_';
    [fragment appendFormat:@"%c", allowed ? (char)character : '_'];
  }
  if ([fragment length] == 0) {
    return @"rel";
  }
  unichar first = [fragment characterAtIndex:0];
  BOOL validStart = [[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_';
  if (!validStart) {
    [fragment insertString:@"r_" atIndex:0];
  }
  return fragment;
}

static NSArray *ALNORMRepositoryUniqueValues(NSArray *values) {
  NSMutableArray *ordered = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  for (id value in values ?: @[]) {
    NSString *signature = [value description] ?: @"<null>";
    if ([seen containsObject:signature]) {
      continue;
    }
    [seen addObject:signature];
    [ordered addObject:value ?: [NSNull null]];
  }
  return ordered;
}

@interface ALNORMContext (ALNORMRepositoryRuntime)
@property(nonatomic, copy, readwrite) NSArray<NSDictionary<NSString *, id> *> *queryEvents;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuerySQL:(NSString *)sql
                                                           parameters:(NSArray *)parameters
                                                            modelName:(NSString *)modelName
                                                         relationName:(nullable NSString *)relationName
                                                         loadStrategy:(ALNORMRelationLoadStrategy)loadStrategy
                                                                error:(NSError **)error;
- (NSInteger)executeCommandSQL:(NSString *)sql
                    parameters:(NSArray *)parameters
                     modelName:(NSString *)modelName
                         error:(NSError **)error;
- (nullable ALNORMModel *)trackedModelForClass:(Class)modelClass
                              primaryKeyValues:(NSDictionary<NSString *, id> *)primaryKeyValues;
- (void)trackModel:(ALNORMModel *)model;
- (void)untrackModel:(ALNORMModel *)model;
@end

@interface ALNORMRepository ()

@property(nonatomic, strong, readwrite) ALNORMContext *context;
@property(nonatomic, assign, readwrite) Class modelClass;
@property(nonatomic, strong, readwrite) ALNORMModelDescriptor *descriptor;

@end

@implementation ALNORMRepository

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithContext:nil modelClass:Nil];
}
#pragma clang diagnostic pop

- (instancetype)initWithContext:(ALNORMContext *)context
                     modelClass:(Class)modelClass {
  self = [super init];
  if (self != nil) {
    if (context == nil || modelClass == Nil || ![modelClass respondsToSelector:@selector(modelDescriptor)]) {
      return nil;
    }
    ALNORMModelDescriptor *descriptor = [modelClass modelDescriptor];
    if (![descriptor isKindOfClass:[ALNORMModelDescriptor class]]) {
      return nil;
    }
    _context = context;
    _modelClass = modelClass;
    _descriptor = descriptor;
  }
  return self;
}

- (ALNORMQuery *)query {
  return [ALNORMQuery queryWithModelClass:self.modelClass];
}

- (ALNORMQuery *)queryByApplyingScope:(ALNORMQueryScope)scope {
  ALNORMQuery *query = [self query];
  return [query applyScope:scope];
}

- (BOOL)joinedStrategyIsSupportedForRelation:(ALNORMRelationDescriptor *)relation {
  return relation != nil &&
         (relation.kind == ALNORMRelationKindBelongsTo || relation.kind == ALNORMRelationKindHasOne) &&
         [relation.sourceFieldNames count] == 1 &&
         [relation.targetFieldNames count] == 1;
}

- (ALNSQLBuilder *)selectBuilderForQuery:(ALNORMQuery *)query
                          joinedRelations:(NSArray<NSDictionary<NSString *, id> *> * __autoreleasing *)joinedRelations
                                    error:(NSError **)error {
  ALNORMQuery *resolvedQuery = query ?: [self query];
  ALNSQLBuilder *builder = [resolvedQuery selectBuilder:error];
  if (builder == nil) {
    return nil;
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *joinedPlans = [NSMutableArray array];
  NSArray<NSString *> *relationNames =
      [[resolvedQuery.relationLoadStrategies allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *relationName in relationNames) {
    ALNORMRelationLoadStrategy strategy = [resolvedQuery loadStrategyForRelationNamed:relationName];
    if (strategy != ALNORMRelationLoadStrategyJoined) {
      continue;
    }

    ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
    if (![self joinedStrategyIsSupportedForRelation:relation]) {
      continue;
    }

    Class targetClass = NSClassFromString(relation.targetClassName);
    ALNORMRepository *targetRepository = [self.context repositoryForModelClass:targetClass];
    if (targetRepository == nil) {
      continue;
    }

    ALNORMFieldDescriptor *sourceField = [self.descriptor fieldNamed:relation.sourceFieldNames[0]];
    ALNORMFieldDescriptor *targetField = [targetRepository.descriptor fieldNamed:relation.targetFieldNames[0]];
    if (sourceField == nil || targetField == nil) {
      continue;
    }

    NSString *alias =
        [NSString stringWithFormat:@"aln_rel_%@", ALNORMRepositorySafeIdentifierFragment(relation.name)];
    [builder leftJoinTable:targetRepository.descriptor.qualifiedTableName
                     alias:alias
               onLeftField:[NSString stringWithFormat:@"%@.%@",
                                                        self.descriptor.qualifiedTableName ?: @"",
                                                        sourceField.columnName ?: @""]
                  operator:@"="
              onRightField:[NSString stringWithFormat:@"%@.%@", alias, targetField.columnName ?: @""]];

    NSMutableDictionary<NSString *, NSString *> *columnAliases = [NSMutableDictionary dictionary];
    for (ALNORMFieldDescriptor *field in targetRepository.descriptor.fields ?: @[]) {
      NSString *columnAlias =
          [NSString stringWithFormat:@"%@__%@", alias, ALNORMRepositorySafeIdentifierFragment(field.columnName)];
      [builder selectExpression:@"{{table}}.{{column}}"
                          alias:columnAlias
             identifierBindings:@{
               @"table" : alias,
               @"column" : field.columnName ?: @"",
             }
                     parameters:nil];
      columnAliases[columnAlias] = field.columnName ?: @"";
    }

    [joinedPlans addObject:@{
      @"relation_name" : relation.name ?: @"",
      @"alias" : alias,
      @"repository" : targetRepository,
      @"column_aliases" : columnAliases,
    }];
  }

  if (joinedRelations != NULL) {
    *joinedRelations = [joinedPlans copy];
  }
  return builder;
}

- (NSDictionary<NSString *, id> *)compiledPlanForQuery:(ALNORMQuery *)query
                                                error:(NSError **)error {
  NSArray<NSDictionary<NSString *, id> *> *joinedRelations = nil;
  ALNSQLBuilder *builder = [self selectBuilderForQuery:query joinedRelations:&joinedRelations error:error];
  if (builder == nil) {
    return nil;
  }
  return ALNORMRepositoryCompileBuilder(self.context.adapter, builder, error);
}

- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters {
  return [self.context fieldConvertersForModelClass:self.modelClass] ?: @{};
}

- (ALNORMValueConverter *)converterForField:(ALNORMFieldDescriptor *)field {
  NSDictionary<NSString *, ALNORMValueConverter *> *converters = [self fieldConverters];
  ALNORMValueConverter *converter = converters[field.name];
  if (converter != nil) {
    return converter;
  }
  converter = converters[field.propertyName];
  if (converter != nil) {
    return converter;
  }
  return converters[field.columnName];
}

- (nullable ALNORMModel *)materializeModelFromRow:(NSDictionary<NSString *, id> *)row
                                            error:(NSError **)error {
  id model = nil;
  BOOL usesDefaultFactory =
      ([self.modelClass methodForSelector:@selector(modelFromRow:error:)] ==
       [ALNORMModel methodForSelector:@selector(modelFromRow:error:)]);
  if (usesDefaultFactory) {
    model = [[self.modelClass alloc] init];
    if ([model isKindOfClass:[ALNORMModel class]]) {
      [(ALNORMModel *)model attachToContext:self.context];
    }
    if ([model respondsToSelector:@selector(applyRow:error:)] &&
        ![model applyRow:row error:error]) {
      return nil;
    }
  } else if ([self.modelClass respondsToSelector:@selector(modelFromRow:error:)]) {
    model = [self.modelClass modelFromRow:row error:error];
  } else {
    model = [[self.modelClass alloc] init];
    if ([model respondsToSelector:@selector(applyRow:error:)] &&
        ![model applyRow:row error:error]) {
      return nil;
    }
  }
  if (![model isKindOfClass:[ALNORMModel class]]) {
    if (error != NULL && *error == nil) {
      *error = ALNORMMakeError(ALNORMErrorMaterializationFailed,
                               @"repository failed to materialize a model row",
                               @{
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return nil;
  }

  ALNORMModel *typedModel = model;
  NSDictionary<NSString *, id> *primaryKeyValues = [typedModel primaryKeyValues];
  ALNORMModel *tracked =
      [self.context trackedModelForClass:self.modelClass primaryKeyValues:primaryKeyValues];
  if (tracked != nil && tracked != typedModel) {
    if (tracked.state != ALNORMModelStateDirty) {
      [tracked applyRow:row error:nil];
    }
    [tracked attachToContext:self.context];
    return tracked;
  }

  [typedModel attachToContext:self.context];
  [self.context trackModel:typedModel];
  return typedModel;
}

- (NSArray *)uniqueModelsFromModels:(NSArray *)models {
  NSMutableArray *unique = [NSMutableArray array];
  NSHashTable *seen = [NSHashTable weakObjectsHashTable];
  for (ALNORMModel *model in models ?: @[]) {
    if ([seen containsObject:model]) {
      continue;
    }
    [seen addObject:model];
    [unique addObject:model];
  }
  return unique;
}

- (void)applyJoinedRelations:(NSArray<NSDictionary<NSString *, id> *> *)joinedRelations
                       toRow:(NSDictionary<NSString *, id> *)row
                    rootModel:(ALNORMModel *)model
                       error:(NSError **)error {
  for (NSDictionary<NSString *, id> *joinedPlan in joinedRelations ?: @[]) {
    NSString *relationName = joinedPlan[@"relation_name"];
    ALNORMRepository *targetRepository = joinedPlan[@"repository"];
    NSDictionary<NSString *, NSString *> *columnAliases = joinedPlan[@"column_aliases"];

    NSMutableDictionary<NSString *, id> *relationRow = [NSMutableDictionary dictionary];
    BOOL hasAnyValue = NO;
    for (NSString *aliasName in columnAliases) {
      id value = row[aliasName];
      if (value != nil && value != [NSNull null]) {
        hasAnyValue = YES;
      }
      relationRow[columnAliases[aliasName]] = value ?: [NSNull null];
    }

    id relationValue = nil;
    if (hasAnyValue) {
      relationValue = [targetRepository materializeModelFromRow:relationRow error:error];
      if (relationValue == nil) {
        return;
      }
    }

    if (![model markRelationLoaded:relationName value:relationValue pivotRows:nil error:error]) {
      return;
    }
  }
}

- (BOOL)preloadSimpleRelation:(ALNORMRelationDescriptor *)relation
                     strategy:(ALNORMRelationLoadStrategy)strategy
                    forModels:(NSArray<ALNORMModel *> *)models
                        error:(NSError **)error {
  if ([relation.sourceFieldNames count] != 1 || [relation.targetFieldNames count] != 1) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedQueryShape,
                               @"select-in relation loading currently requires single-column keys",
                               @{
                                 @"relation_name" : relation.name ?: @"",
                               });
    }
    return NO;
  }

  Class targetClass = NSClassFromString(relation.targetClassName);
  ALNORMRepository *targetRepository = [self.context repositoryForModelClass:targetClass];
  if (targetRepository == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                               @"relation target class is not available",
                               @{
                                 @"target_class_name" : relation.targetClassName ?: @"",
                               });
    }
    return NO;
  }

  NSString *sourceFieldName = relation.sourceFieldNames[0];
  NSString *targetFieldName = relation.targetFieldNames[0];
  NSMutableArray *sourceValues = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSMutableArray<ALNORMModel *> *> *modelsBySource = [NSMutableDictionary dictionary];
  for (ALNORMModel *model in models ?: @[]) {
    id sourceValue = [model objectForFieldName:sourceFieldName];
    if (sourceValue == nil) {
      continue;
    }
    NSString *signature = [sourceValue description] ?: @"<null>";
    if (modelsBySource[signature] == nil) {
      modelsBySource[signature] = [NSMutableArray array];
      [sourceValues addObject:sourceValue];
    }
    [modelsBySource[signature] addObject:model];
  }

  NSArray *uniqueValues = ALNORMRepositoryUniqueValues(sourceValues);
  NSMutableDictionary<NSString *, NSArray *> *relatedBySource = [NSMutableDictionary dictionary];
  if ([uniqueValues count] > 0) {
    ALNORMQuery *targetQuery = [targetRepository query];
    [targetQuery whereFieldIn:targetFieldName values:uniqueValues];
    NSArray *relatedModels = [targetRepository allMatchingQuery:targetQuery error:error];
    if (relatedModels == nil) {
      return NO;
    }

    for (ALNORMModel *relatedModel in relatedModels) {
      id targetValue = [relatedModel objectForFieldName:targetFieldName];
      NSString *signature = [targetValue description] ?: @"<null>";
      NSArray *existing = relatedBySource[signature] ?: @[];
      relatedBySource[signature] = [existing arrayByAddingObject:relatedModel];
    }
  }

  for (ALNORMModel *model in models ?: @[]) {
    id sourceValue = [model objectForFieldName:sourceFieldName];
    NSString *signature = [sourceValue description] ?: @"<null>";
    NSArray *relatedModels = relatedBySource[signature] ?: @[];
    id relationValue = nil;
    if (relation.kind == ALNORMRelationKindBelongsTo || relation.kind == ALNORMRelationKindHasOne) {
      relationValue = [relatedModels firstObject];
    } else {
      relationValue = relatedModels;
    }
    if (![model markRelationLoaded:relation.name value:relationValue pivotRows:nil error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)preloadManyToManyRelation:(ALNORMRelationDescriptor *)relation
                         strategy:(ALNORMRelationLoadStrategy)strategy
                        forModels:(NSArray<ALNORMModel *> *)models
                            error:(NSError **)error {
  if ([relation.sourceFieldNames count] != 1 ||
      [relation.targetFieldNames count] != 1 ||
      [relation.throughSourceFieldNames count] != 1 ||
      [relation.throughTargetFieldNames count] != 1) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedQueryShape,
                               @"many-to-many select-in loading currently requires single-column keys",
                               @{
                                 @"relation_name" : relation.name ?: @"",
                               });
    }
    return NO;
  }

  Class throughClass = NSClassFromString(relation.throughClassName);
  Class targetClass = NSClassFromString(relation.targetClassName);
  ALNORMRepository *throughRepository = [self.context repositoryForModelClass:throughClass];
  ALNORMRepository *targetRepository = [self.context repositoryForModelClass:targetClass];
  if (throughRepository == nil || targetRepository == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                               @"many-to-many relation repositories are unavailable",
                               @{
                                 @"relation_name" : relation.name ?: @"",
                               });
    }
    return NO;
  }

  NSMutableArray *sourceValues = [NSMutableArray array];
  for (ALNORMModel *model in models ?: @[]) {
    id value = [model objectForFieldName:relation.sourceFieldNames[0]];
    if (value != nil) {
      [sourceValues addObject:value];
    }
  }
  NSArray *uniqueSourceValues = ALNORMRepositoryUniqueValues(sourceValues);

  NSMutableDictionary<NSString *, NSArray<ALNORMModel *> *> *throughModelsBySource = [NSMutableDictionary dictionary];
  NSMutableArray *targetValues = [NSMutableArray array];
  if ([uniqueSourceValues count] > 0) {
    ALNORMQuery *throughQuery = [throughRepository query];
    [throughQuery whereFieldIn:relation.throughSourceFieldNames[0] values:uniqueSourceValues];
    NSArray *throughModels = [throughRepository allMatchingQuery:throughQuery error:error];
    if (throughModels == nil) {
      return NO;
    }

    for (ALNORMModel *throughModel in throughModels) {
      id sourceValue = [throughModel objectForFieldName:relation.throughSourceFieldNames[0]];
      id targetValue = [throughModel objectForFieldName:relation.throughTargetFieldNames[0]];
      NSString *signature = [sourceValue description] ?: @"<null>";
      NSArray *existing = throughModelsBySource[signature] ?: @[];
      throughModelsBySource[signature] = [existing arrayByAddingObject:throughModel];
      if (targetValue != nil) {
        [targetValues addObject:targetValue];
      }
    }
  }

  NSMutableDictionary<NSString *, ALNORMModel *> *targetsByValue = [NSMutableDictionary dictionary];
  NSArray *uniqueTargetValues = ALNORMRepositoryUniqueValues(targetValues);
  if ([uniqueTargetValues count] > 0) {
    ALNORMQuery *targetQuery = [targetRepository query];
    [targetQuery whereFieldIn:relation.targetFieldNames[0] values:uniqueTargetValues];
    NSArray *relatedModels = [targetRepository allMatchingQuery:targetQuery error:error];
    if (relatedModels == nil) {
      return NO;
    }
    for (ALNORMModel *relatedModel in relatedModels) {
      id targetValue = [relatedModel objectForFieldName:relation.targetFieldNames[0]];
      if (targetValue != nil) {
        targetsByValue[[targetValue description] ?: @"<null>"] = relatedModel;
      }
    }
  }

  for (ALNORMModel *model in models ?: @[]) {
    id sourceValue = [model objectForFieldName:relation.sourceFieldNames[0]];
    NSString *signature = [sourceValue description] ?: @"<null>";
    NSArray<ALNORMModel *> *throughModels = throughModelsBySource[signature] ?: @[];

    NSMutableArray *relatedModels = [NSMutableArray array];
    NSMutableArray *pivotRows = [NSMutableArray array];
    for (ALNORMModel *throughModel in throughModels) {
      id targetValue = [throughModel objectForFieldName:relation.throughTargetFieldNames[0]];
      ALNORMModel *relatedModel = targetsByValue[[targetValue description] ?: @"<null>"];
      if (relatedModel != nil) {
        [relatedModels addObject:relatedModel];
      }

      if ([relation.pivotFieldNames count] > 0) {
        NSMutableDictionary *pivotRow = [NSMutableDictionary dictionary];
        for (NSString *fieldName in relation.pivotFieldNames ?: @[]) {
          pivotRow[fieldName] = [throughModel objectForFieldName:fieldName] ?: [NSNull null];
        }
        if ([pivotRow count] > 0) {
          [pivotRows addObject:pivotRow];
        }
      }
    }

    if (![model markRelationLoaded:relation.name
                             value:relatedModels
                        pivotRows:pivotRows
                            error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)preloadRelation:(ALNORMRelationDescriptor *)relation
               strategy:(ALNORMRelationLoadStrategy)strategy
              forModels:(NSArray<ALNORMModel *> *)models
                  error:(NSError **)error {
  if (strategy == ALNORMRelationLoadStrategyNoLoad ||
      strategy == ALNORMRelationLoadStrategyRaiseOnAccess ||
      [models count] == 0) {
    for (ALNORMModel *model in models ?: @[]) {
      [model markRelationNamed:relation.name accessStrategy:strategy];
    }
    return YES;
  }

  NSMutableDictionary *event = [NSMutableDictionary dictionary];
  event[@"event_kind"] = @"relation_load";
  event[@"entity_name"] = self.descriptor.entityName ?: @"";
  event[@"relation_name"] = relation.name ?: @"";
  event[@"load_strategy"] = ALNORMRelationLoadStrategyName(strategy);
  self.context.queryEvents = [self.context.queryEvents arrayByAddingObject:event];

  if (relation.kind == ALNORMRelationKindManyToMany) {
    return [self preloadManyToManyRelation:relation strategy:strategy forModels:models error:error];
  }
  return [self preloadSimpleRelation:relation strategy:strategy forModels:models error:error];
}

- (void)applyRelationAccessPoliciesForModels:(NSArray<ALNORMModel *> *)models
                                       query:(ALNORMQuery *)query {
  NSArray<ALNORMModel *> *uniqueModels = [self uniqueModelsFromModels:models];
  for (ALNORMModel *model in uniqueModels) {
    for (ALNORMRelationDescriptor *relation in self.descriptor.relations ?: @[]) {
      if ([model isRelationLoaded:relation.name]) {
        continue;
      }
      ALNORMRelationLoadStrategy strategy = [query loadStrategyForRelationNamed:relation.name];
      if (strategy == ALNORMRelationLoadStrategyJoined &&
          ![self joinedStrategyIsSupportedForRelation:relation]) {
        strategy = ALNORMRelationLoadStrategySelectIn;
      }
      if (strategy == ALNORMRelationLoadStrategyDefault &&
          (query.isStrictLoadingEnabled || self.context.defaultStrictLoadingEnabled)) {
        strategy = ALNORMRelationLoadStrategyRaiseOnAccess;
      }
      if (strategy != ALNORMRelationLoadStrategyDefault) {
        [model markRelationNamed:relation.name accessStrategy:strategy];
      }
    }
  }
}

- (NSArray *)materializedModelsFromRows:(NSArray<NSDictionary<NSString *, id> *> *)rows
                                  query:(ALNORMQuery *)query
                         joinedRelations:(NSArray<NSDictionary<NSString *, id> *> *)joinedRelations
                                  error:(NSError **)error {
  NSMutableArray *models = [NSMutableArray arrayWithCapacity:[rows count]];
  for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
    ALNORMModel *model = [self materializeModelFromRow:row error:error];
    if (model == nil) {
      return nil;
    }
    [self applyJoinedRelations:joinedRelations toRow:row rootModel:model error:error];
    if (error != NULL && *error != nil) {
      return nil;
    }
    [models addObject:model];
  }

  NSArray<ALNORMModel *> *uniqueModels = [self uniqueModelsFromModels:models];
  for (ALNORMRelationDescriptor *relation in self.descriptor.relations ?: @[]) {
    ALNORMRelationLoadStrategy strategy = [query loadStrategyForRelationNamed:relation.name];
    if (strategy == ALNORMRelationLoadStrategyJoined &&
        ![self joinedStrategyIsSupportedForRelation:relation]) {
      strategy = ALNORMRelationLoadStrategySelectIn;
    }
    if (strategy == ALNORMRelationLoadStrategySelectIn) {
      if (![self preloadRelation:relation strategy:strategy forModels:uniqueModels error:error]) {
        return nil;
      }
    }
  }

  [self applyRelationAccessPoliciesForModels:models query:query];
  return models;
}

- (NSArray *)all:(NSError **)error {
  return [self allMatchingQuery:[self query] error:error];
}

- (NSArray *)allMatchingQuery:(ALNORMQuery *)query
                        error:(NSError **)error {
  ALNORMQuery *resolvedQuery = query ?: [self query];
  NSArray<NSDictionary<NSString *, id> *> *joinedRelations = nil;
  ALNSQLBuilder *builder = [self selectBuilderForQuery:resolvedQuery
                                        joinedRelations:&joinedRelations
                                                  error:error];
  if (builder == nil) {
    return nil;
  }
  NSDictionary<NSString *, id> *plan = ALNORMRepositoryCompileBuilder(self.context.adapter, builder, error);
  if (plan == nil) {
    return nil;
  }

  NSString *sql = [plan[@"sql"] isKindOfClass:[NSString class]] ? plan[@"sql"] : @"";
  NSArray *parameters = [plan[@"parameters"] isKindOfClass:[NSArray class]] ? plan[@"parameters"] : @[];
  NSArray<NSDictionary<NSString *, id> *> *rows =
      [self.context executeQuerySQL:sql
                         parameters:parameters
                          modelName:self.descriptor.entityName
                       relationName:nil
                       loadStrategy:ALNORMRelationLoadStrategyDefault
                              error:error];
  if (rows == nil) {
    if (error != NULL && *error == nil) {
      *error = ALNORMMakeError(ALNORMErrorQueryExecutionFailed,
                               @"repository query returned no row set",
                               @{
                                 @"sql" : sql ?: @"",
                               });
    }
    return nil;
  }

  return [self materializedModelsFromRows:rows
                                    query:resolvedQuery
                           joinedRelations:joinedRelations
                                    error:error];
}

- (id)first:(NSError **)error {
  ALNORMQuery *query = [self query];
  [query limit:1];
  return [self firstMatchingQuery:query error:error];
}

- (id)firstMatchingQuery:(ALNORMQuery *)query
                   error:(NSError **)error {
  ALNORMQuery *resolvedQuery = query ?: [self query];
  if (!resolvedQuery.hasLimit) {
    [resolvedQuery limit:1];
  }
  NSArray *models = [self allMatchingQuery:resolvedQuery error:error];
  return [models count] > 0 ? models[0] : nil;
}

- (NSUInteger)count:(NSError **)error {
  return [self countMatchingQuery:[self query] error:error];
}

- (NSUInteger)countMatchingQuery:(ALNORMQuery *)query
                           error:(NSError **)error {
  NSDictionary<NSString *, id> *plan = [self compiledPlanForQuery:query error:error];
  if (plan == nil) {
    return 0;
  }

  NSString *selectSQL = [plan[@"sql"] isKindOfClass:[NSString class]] ? plan[@"sql"] : @"";
  NSArray *parameters = [plan[@"parameters"] isKindOfClass:[NSArray class]] ? plan[@"parameters"] : @[];
  NSString *countSQL =
      [NSString stringWithFormat:@"SELECT COUNT(*) AS count_value FROM (%@) AS aln_orm_count_subquery",
                                 selectSQL ?: @""];

  NSArray<NSDictionary<NSString *, id> *> *rows =
      [self.context executeQuerySQL:countSQL
                         parameters:parameters
                          modelName:self.descriptor.entityName
                       relationName:nil
                       loadStrategy:ALNORMRelationLoadStrategyDefault
                              error:error];
  if (rows == nil) {
    return 0;
  }
  id scalar = ALNDatabaseScalarValueFromRows(rows, @"count_value", error);
  return [scalar respondsToSelector:@selector(unsignedIntegerValue)] ? [scalar unsignedIntegerValue] : 0;
}

- (BOOL)exists:(NSError **)error {
  return [self existsMatchingQuery:[self query] error:error];
}

- (BOOL)existsMatchingQuery:(ALNORMQuery *)query
                      error:(NSError **)error {
  ALNORMQuery *resolvedQuery = query ?: [self query];
  if (!resolvedQuery.hasLimit) {
    [resolvedQuery limit:1];
  }
  NSDictionary<NSString *, id> *plan = [self compiledPlanForQuery:resolvedQuery error:error];
  if (plan == nil) {
    return NO;
  }

  NSString *selectSQL = [plan[@"sql"] isKindOfClass:[NSString class]] ? plan[@"sql"] : @"";
  NSArray *parameters = [plan[@"parameters"] isKindOfClass:[NSArray class]] ? plan[@"parameters"] : @[];
  NSString *existsSQL =
      [NSString stringWithFormat:@"SELECT 1 AS exists_value FROM (%@) AS aln_orm_exists_subquery",
                                 selectSQL ?: @""];
  NSArray<NSDictionary<NSString *, id> *> *rows =
      [self.context executeQuerySQL:existsSQL
                         parameters:parameters
                          modelName:self.descriptor.entityName
                       relationName:nil
                       loadStrategy:ALNORMRelationLoadStrategyDefault
                              error:error];
  if (rows == nil) {
    return NO;
  }
  return [rows count] > 0;
}

- (id)findByPrimaryKey:(id)primaryKey
                 error:(NSError **)error {
  if ([self.descriptor.primaryKeyFieldNames count] != 1) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"findByPrimaryKey requires a single-column primary key",
                               @{
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return nil;
  }
  NSString *fieldName = self.descriptor.primaryKeyFieldNames[0];
  return [self findByPrimaryKeyValues:@{ fieldName : primaryKey ?: [NSNull null] } error:error];
}

- (id)findByPrimaryKeyValues:(NSDictionary<NSString *, id> *)primaryKeyValues
                       error:(NSError **)error {
  if ([primaryKeyValues count] == [self.descriptor.primaryKeyFieldNames count]) {
    ALNORMModel *tracked =
        [self.context trackedModelForClass:self.modelClass primaryKeyValues:primaryKeyValues];
    if (tracked != nil) {
      return tracked;
    }
  }

  ALNORMQuery *query = [self query];
  for (NSString *fieldName in self.descriptor.primaryKeyFieldNames ?: @[]) {
    id value = [primaryKeyValues isKindOfClass:[NSDictionary class]] ? primaryKeyValues[fieldName] : nil;
    if (value == [NSNull null]) {
      value = nil;
    }
    [query whereField:fieldName equals:value];
  }
  [query limit:1];
  return [self firstMatchingQuery:query error:error];
}

- (ALNORMWriteOptions *)resolvedWriteOptions:(ALNORMWriteOptions *)options {
  ALNORMWriteOptions *resolved = [[self.context defaultWriteOptionsForModelClass:self.modelClass] copy] ?: [ALNORMWriteOptions options];
  if (options == nil) {
    return resolved;
  }

  if ([options.optimisticLockFieldName length] > 0) {
    resolved.optimisticLockFieldName = options.optimisticLockFieldName;
  }
  if ([options.createdAtFieldName length] > 0) {
    resolved.createdAtFieldName = options.createdAtFieldName;
  }
  if ([options.updatedAtFieldName length] > 0) {
    resolved.updatedAtFieldName = options.updatedAtFieldName;
  }
  if ([options.conflictFieldNames count] > 0) {
    resolved.conflictFieldNames = [options.conflictFieldNames copy];
  }
  if ([options.saveRelatedRelationNames count] > 0) {
    resolved.saveRelatedRelationNames = [options.saveRelatedRelationNames copy];
  }
  if (options.timestampValue != nil) {
    resolved.timestampValue = options.timestampValue;
  }
  if (options.overwriteAllFields) {
    resolved.overwriteAllFields = YES;
  }
  return resolved;
}

- (BOOL)applyTimestampAutomationToModel:(ALNORMModel *)model
                                options:(ALNORMWriteOptions *)options
                               isInsert:(BOOL)isInsert
                                  error:(NSError **)error {
  NSDate *timestamp = options.timestampValue ?: [NSDate date];
  if (isInsert && [options.createdAtFieldName length] > 0) {
    if (![model setObject:timestamp forFieldName:options.createdAtFieldName error:error]) {
      return NO;
    }
  }
  if ([options.updatedAtFieldName length] > 0) {
    if (![model setObject:timestamp forFieldName:options.updatedAtFieldName error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)saveExplicitRelatedModelsForModel:(ALNORMModel *)model
                                  options:(ALNORMWriteOptions *)options
                                    error:(NSError **)error {
  for (NSString *relationName in options.saveRelatedRelationNames ?: @[]) {
    ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
    if (relation == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                                 @"write graph references an unknown relation",
                                 @{
                                   @"relation_name" : relationName ?: @"",
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return NO;
    }
    if (relation.kind != ALNORMRelationKindBelongsTo) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                                 @"bounded graph saves currently support only belongs-to relations",
                                 @{
                                   @"relation_name" : relation.name ?: @"",
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return NO;
    }
    if (![model isRelationLoaded:relation.name]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                                 @"explicit graph save requires the relation to be preloaded",
                                 @{
                                   @"relation_name" : relation.name ?: @"",
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return NO;
    }

    id relationValue = [model relationObjectForName:relation.name error:error];
    if (relationValue == nil) {
      continue;
    }
    if (![relationValue isKindOfClass:[ALNORMModel class]]) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                                 @"explicit graph save only supports to-one ORM model relations",
                                 @{
                                   @"relation_name" : relation.name ?: @"",
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return NO;
    }

    ALNORMModel *relatedModel = relationValue;
    ALNORMRepository *targetRepository = [self.context repositoryForModelClass:[relatedModel class]];
    if (![targetRepository saveModel:relatedModel error:error]) {
      return NO;
    }

    NSUInteger pairCount = MIN([relation.sourceFieldNames count], [relation.targetFieldNames count]);
    for (NSUInteger index = 0; index < pairCount; index++) {
      NSString *sourceFieldName = relation.sourceFieldNames[index];
      NSString *targetFieldName = relation.targetFieldNames[index];
      if (![model setObject:[relatedModel objectForFieldName:targetFieldName]
               forFieldName:sourceFieldName
                      error:error]) {
        return NO;
      }
    }
  }
  return YES;
}

- (BOOL)applyOptimisticLockToModel:(ALNORMModel *)model
                           options:(ALNORMWriteOptions *)options
                          isInsert:(BOOL)isInsert
                    currentVersion:(id __autoreleasing *)currentVersion
                             error:(NSError **)error {
  if ([options.optimisticLockFieldName length] == 0) {
    return YES;
  }

  id versionValue = [model objectForFieldName:options.optimisticLockFieldName];
  if (isInsert) {
    if (versionValue == nil) {
      versionValue = @1;
      if (![model setObject:versionValue
               forFieldName:options.optimisticLockFieldName
                      error:error]) {
        return NO;
      }
    }
    if (currentVersion != NULL) {
      *currentVersion = nil;
    }
    return YES;
  }

  if (versionValue == nil || ![versionValue respondsToSelector:@selector(integerValue)]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"optimistic locking requires a numeric version value on update",
                               @{
                                 @"field_name" : options.optimisticLockFieldName ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }
  if (currentVersion != NULL) {
    *currentVersion = versionValue;
  }
  NSNumber *nextVersion = @([versionValue integerValue] + 1);
  return [model setObject:nextVersion
             forFieldName:options.optimisticLockFieldName
                    error:error];
}

- (NSArray<NSString *> *)writableFieldNamesForModel:(ALNORMModel *)model
                                           isInsert:(BOOL)isInsert
                                   overwriteAllFields:(BOOL)overwriteAllFields {
  NSMutableArray<NSString *> *fieldNames = [NSMutableArray array];
  NSArray<NSString *> *candidateFieldNames = nil;
  if (isInsert) {
    candidateFieldNames = [[model.fieldValues allKeys] sortedArrayUsingSelector:@selector(compare:)];
  } else if (overwriteAllFields) {
    candidateFieldNames = [[model.fieldValues allKeys] sortedArrayUsingSelector:@selector(compare:)];
  } else {
    candidateFieldNames = [[model.dirtyFieldNames allObjects] sortedArrayUsingSelector:@selector(compare:)];
  }

  for (NSString *fieldName in candidateFieldNames ?: @[]) {
    ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
    if (field == nil || field.isReadOnly || field.isPrimaryKey) {
      continue;
    }
    [fieldNames addObject:field.name ?: @""];
  }
  return fieldNames;
}

- (NSDictionary<NSString *, id> *)encodedValuesForModel:(ALNORMModel *)model
                                             fieldNames:(NSArray<NSString *> *)fieldNames
                                                  error:(NSError **)error {
  NSMutableDictionary<NSString *, id> *encodedValues = [NSMutableDictionary dictionary];
  for (NSString *fieldName in fieldNames ?: @[]) {
    ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
    if (field == nil) {
      continue;
    }
    id value = [model objectForFieldName:field.name];
    ALNORMValueConverter *converter = [self converterForField:field];
    id encoded = value;
    if (converter != nil) {
      encoded = [converter encodeValue:value error:error];
      if (encoded == nil && error != NULL && *error != nil) {
        return nil;
      }
    }
    encodedValues[field.columnName] = encoded ?: [NSNull null];
  }
  return encodedValues;
}

- (BOOL)insertModel:(ALNORMModel *)model
            options:(ALNORMWriteOptions *)options
              error:(NSError **)error {
  if (![self applyTimestampAutomationToModel:model options:options isInsert:YES error:error]) {
    return NO;
  }
  if (![self saveExplicitRelatedModelsForModel:model options:options error:error]) {
    return NO;
  }
  if (![self applyOptimisticLockToModel:model
                                options:options
                               isInsert:YES
                         currentVersion:NULL
                                  error:error]) {
    return NO;
  }

  NSArray<NSString *> *fieldNames = [self writableFieldNamesForModel:model
                                                            isInsert:YES
                                                    overwriteAllFields:YES];
  NSDictionary<NSString *, id> *values = [self encodedValuesForModel:model fieldNames:fieldNames error:error];
  if (values == nil) {
    return NO;
  }
  if ([values count] == 0) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                               @"insert requires at least one writable value",
                               @{
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  ALNSQLBuilder *builder = [ALNSQLBuilder insertInto:self.descriptor.qualifiedTableName values:values];
  NSDictionary<NSString *, id> *plan = ALNORMRepositoryCompileBuilder(self.context.adapter, builder, error);
  if (plan == nil) {
    return NO;
  }

  NSInteger affected = [self.context executeCommandSQL:plan[@"sql"]
                                            parameters:plan[@"parameters"] ?: @[]
                                             modelName:self.descriptor.entityName
                                                 error:error];
  if (affected < 0) {
    if (error != NULL && *error == nil) {
      *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                               @"insert command failed",
                               @{
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  [model markClean];
  [model attachToContext:self.context];
  [self.context trackModel:model];
  return YES;
}

- (BOOL)updateModel:(ALNORMModel *)model
            options:(ALNORMWriteOptions *)options
              error:(NSError **)error {
  if (![self saveExplicitRelatedModelsForModel:model options:options error:error]) {
    return NO;
  }
  if (![self applyTimestampAutomationToModel:model options:options isInsert:NO error:error]) {
    return NO;
  }

  id currentVersion = nil;
  if (![self applyOptimisticLockToModel:model
                                options:options
                               isInsert:NO
                         currentVersion:&currentVersion
                                  error:error]) {
    return NO;
  }

  NSArray<NSString *> *fieldNames = [self writableFieldNamesForModel:model
                                                            isInsert:NO
                                                    overwriteAllFields:options.overwriteAllFields];
  if ([fieldNames count] == 0) {
    [model markClean];
    [model attachToContext:self.context];
    [self.context trackModel:model];
    return YES;
  }

  NSDictionary<NSString *, id> *values = [self encodedValuesForModel:model fieldNames:fieldNames error:error];
  if (values == nil) {
    return NO;
  }
  ALNSQLBuilder *builder = [ALNSQLBuilder updateTable:self.descriptor.qualifiedTableName values:values];
  for (NSString *fieldName in self.descriptor.primaryKeyFieldNames ?: @[]) {
    ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
    [builder whereField:field.columnName equals:[model objectForFieldName:field.name]];
  }
  if ([options.optimisticLockFieldName length] > 0) {
    ALNORMFieldDescriptor *lockField = [self.descriptor fieldNamed:options.optimisticLockFieldName];
    [builder whereField:lockField.columnName equals:currentVersion];
  }

  NSDictionary<NSString *, id> *plan = ALNORMRepositoryCompileBuilder(self.context.adapter, builder, error);
  if (plan == nil) {
    return NO;
  }

  NSInteger affected = [self.context executeCommandSQL:plan[@"sql"]
                                            parameters:plan[@"parameters"] ?: @[]
                                             modelName:self.descriptor.entityName
                                                 error:error];
  if (affected == 0 && [options.optimisticLockFieldName length] > 0) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorOptimisticLockConflict,
                               @"optimistic lock conflict prevented the update",
                               @{
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                                 @"field_name" : options.optimisticLockFieldName ?: @"",
                               });
    }
    return NO;
  }
  if (affected <= 0) {
    if (error != NULL && *error == nil) {
      *error = ALNORMMakeError(ALNORMErrorSaveFailed,
                               @"update command did not affect a row",
                               @{
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  [model markClean];
  [model attachToContext:self.context];
  [self.context trackModel:model];
  return YES;
}

- (BOOL)saveModel:(ALNORMModel *)model error:(NSError **)error {
  return [self saveModel:model changeset:nil options:nil error:error];
}

- (BOOL)saveModel:(ALNORMModel *)model
          options:(ALNORMWriteOptions *)options
            error:(NSError **)error {
  return [self saveModel:model changeset:nil options:options error:error];
}

- (BOOL)saveModel:(ALNORMModel *)model
        changeset:(ALNORMChangeset *)changeset
          options:(ALNORMWriteOptions *)options
            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"save requires a model instance",
                               nil);
    }
    return NO;
  }
  if ([model.descriptor.entityName length] == 0 ||
      ![model.descriptor.entityName isEqualToString:self.descriptor.entityName]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                               @"repository cannot save a model with a mismatched descriptor",
                               @{
                                 @"entity_name" : model.descriptor.entityName ?: @"",
                                 @"repository_entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  if (changeset != nil && ![changeset applyToModel:error]) {
    if (error != NULL && *error == nil && [changeset hasErrors]) {
      *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                               @"changeset failed validation before save",
                               @{
                                 @"field_errors" : changeset.fieldErrors ?: @{},
                               });
    }
    return NO;
  }

  ALNORMWriteOptions *resolvedOptions = [self resolvedWriteOptions:options];
  __weak typeof(self) weakSelf = self;
  return [self.context withTransactionUsingBlock:^BOOL(NSError **blockError) {
           __strong typeof(self) strongSelf = weakSelf;
           BOOL isInsert = (model.state == ALNORMModelStateNew);
           return isInsert ? [strongSelf insertModel:model options:resolvedOptions error:blockError]
                           : [strongSelf updateModel:model options:resolvedOptions error:blockError];
         }
                                      error:error];
}

- (BOOL)deleteModel:(ALNORMModel *)model error:(NSError **)error {
  return [self deleteModel:model options:nil error:error];
}

- (BOOL)deleteModel:(ALNORMModel *)model
            options:(ALNORMWriteOptions *)options
              error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"delete requires a model instance",
                               nil);
    }
    return NO;
  }

  ALNORMWriteOptions *resolvedOptions = [self resolvedWriteOptions:options];
  __weak typeof(self) weakSelf = self;
  return [self.context withTransactionUsingBlock:^BOOL(NSError **blockError) {
           __strong typeof(self) strongSelf = weakSelf;
           ALNSQLBuilder *builder = [ALNSQLBuilder deleteFrom:strongSelf.descriptor.qualifiedTableName];
           for (NSString *fieldName in strongSelf.descriptor.primaryKeyFieldNames ?: @[]) {
             ALNORMFieldDescriptor *field = [strongSelf.descriptor fieldNamed:fieldName];
             [builder whereField:field.columnName equals:[model objectForFieldName:field.name]];
           }
           if ([resolvedOptions.optimisticLockFieldName length] > 0) {
             ALNORMFieldDescriptor *lockField =
                 [strongSelf.descriptor fieldNamed:resolvedOptions.optimisticLockFieldName];
             [builder whereField:lockField.columnName
                         equals:[model objectForFieldName:lockField.name]];
           }
           NSDictionary<NSString *, id> *plan =
               ALNORMRepositoryCompileBuilder(strongSelf.context.adapter, builder, blockError);
           if (plan == nil) {
             return NO;
           }

           NSInteger affected = [strongSelf.context executeCommandSQL:plan[@"sql"]
                                                            parameters:plan[@"parameters"] ?: @[]
                                                             modelName:strongSelf.descriptor.entityName
                                                                 error:blockError];
           if (affected == 0 && [resolvedOptions.optimisticLockFieldName length] > 0) {
             if (blockError != NULL) {
               *blockError = ALNORMMakeError(ALNORMErrorOptimisticLockConflict,
                                             @"optimistic lock conflict prevented the delete",
                                             @{
                                               @"entity_name" : strongSelf.descriptor.entityName ?: @"",
                                               @"field_name" : resolvedOptions.optimisticLockFieldName ?: @"",
                                             });
             }
             return NO;
           }
           if (affected <= 0) {
             if (blockError != NULL && *blockError == nil) {
               *blockError = ALNORMMakeError(ALNORMErrorDeleteFailed,
                                             @"delete command did not affect a row",
                                             @{
                                               @"entity_name" : strongSelf.descriptor.entityName ?: @"",
                                             });
             }
             return NO;
           }

           [strongSelf.context untrackModel:model];
           [model markDetached];
           return YES;
         }
                                      error:error];
}

- (BOOL)upsertModel:(ALNORMModel *)model
             options:(ALNORMWriteOptions *)options
               error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"upsert requires a model instance",
                               nil);
    }
    return NO;
  }

  BOOL supportsUpsert =
      [self.context.capabilityMetadata[@"supports_upsert"] respondsToSelector:@selector(boolValue)] &&
      [self.context.capabilityMetadata[@"supports_upsert"] boolValue];
  NSString *adapterName = [self.context.capabilityMetadata[@"adapter_name"] isKindOfClass:[NSString class]]
                              ? self.context.capabilityMetadata[@"adapter_name"]
                              : @"";
  BOOL usesPostgresConflictMode =
      [adapterName isEqualToString:@"postgresql"] || [adapterName isEqualToString:@"postgres"];
  if (!supportsUpsert || !usesPostgresConflictMode) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUpsertFailed,
                               @"adapter does not support ORM upsert helpers",
                               @{
                                 @"adapter_name" : adapterName ?: @"",
                               });
    }
    return NO;
  }

  ALNORMWriteOptions *resolvedOptions = [self resolvedWriteOptions:options];
  __weak typeof(self) weakSelf = self;
  return [self.context withTransactionUsingBlock:^BOOL(NSError **blockError) {
           __strong typeof(self) strongSelf = weakSelf;
           if (![strongSelf saveExplicitRelatedModelsForModel:model options:resolvedOptions error:blockError]) {
             return NO;
           }
           if (![strongSelf applyTimestampAutomationToModel:model
                                                   options:resolvedOptions
                                                  isInsert:(model.state == ALNORMModelStateNew)
                                                     error:blockError]) {
             return NO;
           }
           if (![strongSelf applyOptimisticLockToModel:model
                                               options:resolvedOptions
                                              isInsert:(model.state == ALNORMModelStateNew)
                                        currentVersion:NULL
                                                 error:blockError]) {
             return NO;
           }

           NSMutableArray<NSString *> *fieldNames = [NSMutableArray array];
           for (NSString *fieldName in [[model.fieldValues allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
             ALNORMFieldDescriptor *field = [strongSelf.descriptor fieldNamed:fieldName];
             if (field != nil && !field.isReadOnly) {
               [fieldNames addObject:field.name ?: @""];
             }
           }
           NSDictionary<NSString *, id> *values =
               [strongSelf encodedValuesForModel:model fieldNames:fieldNames error:blockError];
           if (values == nil) {
             return NO;
           }

           ALNPostgresSQLBuilder *builder =
               [ALNPostgresSQLBuilder insertInto:strongSelf.descriptor.qualifiedTableName values:values];
           NSArray<NSString *> *conflictFieldNames =
               ([resolvedOptions.conflictFieldNames count] > 0)
                   ? resolvedOptions.conflictFieldNames
                   : strongSelf.descriptor.primaryKeyFieldNames;
           NSMutableArray<NSString *> *conflictColumns = [NSMutableArray array];
           for (NSString *fieldName in conflictFieldNames ?: @[]) {
             ALNORMFieldDescriptor *field = [strongSelf.descriptor fieldNamed:fieldName];
             if (field != nil) {
               [conflictColumns addObject:field.columnName ?: @""];
             }
           }

           NSMutableArray<NSString *> *updateColumns = [NSMutableArray array];
           NSSet *conflictColumnSet = [NSSet setWithArray:conflictColumns ?: @[]];
           for (NSString *columnName in [[values allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
             if (![conflictColumnSet containsObject:columnName] &&
                 ![columnName isEqualToString:[strongSelf.descriptor fieldNamed:resolvedOptions.createdAtFieldName].columnName]) {
               [updateColumns addObject:columnName];
             }
           }
           if ([updateColumns count] > 0) {
             [builder onConflictColumns:conflictColumns doUpdateSetFields:updateColumns];
           } else {
             [builder onConflictDoNothing];
           }

           NSDictionary<NSString *, id> *plan =
               ALNORMRepositoryCompileBuilder(strongSelf.context.adapter, builder, blockError);
           if (plan == nil) {
             return NO;
           }

           NSInteger affected = [strongSelf.context executeCommandSQL:plan[@"sql"]
                                                            parameters:plan[@"parameters"] ?: @[]
                                                             modelName:strongSelf.descriptor.entityName
                                                                 error:blockError];
           if (affected < 0) {
             if (blockError != NULL && *blockError == nil) {
               *blockError = ALNORMMakeError(ALNORMErrorUpsertFailed,
                                             @"upsert command failed",
                                             @{
                                               @"entity_name" : strongSelf.descriptor.entityName ?: @"",
                                             });
             }
             return NO;
           }

           [model markClean];
           [model attachToContext:strongSelf.context];
           [strongSelf.context trackModel:model];
           return YES;
         }
                                      error:error];
}

@end
