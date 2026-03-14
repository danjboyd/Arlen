#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNRequest.h"
#import "ALNSchemaContract.h"
#import "ALNValueTransformers.h"

@interface SchemaContractTests : XCTestCase
@end

@implementation SchemaContractTests

- (ALNRequest *)requestWithQueryString:(NSString *)queryString {
  return [[ALNRequest alloc] initWithMethod:@"GET"
                                      path:@"/"
                               queryString:queryString ?: @""
                                   headers:@{}
                                      body:[NSData data]];
}

- (ALNRequest *)requestWithJSONObject:(id)object {
  NSError *error = nil;
  NSData *body = [NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:&error];
  XCTAssertNotNil(body);
  XCTAssertNil(error);
  return [[ALNRequest alloc] initWithMethod:@"POST"
                                      path:@"/"
                               queryString:@""
                                   headers:@{ @"content-type" : @"application/json" }
                                      body:body ?: [NSData data]];
}

- (void)testSchemaCoercionAppliesNamedTransformerBeforeTypeValidation {
  NSDictionary *schema = @{
    @"type" : @"object",
    @"properties" : @{
      @"age" : @{
        @"type" : @"integer",
        @"source" : @"query",
        @"required" : @(YES),
        @"transformer" : @"to_integer",
      },
    },
  };

  NSArray *errors = nil;
  NSDictionary *coerced = ALNSchemaCoerceRequestValues(schema,
                                                       [self requestWithQueryString:@"age=7"],
                                                       @{},
                                                       &errors);
  XCTAssertNotNil(coerced);
  XCTAssertEqualObjects(@7, coerced[@"age"]);
  XCTAssertEqual((NSUInteger)0, [errors count]);
}

- (void)testSchemaCoercionAppliesTransformerPipelineInOrder {
  NSDictionary *schema = @{
    @"type" : @"object",
    @"properties" : @{
      @"name" : @{
        @"type" : @"string",
        @"source" : @"query",
        @"required" : @(YES),
        @"transformers" : @[ @"trim", @"uppercase" ],
      },
    },
  };

  NSArray *errors = nil;
  NSDictionary *coerced = ALNSchemaCoerceRequestValues(schema,
                                                       [self requestWithQueryString:@"name=%20dan%20"],
                                                       @{},
                                                       &errors);
  XCTAssertNotNil(coerced);
  XCTAssertEqualObjects(@"DAN", coerced[@"name"]);
  XCTAssertEqual((NSUInteger)0, [errors count]);
}

- (void)testSchemaCoercionRejectsUnknownTransformerWithDeterministicCode {
  NSDictionary *schema = @{
    @"type" : @"object",
    @"properties" : @{
      @"name" : @{
        @"type" : @"string",
        @"source" : @"query",
        @"required" : @(YES),
        @"transformer" : @"missing_transformer",
      },
    },
  };

  NSArray *errors = nil;
  NSDictionary *coerced = ALNSchemaCoerceRequestValues(schema,
                                                       [self requestWithQueryString:@"name=dan"],
                                                       @{},
                                                       &errors);
  XCTAssertNil(coerced);
  XCTAssertEqual((NSUInteger)1, [errors count]);
  NSDictionary *entry = [errors firstObject];
  XCTAssertEqualObjects(@"name", entry[@"field"]);
  XCTAssertEqualObjects(@"invalid_transformer", entry[@"code"]);
  XCTAssertTrue([entry[@"message"] length] > 0);
  XCTAssertEqualObjects(@"missing_transformer", entry[@"meta"][@"transformer"]);
}

- (void)testSchemaCoercionRejectsInvalidTransformWithDeterministicCode {
  NSDictionary *schema = @{
    @"type" : @"object",
    @"properties" : @{
      @"age" : @{
        @"type" : @"integer",
        @"source" : @"query",
        @"required" : @(YES),
        @"transformer" : @"to_integer",
      },
    },
  };

  NSArray *errors = nil;
  NSDictionary *coerced = ALNSchemaCoerceRequestValues(schema,
                                                       [self requestWithQueryString:@"age=abc"],
                                                       @{},
                                                       &errors);
  XCTAssertNil(coerced);
  XCTAssertEqual((NSUInteger)1, [errors count]);
  NSDictionary *entry = [errors firstObject];
  XCTAssertEqualObjects(@"age", entry[@"field"]);
  XCTAssertEqualObjects(@"invalid_transform", entry[@"code"]);
  XCTAssertEqualObjects(@"to_integer", entry[@"meta"][@"transformer"]);
}

- (void)testSchemaCoercionPreservesNestedObjectItemsInsideBodyArrays {
  NSDictionary *schema = @{
    @"type" : @"object",
    @"properties" : @{
      @"corrections" : @{
        @"type" : @"array",
        @"source" : @"body",
        @"required" : @(YES),
        @"items" : @{
          @"field" : @"string",
          @"before" : @"string",
          @"after" : @"string",
          @"metadata" : @{
            @"reason" : @"string",
          },
        },
      },
    },
  };

  NSArray *errors = nil;
  NSDictionary *coerced = ALNSchemaCoerceRequestValues(
      schema,
      [self requestWithJSONObject:@{
        @"corrections" : @[
          @{
            @"field" : @"status",
            @"before" : @"draft",
            @"after" : @"active",
            @"metadata" : @{ @"reason" : @"human review" },
          },
        ],
      }],
      @{},
      &errors);
  XCTAssertNotNil(coerced);
  XCTAssertEqual((NSUInteger)0, [errors count]);

  NSArray *corrections = [coerced[@"corrections"] isKindOfClass:[NSArray class]] ? coerced[@"corrections"] : @[];
  XCTAssertEqual((NSUInteger)1, [corrections count]);
  NSDictionary *entry = [corrections[0] isKindOfClass:[NSDictionary class]] ? corrections[0] : nil;
  XCTAssertNotNil(entry);
  XCTAssertEqualObjects(@"status", entry[@"field"]);
  XCTAssertEqualObjects(@"draft", entry[@"before"]);
  XCTAssertEqualObjects(@"active", entry[@"after"]);
  XCTAssertTrue([entry[@"metadata"] isKindOfClass:[NSDictionary class]]);
  XCTAssertEqualObjects(@"human review", entry[@"metadata"][@"reason"]);
}

- (void)testSchemaReadinessDiagnosticsReportUnknownTransformerAsError {
  NSDictionary *schema = @{
    @"type" : @"object",
    @"properties" : @{
      @"name" : @{
        @"type" : @"string",
        @"transformer" : @"missing_transformer",
      },
    },
  };

  NSArray *diagnostics = ALNSchemaReadinessDiagnostics(schema);
  XCTAssertEqual((NSUInteger)1, [diagnostics count]);
  NSDictionary *entry =
      [[diagnostics firstObject] isKindOfClass:[NSDictionary class]] ? [diagnostics firstObject] : @{};
  XCTAssertEqualObjects(@"name", entry[@"field"]);
  XCTAssertEqualObjects(@"error", entry[@"severity"]);
  XCTAssertEqualObjects(@"invalid_transformer", entry[@"code"]);
  XCTAssertEqualObjects(@"missing_transformer", entry[@"meta"][@"transformer"]);
}

- (void)testSchemaReadinessDiagnosticsReportDescriptorShapeWarnings {
  NSDictionary *schema = @{
    @"type" : @"array",
    @"items" : @42,
  };

  NSArray *diagnostics = ALNSchemaReadinessDiagnostics(schema);
  XCTAssertEqual((NSUInteger)1, [diagnostics count]);
  NSDictionary *entry =
      [[diagnostics firstObject] isKindOfClass:[NSDictionary class]] ? [diagnostics firstObject] : @{};
  XCTAssertEqualObjects(@"", entry[@"field"]);
  XCTAssertEqualObjects(@"warning", entry[@"severity"]);
  XCTAssertEqualObjects(@"invalid_items_shape", entry[@"code"]);
}

- (void)testDefaultTransformerRegistryIncludesExpectedBuiltIns {
  NSArray<NSString *> *names = ALNRegisteredValueTransformerNames();
  XCTAssertTrue([names containsObject:@"trim"]);
  XCTAssertTrue([names containsObject:@"to_integer"]);
  XCTAssertTrue([names containsObject:@"to_boolean"]);
}

@end
