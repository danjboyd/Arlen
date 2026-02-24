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

- (void)testDefaultTransformerRegistryIncludesExpectedBuiltIns {
  NSArray<NSString *> *names = ALNRegisteredValueTransformerNames();
  XCTAssertTrue([names containsObject:@"trim"]);
  XCTAssertTrue([names containsObject:@"to_integer"]);
  XCTAssertTrue([names containsObject:@"to_boolean"]);
}

@end
