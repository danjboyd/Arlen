#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseCodegen.h"
#import "ALNDataverseMetadata.h"
#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface DataverseMetadataTests : ALNDataverseTestCase
@end

static NSUInteger DataverseMetadataCountOccurrences(NSString *text, NSString *needle) {
  if (![text isKindOfClass:[NSString class]] || ![needle isKindOfClass:[NSString class]] || [needle length] == 0) {
    return 0;
  }

  NSUInteger count = 0;
  NSRange searchRange = NSMakeRange(0, [text length]);
  while (searchRange.location != NSNotFound && searchRange.location < [text length]) {
    NSRange match = [text rangeOfString:needle options:0 range:searchRange];
    if (match.location == NSNotFound) {
      break;
    }
    count += 1;
    NSUInteger nextLocation = NSMaxRange(match);
    if (nextLocation >= [text length]) {
      break;
    }
    searchRange = NSMakeRange(nextLocation, [text length] - nextLocation);
  }
  return count;
}

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
  XCTAssertTrue([transport.capturedRequests[1].URLString containsString:@"AttributeOf"]);
  XCTAssertTrue([transport.capturedRequests[1].URLString containsString:@"IsValidODataAttribute"]);
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

- (void)testDataverseCodegenHandlesPolymorphicLookupNavigationCollisions {
  NSError *error = nil;
  NSDictionary *fixture =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_polymorphic_entitydefinitions.json",
                                          &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSDictionary<NSString *, id> *normalized = [ALNDataverseMetadata normalizedMetadataFromPayload:fixture error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(normalized[@"entity_count"], @2);
  XCTAssertEqualObjects(normalized[@"attribute_count"], @7);

  NSDictionary<NSString *, id> *artifacts = [ALNDataverseCodegen renderArtifactsFromMetadata:normalized
                                                                                  classPrefix:@"ALNDV"
                                                                              dataverseTarget:@"crm"
                                                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);

  NSString *header = [artifacts[@"header"] isKindOfClass:[NSString class]] ? artifacts[@"header"] : @"";
  NSString *implementation =
      [artifacts[@"implementation"] isKindOfClass:[NSString class]] ? artifacts[@"implementation"] : @"";

  XCTAssertTrue([header containsString:@"+ (NSDictionary<NSString *, NSArray<NSString *> *> *)lookupNavigationTargetsMap;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)navigationCampaignid;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)navigationCustomeridAccount;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)navigationCustomeridContact;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)navigationParentcustomeridAccount;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)navigationParentcustomeridContact;"]);
  XCTAssertFalse([header containsString:@"+ (NSString *)navigationCustomerid;"]);
  XCTAssertFalse([header containsString:@"+ (NSString *)navigationParentcustomerid;"]);

  XCTAssertTrue([implementation containsString:@"@\"campaignid\": @\"campaignid\""]);
  XCTAssertFalse([implementation containsString:@"@\"customerid\": @\"customerid_"]);
  XCTAssertFalse([implementation containsString:@"@\"parentcustomerid\": @\"parentcustomerid_"]);
  XCTAssertTrue([implementation containsString:@"@\"customerid\": @[ @\"customerid_account\", @\"customerid_contact\" ]"]);
  XCTAssertTrue([implementation containsString:@"@\"parentcustomerid\": @[ @\"parentcustomerid_account\", @\"parentcustomerid_contact\" ]"]);
  XCTAssertEqual((NSUInteger)1,
                 DataverseMetadataCountOccurrences(implementation,
                                                   @"+ (NSString *)navigationCustomeridAccount { return @\"customerid_account\"; }"));
  XCTAssertEqual((NSUInteger)1,
                 DataverseMetadataCountOccurrences(implementation,
                                                   @"+ (NSString *)navigationCustomeridContact { return @\"customerid_contact\"; }"));

  NSDictionary *manifest = ALNTestJSONDictionaryFromString(artifacts[@"manifest"], &error);
  XCTAssertNil(error);
  NSArray *manifestEntities = [manifest[@"entities"] isKindOfClass:[NSArray class]] ? manifest[@"entities"] : @[];
  NSDictionary *leadEntity = nil;
  for (NSDictionary *entity in manifestEntities) {
    if ([entity[@"logical_name"] isEqualToString:@"lead"]) {
      leadEntity = entity;
      break;
    }
  }
  XCTAssertNotNil(leadEntity);

  NSArray *leadLookups = [leadEntity[@"lookups"] isKindOfClass:[NSArray class]] ? leadEntity[@"lookups"] : @[];
  NSDictionary *campaignLookup = nil;
  NSDictionary *customerLookup = nil;
  for (NSDictionary *lookup in leadLookups) {
    if ([lookup[@"attribute"] isEqualToString:@"campaignid"]) {
      campaignLookup = lookup;
    } else if ([lookup[@"attribute"] isEqualToString:@"customerid"]) {
      customerLookup = lookup;
    }
  }
  XCTAssertNotNil(campaignLookup);
  XCTAssertNotNil(customerLookup);
  XCTAssertEqualObjects(campaignLookup[@"polymorphic"], @NO);
  XCTAssertEqualObjects(campaignLookup[@"lookup_map_included"], @YES);
  XCTAssertEqualObjects(campaignLookup[@"method_names"], @[ @"navigationCampaignid" ]);
  XCTAssertEqualObjects(customerLookup[@"polymorphic"], @YES);
  XCTAssertEqualObjects(customerLookup[@"lookup_map_included"], @NO);
  XCTAssertEqualObjects(customerLookup[@"method_names"], (@[ @"navigationCustomeridAccount", @"navigationCustomeridContact" ]));
  XCTAssertEqualObjects(customerLookup[@"navigation_targets"], (@[ @"customerid_account", @"customerid_contact" ]));
}

- (void)testDataverseCodegenSeparatesNonSelectableLookupNameFields {
  NSError *error = nil;
  NSDictionary *fixture = ALNTestJSONDictionaryAtRelativePath(
      @"tests/fixtures/phase23/dataverse_nonselectable_lookup_name_entitydefinitions.json",
      &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSDictionary<NSString *, id> *normalized = [ALNDataverseMetadata normalizedMetadataFromPayload:fixture error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(normalized[@"entity_count"], @1);
  XCTAssertEqualObjects(normalized[@"attribute_count"], @7);

  NSDictionary *leadEntity = normalized[@"entities"][0];
  NSArray *attributes = [leadEntity[@"attributes"] isKindOfClass:[NSArray class]] ? leadEntity[@"attributes"] : @[];
  NSDictionary *offerNameAttribute = nil;
  NSDictionary *prospectNameAttribute = nil;
  for (NSDictionary *attribute in attributes) {
    if ([attribute[@"logical_name"] isEqualToString:@"synact_offername"]) {
      offerNameAttribute = attribute;
    } else if ([attribute[@"logical_name"] isEqualToString:@"synact_prospectname"]) {
      prospectNameAttribute = attribute;
    }
  }
  XCTAssertNotNil(offerNameAttribute);
  XCTAssertNotNil(prospectNameAttribute);
  XCTAssertEqualObjects(offerNameAttribute[@"attribute_of"], @"synact_offer");
  XCTAssertEqualObjects(offerNameAttribute[@"odata_selectable"], @NO);
  XCTAssertEqualObjects(prospectNameAttribute[@"attribute_of"], @"synact_prospect");
  XCTAssertEqualObjects(prospectNameAttribute[@"odata_selectable"], @NO);

  NSDictionary<NSString *, id> *artifacts = [ALNDataverseCodegen renderArtifactsFromMetadata:normalized
                                                                                  classPrefix:@"ALNDV"
                                                                              dataverseTarget:@"crm"
                                                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);

  NSString *header = [artifacts[@"header"] isKindOfClass:[NSString class]] ? artifacts[@"header"] : @"";
  NSString *implementation =
      [artifacts[@"implementation"] isKindOfClass:[NSString class]] ? artifacts[@"implementation"] : @"";

  XCTAssertTrue([header containsString:@"+ (NSArray<NSString *> *)selectableFields;"]);
  XCTAssertTrue([header containsString:@"+ (NSArray<NSString *> *)nonSelectableFields;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)fieldSynactOffer;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)fieldSynactProspect;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)fieldSynactReferenceid;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)nonSelectableFieldSynactOffername;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)nonSelectableFieldSynactProspectname;"]);
  XCTAssertFalse([header containsString:@"+ (NSString *)fieldSynactOffername;"]);
  XCTAssertFalse([header containsString:@"+ (NSString *)fieldSynactProspectname;"]);

  XCTAssertTrue([implementation containsString:@"@\"synact_offer\", @\"synact_prospect\", @\"synact_referenceid\""]);
  XCTAssertTrue([implementation containsString:@"@\"synact_offername\", @\"synact_prospectname\""]);
  XCTAssertEqual((NSUInteger)1,
                 DataverseMetadataCountOccurrences(implementation,
                                                   @"+ (NSString *)nonSelectableFieldSynactOffername { return @\"synact_offername\"; }"));
  XCTAssertEqual((NSUInteger)1,
                 DataverseMetadataCountOccurrences(implementation,
                                                   @"+ (NSString *)nonSelectableFieldSynactProspectname { return @\"synact_prospectname\"; }"));

  NSDictionary *manifest = ALNTestJSONDictionaryFromString(artifacts[@"manifest"], &error);
  XCTAssertNil(error);
  NSDictionary *manifestLead = [manifest[@"entities"] isKindOfClass:[NSArray class]] ? [manifest[@"entities"] firstObject] : nil;
  XCTAssertNotNil(manifestLead);
  XCTAssertEqualObjects(manifestLead[@"selectable_attribute_count"], @5);
  XCTAssertEqualObjects(manifestLead[@"non_selectable_attribute_count"], @2);
  NSArray *manifestAttributes = [manifestLead[@"attributes"] isKindOfClass:[NSArray class]] ? manifestLead[@"attributes"] : @[];
  NSDictionary *manifestOfferName = nil;
  for (NSDictionary *attribute in manifestAttributes) {
    if ([attribute[@"logical_name"] isEqualToString:@"synact_offername"]) {
      manifestOfferName = attribute;
      break;
    }
  }
  XCTAssertNotNil(manifestOfferName);
  XCTAssertEqualObjects(manifestOfferName[@"method_name"], @"nonSelectableFieldSynactOffername");
  XCTAssertEqualObjects(manifestOfferName[@"selectable"], @NO);
  XCTAssertEqualObjects(manifestOfferName[@"attribute_of"], @"synact_offer");
}

- (void)testDataverseCodegenCLIFromFixture {
  NSString *tempDir = ALNTestTemporaryDirectory(@"dataverse_codegen");
  XCTAssertNotNil(tempDir);
  NSString *fixturePath =
      ALNTestPathFromRepoRoot(@"tests/fixtures/phase23/dataverse_entitydefinitions.json");
  NSString *outputDir = [tempDir stringByAppendingPathComponent:@"Generated"];
  NSString *manifestPath = [tempDir stringByAppendingPathComponent:@"dataverse.json"];
  NSString *arlenCLIPath = ALNTestPathFromRepoRoot(@"bin/arlen");

  NSString *command = [NSString stringWithFormat:@"%@ && LD_PRELOAD='' XCTEST_LD_PRELOAD='' ASAN_OPTIONS='' UBSAN_OPTIONS='' EXTRA_OBJC_FLAGS='' %@ dataverse-codegen --input %@ --output-dir %@ --manifest %@ --prefix ALNDV --force",
                                                 ALNTestGNUstepSourceCommandForRepoRoot(ALNTestRepoRoot()),
                                                 ALNTestShellQuote([arlenCLIPath stringByStandardizingPath]),
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
