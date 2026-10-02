#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNHTTPCompat.h"
#import "ALNOAuthResourceServer.h"

@interface MetadataTransportTests : XCTestCase
@end
@implementation MetadataTransportTests
- (void)exerciseSocketTransport:(BOOL)tls {
  NSTask *peer = [NSTask new];
  peer.launchPath = @"/usr/bin/env";
  peer.arguments = @[@"python3", @"tests/fixtures/http/metadata_server.py"];
  if (tls) peer.arguments = [peer.arguments arrayByAddingObject:@"--tls"];
  NSPipe *output = [NSPipe pipe]; peer.standardOutput = output;
  [peer launch];
  @try {
    NSMutableData *line = [NSMutableData data];
    while (line.length < 8) {
      NSData *byte = [output.fileHandleForReading readDataOfLength:1];
      if (!byte.length || ((const char *)byte.bytes)[0] == '\n') break;
      [line appendData:byte];
    }
    NSInteger port = [[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] integerValue];
    XCTAssertTrue(port > 0);
    if (port <= 0) return;
    NSArray *paths = tls ? @[@"ok"] : @[@"ok", @"exact", @"declared", @"chunked", @"redirect", @"status", @"disconnect", @"timeout", @"trickle", @"ok"];
    for (NSString *path in paths) {
      NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://127.0.0.1:%ld/%@", tls ? @"https" : @"http", (long)port, path]];
      NSError *error = nil;
      NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
      NSData *data = ALNBoundedMetadataGETWithError(url, 32, tls ? 2 : 0.3, &error);
      NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
      if (!tls && ([path isEqual:@"ok"] || [path isEqual:@"exact"])) {
        XCTAssertEqual([path isEqual:@"ok"] ? 2u : 32u, data.length, @"%@ %@", path, error);
        XCTAssertNil(error);
      } else {
        XCTAssertNil(data, @"%@", path);
        XCTAssertEqualObjects(@"Arlen.Metadata", error.domain);
        XCTAssertFalse([error.description containsString:@"127.0.0.1"]);
        if (tls) XCTAssertEqual(5, error.code);
        else if ([path isEqual:@"disconnect"]) XCTAssertNotNil(error);
        else if ([path isEqual:@"redirect"]) XCTAssertEqual(2, error.code);
        else if ([path isEqual:@"declared"] || [path isEqual:@"status"]) XCTAssertEqual(3, error.code);
        else if ([path isEqual:@"chunked"]) XCTAssertEqual(4, error.code);
        else XCTAssertEqual(6, error.code);
        if ([path isEqual:@"timeout"] || [path isEqual:@"trickle"]) {
          XCTAssertTrue(elapsed >= 0.2);
          XCTAssertTrue(elapsed < 0.8, @"total deadline: %f", elapsed);
        }
      }
    }
    if (!tls) {
      for (NSString *path in @[ @"echo", @"redirect", @"declared", @"chunked", @"timeout" ]) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/%@", (long)port, path]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:0.3];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [@"code=private-code&client_secret=private-secret&code_verifier=private-verifier" dataUsingEncoding:NSUTF8StringEncoding];
        [request setValue:@"private-cookie" forHTTPHeaderField:@"Cookie"];
        NSError *error = nil;
        NSData *data = ALNBoundedJSONRequest(request, [path isEqual:@"echo"] ? 4096 : 32, &error);
        if ([path isEqual:@"echo"]) {
          NSDictionary *echo = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
          XCTAssertEqualObjects(@"POST", echo[@"method"], @"%@", error);
          XCTAssertEqualObjects([[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding], echo[@"body"]);
          XCTAssertEqualObjects(@"application/x-www-form-urlencoded", echo[@"headers"][@"content-type"]);
          XCTAssertNil(echo[@"headers"][@"cookie"]);
        } else {
          XCTAssertNil(data);
          XCTAssertNotNil(error);
          XCTAssertFalse([error.description containsString:@"private-"]);
        }
      }
    }
    if (tls) {
      NSMutableDictionary *config = [[ALNOAuthResourceServer entraConfigurationForTenant:
          @"00000000-0000-0000-0000-000000000001" tokenVersion:@"2.0"
          audience:@"00000000-0000-0000-0000-000000000002"
          resourceURL:@"https://resource.example.test/mcp" scopes:@[] error:NULL] mutableCopy];
      config[@"discoveryURL"] = [NSString stringWithFormat:@"https://127.0.0.1:%ld/ok", (long)port];
      config[@"preflightOnStart"] = @YES;
      ALNOAuthResourceServer *server = [[ALNOAuthResourceServer alloc] initWithConfiguration:config
          documentLoader:nil authorizationPolicy:nil error:NULL];
      XCTAssertNotNil(server);
      ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test", @"logLevel":@"error"}];
      XCTAssertTrue([app registerPlugin:server error:NULL]);
      NSError *error = nil;
      XCTAssertFalse([app startWithError:&error]);
      XCTAssertFalse(server.isReady);
      XCTAssertTrue([error.localizedDescription containsString:@"discovery fetch failed"]);
      XCTAssertTrue([error.localizedDescription containsString:@"transport failed"]);
      XCTAssertFalse([error.description containsString:@"127.0.0.1"]);
      XCTAssertFalse([server refreshSigningKeysWithError:&error]);
      XCTAssertEqualObjects(@"OAuth key refresh in cooldown", error.localizedDescription);
    }
  } @finally { [peer terminate]; [peer waitUntilExit]; }
}
- (void)testUntrustedTLSCertificateRejected { [self exerciseSocketTransport:YES]; }
- (void)testRealSocketOnCallingThread { [self exerciseSocketTransport:NO]; }
- (void)testRealSocketOnFreshMaintenanceThread {
  NSOperationQueue *queue = [NSOperationQueue new];
  [queue addOperationWithBlock:^{ @autoreleasepool { [self exerciseSocketTransport:NO]; } }];
  [queue waitUntilAllOperationsAreFinished];
}
// Explicit opt-in: public provider availability is not a deterministic CI gate.
- (void)testLiveEntraProductionLoader {
  NSString *tenant = [NSProcessInfo processInfo].environment[@"ARLEN_TEST_ENTRA_TENANT"];
  if (!tenant.length) return;
  void (^probe)(void) = ^{
    NSError *error = nil;
    NSMutableDictionary *config = [[ALNOAuthResourceServer entraConfigurationForTenant:tenant
        tokenVersion:@"2.0" audience:@"00000000-0000-0000-0000-000000000001"
        resourceURL:@"https://resource.example.test/mcp" scopes:@[] error:&error] mutableCopy];
    config[@"preflightOnStart"] = @YES;
    ALNOAuthResourceServer *server = [[ALNOAuthResourceServer alloc] initWithConfiguration:config
        documentLoader:nil authorizationPolicy:nil error:&error];
    XCTAssertNotNil(server, @"%@", error);
    XCTAssertTrue([server applicationWillStart:[ALNApplication new] error:&error], @"%@", error);
    XCTAssertTrue(server.isReady);
    if (server.isReady) NSLog(@"Live Entra production discovery + JWKS preflight ready (main thread: %@)", [NSThread isMainThread] ? @"yes" : @"no");
  };
  probe();
  NSOperationQueue *queue = [NSOperationQueue new];
  [queue addOperationWithBlock:^{ @autoreleasepool { probe(); } }];
  [queue waitUntilAllOperationsAreFinished];
}
@end
