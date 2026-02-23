#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@interface Phase7ETests : XCTestCase
@end

@implementation Phase7ETests

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

- (void)testTemplatePipelineContractFixtureSchemaAndTestCoverage {
  NSDictionary *fixture =
      [self loadJSONFileAtRelativePath:@"tests/fixtures/phase7e/template_pipeline_contracts.json"];
  XCTAssertEqualObjects(@"phase7e-template-pipeline-contracts-v1", fixture[@"version"]);

  NSArray<NSDictionary *> *contracts =
      [fixture[@"contracts"] isKindOfClass:[NSArray class]] ? fixture[@"contracts"] : @[];
  XCTAssertTrue([contracts count] > 0);

  NSSet *allowedKinds = [NSSet setWithArray:@[ @"unit", @"integration", @"long_run" ]];
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

@end
