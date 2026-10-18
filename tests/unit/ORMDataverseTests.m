#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"
#import "ALNDataverseMetadata.h"
#import "ArlenORM/ArlenORM.h"

static NSDictionary<NSString *, id> *ALNORMDataverseNormalizedMetadata(void) {
  static NSDictionary<NSString *, id> *normalized = nil;
  if (normalized == nil) {
    NSError *error = nil;
    NSDictionary *fixture =
        ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_entitydefinitions.json", &error);
    normalized = [ALNDataverseMetadata normalizedMetadataFromPayload:fixture error:&error];
  }
  return normalized ?: @{};
}

static NSArray<ALNORMDataverseModelDescriptor *> *ALNORMDataverseDescriptors(void) {
  static NSArray<ALNORMDataverseModelDescriptor *> *descriptors = nil;
  if (descriptors == nil) {
    NSError *error = nil;
    descriptors = [ALNORMDataverseCodegen modelDescriptorsFromMetadata:ALNORMDataverseNormalizedMetadata()
                                                            classPrefix:@"ALNORMDV"
                                                        dataverseTarget:@"crm"
                                                                  error:&error];
  }
  return descriptors ?: @[];
}

static ALNORMDataverseModelDescriptor *ALNORMDataverseDescriptorNamed(NSString *logicalName) {
  for (ALNORMDataverseModelDescriptor *descriptor in ALNORMDataverseDescriptors()) {
    if ([descriptor.logicalName isEqualToString:logicalName]) {
      return descriptor;
    }
  }
  return nil;
}

@interface ALNORMDVAccount : ALNORMDataverseModel
@end
@implementation ALNORMDVAccount
+ (ALNORMDataverseModelDescriptor *)dataverseModelDescriptor { return ALNORMDataverseDescriptorNamed(@"account"); }
@end

@interface ALNORMDVContact : ALNORMDataverseModel
@end
@implementation ALNORMDVContact
+ (ALNORMDataverseModelDescriptor *)dataverseModelDescriptor { return ALNORMDataverseDescriptorNamed(@"contact"); }
@end

@interface ORMDataverseTests : ALNDataverseTestCase
@end

@implementation ORMDataverseTests

- (void)testDataverseCodegenBuildsLookupAndReverseCollectionDescriptors {
  ALNORMDataverseModelDescriptor *account = ALNORMDataverseDescriptorNamed(@"account");
  ALNORMDataverseModelDescriptor *contact = ALNORMDataverseDescriptorNamed(@"contact");
  XCTAssertNotNil(account);
  XCTAssertNotNil(contact);

  ALNORMDataverseFieldDescriptor *lookupField = [account fieldNamed:@"primarycontactid"];
  XCTAssertNotNil(lookupField);
  XCTAssertEqualObjects(lookupField.readKey, @"_primarycontactid_value");

  ALNORMDataverseRelationDescriptor *lookupRelation = [account relationNamed:@"primarycontactid"];
  XCTAssertNotNil(lookupRelation);
  XCTAssertFalse(lookupRelation.isCollection);
  XCTAssertEqualObjects(lookupRelation.targetClassName, @"ALNORMDVContact");

  ALNORMDataverseRelationDescriptor *reverseRelation = [contact relationNamed:@"accounts"];
  XCTAssertNotNil(reverseRelation);
  XCTAssertTrue(reverseRelation.isCollection);
  XCTAssertTrue(reverseRelation.isInferred);
  XCTAssertEqualObjects(reverseRelation.targetClassName, @"ALNORMDVAccount");
}

- (void)testDataverseRepositoryMaterializesRecordsAndLoadsExplicitRelations {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"accountid" : @"00000000-0000-0000-0000-0000000000a1",
                                                 @"name" : @"Acme",
                                                 @"accountnumber" : @"A-1",
                                                 @"_primarycontactid_value" : @"00000000-0000-0000-0000-0000000000c1",
                                               },
                                             ],
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"contactid" : @"00000000-0000-0000-0000-0000000000c1",
                                             @"fullname" : @"Chris Contact",
                                           }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNORMDataverseContext *context = [[ALNORMDataverseContext alloc] initWithClient:client];
  ALNORMDataverseRepository *accounts = [context repositoryForModelClass:[ALNORMDVAccount class]];
  NSArray<ALNORMDVAccount *> *models = [accounts all:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [models count]);
  XCTAssertEqualObjects([models[0] objectForFieldName:@"primarycontactid"], @"00000000-0000-0000-0000-0000000000c1");

  XCTAssertTrue([accounts loadRelationNamed:@"primarycontactid" fromModel:models[0] error:&error], @"%@", error);
  XCTAssertNil(error);
  id contact = [models[0] relationObjectForName:@"primarycontactid"];
  XCTAssertTrue([contact isKindOfClass:[ALNORMDVContact class]]);
  XCTAssertEqualObjects([contact objectForFieldName:@"fullname"], @"Chris Contact");
  XCTAssertEqual((NSUInteger)2, context.queryCount);
}

- (void)testDataverseReverseCollectionLoadsThroughExplicitQuery {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"contactid" : @"00000000-0000-0000-0000-0000000000c1",
                                                 @"fullname" : @"Chris Contact",
                                               },
                                             ],
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"accountid" : @"00000000-0000-0000-0000-0000000000a1",
                                                 @"name" : @"Acme",
                                                 @"accountnumber" : @"A-1",
                                                 @"_primarycontactid_value" : @"00000000-0000-0000-0000-0000000000c1",
                                               },
                                             ],
                                           }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNORMDataverseContext *context = [[ALNORMDataverseContext alloc] initWithClient:client];
  ALNORMDataverseRepository *contacts = [context repositoryForModelClass:[ALNORMDVContact class]];
  ALNORMDVContact *contact = [[contacts all:&error] firstObject];
  XCTAssertNil(error);
  XCTAssertNotNil(contact);

  XCTAssertTrue([contacts loadRelationNamed:@"accounts" fromModel:contact error:&error], @"%@", error);
  XCTAssertNil(error);
  NSArray *relatedAccounts = [contact relationObjectForName:@"accounts"];
  XCTAssertEqual((NSUInteger)1, [relatedAccounts count]);
  XCTAssertEqualObjects([relatedAccounts[0] objectForFieldName:@"name"], @"Acme");
}

// PATCH and DELETE target the model's primary ID, so a persisted record's ID
// must not be writable from input.
- (void)testPersistedDataverseRecordKeepsItsPrimaryID {
  NSError *error = nil;
  ALNDataverseRecord *record =
      [ALNDataverseRecord recordWithDictionary:@{ @"accountid" : @"account-2", @"name" : @"Beta" } error:&error];
  XCTAssertNotNil(record, @"%@", error);
  ALNORMDVAccount *account = [[ALNORMDVAccount alloc] init];
  XCTAssertTrue([account applyRecord:record error:&error], @"%@", error);
  XCTAssertEqualObjects(@"account-2", [account primaryIDValue]);

  error = nil;
  XCTAssertFalse([account setObject:@"account-9" forFieldName:@"accountid" error:&error]);
  XCTAssertEqual(ALNORMErrorReadOnlyMutation, error.code);
  XCTAssertEqualObjects(@"account-2", [account primaryIDValue]);

  ALNORMDataverseChangeset *changeset = [ALNORMDataverseChangeset changesetWithModel:account];
  NSDictionary *payload = @{ @"accountid" : @"account-9", @"name" : @"Defaced" };
  BOOL moved = [changeset applyInputValues:payload error:&error] && [changeset applyToModel:&error];
  XCTAssertFalse(moved, @"a changeset must not move a persisted record to another ID");
  XCTAssertEqualObjects(@"account-2", [account primaryIDValue]);
  XCTAssertEqualObjects(@"account-2", [account persistedPrimaryIDValue]);
}

// A record loaded with a $select that left out its primary ID can't be told
// which record it is: no setter or changeset may supply one, and saves and
// deletes refuse instead of creating a duplicate or hitting another record.
- (void)testDataverseRecordLoadedWithoutItsIDRefusesWrites {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:[[ALNFakeDataverseTokenProvider alloc] init]
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNotNil(client, @"%@", error);
  ALNORMDataverseContext *context = [[ALNORMDataverseContext alloc] initWithClient:client];
  ALNORMDataverseRepository *accounts = [context repositoryForModelClass:[ALNORMDVAccount class]];

  ALNDataverseRecord *record = [ALNDataverseRecord recordWithDictionary:@{ @"name" : @"Beta" } error:&error];
  ALNORMDVAccount *account = [[ALNORMDVAccount alloc] init];
  XCTAssertTrue([account applyRecord:record error:&error], @"%@", error);
  XCTAssertTrue(account.isPersisted);
  XCTAssertNil([account persistedPrimaryIDValue]);

  error = nil;
  XCTAssertFalse([account setObject:@"account-9" forFieldName:@"accountid" error:&error]);
  XCTAssertEqual(ALNORMErrorReadOnlyMutation, error.code);

  error = nil;
  ALNORMDataverseChangeset *retarget = [ALNORMDataverseChangeset changesetWithModel:account];
  NSDictionary *payload = @{ @"accountid" : @"account-9", @"name" : @"Defaced" };
  XCTAssertFalse([retarget applyInputValues:payload error:&error]);
  XCTAssertEqual(ALNORMErrorReadOnlyMutation, error.code);

  error = nil;
  XCTAssertTrue([account setObject:@"Renamed" forFieldName:@"name" error:&error], @"%@", error);
  XCTAssertFalse([accounts saveModel:account error:&error]);
  XCTAssertEqual(ALNORMErrorMissingField, error.code);
  error = nil;
  XCTAssertFalse([accounts deleteModel:account error:&error]);
  XCTAssertEqual(ALNORMErrorMissingField, error.code);
  error = nil;
  NSArray *models = @[ account ];
  XCTAssertFalse([accounts saveModelsInBatch:models changesets:@[] error:&error]);
  XCTAssertEqual(ALNORMErrorMissingField, error.code);
  XCTAssertEqual((NSUInteger)0, [transport.capturedRequests count]);
}

// A server may ignore return=representation and answer a PATCH with 204. The
// model then keeps the ID it was saved with, so the next save still PATCHes the
// same record instead of being refused.
- (void)testDataverseUpdateAnsweredWith204KeepsThePersistedID {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:[[ALNFakeDataverseTokenProvider alloc] init]
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNotNil(client, @"%@", error);
  ALNORMDataverseContext *context = [[ALNORMDataverseContext alloc] initWithClient:client];
  ALNORMDataverseRepository *accounts = [context repositoryForModelClass:[ALNORMDVAccount class]];

  ALNDataverseRecord *record =
      [ALNDataverseRecord recordWithDictionary:@{ @"accountid" : @"3f2504e0-4f89-11d3-9a0c-0305e82c3301", @"name" : @"Beta" } error:&error];
  ALNORMDVAccount *account = [[ALNORMDVAccount alloc] init];
  XCTAssertTrue([account applyRecord:record error:&error], @"%@", error);

  XCTAssertTrue([account setObject:@"First" forFieldName:@"name" error:&error], @"%@", error);
  XCTAssertTrue([accounts saveModel:account error:&error], @"%@", error);
  XCTAssertEqualObjects(@"3f2504e0-4f89-11d3-9a0c-0305e82c3301", [account persistedPrimaryIDValue]);
  XCTAssertEqualObjects(@"First", [account objectForFieldName:@"name"]);
  XCTAssertEqual((NSUInteger)0, [account.dirtyFieldNames count]);

  error = nil;
  XCTAssertTrue([account setObject:@"Second" forFieldName:@"name" error:&error], @"%@", error);
  XCTAssertTrue([accounts saveModel:account error:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)2, [transport.capturedRequests count]);
  for (ALNDataverseRequest *request in transport.capturedRequests) {
    XCTAssertEqualObjects(@"PATCH", request.method);
    XCTAssertTrue([request.URLString containsString:@"3f2504e0-4f89-11d3-9a0c-0305e82c3301"], @"%@", request.URLString);
  }
}

- (void)testDataversePermittedFieldsDropUnlistedInput {
  NSError *error = nil;
  ALNDataverseRecord *record =
      [ALNDataverseRecord recordWithDictionary:@{ @"accountid" : @"account-2", @"name" : @"Beta" } error:&error];
  ALNORMDVAccount *account = [[ALNORMDVAccount alloc] init];
  XCTAssertTrue([account applyRecord:record error:&error], @"%@", error);

  ALNORMDataverseChangeset *changeset = [ALNORMDataverseChangeset changesetWithModel:account];
  NSDictionary *payload = @{ @"accountid" : @"account-9", @"name" : @"Renamed", @"accountnumber" : @"Z-9" };
  NSArray *permitted = @[ @"name" ];
  XCTAssertTrue([changeset applyInputValues:payload permittedFields:permitted error:&error], @"%@", error);
  XCTAssertEqualObjects((@[ @"name" ]), [changeset changedFieldNames]);
  XCTAssertEqualObjects(@"Renamed", changeset.values[@"name"]);
  XCTAssertNil(changeset.values[@"accountid"]);
  XCTAssertNil(changeset.values[@"accountnumber"]);

  error = nil;
  NSArray *unknown = @[ @"nope" ];
  BOOL appliedUnknown = [[ALNORMDataverseChangeset changesetWithModel:account] applyInputValues:@{}
                                                                                 permittedFields:unknown
                                                                                           error:&error];
  XCTAssertFalse(appliedUnknown);
  XCTAssertEqual(ALNORMErrorInvalidArgument, error.code);
}

- (void)testDataverseChangesetsSaveUpsertDeleteAndBatchThroughClientContracts {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:201
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"00000000-0000-0000-0000-0000000000a2",
                                             @"name" : @"Beta",
                                             @"accountnumber" : @"A-200",
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"00000000-0000-0000-0000-0000000000a2",
                                             @"name" : @"Beta Updated",
                                             @"accountnumber" : @"A-200",
                                             @"@odata.etag" : @"W/\"2\"",
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"00000000-0000-0000-0000-0000000000a2",
                                             @"name" : @"Beta Upserted",
                                             @"accountnumber" : @"A-200",
                                           }]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];

  NSString *batchBody =
      @"--batchresponse_orm\r\n"
       "Content-Type: application/http\r\n"
       "Content-Transfer-Encoding: binary\r\n"
       "\r\n"
       "HTTP/1.1 204 No Content\r\n"
       "Content-ID: 1\r\n"
       "\r\n"
       "\r\n"
       "--batchresponse_orm\r\n"
       "Content-Type: application/http\r\n"
       "Content-Transfer-Encoding: binary\r\n"
       "\r\n"
       "HTTP/1.1 204 No Content\r\n"
       "Content-ID: 2\r\n"
       "\r\n"
       "\r\n"
       "--batchresponse_orm--\r\n";
  [transport enqueueResponse:[[ALNDataverseResponse alloc]
                                 initWithStatusCode:200
                                            headers:@{ @"Content-Type" : @"multipart/mixed; boundary=batchresponse_orm" }
                                           bodyData:[batchBody dataUsingEncoding:NSUTF8StringEncoding]]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNORMDataverseContext *context = [[ALNORMDataverseContext alloc] initWithClient:client];
  ALNORMDataverseRepository *accounts = [context repositoryForModelClass:[ALNORMDVAccount class]];
  ALNORMDVAccount *account = [[ALNORMDVAccount alloc] init];

  ALNORMDataverseChangeset *createChangeset = [ALNORMDataverseChangeset changesetWithModel:account];
  BOOL createApplied = [createChangeset applyInputValues:@{ @"name" : @"Beta", @"accountnumber" : @"A-200" }
                                                   error:&error];
  XCTAssertTrue(createApplied, @"%@", error);
  XCTAssertTrue([accounts saveModel:account changeset:createChangeset error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqualObjects([account objectForFieldName:@"accountid"], @"00000000-0000-0000-0000-0000000000a2");
  XCTAssertEqualObjects([account objectForFieldName:@"name"], @"Beta");

  ALNORMDataverseChangeset *updateChangeset = [ALNORMDataverseChangeset changesetWithModel:account];
  BOOL updateApplied = [updateChangeset applyInputValues:@{ @"name" : @"Beta Updated" } error:&error];
  XCTAssertTrue(updateApplied, @"%@", error);
  XCTAssertTrue([accounts saveModel:account changeset:updateChangeset error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqualObjects([account objectForFieldName:@"name"], @"Beta Updated");

  ALNORMDataverseChangeset *upsertChangeset = [ALNORMDataverseChangeset changesetWithModel:account];
  BOOL upsertApplied = [upsertChangeset applyInputValues:@{ @"name" : @"Beta Upserted" } error:&error];
  XCTAssertTrue(upsertApplied, @"%@", error);
  XCTAssertTrue([accounts upsertModel:account
                    alternateKeyFields:@[ @"accountnumber" ]
                             changeset:upsertChangeset
                                 error:&error],
                @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqualObjects([account objectForFieldName:@"name"], @"Beta Upserted");

  XCTAssertTrue([accounts deleteModel:account error:&error], @"%@", error);
  XCTAssertNil(error);

  ALNORMDVAccount *batchA = [[ALNORMDVAccount alloc] init];
  ALNORMDVAccount *batchB = [[ALNORMDVAccount alloc] init];
  ALNORMDataverseChangeset *batchChangesetA = [ALNORMDataverseChangeset changesetWithModel:batchA];
  ALNORMDataverseChangeset *batchChangesetB = [ALNORMDataverseChangeset changesetWithModel:batchB];
  BOOL batchAppliedA = [batchChangesetA applyInputValues:@{ @"name" : @"Batch A", @"accountnumber" : @"A-201" }
                                                   error:&error];
  BOOL batchAppliedB = [batchChangesetB applyInputValues:@{ @"name" : @"Batch B", @"accountnumber" : @"A-202" }
                                                   error:&error];
  XCTAssertTrue(batchAppliedA, @"%@", error);
  XCTAssertTrue(batchAppliedB, @"%@", error);
  BOOL batchSaved = [accounts saveModelsInBatch:@[ batchA, batchB ]
                                     changesets:@[ batchChangesetA, batchChangesetB ]
                                          error:&error];
  XCTAssertTrue(batchSaved, @"%@", error);
  XCTAssertNil(error);
  XCTAssertTrue([transport.capturedRequests[4].URLString hasSuffix:@"/$batch"]);
}

@end
