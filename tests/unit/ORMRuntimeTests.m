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

@interface ORMRuntimeFakeAdapter : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, strong) NSMutableArray<NSArray<NSDictionary<NSString *, id> *> *> *queuedRowSets;
@property(nonatomic, strong) NSMutableArray<NSString *> *executedSQL;
@property(nonatomic, strong) NSMutableArray<NSArray *> *executedParameters;

- (instancetype)initWithAdapterName:(NSString *)adapterName;

@end

@implementation ORMRuntimeFakeAdapter

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self != nil) {
    _adapterNameValue = [adapterName copy] ?: @"postgresql";
    _queuedRowSets = [NSMutableArray array];
    _executedSQL = [NSMutableArray array];
    _executedParameters = [NSMutableArray array];
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapterNameValue ?: @"postgresql";
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  (void)error;
  return nil;
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
  [self.executedSQL addObject:sql ?: @""];
  [self.executedParameters addObject:parameters ?: @[]];
  if ([self.queuedRowSets count] == 0) {
    return @[];
  }
  NSArray<NSDictionary<NSString *, id> *> *next = self.queuedRowSets[0];
  [self.queuedRowSets removeObjectAtIndex:0];
  return next;
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  return 0;
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  return (block != nil) ? block(nil, error) : YES;
}

@end

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
  XCTAssertEqualObjects(@NO, postgresCapabilities[@"supports_dataverse_orm"]);

  XCTAssertEqualObjects(@NO, sqliteCapabilities[@"supports_schema_reflection"]);
  XCTAssertEqualObjects(@NO, sqliteCapabilities[@"supports_sql_runtime"]);
}

@end
