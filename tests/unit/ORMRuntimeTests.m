#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"
#import "ArlenORM/ArlenORM.h"

static NSDictionary *ALNORMRuntimeFixtureMetadata(void) {
  static NSDictionary *metadata = nil;
  if (metadata == nil) {
    NSError *error = nil;
    NSDictionary *fixture =
        ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_schema_metadata_contract.json", &error);
    metadata = [fixture[@"metadata"] isKindOfClass:[NSDictionary class]] ? fixture[@"metadata"] : @{};
  }
  return metadata ?: @{};
}

static NSArray<ALNORMModelDescriptor *> *ALNORMRuntimeDescriptors(void) {
  static NSArray<ALNORMModelDescriptor *> *descriptors = nil;
  if (descriptors == nil) {
    NSError *error = nil;
    descriptors = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:ALNORMRuntimeFixtureMetadata()
                                                        classPrefix:@"ALNORMRuntime"
                                                              error:&error];
  }
  return descriptors ?: @[];
}

static ALNORMModelDescriptor *ALNORMRuntimeDescriptorNamed(NSString *entityName) {
  for (ALNORMModelDescriptor *descriptor in ALNORMRuntimeDescriptors()) {
    if ([descriptor.entityName isEqualToString:entityName]) {
      return descriptor;
    }
  }
  return nil;
}

@interface ALNORMRuntimePublicUsersModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicUsersModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeDescriptorNamed(@"public.users"); }
@end

@interface ALNORMRuntimePublicProfilesModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicProfilesModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeDescriptorNamed(@"public.profiles"); }
@end

@interface ALNORMRuntimePublicPostsModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicPostsModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeDescriptorNamed(@"public.posts"); }
@end

@interface ALNORMRuntimePublicTagsModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicTagsModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeDescriptorNamed(@"public.tags"); }
@end

@interface ALNORMRuntimePublicPostTagsModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicPostTagsModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeDescriptorNamed(@"public.post_tags"); }
@end

@interface ALNORMRuntimePublicUserEmailsModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicUserEmailsModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeDescriptorNamed(@"public.user_emails"); }
@end

static ALNORMModelDescriptor *ALNORMRuntimeAuditEntriesDescriptor(void) {
  static ALNORMModelDescriptor *descriptor = nil;
  if (descriptor == nil) {
    NSArray *fields = @[
      [[ALNORMFieldDescriptor alloc] initWithName:@"id"
                                     propertyName:@"id"
                                       columnName:@"id"
                                         dataType:@"text"
                                         objcType:@"NSString *"
                                 runtimeClassName:@"NSString"
                                propertyAttribute:@"copy"
                                          ordinal:1
                                         nullable:NO
                                       primaryKey:YES
                                           unique:YES
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"userId"
                                     propertyName:@"userId"
                                       columnName:@"user_id"
                                         dataType:@"text"
                                         objcType:@"NSString *"
                                 runtimeClassName:@"NSString"
                                propertyAttribute:@"copy"
                                          ordinal:2
                                         nullable:NO
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"version"
                                     propertyName:@"version"
                                       columnName:@"version"
                                         dataType:@"integer"
                                         objcType:@"NSNumber *"
                                 runtimeClassName:@"NSNumber"
                                propertyAttribute:@"strong"
                                          ordinal:3
                                         nullable:NO
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"createdAt"
                                     propertyName:@"createdAt"
                                       columnName:@"created_at"
                                         dataType:@"timestamptz"
                                         objcType:@"NSDate *"
                                 runtimeClassName:@"NSDate"
                                propertyAttribute:@"strong"
                                          ordinal:4
                                         nullable:YES
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"updatedAt"
                                     propertyName:@"updatedAt"
                                       columnName:@"updated_at"
                                         dataType:@"timestamptz"
                                         objcType:@"NSDate *"
                                 runtimeClassName:@"NSDate"
                                propertyAttribute:@"strong"
                                          ordinal:5
                                         nullable:YES
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"payload"
                                     propertyName:@"payload"
                                       columnName:@"payload"
                                         dataType:@"jsonb"
                                         objcType:@"NSDictionary *"
                                 runtimeClassName:@"NSDictionary"
                                propertyAttribute:@"strong"
                                          ordinal:6
                                         nullable:YES
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"tags"
                                     propertyName:@"tags"
                                       columnName:@"tags"
                                         dataType:@"text[]"
                                         objcType:@"NSArray *"
                                 runtimeClassName:@"NSArray"
                                propertyAttribute:@"copy"
                                          ordinal:7
                                         nullable:YES
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
      [[ALNORMFieldDescriptor alloc] initWithName:@"status"
                                     propertyName:@"status"
                                       columnName:@"status"
                                         dataType:@"text"
                                         objcType:@"NSString *"
                                 runtimeClassName:@"NSString"
                                propertyAttribute:@"copy"
                                          ordinal:8
                                         nullable:NO
                                       primaryKey:NO
                                           unique:NO
                                       hasDefault:NO
                                         readOnly:NO
                                defaultValueShape:@"none"],
    ];

    ALNORMRelationDescriptor *userRelation =
        [[ALNORMRelationDescriptor alloc] initWithKind:ALNORMRelationKindBelongsTo
                                                  name:@"user"
                                      sourceEntityName:@"public.audit_entries"
                                      targetEntityName:@"public.users"
                                       targetClassName:@"ALNORMRuntimePublicUsersModel"
                                     throughEntityName:nil
                                      throughClassName:nil
                                      sourceFieldNames:@[ @"userId" ]
                                      targetFieldNames:@[ @"id" ]
                               throughSourceFieldNames:nil
                               throughTargetFieldNames:nil
                                       pivotFieldNames:nil
                                              readOnly:NO
                                              inferred:NO];

    descriptor = [[ALNORMModelDescriptor alloc] initWithClassName:@"ALNORMRuntimePublicAuditEntriesModel"
                                                       entityName:@"public.audit_entries"
                                                       schemaName:@"public"
                                                        tableName:@"audit_entries"
                                               qualifiedTableName:@"public.audit_entries"
                                                     relationKind:@"table"
                                                   databaseTarget:@"postgresql"
                                                         readOnly:NO
                                                           fields:fields
                                             primaryKeyFieldNames:@[ @"id" ]
                                         uniqueConstraintFieldSets:@[ @[ @"id" ] ]
                                                        relations:@[ userRelation ]];
  }
  return descriptor;
}

@interface ALNORMRuntimePublicAuditEntriesModel : ALNORMModel
@end
@implementation ALNORMRuntimePublicAuditEntriesModel
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMRuntimeAuditEntriesDescriptor(); }
@end

@interface ORMRuntimeFakeAdapter : NSObject <ALNDatabaseAdapter, ALNDatabaseConnection>

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableArray<NSArray<NSDictionary<NSString *, id> *> *> *queuedRowSets;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *queuedCommandResults;
@property(nonatomic, strong) NSMutableArray<NSString *> *executedSQL;
@property(nonatomic, strong) NSMutableArray<NSArray *> *executedParameters;
@property(nonatomic, strong) NSMutableArray<NSString *> *executedKinds;
@property(nonatomic, strong) NSMutableArray<NSString *> *transactionLog;

- (instancetype)initWithAdapterName:(NSString *)adapterName;

@end

@implementation ORMRuntimeFakeAdapter

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self != nil) {
    _adapterNameValue = [adapterName copy] ?: @"postgresql";
    _queuedRowSets = [NSMutableArray array];
    _queuedCommandResults = [NSMutableArray array];
    _executedSQL = [NSMutableArray array];
    _executedParameters = [NSMutableArray array];
    _executedKinds = [NSMutableArray array];
    _transactionLog = [NSMutableArray array];
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"postgresql";
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  BOOL postgres = [[self adapterName] isEqualToString:@"postgresql"] || [[self adapterName] isEqualToString:@"postgres"];
  BOOL mssql = [[self adapterName] isEqualToString:@"mssql"];
  return @{
    @"supports_sql_runtime" : @(postgres || mssql),
    @"supports_schema_reflection" : @(postgres),
    @"supports_upsert" : @(postgres),
    @"supports_savepoints" : @YES,
  };
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  (void)error;
  return self;
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  (void)connection;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.executedKinds addObject:@"query"];
  [self.executedSQL addObject:sql ?: @""];
  [self.executedParameters addObject:parameters ?: @[]];
  if ([self.queuedRowSets count] == 0) {
    return @[];
  }
  NSArray<NSDictionary<NSString *, id> *> *next = self.queuedRowSets[0];
  [self.queuedRowSets removeObjectAtIndex:0];
  return next;
}

- (NSDictionary *)executeQueryOne:(NSString *)sql
                       parameters:(NSArray *)parameters
                            error:(NSError **)error {
  return ALNDatabaseFirstRow([self executeQuery:sql parameters:parameters error:error]);
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.executedKinds addObject:@"command"];
  [self.executedSQL addObject:sql ?: @""];
  [self.executedParameters addObject:parameters ?: @[]];
  if ([self.queuedCommandResults count] == 0) {
    return 1;
  }
  NSInteger next = [self.queuedCommandResults[0] integerValue];
  [self.queuedCommandResults removeObjectAtIndex:0];
  return next;
}

- (BOOL)createSavepointNamed:(NSString *)name error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.transactionLog addObject:[NSString stringWithFormat:@"SAVEPOINT:%@", name ?: @""]];
  return YES;
}

- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.transactionLog addObject:[NSString stringWithFormat:@"ROLLBACK_TO:%@", name ?: @""]];
  return YES;
}

- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.transactionLog addObject:[NSString stringWithFormat:@"RELEASE:%@", name ?: @""]];
  return YES;
}

- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(BOOL (^)(NSError **error))block
                     error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.transactionLog addObject:[NSString stringWithFormat:@"SAVEPOINT:%@", name ?: @""]];
  NSError *blockError = nil;
  BOOL success = (block != nil) ? block(&blockError) : YES;
  if (success) {
    [self.transactionLog addObject:[NSString stringWithFormat:@"RELEASE:%@", name ?: @""]];
    return YES;
  }
  [self.transactionLog addObject:[NSString stringWithFormat:@"ROLLBACK_TO:%@", name ?: @""]];
  if (error != NULL) {
    *error = blockError;
  }
  return NO;
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.transactionLog addObject:@"BEGIN"];
  NSError *blockError = nil;
  BOOL success = (block != nil) ? block(self, &blockError) : YES;
  [self.transactionLog addObject:(success ? @"COMMIT" : @"ROLLBACK")];
  if (!success && error != NULL) {
    *error = blockError;
  }
  return success;
}

@end

static ALNORMWriteOptions *ALNORMRuntimeAuditWriteOptions(void) {
  ALNORMWriteOptions *options = [ALNORMWriteOptions options];
  options.optimisticLockFieldName = @"version";
  options.createdAtFieldName = @"createdAt";
  options.updatedAtFieldName = @"updatedAt";
  options.conflictFieldNames = @[ @"id" ];
  return options;
}

static void ALNORMRuntimeRegisterAuditConverters(ALNORMContext *context) {
  [context registerFieldConverters:@{
    @"version" : [ALNORMValueConverter integerConverter],
    @"createdAt" : [ALNORMValueConverter ISO8601DateTimeConverter],
    @"updatedAt" : [ALNORMValueConverter ISO8601DateTimeConverter],
    @"payload" : [ALNORMValueConverter JSONConverter],
    @"tags" : [ALNORMValueConverter arrayConverter],
    @"status" : [ALNORMValueConverter enumConverterWithAllowedValues:@[ @"pending", @"stored" ]],
  }
                    forModelClass:[ALNORMRuntimePublicAuditEntriesModel class]];
}

static ALNORMContext *ALNORMRuntimeConfiguredAuditContext(ORMRuntimeFakeAdapter *adapter) {
  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRuntimeRegisterAuditConverters(context);
  [context registerDefaultWriteOptions:ALNORMRuntimeAuditWriteOptions()
                         forModelClass:[ALNORMRuntimePublicAuditEntriesModel class]];
  return context;
}

@interface ORMRuntimeTests : XCTestCase
@end

@implementation ORMRuntimeTests

- (void)testModelTracksLoadedDirtyAndDetachedState {
  ALNORMRuntimePublicUsersModel *user = [[ALNORMRuntimePublicUsersModel alloc] init];
  XCTAssertEqual(ALNORMModelStateNew, user.state);

  NSError *error = nil;
  XCTAssertTrue([user setObject:@"person@example.com" forFieldName:@"email" error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertTrue([user.dirtyFieldNames containsObject:@"email"]);

  NSDictionary *row = @{
    @"id" : @"user-1",
    @"email" : @"person@example.com",
    @"display_name" : @"Dan",
  };
  XCTAssertTrue([user applyRow:row error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqual(ALNORMModelStateLoaded, user.state);
  XCTAssertEqual((NSUInteger)0, [user.dirtyFieldNames count]);

  XCTAssertTrue([user setObject:@"Bobby" forPropertyName:@"displayName" error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqual(ALNORMModelStateDirty, user.state);
  XCTAssertEqualObjects(@"Bobby", [user objectForFieldName:@"displayName"]);
  XCTAssertEqualObjects((NSDictionary<NSString *, id> *)@{ @"displayName" : @"Bobby" }, [user changedFieldValues]);

  XCTAssertTrue([user setObject:@"Dan" forFieldName:@"displayName" error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqual(ALNORMModelStateLoaded, user.state);
  XCTAssertEqual((NSUInteger)0, [user.dirtyFieldNames count]);

  [user markDetached];
  XCTAssertEqual(ALNORMModelStateDetached, user.state);
}

- (void)testRepositoryBuildsInspectableSQLAndMaterializesModels {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"post-1",
      @"user_id" : @"user-1",
      @"title" : @"Hello",
    },
  ]];

  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  ALNORMQuery *query = [repository query];
  [[query whereField:@"userId" equals:@"user-1"] orderByField:@"title" descending:NO];
  [query limit:1];

  NSError *error = nil;
  NSDictionary *plan = [repository compiledPlanForQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(plan);

  NSString *sql = [plan[@"sql"] isKindOfClass:[NSString class]] ? plan[@"sql"] : @"";
  NSArray *parameters = [plan[@"parameters"] isKindOfClass:[NSArray class]] ? plan[@"parameters"] : @[];
  XCTAssertTrue([sql containsString:@"FROM \"posts\""]);
  XCTAssertTrue([sql containsString:@"\"posts\".\"user_id\""]);
  XCTAssertEqualObjects((NSArray *)@[ @"user-1" ], parameters);

  NSArray *models = [repository allMatchingQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [models count]);
  XCTAssertTrue([models[0] isKindOfClass:[ALNORMRuntimePublicPostsModel class]]);
  XCTAssertEqualObjects(@"Hello", [models[0] objectForFieldName:@"title"]);
}

- (void)testRepositoryFailsClosedForUnknownFieldPredicates {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  ALNORMQuery *query = [[repository query] whereField:@"doesNotExist" equals:@"nope"];

  NSError *error = nil;
  NSDictionary *plan = [repository compiledPlanForQuery:query error:&error];
  XCTAssertNil(plan);
  XCTAssertNotNil(error);
  XCTAssertEqual(ALNORMErrorQueryBuildFailed, error.code);
  XCTAssertEqualObjects(@"doesNotExist", error.userInfo[@"field_name"]);
}

- (void)testRepositoryCountAndExistsWrapSelectPlans {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];

  [adapter.queuedRowSets addObject:@[ @{ @"count_value" : @2 } ]];
  NSError *error = nil;
  NSUInteger count = [repository countMatchingQuery:[[repository query] whereField:@"userId" equals:@"user-1"]
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, count);
  XCTAssertTrue([[adapter.executedSQL firstObject] containsString:@"COUNT(*) AS count_value"]);

  [adapter.executedSQL removeAllObjects];
  [adapter.executedParameters removeAllObjects];
  [adapter.queuedRowSets addObject:@[ @{ @"exists_value" : @1 } ]];
  BOOL exists = [repository existsMatchingQuery:[[repository query] whereField:@"userId" equals:@"user-1"]
                                          error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(exists);
  XCTAssertTrue([[adapter.executedSQL firstObject] containsString:@"SELECT 1 AS exists_value"]);
}

- (void)testContextBuildsBelongsToHasManyAndManyToManyRelationQueries {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];

  ALNORMRuntimePublicPostsModel *post = [[ALNORMRuntimePublicPostsModel alloc] init];
  NSError *error = nil;
  NSDictionary *postRow = @{
    @"id" : @"post-1",
    @"user_id" : @"user-1",
    @"title" : @"Hello",
  };
  XCTAssertTrue([post applyRow:postRow error:&error], @"%@", error);
  XCTAssertNil(error);

  ALNORMQuery *belongsToUserQuery = [context queryForRelationNamed:@"user" fromModel:post error:&error];
  XCTAssertNil(error);
  ALNORMRepository *usersRepository = [context repositoryForModelClass:[ALNORMRuntimePublicUsersModel class]];
  NSDictionary *userPlan = [usersRepository compiledPlanForQuery:belongsToUserQuery error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([userPlan[@"sql"] containsString:@"FROM \"users\""]);
  XCTAssertTrue([userPlan[@"sql"] containsString:@"\"users\".\"id\""]);
  XCTAssertEqualObjects((NSArray *)@[ @"user-1" ], userPlan[@"parameters"]);

  ALNORMRuntimePublicUsersModel *user = [[ALNORMRuntimePublicUsersModel alloc] init];
  NSDictionary *userRow = @{
    @"id" : @"user-1",
    @"email" : @"person@example.com",
    @"display_name" : @"Dan",
  };
  XCTAssertTrue([user applyRow:userRow error:&error], @"%@", error);
  XCTAssertNil(error);

  ALNORMQuery *hasManyPostsQuery = [context queryForRelationNamed:@"posts" fromModel:user error:&error];
  XCTAssertNil(error);
  ALNORMRepository *postsRepository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  NSDictionary *postsPlan = [postsRepository compiledPlanForQuery:hasManyPostsQuery error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([postsPlan[@"sql"] containsString:@"FROM \"posts\""]);
  XCTAssertTrue([postsPlan[@"sql"] containsString:@"\"posts\".\"user_id\""]);
  XCTAssertEqualObjects((NSArray *)@[ @"user-1" ], postsPlan[@"parameters"]);

  ALNORMQuery *manyToManyTagsQuery = [context queryForRelationNamed:@"tags" fromModel:post error:&error];
  XCTAssertNil(error);
  ALNORMRepository *tagsRepository = [context repositoryForModelClass:[ALNORMRuntimePublicTagsModel class]];
  NSDictionary *tagsPlan = [tagsRepository compiledPlanForQuery:manyToManyTagsQuery error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([tagsPlan[@"sql"] containsString:@"FROM \"tags\""]);
  XCTAssertTrue([tagsPlan[@"sql"] containsString:@"FROM \"post_tags\""]);
  XCTAssertEqualObjects((NSArray *)@[ @"post-1" ], tagsPlan[@"parameters"]);

  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"tag-1",
      @"label" : @"objc",
    },
  ]];
  NSArray *tags = [context allForRelationNamed:@"tags" fromModel:post error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [tags count]);
  XCTAssertTrue([tags[0] isKindOfClass:[ALNORMRuntimePublicTagsModel class]]);
  XCTAssertEqualObjects(@"objc", [tags[0] objectForFieldName:@"label"]);
}

- (void)testStrictLoadingRaisesDeterministicExceptionForUnloadedRelation {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"post-1",
      @"user_id" : @"user-1",
      @"title" : @"Strict",
    },
  ]];

  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  ALNORMQuery *query = [[repository query] strictLoading:YES];

  NSError *error = nil;
  NSArray *models = [repository allMatchingQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [models count]);

  ALNORMRuntimePublicPostsModel *post = models[0];
  NSError *relationError = nil;
  XCTAssertNil([post relationObjectForName:@"user" error:&relationError]);
  XCTAssertEqual(ALNORMErrorStrictLoadingViolation, relationError.code);
  XCTAssertEqualObjects(@"user", relationError.userInfo[@"relation_name"]);
  XCTAssertThrowsSpecificNamed([post relationObjectForName:@"user"], NSException, ALNORMStrictLoadingException);
}

- (void)testJoinedPreloadLoadsToOneRelationInSingleQuery {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"post-1",
      @"user_id" : @"user-1",
      @"title" : @"Joined",
      @"aln_rel_user__id" : @"user-1",
      @"aln_rel_user__email" : @"joined@example.com",
      @"aln_rel_user__display_name" : @"Joined User",
    },
  ]];

  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  ALNORMQuery *query = [[repository query] withJoinedRelationNamed:@"user"];

  NSError *error = nil;
  NSDictionary *plan = [repository compiledPlanForQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([plan[@"sql"] containsString:@"LEFT JOIN \"users\" AS \"aln_rel_user\""]);

  NSArray *models = [repository allMatchingQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [models count]);
  XCTAssertEqual((NSUInteger)1, context.queryCount);

  ALNORMRuntimePublicPostsModel *post = models[0];
  XCTAssertTrue([post isRelationLoaded:@"user"]);
  ALNORMRuntimePublicUsersModel *user = [post relationObjectForName:@"user"];
  XCTAssertTrue([user isKindOfClass:[ALNORMRuntimePublicUsersModel class]]);
  XCTAssertEqualObjects(@"Joined User", [user objectForFieldName:@"displayName"]);
}

- (void)testSelectInPreloadAndQueryBudgetDiagnosticsCatchNPlusOneRegression {
  ORMRuntimeFakeAdapter *failingAdapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [failingAdapter.queuedRowSets addObject:@[
    @{
      @"id" : @"post-1",
      @"user_id" : @"user-1",
      @"title" : @"First",
    },
    @{
      @"id" : @"post-2",
      @"user_id" : @"user-1",
      @"title" : @"Second",
    },
  ]];
  [failingAdapter.queuedRowSets addObject:@[
    @{
      @"id" : @"user-1",
      @"email" : @"person@example.com",
      @"display_name" : @"Dan",
    },
  ]];

  ALNORMContext *failingContext = [[ALNORMContext alloc] initWithAdapter:failingAdapter];
  ALNORMRepository *failingRepository =
      [failingContext repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  ALNORMQuery *failingQuery = [[failingRepository query] withSelectInRelationNamed:@"user"];

  NSError *budgetError = nil;
  BOOL withinBudget = [failingContext withQueryBudget:1
                                           usingBlock:^BOOL(NSError **innerError) {
                                             NSArray *models = [failingRepository allMatchingQuery:failingQuery error:innerError];
                                             return (models != nil);
                                           }
                                                error:&budgetError];
  XCTAssertFalse(withinBudget);
  XCTAssertEqual(ALNORMErrorQueryBudgetExceeded, budgetError.code);
  XCTAssertEqualObjects(@2, budgetError.userInfo[@"query_count"]);

  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"post-1",
      @"user_id" : @"user-1",
      @"title" : @"First",
    },
    @{
      @"id" : @"post-2",
      @"user_id" : @"user-1",
      @"title" : @"Second",
    },
  ]];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"user-1",
      @"email" : @"person@example.com",
      @"display_name" : @"Dan",
    },
  ]];

  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicPostsModel class]];
  ALNORMQuery *query = [[repository query] withSelectInRelationNamed:@"user"];

  NSError *error = nil;
  BOOL success = [context withQueryBudget:2
                               usingBlock:^BOOL(NSError **innerError) {
                                 NSArray *models = [repository allMatchingQuery:query error:innerError];
                                 XCTAssertEqual((NSUInteger)2, [models count]);
                                 ALNORMRuntimePublicUsersModel *user = [models[0] relationObjectForName:@"user"];
                                 XCTAssertEqualObjects(@"Dan", [user objectForFieldName:@"displayName"]);
                                 return models != nil;
                               }
                                    error:&error];
  XCTAssertTrue(success, @"%@", error);
  XCTAssertEqual((NSUInteger)2, context.queryCount);
  NSPredicate *relationEvent =
      [NSPredicate predicateWithFormat:@"event_kind == %@ AND relation_name == %@", @"relation_load", @"user"];
  XCTAssertEqual((NSUInteger)1, [[context.queryEvents filteredArrayUsingPredicate:relationEvent] count]);
}

- (void)testChangesetCastsValidatesAndBlocksInvalidMutationBeforeSQL {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  ALNORMContext *context = ALNORMRuntimeConfiguredAuditContext(adapter);
  ALNORMRuntimePublicAuditEntriesModel *audit = [[ALNORMRuntimePublicAuditEntriesModel alloc] init];
  [audit attachToContext:context];

  ALNORMChangeset *invalidChangeset = [ALNORMChangeset changesetWithModel:audit];
  NSError *error = nil;
  BOOL invalidApplied = [invalidChangeset applyInputValues:@{
    @"id" : @"audit-1",
    @"userId" : @"user-1",
    @"version" : @"1",
    @"status" : @"bad-state",
  }
                                                    error:&error];
  XCTAssertFalse(invalidApplied);
  XCTAssertNotNil(error);
  XCTAssertTrue([invalidChangeset hasErrors]);
  XCTAssertEqual((NSUInteger)0, [adapter.executedSQL count]);

  ALNORMChangeset *changeset = [ALNORMChangeset changesetWithModel:audit];
  BOOL applied = [changeset applyInputValues:@{
    @"id" : @"audit-1",
    @"userId" : @"user-1",
    @"version" : @"1",
    @"status" : @"pending",
    @"payload" : @"{\"ok\":true}",
    @"tags" : @[ @"alpha", @"beta" ],
  }
                                             error:&error];
  XCTAssertTrue(applied, @"%@", error);
  XCTAssertTrue([changeset validateFieldName:@"id"
                                  usingBlock:^BOOL(ALNORMFieldDescriptor *field, id value, NSError **validationError) {
                                    (void)field;
                                    if ([value hasPrefix:@"audit-"]) {
                                      return YES;
                                    }
                                    if (validationError != NULL) {
                                      *validationError = ALNORMMakeError(ALNORMErrorValidationFailed,
                                                                         @"id must use the audit- prefix",
                                                                         nil);
                                    }
                                    return NO;
                                  }]);
  XCTAssertTrue([changeset applyToModel:&error], @"%@", error);

  XCTAssertEqualObjects(@1, [audit objectForFieldName:@"version"]);
  XCTAssertTrue([[audit objectForFieldName:@"payload"] isKindOfClass:[NSDictionary class]]);
  XCTAssertTrue([[audit objectForFieldName:@"tags"] isKindOfClass:[NSArray class]]);

  NSDictionary<NSString *, id> *encoded = [changeset encodedValues:&error];
  XCTAssertNotNil(encoded);
  XCTAssertTrue([encoded[@"payload"] isKindOfClass:[ALNDatabaseJSONValue class]]);
  XCTAssertTrue([encoded[@"tags"] isKindOfClass:[ALNDatabaseArrayValue class]]);
  XCTAssertEqual((NSUInteger)0, [adapter.executedSQL count]);
}

- (void)testRepositoryReadAndWriteRoundTripUsesConvertersAndPartialUpdates {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"audit-1",
      @"user_id" : @"user-1",
      @"version" : @"2",
      @"created_at" : @"2026-04-01T00:00:00Z",
      @"updated_at" : @"2026-04-01T01:00:00Z",
      @"payload" : @"{\"ok\":true}",
      @"tags" : @[ @"alpha", @"beta" ],
      @"status" : @"stored",
    },
  ]];
  [adapter.queuedCommandResults addObject:@1];

  ALNORMContext *context = ALNORMRuntimeConfiguredAuditContext(adapter);
  ALNORMRepository *repository =
      [context repositoryForModelClass:[ALNORMRuntimePublicAuditEntriesModel class]];

  NSError *error = nil;
  ALNORMRuntimePublicAuditEntriesModel *audit = [[repository all:&error] firstObject];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@2, [audit objectForFieldName:@"version"]);
  XCTAssertTrue([[audit objectForFieldName:@"createdAt"] isKindOfClass:[NSDate class]]);
  XCTAssertTrue([[audit objectForFieldName:@"payload"] isKindOfClass:[NSDictionary class]]);
  XCTAssertTrue([[audit objectForFieldName:@"tags"] isKindOfClass:[NSArray class]]);

  XCTAssertTrue([audit setObject:@"pending" forFieldName:@"status" error:&error], @"%@", error);
  XCTAssertTrue([repository saveModel:audit options:[ALNORMWriteOptions options] error:&error], @"%@", error);

  NSString *updateSQL = [adapter.executedSQL lastObject];
  XCTAssertTrue([updateSQL containsString:@"UPDATE \"public\".\"audit_entries\" SET"]);
  XCTAssertTrue([updateSQL containsString:@"\"status\""]);
  XCTAssertFalse([updateSQL containsString:@"\"payload\" ="]);
  XCTAssertFalse([updateSQL containsString:@"\"tags\" ="]);
}

- (void)testIdentityMapReloadAndResetTrackingStayExplicit {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"user-1",
      @"email" : @"person@example.com",
      @"display_name" : @"Dan",
    },
  ]];
  [adapter.queuedRowSets addObject:@[
    @{
      @"id" : @"user-1",
      @"email" : @"person@example.com",
      @"display_name" : @"Reloaded Dan",
    },
  ]];

  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter identityTrackingEnabled:YES];
  ALNORMRepository *repository = [context repositoryForModelClass:[ALNORMRuntimePublicUsersModel class]];

  NSError *error = nil;
  ALNORMRuntimePublicUsersModel *first = [repository findByPrimaryKey:@"user-1" error:&error];
  XCTAssertNil(error);
  ALNORMRuntimePublicUsersModel *second = [repository findByPrimaryKey:@"user-1" error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(first, second);
  XCTAssertEqual((NSUInteger)1, context.queryCount);

  ALNORMRuntimePublicUsersModel *reloaded =
      (ALNORMRuntimePublicUsersModel *)[context reloadModel:first error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(first, reloaded);
  XCTAssertEqualObjects(@"Reloaded Dan", [reloaded objectForFieldName:@"displayName"]);

  [context resetTracking];
  XCTAssertEqual(ALNORMModelStateDetached, first.state);
  XCTAssertEqual((NSUInteger)0, context.queryCount);
  XCTAssertEqual((NSUInteger)0, [context.queryEvents count]);
}

- (void)testTransactionAndSavepointHelpersComposeWithAdapterSeams {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  ALNORMContext *context = [[ALNORMContext alloc] initWithAdapter:adapter];

  NSError *error = nil;
  BOOL success = [context withTransactionUsingBlock:^BOOL(NSError **innerError) {
    BOOL firstSavepoint = [context withSavepointNamed:@"named_sp"
                                           usingBlock:^BOOL(NSError **savepointError) {
                                             (void)savepointError;
                                             return YES;
                                           }
                                                error:innerError];
    BOOL nestedTransaction = [context withTransactionUsingBlock:^BOOL(NSError **nestedError) {
      (void)nestedError;
      return YES;
    }
                                                       error:innerError];
    return firstSavepoint && nestedTransaction;
  }
                                          error:&error];
  XCTAssertTrue(success, @"%@", error);
  NSArray *expectedTransactionLog = @[
    @"BEGIN",
    @"SAVEPOINT:named_sp",
    @"RELEASE:named_sp",
    @"SAVEPOINT:aln_orm_nested_1",
    @"RELEASE:aln_orm_nested_1",
    @"COMMIT",
  ];
  XCTAssertEqualObjects(expectedTransactionLog, adapter.transactionLog);
}

- (void)testSaveDeleteAndUpsertHonorWriteOptionsAndOptimisticLocking {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedCommandResults addObjectsFromArray:@[ @1, @1, @0, @1, @1 ]];

  ALNORMContext *context = ALNORMRuntimeConfiguredAuditContext(adapter);
  ALNORMRepository *repository =
      [context repositoryForModelClass:[ALNORMRuntimePublicAuditEntriesModel class]];

  ALNORMRuntimePublicAuditEntriesModel *audit = [[ALNORMRuntimePublicAuditEntriesModel alloc] init];
  NSError *error = nil;
  XCTAssertTrue([audit setObject:@"audit-1" forFieldName:@"id" error:&error], @"%@", error);
  XCTAssertTrue([audit setObject:@"user-1" forFieldName:@"userId" error:&error], @"%@", error);
  XCTAssertTrue([audit setObject:@"pending" forFieldName:@"status" error:&error], @"%@", error);
  XCTAssertTrue([audit setObject:@{ @"ok" : @YES } forFieldName:@"payload" error:&error], @"%@", error);
  XCTAssertTrue([audit setObject:@[ @"alpha" ] forFieldName:@"tags" error:&error], @"%@", error);

  XCTAssertTrue([repository saveModel:audit error:&error], @"%@", error);
  XCTAssertEqualObjects(@1, [audit objectForFieldName:@"version"]);
  XCTAssertNotNil([audit objectForFieldName:@"createdAt"]);
  XCTAssertNotNil([audit objectForFieldName:@"updatedAt"]);
  XCTAssertTrue([[adapter.executedSQL firstObject] containsString:@"INSERT INTO \"public\".\"audit_entries\""]);

  XCTAssertTrue([audit setObject:@"stored" forFieldName:@"status" error:&error], @"%@", error);
  XCTAssertTrue([repository saveModel:audit error:&error], @"%@", error);
  XCTAssertEqualObjects(@2, [audit objectForFieldName:@"version"]);
  XCTAssertTrue([[adapter.executedSQL[1] description] containsString:@"UPDATE \"public\".\"audit_entries\""]);

  XCTAssertTrue([audit setObject:@"pending" forFieldName:@"status" error:&error], @"%@", error);
  XCTAssertFalse([repository saveModel:audit error:&error]);
  XCTAssertEqual(ALNORMErrorOptimisticLockConflict, error.code);

  XCTAssertTrue([repository deleteModel:audit error:&error], @"%@", error);
  XCTAssertEqual(ALNORMModelStateDetached, audit.state);

  ALNORMRuntimePublicAuditEntriesModel *upsertAudit = [[ALNORMRuntimePublicAuditEntriesModel alloc] init];
  XCTAssertTrue([upsertAudit setObject:@"audit-2" forFieldName:@"id" error:&error], @"%@", error);
  XCTAssertTrue([upsertAudit setObject:@"user-2" forFieldName:@"userId" error:&error], @"%@", error);
  XCTAssertTrue([upsertAudit setObject:@"stored" forFieldName:@"status" error:&error], @"%@", error);
  XCTAssertTrue([upsertAudit setObject:@{ @"ok" : @YES } forFieldName:@"payload" error:&error], @"%@", error);
  XCTAssertTrue([repository upsertModel:upsertAudit options:ALNORMRuntimeAuditWriteOptions() error:&error], @"%@", error);
  XCTAssertTrue([[adapter.executedSQL lastObject] containsString:@"ON CONFLICT (\"id\") DO UPDATE SET"]);
}

- (void)testExplicitGraphSavePersistsLoadedBelongsToWithoutImplicitReads {
  ORMRuntimeFakeAdapter *adapter = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedCommandResults addObjectsFromArray:@[ @1, @1 ]];

  ALNORMContext *context = ALNORMRuntimeConfiguredAuditContext(adapter);
  ALNORMRepository *auditRepository =
      [context repositoryForModelClass:[ALNORMRuntimePublicAuditEntriesModel class]];

  ALNORMRuntimePublicUsersModel *user = [[ALNORMRuntimePublicUsersModel alloc] init];
  NSError *error = nil;
  XCTAssertTrue([user setObject:@"user-graph" forFieldName:@"id" error:&error], @"%@", error);
  XCTAssertTrue([user setObject:@"graph@example.com" forFieldName:@"email" error:&error], @"%@", error);
  XCTAssertTrue([user setObject:@"Graph User" forFieldName:@"displayName" error:&error], @"%@", error);

  ALNORMRuntimePublicAuditEntriesModel *audit = [[ALNORMRuntimePublicAuditEntriesModel alloc] init];
  XCTAssertTrue([audit setObject:@"audit-graph" forFieldName:@"id" error:&error], @"%@", error);
  XCTAssertTrue([audit setObject:@"pending" forFieldName:@"status" error:&error], @"%@", error);
  XCTAssertTrue([audit setObject:@{ @"graph" : @YES } forFieldName:@"payload" error:&error], @"%@", error);
  XCTAssertTrue([audit setRelationObject:user forRelationName:@"user" error:&error], @"%@", error);

  ALNORMWriteOptions *options = ALNORMRuntimeAuditWriteOptions();
  options.saveRelatedRelationNames = @[ @"user" ];

  XCTAssertTrue([auditRepository saveModel:audit options:options error:&error], @"%@", error);
  XCTAssertEqualObjects(@"user-graph", [audit objectForFieldName:@"userId"]);
  NSArray *expectedKinds = @[ @"command", @"command" ];
  XCTAssertEqualObjects(expectedKinds, adapter.executedKinds);
  XCTAssertTrue([adapter.executedSQL[0] containsString:@"INSERT INTO \"users\""]);
  XCTAssertTrue([adapter.executedSQL[1] containsString:@"INSERT INTO \"public\".\"audit_entries\""]);
}

- (void)testReadOnlyModelsRejectMutationHelpers {
  ALNORMRuntimePublicUserEmailsModel *emailRow = [[ALNORMRuntimePublicUserEmailsModel alloc] init];
  NSError *error = nil;
  BOOL wrote = [emailRow setObject:@"mutate@example.com" forFieldName:@"email" error:&error];
  XCTAssertFalse(wrote);
  XCTAssertNotNil(error);
  XCTAssertEqual(ALNORMErrorReadOnlyMutation, error.code);
}

- (void)testCapabilityMetadataHonorsReflectionBoundary {
  ORMRuntimeFakeAdapter *postgres = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  ORMRuntimeFakeAdapter *sqlite = [[ORMRuntimeFakeAdapter alloc] initWithAdapterName:@"sqlite"];

  NSDictionary *postgresCapabilities = [ALNORMContext capabilityMetadataForAdapter:postgres];
  NSDictionary *sqliteCapabilities = [ALNORMContext capabilityMetadataForAdapter:sqlite];

  XCTAssertEqualObjects(@YES, postgresCapabilities[@"supports_schema_reflection"]);
  XCTAssertEqualObjects(@YES, postgresCapabilities[@"supports_sql_runtime"]);
  XCTAssertEqualObjects(@NO, sqliteCapabilities[@"supports_schema_reflection"]);
  XCTAssertEqualObjects(@NO, sqliteCapabilities[@"supports_sql_runtime"]);
  XCTAssertEqualObjects(@YES, postgresCapabilities[@"supports_savepoints"]);
  XCTAssertEqualObjects(@YES, postgresCapabilities[@"supports_upsert"]);
  XCTAssertEqualObjects(@NO, postgresCapabilities[@"supports_dataverse_orm"]);
}

@end
