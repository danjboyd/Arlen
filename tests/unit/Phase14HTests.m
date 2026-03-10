#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"

@interface Phase14HArticleResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase14HArticleResource

- (NSString *)searchModuleResourceIdentifier {
  return @"articles";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Articles",
    @"summary" : @"Knowledge base articles",
    @"identifierField" : @"id",
    @"primaryField" : @"title",
    @"indexedFields" : @[ @"body", @"title", @"title" ],
    @"filters" : @[
      @{ @"name" : @"status", @"operators" : @[ @"eq", @"contains" ] },
      @{ @"name" : @"category", @"operators" : @[ @"eq" ] },
    ],
    @"sorts" : @[
      @{ @"name" : @"updated_at" },
      @{ @"name" : @"title" },
    ],
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"id" : @"art-200",
      @"title" : @"Beta Guide",
      @"body" : @"beta release reviewed",
      @"status" : @"draft",
      @"category" : @"guides",
      @"updated_at" : @"2026-03-10",
    },
    @{
      @"id" : @"art-100",
      @"title" : @"Alpha Guide",
      @"body" : @"alpha launch",
      @"status" : @"published",
      @"category" : @"guides",
      @"updated_at" : @"2026-03-09",
    },
  ];
}

@end

@interface Phase14HSearchProvider : NSObject <ALNSearchResourceProvider>
@end

@implementation Phase14HSearchProvider

- (NSArray<id<ALNSearchResourceDefinition>> *)searchModuleResourcesForRuntime:(ALNSearchModuleRuntime *)runtime
                                                                        error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14HArticleResource alloc] init] ];
}

@end

@interface Phase14HTests : XCTestCase
@end

@implementation Phase14HTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"searchModule" : @{
      @"providers" : @{ @"classes" : @[ @"Phase14HSearchProvider" ] },
      @"adminUI" : @{ @"autoResources" : @NO },
    },
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)testSearchableResourceMetadataNormalizesDeterministically {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  NSArray *resources = [[ALNSearchModuleRuntime sharedRuntime] registeredResources];
  XCTAssertEqual((NSUInteger)1, [resources count]);
  NSDictionary *resource = resources[0];
  XCTAssertEqualObjects(@"articles", resource[@"identifier"]);
  XCTAssertEqualObjects((@[ @"body", @"title" ]), resource[@"indexedFields"]);
  XCTAssertEqualObjects(@"category", resource[@"filters"][0][@"name"]);
  XCTAssertEqualObjects(@"status", resource[@"filters"][1][@"name"]);
  XCTAssertEqualObjects((@[ @"contains", @"eq" ]), resource[@"filters"][1][@"operators"]);
  XCTAssertEqualObjects(@"title", resource[@"sorts"][0][@"name"]);
  XCTAssertEqualObjects(@"updated_at", resource[@"sorts"][1][@"name"]);
}

- (void)testQueryFilterParsingFailsClosedOnUnsupportedFieldsAndOperators {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  NSError *error = nil;
  NSDictionary *reindex = [[ALNSearchModuleRuntime sharedRuntime] processReindexJobPayload:@{ @"resource" : @"articles" }
                                                                                      error:&error];
  XCTAssertNotNil(reindex);
  XCTAssertNil(error);

  NSDictionary *result = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"guide"
                                                           resourceIdentifier:@"articles"
                                                                      filters:@{ @"unknown" : @"x" }
                                                                         sort:nil
                                                                        limit:10
                                                                       offset:0
                                                                        error:&error];
  XCTAssertNil(result);
  XCTAssertNotNil(error);

  error = nil;
  result = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"guide"
                                            resourceIdentifier:@"articles"
                                                       filters:@{ @"status__lt" : @"draft" }
                                                          sort:nil
                                                         limit:10
                                                        offset:0
                                                         error:&error];
  XCTAssertNil(result);
  XCTAssertNotNil(error);
}

@end
