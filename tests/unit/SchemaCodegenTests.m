#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNSchemaCodegen.h"

@interface SchemaCodegenTests : XCTestCase
@end

@implementation SchemaCodegenTests

- (NSArray<NSDictionary *> *)sampleRows {
  return @[
    @{
      @"table_schema" : @"public",
      @"table_name" : @"users",
      @"column_name" : @"name",
      @"ordinal_position" : @2,
    },
    @{
      @"table_schema" : @"billing",
      @"table_name" : @"invoices",
      @"column_name" : @"amount_cents",
      @"ordinal_position" : @2,
    },
    @{
      @"table_schema" : @"public",
      @"table_name" : @"users",
      @"column_name" : @"id",
      @"ordinal_position" : @1,
    },
    @{
      @"table_schema" : @"billing",
      @"table_name" : @"invoices",
      @"column_name" : @"invoice_id",
      @"ordinal_position" : @1,
    },
  ];
}

- (NSArray<NSDictionary *> *)typedSampleRows {
  return @[
    @{
      @"table_schema" : @"public",
      @"table_name" : @"users",
      @"column_name" : @"id",
      @"ordinal_position" : @1,
      @"data_type" : @"text",
      @"is_nullable" : @"NO",
    },
    @{
      @"table_schema" : @"public",
      @"table_name" : @"users",
      @"column_name" : @"age",
      @"ordinal_position" : @2,
      @"data_type" : @"integer",
      @"is_nullable" : @"YES",
    },
  ];
}

- (void)testRenderArtifactsDeterministicAndSorted {
  NSArray *rows = [self sampleRows];
  NSArray *reversed = [[rows reverseObjectEnumerator] allObjects];

  NSError *firstError = nil;
  NSDictionary *first = [ALNSchemaCodegen renderArtifactsFromColumns:rows
                                                          classPrefix:@"ALNDB"
                                                                error:&firstError];
  XCTAssertNil(firstError);
  XCTAssertNotNil(first);

  NSError *secondError = nil;
  NSDictionary *second = [ALNSchemaCodegen renderArtifactsFromColumns:reversed
                                                           classPrefix:@"ALNDB"
                                                                 error:&secondError];
  XCTAssertNil(secondError);
  XCTAssertNotNil(second);

  XCTAssertEqualObjects(first[@"baseName"], @"ALNDBSchema");
  XCTAssertEqualObjects(first[@"header"], second[@"header"]);
  XCTAssertEqualObjects(first[@"implementation"], second[@"implementation"]);
  XCTAssertEqualObjects(first[@"manifest"], second[@"manifest"]);
  XCTAssertEqualObjects(first[@"tableCount"], @2);
  XCTAssertEqualObjects(first[@"columnCount"], @4);

  NSString *header = first[@"header"];
  NSString *implementation = first[@"implementation"];
  NSString *manifest = first[@"manifest"];
  XCTAssertTrue([header containsString:@"@interface ALNDBBillingInvoices : NSObject"]);
  XCTAssertTrue([header containsString:@"@interface ALNDBPublicUsers : NSObject"]);
  NSRange billingRange = [header rangeOfString:@"@interface ALNDBBillingInvoices : NSObject"];
  NSRange usersRange = [header rangeOfString:@"@interface ALNDBPublicUsers : NSObject"];
  XCTAssertTrue(billingRange.location != NSNotFound && usersRange.location != NSNotFound);
  XCTAssertTrue(billingRange.location < usersRange.location);
  XCTAssertTrue([header containsString:@"+ (NSString *)columnInvoiceId;"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)qualifiedColumnId;"]);
  XCTAssertTrue([implementation containsString:@"return @\"billing.invoices\";"]);
  XCTAssertTrue([implementation containsString:@"return @\"users.id\";"]);
  XCTAssertTrue([manifest containsString:@"\"class_name\": \"ALNDBBillingInvoices\""]);
  XCTAssertTrue([manifest containsString:@"\"columns\": [\"invoice_id\", \"amount_cents\"]"]);
}

- (void)testRenderArtifactsRejectsUnsafeIdentifiers {
  NSArray *rows = @[
    @{
      @"table_schema" : @"public",
      @"table_name" : @"users;drop",
      @"column_name" : @"id",
      @"ordinal_position" : @1,
    },
  ];

  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:rows
                                                              classPrefix:@"ALNDB"
                                                                    error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSchemaCodegenErrorDomain, error.domain);
  XCTAssertEqual(ALNSchemaCodegenErrorInvalidMetadata, error.code);
}

- (void)testRenderArtifactsRejectsInvalidClassPrefix {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:[self sampleRows]
                                                              classPrefix:@"123bad"
                                                                    error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSchemaCodegenErrorDomain, error.domain);
  XCTAssertEqual(ALNSchemaCodegenErrorInvalidArgument, error.code);
}

- (void)testRenderArtifactsRejectsClassNameCollisions {
  NSArray *rows = @[
    @{
      @"table_schema" : @"a_b",
      @"table_name" : @"logs",
      @"column_name" : @"id",
      @"ordinal_position" : @1,
    },
    @{
      @"table_schema" : @"a__b",
      @"table_name" : @"logs",
      @"column_name" : @"id",
      @"ordinal_position" : @1,
    },
  ];

  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:rows
                                                              classPrefix:@"ALNDB"
                                                                    error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSchemaCodegenErrorDomain, error.domain);
  XCTAssertEqual(ALNSchemaCodegenErrorIdentifierCollision, error.code);
}

- (void)testRenderArtifactsIncludesDatabaseTargetMetadata {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:[self sampleRows]
                                                              classPrefix:@"ALNDB"
                                                           databaseTarget:@"analytics"
                                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);
  NSString *manifest = [artifacts[@"manifest"] isKindOfClass:[NSString class]] ? artifacts[@"manifest"] : @"";
  XCTAssertTrue([manifest containsString:@"\"database_target\": \"analytics\""]);
}

- (void)testRenderArtifactsRejectsInvalidDatabaseTarget {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:[self sampleRows]
                                                              classPrefix:@"ALNDB"
                                                           databaseTarget:@"bad-target"
                                                                    error:&error];
  XCTAssertNil(artifacts);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNSchemaCodegenErrorDomain, error.domain);
  XCTAssertEqual(ALNSchemaCodegenErrorInvalidArgument, error.code);
}

- (void)testRenderArtifactsWithTypedContractsIncludesDecodeAndContractSurfaces {
  NSError *error = nil;
  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:[self typedSampleRows]
                                                              classPrefix:@"ALNDB"
                                                           databaseTarget:@"analytics"
                                                    includeTypedContracts:YES
                                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(artifacts);

  NSString *header = [artifacts[@"header"] isKindOfClass:[NSString class]] ? artifacts[@"header"] : @"";
  NSString *implementation =
      [artifacts[@"implementation"] isKindOfClass:[NSString class]] ? artifacts[@"implementation"] : @"";
  NSString *manifest = [artifacts[@"manifest"] isKindOfClass:[NSString class]] ? artifacts[@"manifest"] : @"";

  XCTAssertTrue([header containsString:@"ALNDBSchemaTypedDecodeErrorDomain"]);
  XCTAssertTrue([header containsString:@"@interface ALNDBPublicUsersRow : NSObject"]);
  XCTAssertTrue([header containsString:@"@interface ALNDBPublicUsersInsert : NSObject"]);
  XCTAssertTrue([header containsString:@"@interface ALNDBPublicUsersUpdate : NSObject"]);
  XCTAssertTrue([header containsString:@"+ (ALNSQLBuilder *)insertContract:(ALNDBPublicUsersInsert *)contractValues;"]);
  XCTAssertTrue([header containsString:@"+ (nullable ALNDBPublicUsersRow *)decodeTypedRow:(NSDictionary<NSString *, id> *)row"]);

  XCTAssertTrue([implementation containsString:@"Arlen.Data.SchemaCodegen.TypedDecode.ALNDBSchema"]);
  XCTAssertTrue([implementation containsString:@"+ (ALNSQLBuilder *)insertContract:(ALNDBPublicUsersInsert *)contractValues {"]);
  XCTAssertTrue([implementation containsString:@"+ (nullable ALNDBPublicUsersRow *)decodeTypedRow:(NSDictionary<NSString *, id> *)row"]);
  XCTAssertTrue([implementation containsString:@"missing required field"]);
  XCTAssertTrue([implementation containsString:@"field has unexpected runtime type"]);

  XCTAssertTrue([manifest containsString:@"\"typed_contracts\": true"]);
  XCTAssertTrue([manifest containsString:@"\"row_class_name\": \"ALNDBPublicUsersRow\""]);
  XCTAssertTrue([manifest containsString:@"\"insert_class_name\": \"ALNDBPublicUsersInsert\""]);
}

@end
