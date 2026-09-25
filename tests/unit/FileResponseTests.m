#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNFileResponse.h"
#import "ALNMIMETypes.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "../shared/ALNWebTestSupport.h"

static NSString *gFileResponseTestMediaPath = nil;
static NSDictionary *gFileResponseTestOptions = nil;

@interface FileResponseMediaController : ALNController
@end

@implementation FileResponseMediaController

- (id)login:(ALNContext *)ctx {
  (void)ctx;
  [self session][@"user"] = @"kid-1";
  [self markSessionDirty];
  [self renderText:@"ok\n"];
  return nil;
}

- (id)media:(ALNContext *)ctx {
  (void)ctx;
  if (![[self session][@"user"] isKindOfClass:[NSString class]]) {
    [self setStatus:401];
    [self renderText:@"unauthorized\n"];
    return nil;
  }
  NSString *name = [self stringParamForName:@"name"] ?: @"";
  NSString *path = [name isEqualToString:@"voice.m4a"]
                       ? gFileResponseTestMediaPath
                       : [[gFileResponseTestMediaPath stringByDeletingLastPathComponent]
                             stringByAppendingPathComponent:@"missing.m4a"];
  [self renderFileAtPath:path contentType:nil options:gFileResponseTestOptions];
  return nil;
}

@end

@interface FileResponseTests : XCTestCase
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, strong) NSData *payload;
@end

@implementation FileResponseTests

- (void)setUp {
  [super setUp];
  self.directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                               [NSString stringWithFormat:@"arlen-file-response-%@",
                                                                          [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:self.directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  self.payload = [@"0123456789abcdef" dataUsingEncoding:NSUTF8StringEncoding];
  gFileResponseTestMediaPath = [self.directory stringByAppendingPathComponent:@"voice.m4a"];
  XCTAssertTrue([self.payload writeToFile:gFileResponseTestMediaPath atomically:YES]);
  NSDate *past = [NSDate dateWithTimeIntervalSinceNow:-600];
  [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate : past }
                                   ofItemAtPath:gFileResponseTestMediaPath
                                          error:NULL];
  gFileResponseTestOptions = nil;
}

- (void)tearDown {
  [[NSFileManager defaultManager] removeItemAtPath:self.directory error:NULL];
  gFileResponseTestMediaPath = nil;
  gFileResponseTestOptions = nil;
  [super tearDown];
}

- (ALNWebTestHarness *)loggedInHarnessWithConfig:(NSDictionary *)extraConfig {
  NSMutableDictionary *config = [@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
      @"secure" : @(NO),
    },
  } mutableCopy];
  [config addEntriesFromDictionary:extraConfig ?: @{}];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  [app registerRouteMethod:@"GET"
                      path:@"/login"
                      name:@"login"
           controllerClass:[FileResponseMediaController class]
                    action:@"login"];
  for (NSString *method in @[ @"GET", @"HEAD" ]) {
    [app registerRouteMethod:method
                        path:@"/media/:name"
                        name:[@"media_" stringByAppendingString:[method lowercaseString]]
             controllerClass:[FileResponseMediaController class]
                      action:@"media"];
  }
  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];
  ALNResponse *login = [harness dispatchMethod:@"GET" path:@"/login"];
  ALNAssertResponseStatus(login, 200);
  [harness recycleCookiesFromResponse:login];
  return harness;
}

- (ALNResponse *)harness:(ALNWebTestHarness *)harness
                  method:(NSString *)method
                    path:(NSString *)path
                 headers:(NSDictionary *)headers {
  return [harness dispatchMethod:method path:path queryString:@"" headers:headers body:nil];
}

#pragma mark - MIME table (issue 57)

- (void)testDefaultStaticAllowExtensionsHaveSpecificContentTypes {
  NSArray *defaultAllowed = @[
    @"css", @"js", @"json", @"txt", @"html", @"htm", @"svg", @"png", @"jpg", @"jpeg",
    @"gif", @"ico", @"webp", @"woff", @"woff2", @"map", @"xml"
  ];
  for (NSString *extension in defaultAllowed) {
    NSString *type = [ALNMIMETypes contentTypeForFilePath:[@"asset." stringByAppendingString:extension]];
    XCTAssertFalse([type isEqualToString:@"application/octet-stream"], @"%@", extension);
  }
  XCTAssertEqualObjects(@"font/woff2", [ALNMIMETypes typeForExtension:@"woff2"]);
  XCTAssertEqualObjects(@"image/webp", [ALNMIMETypes typeForExtension:@"WEBP"]);
  XCTAssertEqualObjects(@"image/gif", [ALNMIMETypes typeForExtension:@".gif"]);
  XCTAssertEqualObjects(@"image/x-icon", [ALNMIMETypes typeForExtension:@"ico"]);
  XCTAssertEqualObjects(@"application/json; charset=utf-8", [ALNMIMETypes typeForExtension:@"map"]);
}

- (void)testMediaExtensionsHaveBrowserPlayableContentTypes {
  NSDictionary *expected = @{
    @"mp3" : @"audio/mpeg",
    @"m4a" : @"audio/mp4",
    @"ogg" : @"audio/ogg",
    @"oga" : @"audio/ogg",
    @"opus" : @"audio/ogg",
    @"wav" : @"audio/wav",
    @"weba" : @"audio/webm",
    @"mp4" : @"video/mp4",
    @"webm" : @"video/webm",
    @"avif" : @"image/avif",
    @"heic" : @"image/heic",
    @"webmanifest" : @"application/manifest+json; charset=utf-8",
  };
  for (NSString *extension in expected) {
    XCTAssertEqualObjects(expected[extension], [ALNMIMETypes typeForExtension:extension], @"%@", extension);
  }
}

- (void)testUnknownExtensionFallsBackToOctetStream {
  XCTAssertNil([ALNMIMETypes typeForExtension:@"unknownext"]);
  XCTAssertEqualObjects(@"application/octet-stream", [ALNMIMETypes contentTypeForFilePath:@"a.unknownext"]);
  XCTAssertEqualObjects(@"application/octet-stream", [ALNMIMETypes contentTypeForFilePath:@"noext"]);
}

- (void)testOverridesWinAndInvalidOverridesAreIgnored {
  NSDictionary *overrides = @{
    @".GLB" : @"model/gltf-binary",
    @"png" : @"image/x-custom-png",
    @"svg" : @"image/svg+xml\r\nX-Injected: 1",
    @"css" : @"",
  };
  XCTAssertEqualObjects(@"model/gltf-binary", [ALNMIMETypes typeForExtension:@"glb" overrides:overrides]);
  XCTAssertEqualObjects(@"image/x-custom-png", [ALNMIMETypes typeForExtension:@"png" overrides:overrides]);
  XCTAssertEqualObjects(@"image/svg+xml", [ALNMIMETypes typeForExtension:@"svg" overrides:overrides]);
  XCTAssertEqualObjects(@"text/css; charset=utf-8", [ALNMIMETypes typeForExtension:@"css" overrides:overrides]);
}

#pragma mark - Controller file responses (issue 58)

- (void)testSessionGuardRejectsAnonymousRequests {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  [harness resetRecycledState];
  ALNResponse *response = [self harness:harness method:@"GET" path:@"/media/voice.m4a" headers:nil];
  ALNAssertResponseStatus(response, 401);
  XCTAssertNil(response.fileBodyPath);
}

- (void)testFullGetStreamsFileWithValidators {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness method:@"GET" path:@"/media/voice.m4a" headers:nil];
  ALNAssertResponseStatus(response, 200);
  ALNAssertResponseHeaderEquals(response, @"Content-Type", @"audio/mp4");
  ALNAssertResponseHeaderEquals(response, @"Accept-Ranges", @"bytes");
  XCTAssertTrue([[response headerForName:@"ETag"] hasPrefix:@"W/\""]);
  XCTAssertNotNil([response headerForName:@"Last-Modified"]);
  XCTAssertNil([response headerForName:@"Content-Range"]);
  XCTAssertEqualObjects(gFileResponseTestMediaPath, response.fileBodyPath);
  XCTAssertEqual((unsigned long long)16, response.fileBodyLength);
  XCTAssertEqual((unsigned long long)0, response.fileBodyOffset);
  XCTAssertEqual((unsigned long long)16, response.fileBodyFullLength);
  XCTAssertTrue(response.committed);
}

- (void)testSafariProbeRangeReturns206 {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness
                                 method:@"GET"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"range" : @"bytes=0-1" }];
  ALNAssertResponseStatus(response, 206);
  ALNAssertResponseHeaderEquals(response, @"Content-Range", @"bytes 0-1/16");
  XCTAssertEqual((unsigned long long)0, response.fileBodyOffset);
  XCTAssertEqual((unsigned long long)2, response.fileBodyLength);
  XCTAssertEqual((unsigned long long)16, response.fileBodyFullLength);
}

- (void)testSuffixRangeSelectsFileTail {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness
                                 method:@"GET"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"range" : @"bytes=-4" }];
  ALNAssertResponseStatus(response, 206);
  ALNAssertResponseHeaderEquals(response, @"Content-Range", @"bytes 12-15/16");
  XCTAssertEqual((unsigned long long)12, response.fileBodyOffset);
  XCTAssertEqual((unsigned long long)4, response.fileBodyLength);
}

- (void)testUnsatisfiableRangeReturns416 {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness
                                 method:@"GET"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"range" : @"bytes=16-" }];
  ALNAssertResponseStatus(response, 416);
  ALNAssertResponseHeaderEquals(response, @"Content-Range", @"bytes */16");
  XCTAssertNil(response.fileBodyPath);
}

- (void)testIfNoneMatchReturns304 {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *first = [self harness:harness method:@"GET" path:@"/media/voice.m4a" headers:nil];
  NSString *etag = [first headerForName:@"ETag"];
  XCTAssertTrue([etag length] > 0);
  ALNResponse *response = [self harness:harness
                                 method:@"GET"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"if-none-match" : etag ?: @"" }];
  ALNAssertResponseStatus(response, 304);
  XCTAssertNil(response.fileBodyPath);
  XCTAssertEqual((NSUInteger)0, [response bodyLength]);
}

- (void)testHeadKeepsFullRepresentationMetadataAndIgnoresRange {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness
                                 method:@"HEAD"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"range" : @"bytes=0-1" }];
  ALNAssertResponseStatus(response, 200);
  XCTAssertNil([response headerForName:@"Content-Range"]);
  XCTAssertEqual((unsigned long long)16, response.fileBodyLength);
  ALNAssertResponseHeaderEquals(response, @"Content-Type", @"audio/mp4");
}

- (void)testMissingFileReturns404 {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness method:@"GET" path:@"/media/other.m4a" headers:nil];
  ALNAssertResponseStatus(response, 404);
  XCTAssertNil(response.fileBodyPath);
}

- (void)testOptionsSetCacheControlDownloadNameAndStrongETagIfRange {
  gFileResponseTestOptions = @{
    ALNFileResponseCacheControlOption : @"private, max-age=60",
    ALNFileResponseDownloadNameOption : @"../Voice \"note\" é.m4a",
    ALNFileResponseETagOption : @"sha256-abc",
  };
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *response = [self harness:harness method:@"GET" path:@"/media/voice.m4a" headers:nil];
  ALNAssertResponseStatus(response, 200);
  ALNAssertResponseHeaderEquals(response, @"Cache-Control", @"private, max-age=60");
  ALNAssertResponseHeaderEquals(response, @"ETag", @"\"sha256-abc\"");
  ALNAssertResponseHeaderEquals(response,
                                @"Content-Disposition",
                                @"attachment; filename=\"Voice _note_ _.m4a\"; "
                                @"filename*=UTF-8''Voice%20%22note%22%20%C3%A9.m4a");

  ALNResponse *matching = [self harness:harness
                                 method:@"GET"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"range" : @"bytes=2-3", @"if-range" : @"\"sha256-abc\"" }];
  ALNAssertResponseStatus(matching, 206);
  ALNAssertResponseHeaderEquals(matching, @"Content-Range", @"bytes 2-3/16");

  ALNResponse *stale = [self harness:harness
                              method:@"GET"
                                path:@"/media/voice.m4a"
                             headers:@{ @"range" : @"bytes=2-3", @"if-range" : @"\"sha256-old\"" }];
  ALNAssertResponseStatus(stale, 200);
  XCTAssertEqual((unsigned long long)16, stale.fileBodyLength);
}

- (void)testWeakMetadataETagNeverSatisfiesIfRange {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:nil];
  ALNResponse *first = [self harness:harness method:@"GET" path:@"/media/voice.m4a" headers:nil];
  NSString *etag = [first headerForName:@"ETag"] ?: @"";
  ALNResponse *response = [self harness:harness
                                 method:@"GET"
                                   path:@"/media/voice.m4a"
                                headers:@{ @"range" : @"bytes=0-1", @"if-range" : etag }];
  ALNAssertResponseStatus(response, 200);
  XCTAssertEqual((unsigned long long)16, response.fileBodyLength);
}

- (void)testAppMIMETypeConfigAppliesToControllerFiles {
  ALNWebTestHarness *harness = [self loggedInHarnessWithConfig:@{ @"mimeTypes" : @{ @"m4a" : @"audio/x-m4a" } }];
  ALNResponse *response = [self harness:harness method:@"GET" path:@"/media/voice.m4a" headers:nil];
  ALNAssertResponseStatus(response, 200);
  ALNAssertResponseHeaderEquals(response, @"Content-Type", @"audio/x-m4a");
}

- (void)testPrepareResponseReplacesPreviousBody {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response setTextBody:@"stale body"];
  ALNRequest *request = ALNTestRequestWithMethod(@"GET", @"/x", @"", @{}, nil);
  XCTAssertTrue([ALNFileResponse prepareResponse:response
                                      forRequest:request
                                        filePath:gFileResponseTestMediaPath
                                     contentType:@"audio/mp4"
                                         options:nil]);
  XCTAssertEqual((NSUInteger)0, [response bodyLength]);
  XCTAssertEqualObjects(gFileResponseTestMediaPath, response.fileBodyPath);

  XCTAssertFalse([ALNFileResponse prepareResponse:response
                                       forRequest:request
                                         filePath:self.directory
                                      contentType:nil
                                          options:nil]);
  XCTAssertEqual((NSInteger)404, response.statusCode);
  XCTAssertNil(response.fileBodyPath);
}

@end
