#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNFileResponseInternal.h"

@interface StaticCacheControlTests : XCTestCase
@end

@implementation StaticCacheControlTests

- (NSString *)valueForPath:(NSString *)path config:(id)config {
  NSArray *rules = ALNStaticCacheControlRules(config, NULL);
  XCTAssertNotNil(rules);
  return ALNStaticCacheControlForPath(rules, path);
}

- (void)testStringConfigAppliesToEveryFile {
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"index.html" config:@"no-cache"]);
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"assets/app.js" config:@"no-cache"]);
  XCTAssertEqualObjects(@[], ALNStaticCacheControlRules(nil, NULL));
  XCTAssertNil(ALNStaticCacheControlForPath(@[], @"index.html"));
}

- (void)testHashedAssetsImmutableAndShellNoCache {
  NSDictionary *config = @{
    @"assets/*" : @"public, max-age=31536000, immutable",
    @"default" : @"no-cache",
  };
  XCTAssertEqualObjects(@"public, max-age=31536000, immutable",
                        [self valueForPath:@"assets/index-3f9a1c.js" config:config]);
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"index.html" config:config]);
  // `*` stays within one path segment.
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"assets/nested/chunk.js" config:config]);
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"assetsX/app.js" config:config]);
}

- (void)testDoubleStarSpansSegmentsAndMostLiteralPatternWins {
  NSDictionary *config = @{
    @"**/*.html" : @"no-cache",
    @"assets/**" : @"public, max-age=31536000, immutable",
    @"assets/legacy/**" : @"public, max-age=60",
    @"/?.txt" : @"private",
  };
  XCTAssertEqualObjects(@"public, max-age=31536000, immutable",
                        [self valueForPath:@"assets/nested/chunk.js" config:config]);
  XCTAssertEqualObjects(@"public, max-age=60", [self valueForPath:@"assets/legacy/old.js" config:config]);
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"index.html" config:config]);
  XCTAssertEqualObjects(@"no-cache", [self valueForPath:@"docs/guide/page.html" config:config]);
  XCTAssertEqualObjects(@"private", [self valueForPath:@"a.txt" config:config]);
  XCTAssertNil([self valueForPath:@"ab.txt" config:config]);
  XCTAssertNil([self valueForPath:@"robots.json" config:config]);
}

- (void)testInvalidConfigIsRejectedWithReason {
  for (id config in @[ @[ @"no-cache" ], @{ @"" : @"no-cache" }, @{ @"*.js" : @"" },
                       @{ @"*.js" : @"no-cache\r\nX-Injected: 1" }, @{ @"*.js" : @42 } ]) {
    NSString *reason = nil;
    XCTAssertNil(ALNStaticCacheControlRules(config, &reason), @"%@", config);
    XCTAssertTrue([reason containsString:@"cacheControl"], @"%@", reason);
  }
}

- (void)testConfiguredMountsStoreRulesAndSkipInvalidEntries {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
    @"staticMounts" : @[
      @{
        @"prefix" : @"/app",
        @"directory" : @"public/app",
        @"cacheControl" : @{ @"assets/*" : @"public, max-age=31536000, immutable", @"default" : @"no-cache" },
      },
      @{ @"prefix" : @"/bad", @"directory" : @"public", @"cacheControl" : @[ @"no-cache" ] },
      @{ @"prefix" : @"/plain", @"directory" : @"public" },
    ],
  }];
  NSArray *mounts = app.staticMounts;
  XCTAssertEqual((NSUInteger)2, [mounts count]);
  NSDictionary *spa = mounts[0];
  XCTAssertEqualObjects(@"/app", spa[@"prefix"]);
  XCTAssertEqualObjects(@"no-cache", ALNStaticCacheControlForPath(spa[@"cacheControlRules"], @"index.html"));
  XCTAssertEqualObjects(@"public, max-age=31536000, immutable",
                        ALNStaticCacheControlForPath(spa[@"cacheControlRules"], @"assets/a.js"));
  XCTAssertEqualObjects(@[], mounts[1][@"cacheControlRules"]);

  XCTAssertFalse([app mountStaticDirectory:@"public"
                                  atPrefix:@"/media"
                           allowExtensions:nil
                                   options:@{ @"cacheControl" : @42 }]);
  XCTAssertTrue([app mountStaticDirectory:@"public"
                                 atPrefix:@"/media"
                          allowExtensions:nil
                                  options:@{ @"cacheControl" : @"private, max-age=60" }]);
}

@end
