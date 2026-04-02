#import "ALNORMDataverseRepository.h"

#import "ALNORMDataverseContext.h"
#import "ALNORMErrors.h"

@interface ALNORMDataverseContext (ALNORMDataverseRepositoryRuntime)
- (void)appendEvent:(NSDictionary<NSString *, id> *)event countAsQuery:(BOOL)countAsQuery;
- (nullable ALNORMDataverseModel *)trackedModelForClass:(Class)modelClass primaryIDValue:(nullable id)primaryIDValue;
- (void)trackModel:(ALNORMDataverseModel *)model;
@end

@interface ALNORMDataverseRepository ()

@property(nonatomic, strong, readwrite) ALNORMDataverseContext *context;
@property(nonatomic, assign, readwrite) Class modelClass;
@property(nonatomic, strong, readwrite) ALNORMDataverseModelDescriptor *descriptor;

@end

@implementation ALNORMDataverseRepository

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithContext:nil modelClass:Nil];
}
#pragma clang diagnostic pop

- (instancetype)initWithContext:(ALNORMDataverseContext *)context modelClass:(Class)modelClass {
  self = [super init];
  if (self != nil) {
    if (context == nil || modelClass == Nil || ![modelClass respondsToSelector:@selector(dataverseModelDescriptor)]) {
      return nil;
    }
    ALNORMDataverseModelDescriptor *descriptor = [modelClass dataverseModelDescriptor];
    if (![descriptor isKindOfClass:[ALNORMDataverseModelDescriptor class]]) {
      return nil;
    }
    _context = context;
    _modelClass = modelClass;
    _descriptor = descriptor;
  }
  return self;
}

- (ALNDataverseQuery *)query {
  NSError *error = nil;
  return [ALNDataverseQuery queryWithEntitySetName:self.descriptor.entitySetName error:&error];
}

- (ALNORMDataverseChangeset *)changesetForModelIfNeeded:(ALNORMDataverseModel *)model
                                              changeset:(ALNORMDataverseChangeset *)changeset {
  if (changeset != nil) {
    return changeset;
  }
  ALNORMDataverseChangeset *generated = [ALNORMDataverseChangeset changesetWithModel:model];
  for (NSString *fieldName in model.dirtyFieldNames ?: [NSSet set]) {
    [generated castInputValue:[model objectForFieldName:fieldName] forFieldName:fieldName error:NULL];
  }
  return generated;
}

- (ALNORMDataverseModel *)materializeModelFromRecord:(ALNDataverseRecord *)record error:(NSError **)error {
  ALNORMDataverseModel *candidate = nil;
  BOOL usesDefaultFactory =
      ([self.modelClass methodForSelector:@selector(modelFromRecord:error:)] ==
       [ALNORMDataverseModel methodForSelector:@selector(modelFromRecord:error:)]);
  if (usesDefaultFactory) {
    candidate = [[self.modelClass alloc] init];
    if (![candidate applyRecord:record error:error]) {
      return nil;
    }
  } else {
    candidate = [self.modelClass modelFromRecord:record error:error];
  }
  if (![candidate isKindOfClass:[ALNORMDataverseModel class]]) {
    if (error != NULL && *error == nil) {
      *error = ALNORMMakeError(ALNORMErrorMaterializationFailed,
                               @"Dataverse repository failed to materialize a model",
                               @{
                                 @"entity_name" : self.descriptor.logicalName ?: @"",
                               });
    }
    return nil;
  }

  id primaryID = [candidate primaryIDValue];
  ALNORMDataverseModel *tracked = [self.context trackedModelForClass:self.modelClass primaryIDValue:primaryID];
  if (tracked != nil) {
    [tracked applyRecord:record error:nil];
    return tracked;
  }
  [candidate attachToContext:self.context];
  [self.context trackModel:candidate];
  return candidate;
}

- (BOOL)materializeExpandedRelationsFromRecord:(ALNDataverseRecord *)record
                                        model:(ALNORMDataverseModel *)model
                                        error:(NSError **)error {
  NSDictionary<NSString *, id> *raw = record.rawDictionary ?: @{};
  for (ALNORMDataverseRelationDescriptor *relation in self.descriptor.relations ?: @[]) {
    id expandedValue = raw[relation.name];
    if (expandedValue == nil) {
      continue;
    }
    ALNORMDataverseRepository *targetRepository =
        [self.context repositoryForModelClass:NSClassFromString(relation.targetClassName)];
    if (targetRepository == nil) {
      continue;
    }

    if (relation.isCollection) {
      NSMutableArray *models = [NSMutableArray array];
      for (NSDictionary *item in ([expandedValue isKindOfClass:[NSArray class]] ? expandedValue : @[])) {
        ALNDataverseRecord *expandedRecord = [ALNDataverseRecord recordWithDictionary:item error:error];
        if (expandedRecord == nil) {
          return NO;
        }
        ALNORMDataverseModel *expandedModel = [targetRepository materializeModelFromRecord:expandedRecord error:error];
        if (expandedModel == nil) {
          return NO;
        }
        [models addObject:expandedModel];
      }
      if (![model markRelationLoaded:relation.name value:models error:error]) {
        return NO;
      }
      continue;
    }

    if ([expandedValue isKindOfClass:[NSDictionary class]]) {
      ALNDataverseRecord *expandedRecord = [ALNDataverseRecord recordWithDictionary:expandedValue error:error];
      if (expandedRecord == nil) {
        return NO;
      }
      ALNORMDataverseModel *expandedModel = [targetRepository materializeModelFromRecord:expandedRecord error:error];
      if (expandedModel == nil) {
        return NO;
      }
      if (![model markRelationLoaded:relation.name value:expandedModel error:error]) {
        return NO;
      }
    }
  }
  return YES;
}

- (NSArray *)all:(NSError **)error {
  return [self allMatchingQuery:[self query] error:error];
}

- (NSArray *)allMatchingQuery:(ALNDataverseQuery *)query error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNDataverseQuery *resolvedQuery = query ?: [self query];
  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_query",
    @"entity_name" : self.descriptor.logicalName ?: @"",
    @"entity_set_name" : self.descriptor.entitySetName ?: @"",
  }
                countAsQuery:YES];
  ALNDataverseEntityPage *page = [self.context.client fetchPageForQuery:resolvedQuery error:error];
  if (page == nil) {
    return nil;
  }

  NSMutableArray *records = [NSMutableArray arrayWithArray:page.records ?: @[]];
  NSString *nextLink = page.nextLinkURLString;
  while ([nextLink length] > 0) {
    ALNDataverseEntityPage *nextPage = [self.context.client fetchNextPageWithURLString:nextLink error:error];
    if (nextPage == nil) {
      return nil;
    }
    [records addObjectsFromArray:nextPage.records ?: @[]];
    nextLink = nextPage.nextLinkURLString;
  }

  NSMutableArray *models = [NSMutableArray array];
  for (ALNDataverseRecord *record in records) {
    ALNORMDataverseModel *model = [self materializeModelFromRecord:record error:error];
    if (model == nil) {
      return nil;
    }
    if (![self materializeExpandedRelationsFromRecord:record model:model error:error]) {
      return nil;
    }
    [models addObject:model];
  }
  return [NSArray arrayWithArray:models];
}

- (id)firstMatchingQuery:(ALNDataverseQuery *)query error:(NSError **)error {
  ALNDataverseQuery *resolvedQuery = (query ?: [self query]);
  resolvedQuery = [resolvedQuery queryBySettingTop:@1];
  NSArray *models = [self allMatchingQuery:resolvedQuery error:error];
  return [models firstObject];
}

- (id)findByPrimaryID:(NSString *)primaryID error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNORMDataverseModel *tracked = [self.context trackedModelForClass:self.modelClass primaryIDValue:primaryID];
  if (tracked != nil) {
    return tracked;
  }

  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_retrieve",
    @"entity_name" : self.descriptor.logicalName ?: @"",
    @"record_id" : primaryID ?: @"",
  }
                countAsQuery:YES];
  ALNDataverseRecord *record =
      [self.context.client retrieveRecordInEntitySet:self.descriptor.entitySetName
                                            recordID:primaryID
                                        selectFields:nil
                                              expand:nil
                              includeFormattedValues:YES
                                               error:error];
  if (record == nil) {
    return nil;
  }
  return [self materializeModelFromRecord:record error:error];
}

- (id)findByAlternateKeyValues:(NSDictionary<NSString *,id> *)alternateKeyValues error:(NSError **)error {
  ALNDataverseQuery *query = [self query];
  query = [query queryBySettingPredicate:alternateKeyValues ?: @{}];
  query = [query queryBySettingTop:@1];
  return [self firstMatchingQuery:query error:error];
}

- (BOOL)loadRelationNamed:(NSString *)relationName fromModel:(ALNORMDataverseModel *)model error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNORMDataverseRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse model relation is not defined",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : self.descriptor.logicalName ?: @"",
                               });
    }
    return NO;
  }
  ALNORMDataverseRepository *targetRepository =
      [self.context repositoryForModelClass:NSClassFromString(relation.targetClassName)];
  if (targetRepository == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                               @"Dataverse relation target class is not available",
                               @{
                                 @"target_class_name" : relation.targetClassName ?: @"",
                               });
    }
    return NO;
  }

  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_relation_load",
    @"entity_name" : self.descriptor.logicalName ?: @"",
    @"relation_name" : relation.name ?: @"",
  }
                countAsQuery:NO];

  id sourceValue = [model objectForFieldName:relation.sourceValueFieldName];
  if (sourceValue == nil || sourceValue == [NSNull null]) {
    return [model markRelationLoaded:relation.name value:(relation.isCollection ? @[] : nil) error:error];
  }

  if (!relation.isCollection) {
    id related = [targetRepository findByPrimaryID:[sourceValue description] error:error];
    if (related == nil && error != NULL && *error != nil) {
      return NO;
    }
    return [model markRelationLoaded:relation.name value:related error:error];
  }

  ALNDataverseQuery *query = [targetRepository query];
  query =
      [query queryBySettingPredicate:@{ relation.queryFieldLogicalName ?: @"" : sourceValue ?: [NSNull null] }];
  NSArray *related = [targetRepository allMatchingQuery:query error:error];
  if (related == nil) {
    return NO;
  }
  return [model markRelationLoaded:relation.name value:related error:error];
}

- (BOOL)saveModel:(ALNORMDataverseModel *)model error:(NSError **)error {
  return [self saveModel:model changeset:nil error:error];
}

- (BOOL)saveModel:(ALNORMDataverseModel *)model changeset:(ALNORMDataverseChangeset *)changeset error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNORMDataverseChangeset *resolved = [self changesetForModelIfNeeded:model changeset:changeset];
  NSDictionary<NSString *, id> *encodedValues = [resolved encodedValues:error];
  if (encodedValues == nil) {
    return NO;
  }
  if (![resolved applyToModel:error]) {
    return NO;
  }

  id primaryID = [model primaryIDValue];
  if (primaryID == nil || primaryID == [NSNull null] || !model.isPersisted) {
    [self.context appendEvent:@{
      @"event_kind" : @"dataverse_create",
      @"entity_name" : self.descriptor.logicalName ?: @"",
    }
                  countAsQuery:YES];
    NSDictionary *created = [self.context.client createRecordInEntitySet:self.descriptor.entitySetName
                                                                  values:encodedValues
                                                     returnRepresentation:YES
                                                                   error:error];
    if (created == nil) {
      return NO;
    }
    ALNDataverseRecord *record = [ALNDataverseRecord recordWithDictionary:created error:error];
    if (record == nil) {
      return NO;
    }
    if (![model applyRecord:record error:error]) {
      return NO;
    }
    [self.context trackModel:model];
    return YES;
  }

  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_update",
    @"entity_name" : self.descriptor.logicalName ?: @"",
  }
                countAsQuery:YES];
  NSDictionary *updated = [self.context.client updateRecordInEntitySet:self.descriptor.entitySetName
                                                              recordID:[primaryID description]
                                                                values:encodedValues
                                                               ifMatch:([model.etag length] > 0 ? model.etag : nil)
                                                   returnRepresentation:YES
                                                                 error:error];
  if (updated == nil) {
    return NO;
  }
  ALNDataverseRecord *record = [ALNDataverseRecord recordWithDictionary:updated error:error];
  if (record != nil) {
    [model applyRecord:record error:nil];
  } else {
    [model markClean];
  }
  [self.context trackModel:model];
  return YES;
}

- (BOOL)upsertModel:(ALNORMDataverseModel *)model
  alternateKeyFields:(NSArray<NSString *> *)alternateKeyFields
           changeset:(ALNORMDataverseChangeset *)changeset
               error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNORMDataverseChangeset *resolved = [self changesetForModelIfNeeded:model changeset:changeset];
  NSDictionary<NSString *, id> *encodedValues = [resolved encodedValues:error];
  if (encodedValues == nil) {
    return NO;
  }
  NSMutableDictionary<NSString *, id> *alternateKeyValues = [NSMutableDictionary dictionary];
  for (NSString *fieldName in alternateKeyFields ?: @[]) {
    id value = [model objectForFieldName:fieldName];
    if (value == nil || value == [NSNull null]) {
      value = encodedValues[fieldName];
    }
    if (value != nil && value != [NSNull null]) {
      alternateKeyValues[fieldName] = value;
    }
  }
  if ([alternateKeyValues count] == 0) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse upsert requires at least one alternate key value",
                               nil);
    }
    return NO;
  }
  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_upsert",
    @"entity_name" : self.descriptor.logicalName ?: @"",
  }
                countAsQuery:YES];
  NSDictionary *result = [self.context.client upsertRecordInEntitySet:self.descriptor.entitySetName
                                                   alternateKeyValues:alternateKeyValues
                                                               values:encodedValues
                                                            createOnly:NO
                                                            updateOnly:NO
                                                   returnRepresentation:YES
                                                                error:error];
  if (result == nil) {
    return NO;
  }
  ALNDataverseRecord *record = [ALNDataverseRecord recordWithDictionary:result error:error];
  if (record != nil) {
    [model applyRecord:record error:nil];
  }
  [self.context trackModel:model];
  return YES;
}

- (BOOL)deleteModel:(ALNORMDataverseModel *)model error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  id primaryID = [model primaryIDValue];
  if (primaryID == nil || primaryID == [NSNull null]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorDeleteFailed,
                               @"Dataverse delete requires a persisted model primary ID",
                               nil);
    }
    return NO;
  }
  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_delete",
    @"entity_name" : self.descriptor.logicalName ?: @"",
  }
                countAsQuery:YES];
  return [self.context.client deleteRecordInEntitySet:self.descriptor.entitySetName
                                             recordID:[primaryID description]
                                              ifMatch:([model.etag length] > 0 ? model.etag : nil)
                                                error:error];
}

- (BOOL)saveModelsInBatch:(NSArray<ALNORMDataverseModel *> *)models
               changesets:(NSArray<ALNORMDataverseChangeset *> *)changesets
                    error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSMutableArray<ALNDataverseBatchRequest *> *requests = [NSMutableArray array];
  for (NSUInteger index = 0; index < [models count]; index++) {
    ALNORMDataverseModel *model = models[index];
    ALNORMDataverseChangeset *changeset =
        (index < [changesets count]) ? changesets[index] : [self changesetForModelIfNeeded:model changeset:nil];
    NSDictionary<NSString *, id> *encodedValues = [changeset encodedValues:error];
    if (encodedValues == nil) {
      return NO;
    }

    NSString *method = @"POST";
    NSString *relativePath = self.descriptor.entitySetName ?: @"";
    id primaryID = [model primaryIDValue];
    if (primaryID != nil && primaryID != [NSNull null] && model.isPersisted) {
      method = @"PATCH";
      NSString *path = [ALNDataverseClient recordPathForEntitySet:self.descriptor.entitySetName
                                                         recordID:[primaryID description]
                                                            error:error];
      if (path == nil) {
        return NO;
      }
      relativePath = path;
    }

    [requests addObject:[ALNDataverseBatchRequest requestWithMethod:method
                                                       relativePath:relativePath
                                                            headers:nil
                                                         bodyObject:encodedValues
                                                          contentID:[NSString stringWithFormat:@"%lu", (unsigned long)(index + 1)]]];
  }

  [self.context appendEvent:@{
    @"event_kind" : @"dataverse_batch",
    @"entity_name" : self.descriptor.logicalName ?: @"",
    @"request_count" : @([requests count]),
  }
                countAsQuery:YES];
  NSArray<ALNDataverseBatchResponse *> *responses = [self.context.client executeBatchRequests:requests error:error];
  return [responses count] == [requests count];
}

@end
