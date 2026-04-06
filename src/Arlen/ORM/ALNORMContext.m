#import "ALNORMContext.h"

#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMModel.h"
#import "ALNORMQuery.h"
#import "ALNORMRelationDescriptor.h"
#import "ALNORMRepository.h"

static NSString *ALNORMContextClassKey(Class modelClass) {
  return NSStringFromClass(modelClass) ?: @"";
}

static NSString *ALNORMContextStableValueDescription(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"<null>";
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  return [value description] ?: @"";
}

static NSString *ALNORMContextIdentityKey(NSString *classKey,
                                          NSDictionary<NSString *, id> *primaryKeyValues) {
  NSArray<NSString *> *sortedKeys =
      [[primaryKeyValues allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[sortedKeys count] + 1];
  [parts addObject:classKey ?: @""];
  for (NSString *key in sortedKeys) {
    [parts addObject:[NSString stringWithFormat:@"%@=%@",
                                                key ?: @"",
                                                ALNORMContextStableValueDescription(primaryKeyValues[key])]];
  }
  return [parts componentsJoinedByString:@"|"];
}

@interface ALNORMContext ()

@property(nonatomic, strong, readwrite) id<ALNDatabaseAdapter> adapter;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *capabilityMetadata;
@property(nonatomic, assign, readwrite, getter=isIdentityTrackingEnabled) BOOL identityTrackingEnabled;
@property(nonatomic, assign, readwrite) NSUInteger queryCount;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary<NSString *, id> *> *queryEvents;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ALNORMRepository *> *repositoryCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, ALNORMValueConverter *> *> *fieldConverterRegistry;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ALNORMWriteOptions *> *defaultWriteOptionsRegistry;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ALNORMModel *> *identityMap;
@property(nonatomic, weak) id<ALNDatabaseConnection> activeConnection;
@property(nonatomic, assign) NSUInteger transactionDepth;
@property(nonatomic, assign) NSUInteger savepointSequence;

@end

@interface ALNORMContext (ALNORMRepositoryRuntime)
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
- (nullable NSDictionary<NSString *, id> *)executeCommandReturningOneSQL:(NSString *)sql
                                                               parameters:(NSArray *)parameters
                                                                modelName:(NSString *)modelName
                                                                    error:(NSError **)error;
- (nullable ALNORMModel *)trackedModelForClass:(Class)modelClass
                              primaryKeyValues:(NSDictionary<NSString *, id> *)primaryKeyValues;
- (void)trackModel:(ALNORMModel *)model;
- (void)untrackModel:(ALNORMModel *)model;
@end

@implementation ALNORMContext

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithAdapter:nil identityTrackingEnabled:YES];
}
#pragma clang diagnostic pop

- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter {
  return [self initWithAdapter:adapter identityTrackingEnabled:YES];
}

- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter
         identityTrackingEnabled:(BOOL)identityTrackingEnabled {
  self = [super init];
  if (self != nil) {
    if (adapter == nil) {
      return nil;
    }
    _adapter = adapter;
    _identityTrackingEnabled = identityTrackingEnabled;
    _defaultStrictLoadingEnabled = NO;
    _queryCount = 0;
    _queryEvents = @[];
    _capabilityMetadata = [[[self class] capabilityMetadataForAdapter:adapter] copy] ?: @{};
    _repositoryCache = [NSMutableDictionary dictionary];
    _fieldConverterRegistry = [NSMutableDictionary dictionary];
    _defaultWriteOptionsRegistry = [NSMutableDictionary dictionary];
    _identityMap = [NSMutableDictionary dictionary];
    _transactionDepth = 0;
    _savepointSequence = 0;
  }
  return self;
}

+ (NSDictionary<NSString *, id> *)capabilityMetadataForAdapter:(id<ALNDatabaseAdapter>)adapter {
  NSString *adapterName =
      [[[adapter respondsToSelector:@selector(adapterName)] ? [adapter adapterName] : @"" lowercaseString]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSDictionary<NSString *, id> *adapterCapabilities =
      [adapter respondsToSelector:@selector(capabilityMetadata)] ? [adapter capabilityMetadata] : @{};

  BOOL sqlRuntimeSupported =
      ([adapterCapabilities[@"supports_sql_runtime"] respondsToSelector:@selector(boolValue)]
           ? [adapterCapabilities[@"supports_sql_runtime"] boolValue]
           : ([adapterName isEqualToString:@"postgresql"] ||
              [adapterName isEqualToString:@"postgres"] ||
              [adapterName isEqualToString:@"mssql"]));
  BOOL reflectionSupported =
      ([adapterCapabilities[@"supports_schema_reflection"] respondsToSelector:@selector(boolValue)]
           ? [adapterCapabilities[@"supports_schema_reflection"] boolValue]
           : ([adapterName isEqualToString:@"postgresql"] || [adapterName isEqualToString:@"postgres"]));
  BOOL savepointsSupported =
      ([adapterCapabilities[@"supports_savepoints"] respondsToSelector:@selector(boolValue)]
           ? [adapterCapabilities[@"supports_savepoints"] boolValue]
           : sqlRuntimeSupported);
  BOOL upsertSupported =
      ([adapterCapabilities[@"supports_upsert"] respondsToSelector:@selector(boolValue)]
           ? [adapterCapabilities[@"supports_upsert"] boolValue]
           : [adapterName isEqualToString:@"postgresql"] || [adapterName isEqualToString:@"postgres"]);

  NSMutableDictionary<NSString *, id> *metadata =
      [NSMutableDictionary dictionaryWithDictionary:adapterCapabilities ?: @{}];
  metadata[@"adapter_name"] = adapterName ?: @"";
  metadata[@"supports_sql_runtime"] = @(sqlRuntimeSupported);
  metadata[@"supports_schema_reflection"] = @(reflectionSupported);
  metadata[@"supports_generated_models"] = @(reflectionSupported);
  metadata[@"supports_associations"] = @(sqlRuntimeSupported);
  metadata[@"supports_many_to_many"] = @(sqlRuntimeSupported);
  metadata[@"supports_dataverse_orm"] = @NO;
  metadata[@"supports_strict_loading"] = @YES;
  metadata[@"supports_query_budget_guards"] = @YES;
  metadata[@"supports_unit_of_work"] = @YES;
  metadata[@"supports_identity_map"] = @YES;
  metadata[@"supports_savepoints"] = @(savepointsSupported);
  metadata[@"supports_optimistic_locking"] = @(sqlRuntimeSupported);
  metadata[@"supports_upsert"] = @(upsertSupported);
  if (![[metadata[@"returning_mode"] description] length]) {
    if ([adapterName isEqualToString:@"postgresql"] || [adapterName isEqualToString:@"postgres"]) {
      metadata[@"returning_mode"] = @"returning";
    } else if ([adapterName isEqualToString:@"mssql"]) {
      metadata[@"returning_mode"] = @"output";
    }
  }
  if (metadata[@"boundary_note"] == nil) {
    metadata[@"boundary_note"] =
        reflectionSupported ? @"SQL ORM runtime is enabled; descriptor reflection currently follows PostgreSQL metadata contracts."
                            : @"SQL ORM runtime may be usable, but schema reflection/codegen is not yet available for this adapter.";
  }
  return metadata;
}

- (nullable ALNORMRepository *)repositoryForModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return nil;
  }
  NSString *className = ALNORMContextClassKey(modelClass);
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

- (void)registerFieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                  forModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return;
  }
  self.fieldConverterRegistry[ALNORMContextClassKey(modelClass)] = [fieldConverters copy] ?: @{};
}

- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return @{};
  }
  return self.fieldConverterRegistry[ALNORMContextClassKey(modelClass)] ?: @{};
}

- (void)registerDefaultWriteOptions:(ALNORMWriteOptions *)writeOptions
                      forModelClass:(Class)modelClass {
  if (modelClass == Nil || writeOptions == nil) {
    return;
  }
  self.defaultWriteOptionsRegistry[ALNORMContextClassKey(modelClass)] = [writeOptions copy];
}

- (nullable ALNORMWriteOptions *)defaultWriteOptionsForModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return nil;
  }
  return [self.defaultWriteOptionsRegistry[ALNORMContextClassKey(modelClass)] copy];
}

- (void)resetTracking {
  for (ALNORMModel *model in [self.identityMap allValues]) {
    [model markDetached];
  }
  [self.identityMap removeAllObjects];
  self.queryCount = 0;
  self.queryEvents = @[];
}

- (void)detachModel:(ALNORMModel *)model {
  if (model == nil) {
    return;
  }
  [self untrackModel:model];
  [model markDetached];
}

- (nullable ALNORMModel *)reloadModel:(ALNORMModel *)model
                                error:(NSError **)error {
  if (model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"reload requires a model instance",
                               nil);
    }
    return nil;
  }
  NSDictionary<NSString *, id> *primaryKeyValues = [model primaryKeyValues];
  if ([primaryKeyValues count] != [model.descriptor.primaryKeyFieldNames count]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"reload requires a complete primary key",
                               @{
                                 @"entity_name" : model.descriptor.entityName ?: @"",
                               });
    }
    return nil;
  }

  ALNORMRepository *repository = [self repositoryForModelClass:[model class]];
  ALNORMQuery *query = [repository query];
  for (NSString *fieldName in model.descriptor.primaryKeyFieldNames ?: @[]) {
    [query whereField:fieldName equals:primaryKeyValues[fieldName]];
  }
  [query limit:1];

  NSDictionary<NSString *, id> *plan = [repository compiledPlanForQuery:query error:error];
  if (plan == nil) {
    return nil;
  }
  NSString *sql = [plan[@"sql"] isKindOfClass:[NSString class]] ? plan[@"sql"] : @"";
  NSArray *parameters = [plan[@"parameters"] isKindOfClass:[NSArray class]] ? plan[@"parameters"] : @[];
  NSArray<NSDictionary<NSString *, id> *> *rows = [self executeQuerySQL:sql
                                                             parameters:parameters
                                                              modelName:model.descriptor.entityName
                                                           relationName:nil
                                                           loadStrategy:ALNORMRelationLoadStrategyDefault
                                                                  error:error];
  NSDictionary<NSString *, id> *row = [rows firstObject];
  if (row == nil) {
    return nil;
  }
  if (![model applyRow:row error:error]) {
    return nil;
  }
  [model attachToContext:self];
  [self trackModel:model];
  return model;
}

- (BOOL)withTransactionUsingBlock:(ALNORMContextBlock)block
                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (block == nil) {
    return YES;
  }

  if (self.activeConnection != nil) {
    NSString *nestedName = [NSString stringWithFormat:@"aln_orm_nested_%lu",
                                                      (unsigned long)(++self.savepointSequence)];
    return [self withSavepointNamed:nestedName usingBlock:block error:error];
  }

  __block BOOL outerResult = NO;
  __weak typeof(self) weakSelf = self;
  BOOL transactionResult =
      [self.adapter withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection, NSError **blockError) {
        __strong typeof(self) strongSelf = weakSelf;
        strongSelf.activeConnection = connection;
        strongSelf.transactionDepth = 1;
        BOOL result = block(blockError);
        strongSelf.transactionDepth = 0;
        strongSelf.activeConnection = nil;
        outerResult = result;
        return result;
      }
                                 error:error];
  return transactionResult && outerResult;
}

- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(ALNORMContextBlock)block
                     error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (block == nil) {
    return YES;
  }
  if (self.activeConnection == nil) {
    return [self withTransactionUsingBlock:block error:error];
  }

  NSString *savepointName = [name length] > 0
                                ? name
                                : [NSString stringWithFormat:@"aln_orm_savepoint_%lu",
                                                             (unsigned long)(++self.savepointSequence)];
  if (!ALNDatabaseConnectionSupportsSavepoints(self.activeConnection)) {
    return block(error);
  }

  self.transactionDepth += 1;
  BOOL result = ALNDatabaseWithSavepoint(self.activeConnection,
                                         savepointName,
                                         ^BOOL(NSError **innerError) {
                                           return block(innerError);
                                         },
                                         error);
  self.transactionDepth -= 1;
  return result;
}

- (BOOL)withQueryBudget:(NSUInteger)maximum
             usingBlock:(ALNORMContextBlock)block
                  error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (block == nil) {
    return YES;
  }

  NSUInteger startingQueryCount = self.queryCount;
  BOOL result = block(error);
  if (!result) {
    return NO;
  }

  NSUInteger used = self.queryCount - startingQueryCount;
  if (used > maximum) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorQueryBudgetExceeded,
                               @"query budget exceeded during ORM operation",
                               @{
                                 @"query_budget" : @(maximum),
                                 @"query_count" : @(used),
                               });
    }
    return NO;
  }
  return YES;
}

- (nullable ALNORMQuery *)queryForRelationNamed:(NSString *)relationName
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
    ALNORMFieldDescriptor *targetField = [targetRepository.descriptor fieldNamed:relation.targetFieldNames[0]];
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

- (nullable NSArray<NSDictionary<NSString *, id> *> *)pivotRowsForManyToManyRelation:(ALNORMRelationDescriptor *)relation
                                                                            fromModel:(ALNORMModel *)model
                                                                                error:(NSError **)error {
  Class throughClass = NSClassFromString(relation.throughClassName);
  ALNORMRepository *throughRepository = [self repositoryForModelClass:throughClass];
  if (throughRepository == nil || [relation.throughSourceFieldNames count] != 1) {
    return @[];
  }

  ALNORMQuery *throughQuery = [throughRepository query];
  [throughQuery whereField:relation.throughSourceFieldNames[0]
                    equals:[model objectForFieldName:relation.sourceFieldNames[0]]];
  NSArray *throughModels = [throughRepository allMatchingQuery:throughQuery error:error];
  if (throughModels == nil) {
    return nil;
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *pivotRows = [NSMutableArray array];
  for (ALNORMModel *throughModel in throughModels) {
    NSMutableDictionary<NSString *, id> *pivotRow = [NSMutableDictionary dictionary];
    for (NSString *fieldName in relation.pivotFieldNames ?: @[]) {
      id value = [throughModel objectForFieldName:fieldName];
      pivotRow[fieldName] = value ?: [NSNull null];
    }
    if ([pivotRow count] > 0) {
      [pivotRows addObject:pivotRow];
    }
  }
  return pivotRows;
}

- (BOOL)loadRelationNamed:(NSString *)relationName
                fromModel:(ALNORMModel *)model
                 strategy:(ALNORMRelationLoadStrategy)strategy
                    error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"relation loading requires a model instance",
                               nil);
    }
    return NO;
  }

  ALNORMRelationDescriptor *relation = [model.descriptor relationNamed:relationName];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"requested relation is not defined on the model",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : model.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  if (strategy == ALNORMRelationLoadStrategyNoLoad ||
      strategy == ALNORMRelationLoadStrategyRaiseOnAccess) {
    [model markRelationNamed:relation.name accessStrategy:strategy];
    return YES;
  }

  ALNORMQuery *query = [self queryForRelationNamed:relation.name fromModel:model error:error];
  if (query == nil) {
    return NO;
  }
  Class targetClass = NSClassFromString(relation.targetClassName);
  ALNORMRepository *repository = [self repositoryForModelClass:targetClass];
  NSArray *results = [repository allMatchingQuery:query error:error];
  if (results == nil) {
    return NO;
  }

  id value = nil;
  if (relation.kind == ALNORMRelationKindBelongsTo ||
      relation.kind == ALNORMRelationKindHasOne) {
    value = [results firstObject];
  } else {
    value = results ?: @[];
  }

  NSArray<NSDictionary<NSString *, id> *> *pivotRows = nil;
  if (relation.kind == ALNORMRelationKindManyToMany && [relation.pivotFieldNames count] > 0) {
    pivotRows = [self pivotRowsForManyToManyRelation:relation fromModel:model error:error];
    if (pivotRows == nil && error != NULL && *error != nil) {
      return NO;
    }
  }

  if (![model markRelationLoaded:relation.name value:value pivotRows:pivotRows error:error]) {
    return NO;
  }

  NSMutableDictionary *event = [NSMutableDictionary dictionary];
  event[@"event_kind"] = @"relation_load";
  event[@"entity_name"] = model.descriptor.entityName ?: @"";
  event[@"relation_name"] = relation.name ?: @"";
  event[@"load_strategy"] = ALNORMRelationLoadStrategyName(strategy);
  self.queryEvents = [self.queryEvents arrayByAddingObject:event];
  return YES;
}

- (nullable NSArray *)allForRelationNamed:(NSString *)relationName
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

- (void)appendQueryEvent:(NSDictionary<NSString *, id> *)event
             countAsQuery:(BOOL)countAsQuery {
  if (countAsQuery) {
    self.queryCount += 1;
  }
  self.queryEvents = [self.queryEvents arrayByAddingObject:event ?: @{}];
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuerySQL:(NSString *)sql
                                                           parameters:(NSArray *)parameters
                                                            modelName:(NSString *)modelName
                                                         relationName:(NSString *)relationName
                                                         loadStrategy:(ALNORMRelationLoadStrategy)loadStrategy
                                                                error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  NSMutableDictionary *event = [NSMutableDictionary dictionary];
  event[@"event_kind"] = @"sql_query";
  event[@"sql"] = sql ?: @"";
  event[@"parameters"] = parameters ?: @[];
  event[@"entity_name"] = modelName ?: @"";
  if ([relationName length] > 0) {
    event[@"relation_name"] = relationName;
    event[@"load_strategy"] = ALNORMRelationLoadStrategyName(loadStrategy);
  }
  [self appendQueryEvent:event countAsQuery:YES];

  if (self.activeConnection != nil) {
    return [self.activeConnection executeQuery:sql parameters:parameters ?: @[] error:error];
  }
  return [self.adapter executeQuery:sql parameters:parameters ?: @[] error:error];
}

- (NSInteger)executeCommandSQL:(NSString *)sql
                    parameters:(NSArray *)parameters
                     modelName:(NSString *)modelName
                         error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  [self appendQueryEvent:@{
    @"event_kind" : @"sql_command",
    @"sql" : sql ?: @"",
    @"parameters" : parameters ?: @[],
    @"entity_name" : modelName ?: @"",
  }
             countAsQuery:YES];

  if (self.activeConnection != nil) {
    return [self.activeConnection executeCommand:sql parameters:parameters ?: @[] error:error];
  }
  return [self.adapter executeCommand:sql parameters:parameters ?: @[] error:error];
}

- (nullable NSDictionary<NSString *, id> *)executeCommandReturningOneSQL:(NSString *)sql
                                                               parameters:(NSArray *)parameters
                                                                modelName:(NSString *)modelName
                                                                    error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  [self appendQueryEvent:@{
    @"event_kind" : @"sql_command",
    @"sql" : sql ?: @"",
    @"parameters" : parameters ?: @[],
    @"entity_name" : modelName ?: @"",
    @"result_mode" : @"returning_one",
  }
             countAsQuery:YES];

  if (self.activeConnection != nil) {
    if ([self.activeConnection respondsToSelector:@selector(executeQueryOne:parameters:error:)]) {
      return [self.activeConnection executeQueryOne:sql parameters:parameters ?: @[] error:error];
    }
    return ALNDatabaseFirstRow([self.activeConnection executeQuery:sql
                                                        parameters:parameters ?: @[]
                                                             error:error]);
  }
  return ALNDatabaseFirstRow([self.adapter executeQuery:sql
                                             parameters:parameters ?: @[]
                                                  error:error]);
}

- (nullable ALNORMModel *)trackedModelForClass:(Class)modelClass
                              primaryKeyValues:(NSDictionary<NSString *, id> *)primaryKeyValues {
  if (!self.identityTrackingEnabled || modelClass == Nil || [primaryKeyValues count] == 0) {
    return nil;
  }
  return self.identityMap[ALNORMContextIdentityKey(ALNORMContextClassKey(modelClass), primaryKeyValues)];
}

- (void)trackModel:(ALNORMModel *)model {
  if (model == nil) {
    return;
  }
  [model attachToContext:self];
  if (!self.identityTrackingEnabled) {
    return;
  }
  NSDictionary<NSString *, id> *primaryKeyValues = [model primaryKeyValues];
  if ([primaryKeyValues count] == 0 ||
      [primaryKeyValues count] != [model.descriptor.primaryKeyFieldNames count]) {
    return;
  }
  NSString *key = ALNORMContextIdentityKey(ALNORMContextClassKey([model class]), primaryKeyValues);
  self.identityMap[key] = model;
}

- (void)untrackModel:(ALNORMModel *)model {
  if (!self.identityTrackingEnabled || model == nil) {
    return;
  }
  NSDictionary<NSString *, id> *primaryKeyValues = [model primaryKeyValues];
  if ([primaryKeyValues count] == 0) {
    return;
  }
  [self.identityMap removeObjectForKey:ALNORMContextIdentityKey(ALNORMContextClassKey([model class]),
                                                                primaryKeyValues)];
}

@end
