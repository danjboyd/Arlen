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

@end
