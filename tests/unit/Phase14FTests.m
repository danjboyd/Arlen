#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNStorageModule.h"

@interface Phase14FMediaCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase14FMediaCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"media";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Media",
    @"acceptedContentTypes" : @[ @"image/png" ],
    @"maxBytes" : @64,
    @"visibility" : @"public",
    @"variants" : @[
      @{ @"identifier" : @"thumb", @"contentType" : @"image/png" },
      @{ @"identifier" : @"hero", @"contentType" : @"image/png" },
    ],
  };
}

@end

@interface Phase14FCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase14FCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14FMediaCollection alloc] init] ];
}

@end

@interface Phase14FTests : XCTestCase
@end

@implementation Phase14FTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"Phase14FCollectionProvider" ] },
      @"uploadSessionTTLSeconds" : @1,
    },
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)testVariantDefinitionsNormalizeDeterministically {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  NSDictionary *collection = [[ALNStorageModuleRuntime sharedRuntime] collectionMetadataForIdentifier:@"media"];
  NSArray *variants = collection[@"variants"];
  XCTAssertEqual((NSUInteger)2, [variants count]);
  XCTAssertEqualObjects(@"hero", variants[0][@"identifier"]);
  XCTAssertEqualObjects(@"thumb", variants[1][@"identifier"]);
  XCTAssertEqualObjects(@"public", collection[@"visibility"]);
}

- (void)testDirectUploadSessionRejectsTamperAndExpiryDeterministically {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *session = [runtime createUploadSessionForCollection:@"media"
                                                               name:@"avatar.png"
                                                        contentType:@"image/png"
                                                          sizeBytes:4
                                                           metadata:@{ @"kind" : @"avatar" }
                                                          expiresIn:60
                                                              error:&error];
  XCTAssertNotNil(session);
  XCTAssertNil(error);

  NSDictionary *object = [runtime storeUploadData:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                               forUploadSessionID:session[@"sessionID"]
                                            token:[session[@"token"] stringByAppendingString:@"x"]
                                            error:&error];
  XCTAssertNil(object);
  XCTAssertNotNil(error);

  error = nil;
  session = [runtime createUploadSessionForCollection:@"media"
                                                 name:@"fresh.png"
                                          contentType:@"image/png"
                                            sizeBytes:4
                                             metadata:@{}
                                            expiresIn:0.2
                                                error:&error];
  XCTAssertNotNil(session);
  XCTAssertNil(error);
  usleep(300000);
  XCTAssertNil([runtime storeUploadData:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                     forUploadSessionID:session[@"sessionID"]
                                  token:session[@"token"]
                                  error:&error]);
  XCTAssertNotNil(error);

  error = nil;
  session = [runtime createUploadSessionForCollection:@"media"
                                                 name:@"ok.png"
                                          contentType:@"image/png"
                                            sizeBytes:4
                                             metadata:@{}
                                            expiresIn:60
                                                error:&error];
  XCTAssertNotNil(session);
  NSDictionary *stored = [runtime storeUploadData:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                               forUploadSessionID:session[@"sessionID"]
                                            token:session[@"token"]
                                            error:&error];
  XCTAssertNotNil(stored);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"pending", stored[@"variantState"]);
}

@end
