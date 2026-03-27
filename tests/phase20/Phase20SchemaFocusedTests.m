#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDataTestAssertions.h"
#import "../shared/ALNTestSupport.h"
#import "ALNDatabaseInspector.h"
#import "ALNSchemaCodegen.h"

@interface Phase20SchemaFocusedFakeAdapter : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy) NSString *adapter;
@property(nonatomic, strong) NSMutableArray<NSArray<NSDictionary<NSString *, id> *> *> *queuedRowSets;
@property(nonatomic, assign) NSInteger queryCount;

- (instancetype)initWithAdapterName:(NSString *)adapterName;

@end

@implementation Phase20SchemaFocusedFakeAdapter

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self != nil) {
    _adapter = [adapterName copy] ?: @"";
    _queuedRowSets = [NSMutableArray array];
    _queryCount = 0;
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapter;
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
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  self.queryCount += 1;
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

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection, NSError **error))block
                            error:(NSError **)error {
  (void)block;
  if (error != NULL) {
    *error = nil;
  }
  return YES;
}

@end

@interface Phase20SchemaFocusedTests : XCTestCase
@end

@implementation Phase20SchemaFocusedTests

- (NSDictionary *)fixtureNamed:(NSString *)relativePath {
  NSError *error = nil;
  NSDictionary *fixture = ALNTestJSONDictionaryAtRelativePath(relativePath, &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);
  return fixture ?: @{};
}

- (NSArray<NSDictionary *> *)mixedRelationRows {
  return @[
    @{
      @"schema" : @"public",
      @"table" : @"users",
      @"column" : @"id",
      @"ordinal" : @1,
      @"data_type" : @"uuid",
      @"nullable" : @NO,
      @"primary_key" : @YES,
      @"has_default" : @YES,
      @"default_value_shape" : @"expression",
      @"relation_kind" : @"table",
      @"read_only" : @NO,
    },
    @{
      @"schema" : @"public",
      @"table" : @"user_emails",
      @"column" : @"email",
      @"ordinal" : @1,
      @"data_type" : @"text",
      @"nullable" : @YES,
      @"primary_key" : @NO,
      @"has_default" : @NO,
      @"default_value_shape" : @"none",
      @"relation_kind" : @"view",
      @"read_only" : @YES,
    },
  ];
}

- (void)testInspectorMetadataMatchesPhase20FixtureContract {
  NSDictionary *fixture =
      [self fixtureNamed:@"tests/fixtures/phase20/postgres_inspector_metadata_contract.json"];
  NSDictionary *expected = [fixture[@"expected_metadata"] isKindOfClass:[NSDictionary class]]
                               ? fixture[@"expected_metadata"]
                               : @{};

  Phase20SchemaFocusedFakeAdapter *adapter =
      [[Phase20SchemaFocusedFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  [adapter.queuedRowSets addObject:[fixture[@"relation_rows"] isKindOfClass:[NSArray class]] ? fixture[@"relation_rows"] : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"column_rows"] isKindOfClass:[NSArray class]] ? fixture[@"column_rows"] : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"primary_key_rows"] isKindOfClass:[NSArray class]] ? fixture[@"primary_key_rows"] : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"unique_constraint_rows"] isKindOfClass:[NSArray class]]
                                    ? fixture[@"unique_constraint_rows"]
                                    : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"foreign_key_rows"] isKindOfClass:[NSArray class]] ? fixture[@"foreign_key_rows"] : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"index_rows"] isKindOfClass:[NSArray class]] ? fixture[@"index_rows"] : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"check_constraint_rows"] isKindOfClass:[NSArray class]]
                                    ? fixture[@"check_constraint_rows"]
                                    : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"view_definition_rows"] isKindOfClass:[NSArray class]]
                                    ? fixture[@"view_definition_rows"]
                                    : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"relation_comment_rows"] isKindOfClass:[NSArray class]]
                                    ? fixture[@"relation_comment_rows"]
                                    : @[]];
  [adapter.queuedRowSets addObject:[fixture[@"column_comment_rows"] isKindOfClass:[NSArray class]]
                                    ? fixture[@"column_comment_rows"]
                                    : @[]];

  NSError *error = nil;
  NSDictionary *metadata = [ALNDatabaseInspector inspectSchemaMetadataForAdapter:adapter error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)10, adapter.queryCount);
  XCTAssertEqualObjects(expected, metadata);
}

- (void)testSchemaCodegenTreatsViewsAsReadOnlyRelations {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:[self mixedRelationRows]
                                                              classPrefix:@"ALNDB"
                                                           databaseTarget:nil
                                                    includeTypedContracts:YES
                                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);

  NSString *header = [artifacts[@"header"] isKindOfClass:[NSString class]] ? artifacts[@"header"] : @"";
  NSString *implementation =
      [artifacts[@"implementation"] isKindOfClass:[NSString class]] ? artifacts[@"implementation"] : @"";
  NSString *manifest = [artifacts[@"manifest"] isKindOfClass:[NSString class]] ? artifacts[@"manifest"] : @"";

  XCTAssertFalse([header containsString:@"@interface ALNDBPublicUserEmailsInsert : NSObject"]);
  XCTAssertFalse([header containsString:@"@interface ALNDBPublicUserEmailsUpdate : NSObject"]);
  XCTAssertTrue([header containsString:@"@interface ALNDBPublicUserEmailsRow : NSObject"]);
  XCTAssertTrue([implementation containsString:@"+ (NSString *)relationKind {\n  return @\"view\";\n}"]);
  XCTAssertTrue([implementation containsString:@"+ (BOOL)isReadOnlyRelation {\n  return YES;\n}"]);
  XCTAssertTrue([manifest containsString:@"\"relation_kind\": \"view\""]);
  XCTAssertTrue([manifest containsString:@"\"read_only\": true"]);
  XCTAssertTrue([manifest containsString:@"\"supports_write_contracts\": false"]);
}

- (void)testInspectorRejectsUnsupportedAdaptersWithSharedDiagnosticsAssertions {
  Phase20SchemaFocusedFakeAdapter *adapter =
      [[Phase20SchemaFocusedFakeAdapter alloc] initWithAdapterName:@"sqlite"];

  NSError *error = nil;
  NSArray *normalized = [ALNDatabaseInspector inspectSchemaColumnsForAdapter:adapter error:&error];
  XCTAssertNil(normalized);
  ALNAssertErrorDetails(error,
                        ALNDatabaseInspectorErrorDomain,
                        ALNDatabaseInspectorErrorUnsupportedAdapter,
                        @"does not support this adapter");
}

@end
