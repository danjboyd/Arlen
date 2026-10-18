#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNStorageModule.h"

@interface StorageDownloadSafetyFilesCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation StorageDownloadSafetyFilesCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"files";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Files",
    @"acceptedContentTypes" : @[
      @"text/html", @"image/svg+xml", @"image/png", @"application/pdf", @"video/mp4", @"text/plain"
    ],
    @"visibility" : @"private",
  };
}

@end

@interface StorageDownloadSafetyImagesCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation StorageDownloadSafetyImagesCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"images";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Images",
    @"acceptedContentTypes" : @[ @"image/*" ],
    @"visibility" : @"private",
  };
}

@end

@interface StorageDownloadSafetyAnyCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation StorageDownloadSafetyAnyCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"any";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{ @"title" : @"Any", @"visibility" : @"private" };
}

@end

@interface StorageDownloadSafetyCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation StorageDownloadSafetyCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    [[StorageDownloadSafetyFilesCollection alloc] init],
    [[StorageDownloadSafetyImagesCollection alloc] init],
    [[StorageDownloadSafetyAnyCollection alloc] init],
  ];
}

@end

@interface StorageDownloadSafetyTests : XCTestCase
@property(nonatomic, strong) ALNApplication *app;
@end

@implementation StorageDownloadSafetyTests

- (void)setUp {
  [super setUp];
  self.app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"StorageDownloadSafetyCollectionProvider" ] },
      @"downloadTokenTTLSeconds" : @60,
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:self.app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:self.app error:&error]);
  XCTAssertNil(error);
}

- (void)tearDown {
  self.app = nil;
  [super tearDown];
}

- (ALNResponse *)downloadObjectNamed:(NSString *)name
                         contentType:(NSString *)contentType
                                body:(NSString *)body {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *object = [runtime storeObjectInCollection:@"files"
                                                     name:name
                                              contentType:contentType
                                                     data:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:nil
                                                    error:&error];
  XCTAssertNotNil(object, @"%@", error);
  NSString *token = [runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:60 error:&error];
  XCTAssertTrue([token length] > 0, @"%@", error);
  ALNRequest *request =
      [[ALNRequest alloc] initWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"/storage/api/download/%@", token ?: @""]
                             queryString:@""
                                 headers:@{}
                                    body:[NSData data]];
  ALNResponse *response = [self.app dispatchRequest:request];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  return response;
}

- (void)testHTMLDownloadIsSandboxedAttachment {
  ALNResponse *response = [self downloadObjectNamed:@"page.html"
                                        contentType:@"text/html"
                                               body:@"<script>alert(1)</script>"];
  XCTAssertEqualObjects(@"attachment; filename=\"page.html\"",
                        [response headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
}

- (void)testSVGDownloadIsSandboxedAttachment {
  ALNResponse *response = [self downloadObjectNamed:@"logo.svg"
                                        contentType:@"image/svg+xml"
                                               body:@"<svg xmlns=\"http://www.w3.org/2000/svg\"/>"];
  XCTAssertEqualObjects(@"attachment; filename=\"logo.svg\"",
                        [response headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
}

- (void)testPlainTextDownloadIsAttachment {
  ALNResponse *response = [self downloadObjectNamed:@"notes.txt" contentType:@"text/plain" body:@"hi"];
  XCTAssertTrue([[response headerForName:@"Content-Disposition"] hasPrefix:@"attachment;"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
}

- (void)testPNGDownloadIsInline {
  ALNResponse *response = [self downloadObjectNamed:@"photo.png" contentType:@"image/png" body:@"png!"];
  XCTAssertEqualObjects(@"image/png", [response headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"inline; filename=\"photo.png\"",
                        [response headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
}

- (void)testDeclaredContentTypeMustBeASingleMediaType {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSData *data = [@"<script>alert(1)</script>" dataUsingEncoding:NSUTF8StringEncoding];
  for (NSString *declared in @[
         @"application/pdf;x=,text/html", @"video/mp4,text/html", @"application/pdf, text/html",
         @"application/pdf; name=\"a,b\"", @"application/pdf;\ttext/html", @"application/pdf\r\nX-Evil: 1",
         @"application/pdf; x", @"application/pdf; =v", @"application/pdf/x", @"application", @"application/pdf;;",
         @"image/pngé"
       ]) {
    NSError *error = nil;
    XCTAssertNil([runtime storeObjectInCollection:@"files" name:@"f" contentType:declared data:data metadata:nil error:&error],
                 @"%@", declared);
    XCTAssertEqualObjects(@"contentType", error.userInfo[@"field"], @"%@", declared);
    error = nil;
    XCTAssertNil([runtime createUploadSessionForCollection:@"files"
                                                      name:@"f"
                                               contentType:declared
                                                 sizeBytes:4
                                                  metadata:nil
                                                 expiresIn:60
                                                     error:&error],
                 @"%@", declared);
  }
}

- (void)testDownloadSendsOnlyTheNormalizedMediaType {
  ALNResponse *text = [self downloadObjectNamed:@"notes.txt" contentType:@"Text/Plain; Charset=UTF-8; x=1" body:@"hi"];
  XCTAssertEqualObjects(@"text/plain; charset=utf-8", [text headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"sandbox", [text headerForName:@"Content-Security-Policy"]);

  ALNResponse *pdf = [self downloadObjectNamed:@"guide.pdf" contentType:@"application/PDF; version=1" body:@"%PDF"];
  XCTAssertEqualObjects(@"application/pdf", [pdf headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"inline; filename=\"guide.pdf\"", [pdf headerForName:@"Content-Disposition"]);
}

- (void)testPDFAndVideoDownloadsAreInline {
  ALNResponse *pdf = [self downloadObjectNamed:@"guide.pdf" contentType:@"application/pdf" body:@"%PDF"];
  XCTAssertEqualObjects(@"inline; filename=\"guide.pdf\"", [pdf headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"nosniff", [pdf headerForName:@"X-Content-Type-Options"]);
  XCTAssertNotEqualObjects(@"sandbox", [pdf headerForName:@"Content-Security-Policy"]);

  ALNResponse *video = [self downloadObjectNamed:@"clip.mp4" contentType:@"video/mp4" body:@"mp4"];
  XCTAssertEqualObjects(@"inline; filename=\"clip.mp4\"", [video headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [video headerForName:@"Content-Security-Policy"]);
}

- (void)testDownloadFilenameIsSanitized {
  ALNResponse *response = [self downloadObjectNamed:@"../résumé \"final\".html"
                                        contentType:@"text/html"
                                               body:@"x"];
  NSString *disposition = [response headerForName:@"Content-Disposition"];
  XCTAssertEqualObjects(@"attachment; filename=\"r_sum___final_.html\"; "
                        @"filename*=UTF-8''r%C3%A9sum%C3%A9%20%22final%22.html",
                        disposition);
}

- (void)testWildcardImageCollectionRejectsSVG {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSData *data = [@"<svg/>" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  XCTAssertNil([runtime storeObjectInCollection:@"images"
                                           name:@"logo.svg"
                                    contentType:@"image/svg+xml"
                                           data:data
                                       metadata:nil
                                          error:&error]);
  XCTAssertNotNil(error);

  error = nil;
  XCTAssertNil([runtime createUploadSessionForCollection:@"images"
                                                    name:@"logo.svg"
                                             contentType:@"image/svg+xml"
                                               sizeBytes:6
                                                metadata:nil
                                               expiresIn:60
                                                   error:&error]);
  XCTAssertNotNil(error);

  error = nil;
  XCTAssertNotNil([runtime storeObjectInCollection:@"images"
                                              name:@"photo.png"
                                       contentType:@"image/png"
                                              data:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                                          metadata:nil
                                             error:&error],
                  @"%@", error);
}

- (void)testDefaultCollectionRejectsHTMLAndSVGButAcceptsOtherTypes {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSData *data = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
  for (NSString *type in @[ @"text/html", @"text/html; charset=utf-8", @"image/svg+xml", @"application/xhtml+xml" ]) {
    NSError *error = nil;
    XCTAssertNil([runtime storeObjectInCollection:@"any" name:@"f" contentType:type data:data metadata:nil error:&error],
                 @"%@", type);
    XCTAssertNotNil(error, @"%@", type);
  }
  NSError *error = nil;
  XCTAssertNotNil([runtime storeObjectInCollection:@"any"
                                              name:@"f.json"
                                       contentType:@"application/json"
                                              data:data
                                          metadata:nil
                                             error:&error],
                  @"%@", error);
}

@end
