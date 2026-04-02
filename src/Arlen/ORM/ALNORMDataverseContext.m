#import "ALNORMDataverseContext.h"

#import "ALNORMDataverseModel.h"
#import "ALNORMDataverseRepository.h"

static NSString *ALNORMDataverseContextClassKey(Class modelClass) {
  return NSStringFromClass(modelClass) ?: @"";
}

static NSString *ALNORMDataverseContextIdentityKey(Class modelClass, id value) {
  return [NSString stringWithFormat:@"%@|%@",
                                    ALNORMDataverseContextClassKey(modelClass),
                                    ([value description] ?: @"<null>")];
}

@interface ALNORMDataverseContext ()

@property(nonatomic, strong, readwrite) ALNDataverseClient *client;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *capabilityMetadata;
@property(nonatomic, assign, readwrite) BOOL identityTrackingEnabled;
@property(nonatomic, assign, readwrite) NSUInteger queryCount;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary<NSString *, id> *> *queryEvents;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ALNORMDataverseRepository *> *repositoryCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, ALNORMValueConverter *> *> *fieldConverterRegistry;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ALNORMDataverseModel *> *identityMap;

@end

@interface ALNORMDataverseContext (ALNORMDataverseRepositoryRuntime)
- (void)appendEvent:(NSDictionary<NSString *, id> *)event countAsQuery:(BOOL)countAsQuery;
- (nullable ALNORMDataverseModel *)trackedModelForClass:(Class)modelClass primaryIDValue:(nullable id)primaryIDValue;
- (void)trackModel:(ALNORMDataverseModel *)model;
- (void)untrackModel:(ALNORMDataverseModel *)model;
@end

@implementation ALNORMDataverseContext

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithClient:nil identityTrackingEnabled:YES];
}
#pragma clang diagnostic pop

- (instancetype)initWithClient:(ALNDataverseClient *)client {
  return [self initWithClient:client identityTrackingEnabled:YES];
}

- (instancetype)initWithClient:(ALNDataverseClient *)client identityTrackingEnabled:(BOOL)identityTrackingEnabled {
  self = [super init];
  if (self != nil) {
    if (client == nil) {
      return nil;
    }
    _client = client;
    _identityTrackingEnabled = identityTrackingEnabled;
    _capabilityMetadata = [[[self class] capabilityMetadataForClient:client] copy] ?: @{};
    _queryCount = 0;
    _queryEvents = @[];
    _repositoryCache = [NSMutableDictionary dictionary];
    _fieldConverterRegistry = [NSMutableDictionary dictionary];
    _identityMap = [NSMutableDictionary dictionary];
  }
  return self;
}

+ (NSDictionary<NSString *, id> *)capabilityMetadataForClient:(ALNDataverseClient *)client {
  NSMutableDictionary<NSString *, id> *metadata =
      [NSMutableDictionary dictionaryWithDictionary:[ALNDataverseClient capabilityMetadata] ?: @{}];
  metadata[@"adapter_name"] = @"dataverse";
  metadata[@"supports_sql_runtime"] = @NO;
  metadata[@"supports_schema_reflection"] = @NO;
  metadata[@"supports_generated_models"] = @YES;
  metadata[@"supports_dataverse_orm"] = @YES;
  metadata[@"supports_associations"] = @YES;
  metadata[@"supports_many_to_many"] = @NO;
  metadata[@"supports_reverse_collections"] = @YES;
  metadata[@"supports_upsert"] = @YES;
  metadata[@"supports_unit_of_work"] = @NO;
  metadata[@"supports_batch_writes"] = @YES;
  metadata[@"supports_transactions"] = @NO;
  metadata[@"boundary_note"] =
      @"Dataverse ORM is separate from the SQL ORM runtime. Lookup and reverse-collection relations are supported; many-to-many remains explicit Dataverse client work.";
  if (client != nil) {
    metadata[@"target_name"] = client.target.targetName ?: @"default";
  }
  return metadata;
}

- (ALNORMDataverseRepository *)repositoryForModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return nil;
  }
  NSString *key = ALNORMDataverseContextClassKey(modelClass);
  ALNORMDataverseRepository *existing = self.repositoryCache[key];
  if (existing != nil) {
    return existing;
  }
  ALNORMDataverseRepository *repository = [[ALNORMDataverseRepository alloc] initWithContext:self modelClass:modelClass];
  if (repository != nil) {
    self.repositoryCache[key] = repository;
  }
  return repository;
}

- (void)registerFieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                  forModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return;
  }
  self.fieldConverterRegistry[ALNORMDataverseContextClassKey(modelClass)] = [fieldConverters copy] ?: @{};
}

- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass {
  if (modelClass == Nil) {
    return @{};
  }
  return self.fieldConverterRegistry[ALNORMDataverseContextClassKey(modelClass)] ?: @{};
}

- (BOOL)loadRelationNamed:(NSString *)relationName fromModel:(ALNORMDataverseModel *)model error:(NSError **)error {
  if (model == nil) {
    return NO;
  }
  ALNORMDataverseRepository *repository = [self repositoryForModelClass:[model class]];
  return [repository loadRelationNamed:relationName fromModel:model error:error];
}

- (void)resetTracking {
  [self.identityMap removeAllObjects];
  self.queryCount = 0;
  self.queryEvents = @[];
}

- (void)detachModel:(ALNORMDataverseModel *)model {
  [self untrackModel:model];
  [model attachToContext:nil];
}

- (void)appendEvent:(NSDictionary<NSString *,id> *)event countAsQuery:(BOOL)countAsQuery {
  if (countAsQuery) {
    self.queryCount += 1;
  }
  self.queryEvents = [self.queryEvents arrayByAddingObject:event ?: @{}];
}

- (ALNORMDataverseModel *)trackedModelForClass:(Class)modelClass primaryIDValue:(id)primaryIDValue {
  if (!self.identityTrackingEnabled || modelClass == Nil || primaryIDValue == nil || primaryIDValue == [NSNull null]) {
    return nil;
  }
  return self.identityMap[ALNORMDataverseContextIdentityKey(modelClass, primaryIDValue)];
}

- (void)trackModel:(ALNORMDataverseModel *)model {
  [model attachToContext:self];
  if (!self.identityTrackingEnabled) {
    return;
  }
  id primaryIDValue = [model primaryIDValue];
  if (primaryIDValue == nil || primaryIDValue == [NSNull null]) {
    return;
  }
  self.identityMap[ALNORMDataverseContextIdentityKey([model class], primaryIDValue)] = model;
}

- (void)untrackModel:(ALNORMDataverseModel *)model {
  if (!self.identityTrackingEnabled || model == nil) {
    return;
  }
  id primaryIDValue = [model primaryIDValue];
  if (primaryIDValue == nil || primaryIDValue == [NSNull null]) {
    return;
  }
  [self.identityMap removeObjectForKey:ALNORMDataverseContextIdentityKey([model class], primaryIDValue)];
}

@end
