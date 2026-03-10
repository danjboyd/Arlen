#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNStorageModule.h"

@interface Phase14EDocumentsCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase14EDocumentsCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"documents";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Documents",
    @"acceptedContentTypes" : @[ @"application/pdf" ],
    @"maxBytes" : @12,
    @"visibility" : @"private",
  };
}

@end

@interface Phase14ECollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase14ECollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14EDocumentsCollection alloc] init] ];
}

@end

@interface Phase14ETests : XCTestCase
@end

@implementation Phase14ETests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"Phase14ECollectionProvider" ] },
      @"downloadTokenTTLSeconds" : @1,
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

- (void)testCollectionRegistrationAndPolicyValidationAreDeterministic {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSArray *collections = [runtime registeredCollections];
  XCTAssertEqual((NSUInteger)1, [collections count]);
  XCTAssertEqualObjects(@"documents", collections[0][@"identifier"]);
  XCTAssertEqualObjects((@[ @"application/pdf" ]), collections[0][@"acceptedContentTypes"]);
  XCTAssertEqualObjects(@12, collections[0][@"maxBytes"]);

  NSError *error = nil;
  NSDictionary *session = [runtime createUploadSessionForCollection:@"documents"
                                                               name:@"bad.txt"
                                                        contentType:@"text/plain"
                                                          sizeBytes:4
                                                           metadata:nil
                                                          expiresIn:60
                                                              error:&error];
  XCTAssertNil(session);
  XCTAssertNotNil(error);

  error = nil;
  NSDictionary *object = [runtime storeObjectInCollection:@"documents"
                                                     name:@"too-big.pdf"
                                              contentType:@"application/pdf"
                                                     data:[@"0123456789abc" dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:nil
                                                    error:&error];
  XCTAssertNil(object);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSUInteger)0, [[app.attachmentAdapter listAttachmentMetadata] count]);
}

- (void)testSignedDownloadTokensFailClosedWhenTamperedOrExpired {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *object = [runtime storeObjectInCollection:@"documents"
                                                     name:@"guide.pdf"
                                              contentType:@"application/pdf"
                                                     data:[@"guide" dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:@{ @"topic" : @"phase14e" }
                                                    error:&error];
  XCTAssertNotNil(object);
  XCTAssertNil(error);

  NSString *token = [runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:0.2 error:&error];
  XCTAssertNotNil(token);
  XCTAssertNil(error);

  NSDictionary *payload = [runtime payloadForDownloadToken:token error:&error];
  XCTAssertNotNil(payload);
  XCTAssertNil(error);
  NSDictionary *metadata = nil;
  NSData *data = [runtime downloadDataForToken:token metadata:&metadata error:&error];
  XCTAssertEqualObjects(@"guide", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(object[@"objectID"], metadata[@"object"][@"objectID"]);

  error = nil;
  XCTAssertNil([runtime payloadForDownloadToken:[token stringByAppendingString:@"x"] error:&error]);
  XCTAssertNotNil(error);

  usleep(300000);
  error = nil;
  XCTAssertNil([runtime payloadForDownloadToken:token error:&error]);
  XCTAssertNotNil(error);
}

@end
