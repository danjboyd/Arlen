#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseCodegen.h"
#import "ALNDataverseMetadata.h"
#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface DataverseMetadataTests : ALNDataverseTestCase
@end

@implementation DataverseMetadataTests

- (void)testMetadataFetchUsesEntityDefinitionsSummaryDetailsAndPicklists {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];

  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"LogicalName" : @"account",
                                               },
                                             ],
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"LogicalName" : @"account",
                                             @"SchemaName" : @"Account",
                                             @"EntitySetName" : @"accounts",
                                             @"PrimaryIdAttribute" : @"accountid",
                                             @"PrimaryNameAttribute" : @"name",
                                             @"DisplayName" : @{
                                               @"UserLocalizedLabel" : @{
                                                 @"Label" : @"Account",
                                               },
                                             },
                                             @"Attributes" : @[
                                               @{
                                                 @"LogicalName" : @"accountid",
                                                 @"SchemaName" : @"AccountId",
                                                 @"AttributeType" : @"Uniqueidentifier",
                                                 @"IsPrimaryId" : @YES,
                                               },
                                               @{
                                                 @"LogicalName" : @"name",
                                                 @"SchemaName" : @"Name",
                                                 @"AttributeType" : @"String",
                                               },
                                               @{
                                                 @"LogicalName" : @"statuscode",
                                                 @"SchemaName" : @"StatusCode",
                                                 @"AttributeType" : @"Picklist",
                                               },
                                             ],
                                             @"Keys" : @[
                                               @{
                                                 @"LogicalName" : @"accountnumber_key",
                                                 @"KeyAttributes" : @[ @"accountnumber" ],
                                               },
                                             ],
                                             @"ManyToOneRelationships" : @[
                                               @{
                                                 @"SchemaName" : @"lk_account_primarycontact",
                                                 @"ReferencingAttribute" : @"primarycontactid",
                                                 @"NavigationPropertyName" : @"primarycontactid",
                                                 @"ReferencedEntity" : @"contact",
                                                 @"ReferencedAttribute" : @"contactid",
                                               },
                                             ],
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"LogicalName" : @"statuscode",
                                                 @"SchemaName" : @"StatusCode",
                                                 @"DisplayName" : @{
                                                   @"UserLocalizedLabel" : @{
                                                     @"Label" : @"Status",
                                                   },
                                                 },
                                                 @"OptionSet" : @{
                                                   @"Options" : @[
                                                     @{
                                                       @"Value" : @1,
                                                       @"Label" : @{
                                                         @"UserLocalizedLabel" : @{
                                                           @"Label" : @"Active",
                                                         },
                                                       },
                                                     },
                                                   ],
                                                 },
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

  NSDictionary<NSString *, id> *metadata =
      [ALNDataverseMetadata fetchNormalizedMetadataWithClient:client logicalNames:nil error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(metadata[@"entity_count"], @1);
  XCTAssertEqualObjects(metadata[@"attribute_count"], @3);
  XCTAssertEqualObjects(metadata[@"entities"][0][@"attributes"][2][@"choices"][0][@"label"], @"Active");
  XCTAssertEqual((NSUInteger)3, transport.capturedRequests.count);
  XCTAssertTrue([transport.capturedRequests[0].URLString containsString:@"EntityDefinitions"]);
  XCTAssertTrue([transport.capturedRequests[1].URLString containsString:@"EntityDefinitions(LogicalName='account')"]);
  XCTAssertFalse([transport.capturedRequests[1].URLString containsString:@"Targets"]);
  XCTAssertFalse([transport.capturedRequests[1].URLString containsString:@"ReferencedAttribute,NavigationPropertyName"]);
  XCTAssertTrue([transport.capturedRequests[1].URLString containsString:@"ReferencingEntityNavigationPropertyName"]);
  XCTAssertTrue([transport.capturedRequests[2].URLString containsString:@"PicklistAttributeMetadata"]);
}

- (void)testMetadataNormalizationAndCodegenAreDeterministic {
  NSError *error = nil;
  NSDictionary *fixture = ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_entitydefinitions.json",
                                                              &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSDictionary<NSString *, id> *normalized = [ALNDataverseMetadata normalizedMetadataFromPayload:fixture error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(normalized[@"entity_count"], @2);
  XCTAssertEqualObjects(normalized[@"attribute_count"], @7);

  NSDictionary *firstEntity = normalized[@"entities"][0];
  XCTAssertEqualObjects(firstEntity[@"logical_name"], @"account");
  XCTAssertEqualObjects(firstEntity[@"entity_set_name"], @"accounts");
  XCTAssertEqualObjects(firstEntity[@"attributes"][0][@"logical_name"], @"accountid");
  XCTAssertEqualObjects(firstEntity[@"keys"][0][@"key_attributes"][0], @"accountnumber");
  XCTAssertEqualObjects(firstEntity[@"lookups"][0][@"navigation_property_name"], @"primarycontactid");
  XCTAssertEqualObjects(firstEntity[@"attributes"][4][@"choices"][0][@"label"], @"Active");

  NSMutableDictionary *reversedFixture = [fixture mutableCopy];
  reversedFixture[@"value"] = [[fixture[@"value"] reverseObjectEnumerator] allObjects];
  NSDictionary<NSString *, id> *normalizedReversed =
      [ALNDataverseMetadata normalizedMetadataFromPayload:reversedFixture error:&error];
  XCTAssertNil(error);

  NSDictionary<NSString *, id> *artifacts = [ALNDataverseCodegen renderArtifactsFromMetadata:normalized
                                                                                  classPrefix:@"ALNDV"
                                                                              dataverseTarget:@"crm"
                                                                                        error:&error];
  XCTAssertNil(error);
  NSDictionary<NSString *, id> *artifactsReversed =
      [ALNDataverseCodegen renderArtifactsFromMetadata:normalizedReversed
                                           classPrefix:@"ALNDV"
                                       dataverseTarget:@"crm"
                                                 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(artifacts[@"header"], artifactsReversed[@"header"]);
  XCTAssertEqualObjects(artifacts[@"implementation"], artifactsReversed[@"implementation"]);
  XCTAssertEqualObjects(artifacts[@"manifest"], artifactsReversed[@"manifest"]);
}

- (void)testDataverseCodegenCLIFromFixture {
  NSString *tempDir = ALNTestTemporaryDirectory(@"dataverse_codegen");
  XCTAssertNotNil(tempDir);
  NSString *fixturePath =
      ALNTestPathFromRepoRoot(@"tests/fixtures/phase23/dataverse_entitydefinitions.json");
  NSString *outputDir = [tempDir stringByAppendingPathComponent:@"Generated"];
  NSString *manifestPath = [tempDir stringByAppendingPathComponent:@"dataverse.json"];
  NSString *command = [NSString stringWithFormat:@"%@ && %@ dataverse-codegen --input %@ --output-dir %@ --manifest %@ --prefix ALNDV --force",
                                                 ALNTestGNUstepSourceCommandForRepoRoot(ALNTestRepoRoot()),
                                                 ALNTestShellQuote([ALNTestPathFromRepoRoot(@"build/arlen") stringByStandardizingPath]),
                                                 ALNTestShellQuote(fixturePath),
                                                 ALNTestShellQuote(outputDir),
                                                 ALNTestShellQuote(manifestPath)];
  int exitCode = 0;
  NSString *output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  XCTAssertTrue([output containsString:@"Generated Dataverse artifacts."]);

  NSString *headerPath = [outputDir stringByAppendingPathComponent:@"ALNDVDataverseSchema.h"];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:headerPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:manifestPath]);
  NSString *header = [NSString stringWithContentsOfFile:headerPath
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
  XCTAssertTrue([header containsString:@"@interface ALNDVAccount : NSObject"]);
}

@end
