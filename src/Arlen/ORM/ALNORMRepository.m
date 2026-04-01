#import "ALNORMRepository.h"

#import "ALNORMContext.h"
#import "ALNORMErrors.h"
#import "ALNORMModel.h"

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

- (NSDictionary<NSString *,id> *)compiledPlanForQuery:(ALNORMQuery *)query
                                                error:(NSError **)error {
  ALNORMQuery *resolvedQuery = query ?: [self query];
  ALNSQLBuilder *builder = [resolvedQuery selectBuilder:error];
  if (builder == nil) {
    return nil;
  }
  return ALNORMRepositoryCompileBuilder(self.context.adapter, builder, error);
}

- (NSArray *)materializedModelsFromRows:(NSArray<NSDictionary<NSString *, id> *> *)rows
                                  error:(NSError **)error {
  NSMutableArray *models = [NSMutableArray arrayWithCapacity:[rows count]];
  for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
    id model = nil;
    if ([self.modelClass respondsToSelector:@selector(modelFromRow:error:)]) {
      model = [self.modelClass modelFromRow:row error:error];
    } else {
      model = [[self.modelClass alloc] init];
      if ([model respondsToSelector:@selector(applyRow:error:)]) {
        BOOL applied = [model applyRow:row error:error];
        if (!applied) {
          return nil;
        }
      }
    }
    if (model == nil) {
      if (error != NULL && *error == nil) {
        *error = ALNORMMakeError(ALNORMErrorMaterializationFailed,
                                 @"repository failed to materialize a model row",
                                 @{
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return nil;
    }
    [models addObject:model];
  }
  return models;
}

- (NSArray *)all:(NSError **)error {
  return [self allMatchingQuery:[self query] error:error];
}

- (NSArray *)allMatchingQuery:(ALNORMQuery *)query
                        error:(NSError **)error {
  NSDictionary<NSString *, id> *plan = [self compiledPlanForQuery:query error:error];
  if (plan == nil) {
    return nil;
  }
  NSString *sql = [plan[@"sql"] isKindOfClass:[NSString class]] ? plan[@"sql"] : @"";
  NSArray *parameters = [plan[@"parameters"] isKindOfClass:[NSArray class]] ? plan[@"parameters"] : @[];
  NSArray<NSDictionary<NSString *, id> *> *rows = [self.context.adapter executeQuery:sql
                                                                          parameters:parameters
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
  return [self materializedModelsFromRows:rows error:error];
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
      [self.context.adapter executeQuery:countSQL parameters:parameters error:error];
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
      [self.context.adapter executeQuery:existsSQL parameters:parameters error:error];
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

- (id)findByPrimaryKeyValues:(NSDictionary<NSString *,id> *)primaryKeyValues
                       error:(NSError **)error {
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

@end
