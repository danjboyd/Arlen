#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <math.h>
#import <stdlib.h>

#import "ALNJSONSerialization.h"

@interface JSONSerializationTests : XCTestCase
@property(nonatomic, copy) NSString *originalBackendEnv;
@end

@implementation JSONSerializationTests

- (void)setUp {
  [super setUp];
  const char *raw = getenv("ARLEN_JSON_BACKEND");
  self.originalBackendEnv = (raw != NULL) ? [NSString stringWithUTF8String:raw] : nil;
  [ALNJSONSerialization resetBackendForTesting];
}

- (void)tearDown {
  if (self.originalBackendEnv != nil) {
    setenv("ARLEN_JSON_BACKEND", [self.originalBackendEnv UTF8String], 1);
  } else {
    unsetenv("ARLEN_JSON_BACKEND");
  }
  [ALNJSONSerialization resetBackendForTesting];
  [super tearDown];
}

- (NSData *)utf8Data:(NSString *)text {
  return [text dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)forEachBackend:(void (^)(ALNJSONBackend backend))block {
  NSArray<NSNumber *> *backends = @[ @(ALNJSONBackendFoundation), @(ALNJSONBackendYYJSON) ];
  for (NSNumber *entry in backends) {
    ALNJSONBackend backend = (ALNJSONBackend)[entry unsignedIntegerValue];
    [ALNJSONSerialization setBackendForTesting:backend];
    block(backend);
  }
  [ALNJSONSerialization resetBackendForTesting];
}

- (void)testBackendSelectionFromEnvironment {
  setenv("ARLEN_JSON_BACKEND", "foundation", 1);
  [ALNJSONSerialization resetBackendForTesting];
  XCTAssertEqual(ALNJSONBackendFoundation, [ALNJSONSerialization backend]);
  XCTAssertEqualObjects(@"foundation", [ALNJSONSerialization backendName]);

  setenv("ARLEN_JSON_BACKEND", "nsjson", 1);
  [ALNJSONSerialization resetBackendForTesting];
  XCTAssertEqual(ALNJSONBackendFoundation, [ALNJSONSerialization backend]);

  setenv("ARLEN_JSON_BACKEND", "yyjson", 1);
  [ALNJSONSerialization resetBackendForTesting];
  XCTAssertEqual(ALNJSONBackendYYJSON, [ALNJSONSerialization backend]);
  XCTAssertEqualObjects(@"yyjson", [ALNJSONSerialization backendName]);

  setenv("ARLEN_JSON_BACKEND", "unknown", 1);
  [ALNJSONSerialization resetBackendForTesting];
  XCTAssertEqual(ALNJSONBackendYYJSON, [ALNJSONSerialization backend]);
}

- (void)testYYJSONVersionMetadataIsAvailable {
  NSString *version = [ALNJSONSerialization yyjsonVersion];
  XCTAssertNotNil(version);
  XCTAssertTrue([version length] > 0);

  NSError *error = nil;
  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+\\.[0-9]+\\.[0-9]+$"
                                                options:0
                                                  error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(regex);
  if (regex == nil) {
    return;
  }
  NSUInteger matches = [regex numberOfMatchesInString:version options:0 range:NSMakeRange(0, [version length])];
  XCTAssertEqual((NSUInteger)1, matches);
}

- (void)testRoundTripParityAcrossBackends {
  NSString *fixture = @"{\"name\":\"Arlen\",\"count\":3,\"ok\":true,\"items\":[1,2,{\"x\":\"y\"}],\"unicode\":\"mañana\"}";
  NSData *input = [self utf8Data:fixture];

  __block id baselineObject = nil;
  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *parseError = nil;
    id parsed = [ALNJSONSerialization JSONObjectWithData:input options:0 error:&parseError];
    XCTAssertNil(parseError, @"backend=%lu", (unsigned long)backend);
    XCTAssertTrue([parsed isKindOfClass:[NSDictionary class]], @"backend=%lu", (unsigned long)backend);

    NSError *encodeError = nil;
    NSData *encoded = [ALNJSONSerialization dataWithJSONObject:parsed options:0 error:&encodeError];
    XCTAssertNil(encodeError, @"backend=%lu", (unsigned long)backend);
    XCTAssertNotNil(encoded, @"backend=%lu", (unsigned long)backend);
    if (encoded == nil) {
      return;
    }

    NSError *reparseError = nil;
    id reparsed = [ALNJSONSerialization JSONObjectWithData:encoded options:0 error:&reparseError];
    XCTAssertNil(reparseError, @"backend=%lu", (unsigned long)backend);
    XCTAssertEqualObjects(parsed, reparsed, @"backend=%lu", (unsigned long)backend);

    if (baselineObject == nil) {
      baselineObject = parsed;
    } else {
      XCTAssertEqualObjects(baselineObject, parsed, @"backend=%lu", (unsigned long)backend);
    }
  }];
}

- (void)testMutableContainerAndLeafParity {
  NSData *data = [self utf8Data:@"{\"key\":\"value\",\"nested\":{\"leaf\":\"x\"}}"];
  NSJSONReadingOptions options = NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves;

  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *error = nil;
    id parsed = [ALNJSONSerialization JSONObjectWithData:data options:options error:&error];
    XCTAssertNil(error, @"backend=%lu", (unsigned long)backend);
    XCTAssertTrue([parsed isKindOfClass:[NSMutableDictionary class]], @"backend=%lu", (unsigned long)backend);

    NSDictionary *dict = (NSDictionary *)parsed;
    id nested = dict[@"nested"];
    XCTAssertTrue([nested isKindOfClass:[NSMutableDictionary class]], @"backend=%lu", (unsigned long)backend);

    id keyLeaf = dict[@"key"];
    XCTAssertTrue([keyLeaf isKindOfClass:[NSMutableString class]], @"backend=%lu", (unsigned long)backend);
  }];
}

- (void)testAllowFragmentsParity {
  NSData *fragment = [self utf8Data:@"123"];

  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *error = nil;
    id parsed = [ALNJSONSerialization JSONObjectWithData:fragment options:0 error:&error];
    XCTAssertNil(parsed, @"backend=%lu", (unsigned long)backend);
    XCTAssertNotNil(error, @"backend=%lu", (unsigned long)backend);

    error = nil;
    parsed = [ALNJSONSerialization JSONObjectWithData:fragment
                                              options:NSJSONReadingAllowFragments
                                                error:&error];
    XCTAssertNil(error, @"backend=%lu", (unsigned long)backend);
    XCTAssertEqualObjects(@123, parsed, @"backend=%lu", (unsigned long)backend);
  }];
}

- (void)testInvalidJSONProducesErrorsWithoutCrashes {
  NSData *invalid = [self utf8Data:@"{\"unterminated\":[1,2}"];

  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *error = nil;
    id parsed = [ALNJSONSerialization JSONObjectWithData:invalid options:0 error:&error];
    XCTAssertNil(parsed, @"backend=%lu", (unsigned long)backend);
    XCTAssertNotNil(error, @"backend=%lu", (unsigned long)backend);
    XCTAssertTrue([[error localizedDescription] length] > 0, @"backend=%lu", (unsigned long)backend);
  }];
}

- (void)testValidJSONObjectRulesStayConsistent {
  NSDictionary *valid = @{ @"id" : @1, @"name" : @"ok", @"items" : @[ @1, @2 ] };
  NSDictionary *invalidKey = @{ @1 : @"value" };
  NSDictionary *invalidNumber = @{ @"bad" : @(NAN) };

  [self forEachBackend:^(ALNJSONBackend backend) {
    XCTAssertTrue([ALNJSONSerialization isValidJSONObject:valid], @"backend=%lu", (unsigned long)backend);
    XCTAssertFalse([ALNJSONSerialization isValidJSONObject:@42], @"backend=%lu", (unsigned long)backend);
    XCTAssertFalse([ALNJSONSerialization isValidJSONObject:invalidKey], @"backend=%lu", (unsigned long)backend);
    XCTAssertFalse([ALNJSONSerialization isValidJSONObject:invalidNumber], @"backend=%lu", (unsigned long)backend);
  }];
}

- (void)testSortedKeysOptionParsesToEquivalentContentAcrossBackends {
#ifdef NSJSONWritingSortedKeys
  NSDictionary *payload = @{ @"z" : @1, @"a" : @2, @"m" : @{ @"b" : @1, @"a" : @2 } };
  NSJSONWritingOptions options = NSJSONWritingSortedKeys;

  id baselineParsed = nil;
  [self forEachBackend:^(ALNJSONBackend backend) {
    NSError *error = nil;
    NSData *encoded = [ALNJSONSerialization dataWithJSONObject:payload options:options error:&error];
    XCTAssertNil(error, @"backend=%lu", (unsigned long)backend);
    XCTAssertNotNil(encoded, @"backend=%lu", (unsigned long)backend);
    if (encoded == nil) {
      return;
    }
    id parsed = [ALNJSONSerialization JSONObjectWithData:encoded options:0 error:&error];
    XCTAssertNil(error, @"backend=%lu", (unsigned long)backend);
    if (baselineParsed == nil) {
      baselineParsed = parsed;
    } else {
      XCTAssertEqualObjects(baselineParsed, parsed, @"backend=%lu", (unsigned long)backend);
    }
  }];
#endif
}

- (void)testRuntimeJSONCallsitesUseAbstraction {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray<NSString *> *runtimeFiles = @[
    @"src/Arlen/HTTP/ALNResponse.m",
    @"src/Arlen/Core/ALNSchemaContract.m",
    @"src/Arlen/MVC/Middleware/ALNResponseEnvelopeMiddleware.m",
    @"src/Arlen/MVC/Middleware/ALNSessionMiddleware.m",
    @"src/Arlen/Support/ALNAuth.m",
    @"src/Arlen/Support/ALNLogger.m",
    @"src/Arlen/Core/ALNApplication.m",
    @"src/Arlen/Data/ALNPg.m",
    @"src/Arlen/MVC/Controller/ALNController.m",
  ];

  for (NSString *relativePath in runtimeFiles) {
    NSString *path = [repoRoot stringByAppendingPathComponent:relativePath];
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    XCTAssertNotNil(contents, @"file=%@", relativePath);
    XCTAssertNil(error, @"file=%@", relativePath);
    if (contents == nil) {
      continue;
    }
    XCTAssertFalse([contents containsString:@"NSJSONSerialization"], @"file=%@", relativePath);
    XCTAssertTrue([contents containsString:@"ALNJSONSerialization"], @"file=%@", relativePath);
  }
}

- (void)testYYJSONAPIsAreEncapsulatedToSerializationModule {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[repoRoot stringByAppendingPathComponent:@"src/Arlen"]];
  NSString *relativePath = nil;
  while ((relativePath = [enumerator nextObject]) != nil) {
    if (![relativePath hasSuffix:@".m"] && ![relativePath hasSuffix:@".h"]) {
      continue;
    }
    if ([relativePath hasPrefix:@"Support/third_party/yyjson/"]) {
      continue;
    }
    if ([relativePath isEqualToString:@"Support/ALNJSONSerialization.m"]) {
      continue;
    }
    if ([relativePath isEqualToString:@"Support/ALNJSONSerialization.h"]) {
      continue;
    }

    NSString *path = [[repoRoot stringByAppendingPathComponent:@"src/Arlen"] stringByAppendingPathComponent:relativePath];
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(contents, @"file=%@", relativePath);
    XCTAssertNil(error, @"file=%@", relativePath);
    if (contents == nil) {
      continue;
    }
    XCTAssertFalse([contents containsString:@"yyjson_"], @"file=%@", relativePath);
  }
}

@end
