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
                                                 @"accountid" : @"account-1",
                                                 @"name" : @"Acme",
                                                 @"accountnumber" : @"A-1",
                                                 @"_primarycontactid_value" : @"contact-1",
                                               },
                                             ],
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"contactid" : @"contact-1",
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
  XCTAssertEqualObjects([models[0] objectForFieldName:@"primarycontactid"], @"contact-1");

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
                                                 @"contactid" : @"contact-1",
                                                 @"fullname" : @"Chris Contact",
                                               },
                                             ],
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"accountid" : @"account-1",
                                                 @"name" : @"Acme",
                                                 @"accountnumber" : @"A-1",
                                                 @"_primarycontactid_value" : @"contact-1",
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

- (void)testDataverseChangesetsSaveUpsertDeleteAndBatchThroughClientContracts {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:201
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"account-2",
                                             @"name" : @"Beta",
                                             @"accountnumber" : @"A-200",
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"account-2",
                                             @"name" : @"Beta Updated",
                                             @"accountnumber" : @"A-200",
                                             @"@odata.etag" : @"W/\"2\"",
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"account-2",
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
  XCTAssertEqualObjects([account objectForFieldName:@"accountid"], @"account-2");
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
