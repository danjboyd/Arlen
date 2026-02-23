#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNGDL2Adapter.h"
#import "ALNPg.h"

@interface Phase5ATests : XCTestCase
@end

@implementation Phase5ATests

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)absolutePathForRelativePath:(NSString *)relativePath {
  return [[self repoRoot] stringByAppendingPathComponent:(relativePath ?: @"")];
}

- (NSDictionary *)loadJSONFileAtRelativePath:(NSString *)relativePath {
  NSString *path = [self absolutePathForRelativePath:relativePath];
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data, @"missing fixture: %@", relativePath);
  if (data == nil) {
    return @{};
  }

  NSError *jsonError = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  XCTAssertNil(jsonError, @"invalid JSON in %@", relativePath);
  XCTAssertNotNil(payload, @"invalid JSON object in %@", relativePath);
  if (payload == nil) {
    return @{};
  }
  return payload;
}

- (NSSet<NSString *> *)testMethodNamesForFile:(NSString *)relativePath {
  NSString *absolutePath = [self absolutePathForRelativePath:relativePath];
  NSString *source = [NSString stringWithContentsOfFile:absolutePath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
  XCTAssertNotNil(source, @"missing test source: %@", relativePath);
  if (source == nil) {
    return [NSSet set];
  }

  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"-\\s*\\(void\\)\\s*(test[A-Za-z0-9_]+)\\s*\\{"
                                                options:0
                                                  error:nil];
  XCTAssertNotNil(regex);
  if (regex == nil) {
    return [NSSet set];
  }

  NSArray<NSTextCheckingResult *> *matches =
      [regex matchesInString:source options:0 range:NSMakeRange(0, [source length])];
  NSMutableSet<NSString *> *names = [NSMutableSet setWithCapacity:[matches count]];
  for (NSTextCheckingResult *match in matches) {
    NSRange range = [match rangeAtIndex:1];
    if (range.location == NSNotFound || range.length == 0) {
      continue;
    }
    [names addObject:[source substringWithRange:range]];
  }
  return [NSSet setWithSet:names];
}

- (void)assertTestReference:(NSDictionary *)reference
                     cache:(NSMutableDictionary<NSString *, NSSet<NSString *> *> *)cache {
  NSString *file = [reference[@"file"] isKindOfClass:[NSString class]] ? reference[@"file"] : @"";
  NSString *test = [reference[@"test"] isKindOfClass:[NSString class]] ? reference[@"test"] : @"";
  XCTAssertTrue([file length] > 0);
  XCTAssertTrue([test length] > 0);
  if ([file length] == 0 || [test length] == 0) {
    return;
  }

  NSString *absolutePath = [self absolutePathForRelativePath:file];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:absolutePath], @"missing referenced file: %@", file);
  if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
    return;
  }

  NSSet<NSString *> *methods = cache[file];
  if (methods == nil) {
    methods = [self testMethodNamesForFile:file];
    cache[file] = methods ?: [NSSet set];
  }
  XCTAssertTrue([methods containsObject:test], @"missing referenced test '%@' in %@", test, file);
}

- (void)testReliabilityContractFixtureSchemaAndTestCoverage {
  NSDictionary *fixture =
      [self loadJSONFileAtRelativePath:@"tests/fixtures/phase5a/data_layer_reliability_contracts.json"];
  XCTAssertEqualObjects(@"phase5a-v1", fixture[@"version"]);

  NSArray<NSDictionary *> *contracts =
      [fixture[@"contracts"] isKindOfClass:[NSArray class]] ? fixture[@"contracts"] : @[];
  XCTAssertTrue([contracts count] > 0);

  NSSet *allowedKinds = [NSSet setWithArray:@[ @"unit", @"integration", @"long_run", @"conformance" ]];
  NSMutableSet<NSString *> *ids = [NSMutableSet setWithCapacity:[contracts count]];
  NSMutableDictionary<NSString *, NSSet<NSString *> *> *methodCache = [NSMutableDictionary dictionary];

  for (NSDictionary *contract in contracts) {
    NSString *contractID = [contract[@"id"] isKindOfClass:[NSString class]] ? contract[@"id"] : @"";
    NSString *claim = [contract[@"claim"] isKindOfClass:[NSString class]] ? contract[@"claim"] : @"";
    XCTAssertTrue([contractID length] > 0);
    XCTAssertTrue([claim length] > 0);
    XCTAssertFalse([ids containsObject:contractID], @"duplicate contract id: %@", contractID);
    [ids addObject:contractID];

    NSArray<NSString *> *sourceDocs =
        [contract[@"source_docs"] isKindOfClass:[NSArray class]] ? contract[@"source_docs"] : @[];
    XCTAssertTrue([sourceDocs count] > 0);
    for (id rawDocPath in sourceDocs) {
      NSString *docPath = [rawDocPath isKindOfClass:[NSString class]] ? rawDocPath : @"";
      XCTAssertTrue([docPath length] > 0);
      if ([docPath length] == 0) {
        continue;
      }
      NSString *absoluteDocPath = [self absolutePathForRelativePath:docPath];
      XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:absoluteDocPath], @"missing source doc: %@", docPath);
    }

    NSArray<NSDictionary *> *verification =
        [contract[@"verification"] isKindOfClass:[NSArray class]] ? contract[@"verification"] : @[];
    XCTAssertTrue([verification count] > 0, @"contract '%@' has no verification", contractID);
    for (NSDictionary *reference in verification) {
      NSString *kind = [reference[@"kind"] isKindOfClass:[NSString class]] ? reference[@"kind"] : @"";
      XCTAssertTrue([allowedKinds containsObject:kind], @"unsupported verification kind: %@", kind);
      [self assertTestReference:reference cache:methodCache];
    }
  }
}

- (void)testExternalRegressionIntakeFixtureMapsToKnownContracts {
  NSDictionary *contractsFixture =
      [self loadJSONFileAtRelativePath:@"tests/fixtures/phase5a/data_layer_reliability_contracts.json"];
  NSArray<NSDictionary *> *contracts =
      [contractsFixture[@"contracts"] isKindOfClass:[NSArray class]] ? contractsFixture[@"contracts"] : @[];
  NSMutableSet<NSString *> *contractIDs = [NSMutableSet setWithCapacity:[contracts count]];
  for (NSDictionary *contract in contracts) {
    NSString *contractID = [contract[@"id"] isKindOfClass:[NSString class]] ? contract[@"id"] : @"";
    if ([contractID length] > 0) {
      [contractIDs addObject:contractID];
    }
  }
  XCTAssertTrue([contractIDs count] > 0);

  NSDictionary *intakeFixture =
      [self loadJSONFileAtRelativePath:@"tests/fixtures/phase5a/external_regression_intake.json"];
  XCTAssertEqualObjects(@"phase5a-intake-v1", intakeFixture[@"version"]);
  NSArray<NSDictionary *> *scenarios =
      [intakeFixture[@"scenarios"] isKindOfClass:[NSArray class]] ? intakeFixture[@"scenarios"] : @[];
  XCTAssertTrue([scenarios count] > 0);

  NSSet *allowedStatuses = [NSSet setWithArray:@[ @"covered", @"planned" ]];
  NSMutableSet<NSString *> *scenarioIDs = [NSMutableSet setWithCapacity:[scenarios count]];
  NSMutableDictionary<NSString *, NSSet<NSString *> *> *methodCache = [NSMutableDictionary dictionary];

  for (NSDictionary *scenario in scenarios) {
    NSString *scenarioID = [scenario[@"id"] isKindOfClass:[NSString class]] ? scenario[@"id"] : @"";
    XCTAssertTrue([scenarioID length] > 0);
    XCTAssertFalse([scenarioIDs containsObject:scenarioID], @"duplicate scenario id: %@", scenarioID);
    [scenarioIDs addObject:scenarioID];

    NSString *framework =
        [scenario[@"source_framework"] isKindOfClass:[NSString class]] ? scenario[@"source_framework"] : @"";
    NSString *sourceArea = [scenario[@"source_area"] isKindOfClass:[NSString class]] ? scenario[@"source_area"] : @"";
    NSString *sourceReference =
        [scenario[@"source_reference"] isKindOfClass:[NSString class]] ? scenario[@"source_reference"] : @"";
    NSString *status = [scenario[@"status"] isKindOfClass:[NSString class]] ? scenario[@"status"] : @"";
    NSString *contractID =
        [scenario[@"arlen_contract_id"] isKindOfClass:[NSString class]] ? scenario[@"arlen_contract_id"] : @"";

    XCTAssertTrue([framework length] > 0);
    XCTAssertTrue([sourceArea length] > 0);
    XCTAssertTrue([sourceReference length] > 0);
    XCTAssertTrue([allowedStatuses containsObject:status], @"unsupported scenario status: %@", status);
    XCTAssertTrue([contractIDs containsObject:contractID], @"unknown contract id '%@' in scenario %@", contractID, scenarioID);

    NSArray<NSDictionary *> *arlenTests =
        [scenario[@"arlen_tests"] isKindOfClass:[NSArray class]] ? scenario[@"arlen_tests"] : @[];
    if ([status isEqualToString:@"covered"]) {
      XCTAssertTrue([arlenTests count] > 0, @"covered scenario '%@' is missing test references", scenarioID);
    }
    for (NSDictionary *reference in arlenTests) {
      [self assertTestReference:reference cache:methodCache];
    }
  }
}

- (void)testAdapterCapabilityMetadataMatchesFixtureContracts {
  NSDictionary *fixture =
      [self loadJSONFileAtRelativePath:@"tests/fixtures/phase5a/adapter_capabilities.json"];
  XCTAssertEqualObjects(@"phase5a-capabilities-v1", fixture[@"version"]);
  NSDictionary *adapters =
      [fixture[@"adapters"] isKindOfClass:[NSDictionary class]] ? fixture[@"adapters"] : @{};

  NSDictionary *expectedPostgres =
      [adapters[@"postgresql"] isKindOfClass:[NSDictionary class]] ? adapters[@"postgresql"] : nil;
  NSDictionary *expectedGDL2 =
      [adapters[@"gdl2"] isKindOfClass:[NSDictionary class]] ? adapters[@"gdl2"] : nil;
  XCTAssertNotNil(expectedPostgres);
  XCTAssertNotNil(expectedGDL2);
  if (expectedPostgres == nil || expectedGDL2 == nil) {
    return;
  }

  XCTAssertEqualObjects(expectedPostgres, [ALNPg capabilityMetadata]);
  XCTAssertEqualObjects(expectedGDL2, [ALNGDL2Adapter capabilityMetadata]);

  ALNGDL2Adapter *instance = [[ALNGDL2Adapter alloc] init];
  NSDictionary *instanceMetadata = [instance capabilityMetadata];
  XCTAssertEqualObjects(@"gdl2", instanceMetadata[@"adapter"]);
  XCTAssertEqualObjects(@"compat_fallback_pg", instanceMetadata[@"migration_mode"]);
}

@end
