#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNStorageModule.h"

@interface Phase14StorageInjectedAuthMiddleware : NSObject <ALNMiddleware>

@property(nonatomic, copy) NSString *subject;
@property(nonatomic, copy) NSArray *roles;
@property(nonatomic, assign) NSUInteger assuranceLevel;

@end

@implementation Phase14StorageInjectedAuthMiddleware

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _roles = @[];
    _assuranceLevel = 0;
  }
  return self;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSString *subject = [self.subject isKindOfClass:[NSString class]] ? self.subject : @"";
  NSArray *roles = [self.roles isKindOfClass:[NSArray class]] ? self.roles : @[];
  if ([subject length] == 0 && [roles count] == 0) {
    return YES;
  }

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = subject;
  context.stash[ALNContextAuthRolesStashKey] = roles;
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : subject,
    @"roles" : roles,
    @"aal" : @(MAX(self.assuranceLevel, (NSUInteger)1)),
    @"amr" : @[ (self.assuranceLevel >= 2) ? @"otp" : @"pwd" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface Phase14StorageCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase14StorageCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"media";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Media Library",
    @"description" : @"Phase 14 storage integration fixtures",
    @"acceptedContentTypes" : @[ @"image/png" ],
    @"maxBytes" : @64,
    @"visibility" : @"public",
    @"variants" : @[
      @{ @"identifier" : @"thumb", @"label" : @"Thumb", @"contentType" : @"image/png" },
      @{ @"identifier" : @"hero", @"label" : @"Hero", @"contentType" : @"image/png" },
    ],
  };
}

@end

@interface Phase14StorageCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase14StorageCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14StorageCollection alloc] init] ];
}

@end

@interface Phase14StorageIntegrationTests : XCTestCase
@end

@implementation Phase14StorageIntegrationTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"Phase14StorageCollectionProvider" ] },
      @"uploadSessionTTLSeconds" : @60,
      @"downloadTokenTTLSeconds" : @60,
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

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:body ?: [NSData data]];
}

- (NSDictionary *)JSONObjectFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSString *)stringFromResponse:(ALNResponse *)response {
  return [[NSString alloc] initWithData:response.bodyData encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)testDirectUploadAndProtectedManagementSurfaces {
  ALNApplication *app = [self application];
  Phase14StorageInjectedAuthMiddleware *middleware =
      [[Phase14StorageInjectedAuthMiddleware alloc] init];
  [app addMiddleware:middleware];
  [self registerModulesForApplication:app];

  ALNResponse *redirectResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/storage/"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)302, redirectResponse.statusCode);
  NSString *redirectLocation = [redirectResponse headerForName:@"Location"] ?: @"";
  XCTAssertTrue([redirectLocation containsString:@"/auth/login?return_to="]);

  middleware.subject = @"storage-user";
  middleware.roles = @[];
  middleware.assuranceLevel = 1;

  ALNResponse *forbiddenResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/storage/"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)403, forbiddenResponse.statusCode);
  XCTAssertTrue([[self stringFromResponse:forbiddenResponse] containsString:@"Access denied"]);

  middleware.roles = @[ @"admin" ];
  ALNResponse *stepUpResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/storage/"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)302, stepUpResponse.statusCode);
  NSString *stepUpLocation = [stepUpResponse headerForName:@"Location"] ?: @"";
  XCTAssertTrue([stepUpLocation containsString:@"/auth/mfa/totp?return_to="]);

  middleware.assuranceLevel = 2;

  ALNResponse *dashboardResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/storage/"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, dashboardResponse.statusCode);
  XCTAssertTrue([[self stringFromResponse:dashboardResponse] containsString:@"Media Library"]);

  NSData *sessionBody =
      [NSJSONSerialization dataWithJSONObject:@{
        @"collection" : @"media",
        @"name" : @"avatar.png",
        @"contentType" : @"image/png",
        @"sizeBytes" : @4,
        @"metadata" : @{ @"kind" : @"avatar" },
        @"expiresIn" : @60,
      }
                                  options:0
                                    error:NULL];
  ALNResponse *sessionResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/storage/api/upload-sessions"
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"Content-Type" : @"application/json",
                                           }
                                              body:sessionBody]];
  XCTAssertEqual((NSInteger)200, sessionResponse.statusCode);
  NSDictionary *sessionJSON = [self JSONObjectFromResponse:sessionResponse];
  NSDictionary *session = [sessionJSON[@"data"] isKindOfClass:[NSDictionary class]] ? sessionJSON[@"data"] : @{};
  XCTAssertTrue([[session[@"sessionID"] description] length] > 0);
  XCTAssertTrue([[session[@"token"] description] length] > 0);

  ALNResponse *uploadResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:[NSString stringWithFormat:@"/storage/api/upload-sessions/%@/upload", session[@"sessionID"] ?: @""]
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"Content-Type" : @"image/png",
                                             @"X-Upload-Token" : session[@"token"] ?: @"",
                                           }
                                              body:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]]];
  XCTAssertEqual((NSInteger)200, uploadResponse.statusCode);
  NSDictionary *uploadJSON = [self JSONObjectFromResponse:uploadResponse];
  NSDictionary *object = [uploadJSON[@"data"][@"object"] isKindOfClass:[NSDictionary class]] ? uploadJSON[@"data"][@"object"] : @{};
  NSString *objectID = [object[@"objectID"] isKindOfClass:[NSString class]] ? object[@"objectID"] : @"";
  XCTAssertTrue([objectID length] > 0);
  XCTAssertEqualObjects(@"pending", object[@"variantState"]);

  NSError *error = nil;
  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@2, workerSummary[@"acknowledgedCount"]);

  ALNResponse *detailResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:[NSString stringWithFormat:@"/storage/api/collections/media/objects/%@", objectID]
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, detailResponse.statusCode);
  NSDictionary *detailJSON = [self JSONObjectFromResponse:detailResponse];
  NSDictionary *storedObject = [detailJSON[@"data"][@"object"] isKindOfClass:[NSDictionary class]] ? detailJSON[@"data"][@"object"] : @{};
  XCTAssertEqualObjects(@"ready", storedObject[@"variantState"]);
  NSArray *variants = [storedObject[@"variants"] isKindOfClass:[NSArray class]] ? storedObject[@"variants"] : @[];
  XCTAssertEqual((NSUInteger)2, [variants count]);
  XCTAssertEqualObjects(@"ready", variants[0][@"status"]);
  XCTAssertEqualObjects(@"ready", variants[1][@"status"]);

  NSData *downloadTokenBody =
      [NSJSONSerialization dataWithJSONObject:@{ @"expiresIn" : @60 } options:0 error:NULL];
  ALNResponse *downloadTokenResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:[NSString stringWithFormat:@"/storage/api/collections/media/objects/%@/download-token", objectID]
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"Content-Type" : @"application/json",
                                           }
                                              body:downloadTokenBody]];
  XCTAssertEqual((NSInteger)200, downloadTokenResponse.statusCode);
  NSDictionary *downloadTokenJSON = [self JSONObjectFromResponse:downloadTokenResponse];
  NSString *token = [downloadTokenJSON[@"data"][@"token"] isKindOfClass:[NSString class]]
                        ? downloadTokenJSON[@"data"][@"token"]
                        : @"";
  XCTAssertTrue([token length] > 0);

  ALNResponse *downloadResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:[NSString stringWithFormat:@"/storage/api/download/%@", token]
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, downloadResponse.statusCode);
  XCTAssertEqualObjects(@"image/png", [downloadResponse headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"png!", [self stringFromResponse:downloadResponse]);

  ALNResponse *tamperedDownloadResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:[NSString stringWithFormat:@"/storage/api/download/%@x", token]
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)404, tamperedDownloadResponse.statusCode);

  ALNResponse *htmlDetailResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:[NSString stringWithFormat:@"/storage/collections/media/objects/%@", objectID]
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, htmlDetailResponse.statusCode);
  NSString *html = [self stringFromResponse:htmlDetailResponse];
  XCTAssertTrue([html containsString:@"avatar.png"]);
  XCTAssertTrue([html containsString:@"Variant State"]);
  XCTAssertTrue([html containsString:@"ready"]);
}

@end
