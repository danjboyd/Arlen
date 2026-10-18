#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNSearchModule.h"

@interface NSObject (SearchEnginePathTestsLiveSync)
- (BOOL)syncLiveOperation:(NSString *)operation
                   record:(NSDictionary *)record
                 metadata:(NSDictionary *)metadata
                 snapshot:(NSDictionary *)snapshot
                    error:(NSError **)error;
@end

#if !defined(_WIN32)
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

// In-process stand-in for a search engine: listens on 127.0.0.1 (ephemeral
// port), records each request line ("METHOD /path?query") and answers every
// request with `200 {}`.
@interface SearchEnginePathFakeHTTPServer : NSObject
@property(nonatomic, assign, readonly) int port;
- (BOOL)start;
- (void)stop;
- (NSArray<NSString *> *)requestLines;
@end

@implementation SearchEnginePathFakeHTTPServer {
  int _listenFD;
  NSLock *_lock;
  NSMutableArray<NSString *> *_requestLines;
  volatile BOOL _stopping;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _listenFD = -1;
    _lock = [[NSLock alloc] init];
    _requestLines = [NSMutableArray array];
  }
  return self;
}

- (BOOL)start {
  _listenFD = socket(AF_INET, SOCK_STREAM, 0);
  if (_listenFD < 0) {
    return NO;
  }
  int reuse = 1;
  (void)setsockopt(_listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  address.sin_port = 0;
  socklen_t length = sizeof(address);
  if (bind(_listenFD, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(_listenFD, 16) != 0 ||
      getsockname(_listenFD, (struct sockaddr *)&address, &length) != 0) {
    close(_listenFD);
    _listenFD = -1;
    return NO;
  }
  _port = ntohs(address.sin_port);
  [NSThread detachNewThreadSelector:@selector(acceptLoop) toTarget:self withObject:nil];
  return YES;
}

- (void)stop {
  _stopping = YES;
}

- (NSArray<NSString *> *)requestLines {
  [_lock lock];
  NSArray *lines = [_requestLines copy];
  [_lock unlock];
  return lines;
}

- (void)acceptLoop {
  @autoreleasepool {
    int listenFD = _listenFD;
    while (!_stopping) {
      struct pollfd descriptor = { listenFD, POLLIN, 0 };
      if (poll(&descriptor, 1, 50) <= 0) {
        continue;
      }
      int clientFD = accept(listenFD, NULL, NULL);
      if (clientFD < 0) {
        continue;
      }
#if defined(SO_NOSIGPIPE)
      int noSigPipe = 1;
      (void)setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
      [NSThread detachNewThreadSelector:@selector(serveClient:) toTarget:self withObject:@(clientFD)];
    }
    close(listenFD);
  }
}

- (void)serveClient:(NSNumber *)descriptor {
  @autoreleasepool {
    int fd = [descriptor intValue];
    NSMutableData *buffer = [NSMutableData data];
    NSData *terminator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    uint8_t chunk[4096];
    NSRange headerEnd = NSMakeRange(NSNotFound, 0);
    while (headerEnd.location == NSNotFound) {
      ssize_t count = recv(fd, chunk, sizeof(chunk), 0);
      if (count < 0 && errno == EINTR) {
        continue;
      }
      if (count <= 0) {
        close(fd);
        return;
      }
      [buffer appendBytes:chunk length:(NSUInteger)count];
      headerEnd = [buffer rangeOfData:terminator options:0 range:NSMakeRange(0, [buffer length])];
    }
    NSString *head = [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0, headerEnd.location)]
                                           encoding:NSISOLatin1StringEncoding] ?: @"";
    NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
    NSUInteger contentLength = 0;
    for (NSString *line in lines) {
      if ([[line lowercaseString] hasPrefix:@"content-length:"]) {
        contentLength = (NSUInteger)[[line substringFromIndex:15] integerValue];
      }
    }
    NSUInteger bodyStart = NSMaxRange(headerEnd);
    while ([buffer length] < bodyStart + contentLength) {
      ssize_t count = recv(fd, chunk, sizeof(chunk), 0);
      if (count < 0 && errno == EINTR) {
        continue;
      }
      if (count <= 0) {
        break;
      }
      [buffer appendBytes:chunk length:(NSUInteger)count];
    }
    NSArray<NSString *> *requestLine = [[lines firstObject] componentsSeparatedByString:@" "];
    if ([requestLine count] >= 2) {
      [_lock lock];
      [_requestLines addObject:[NSString stringWithFormat:@"%@ %@", requestLine[0], requestLine[1]]];
      [_lock unlock];
    }
    const char *response =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}";
    (void)send(fd, response, strlen(response), 0);
    close(fd);
  }
}

@end
#endif

@interface SearchEnginePathTests : XCTestCase
@end

@implementation SearchEnginePathTests

- (void)testEnginePathComponentEncodesAllButUnreservedCharacters {
  NSError *error = nil;
  XCTAssertEqualObjects(@"AZaz09-._~", ALNSearchEnginePathComponent(@"AZaz09-._~", &error));
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"a%20b%2Fc%3Fd%23e%25f", ALNSearchEnginePathComponent(@"a b/c?d#e%f", &error));
  XCTAssertEqualObjects(@"a%3Ab%40c%21d%3Be%2Cf%2Bg%3Dh%26i",
                        ALNSearchEnginePathComponent(@"a:b@c!d;e,f+g=h&i", &error));
  XCTAssertEqualObjects(@"r%C3%A9sum%C3%A9", ALNSearchEnginePathComponent(@"résumé", &error));
  XCTAssertEqualObjects(@"my-post", ALNSearchEnginePathComponent(@"  my-post  ", &error));
  XCTAssertEqualObjects(@"...", ALNSearchEnginePathComponent(@"...", &error));
  XCTAssertEqualObjects(@"..a", ALNSearchEnginePathComponent(@"..a", &error));
  XCTAssertEqualObjects(@"..%2F", ALNSearchEnginePathComponent(@"../", &error));
  XCTAssertNil(error);
}

- (void)testEnginePathComponentRejectsEmptyAndDotSegments {
  for (NSString *value in @[ @"", @"   ", @".", @"..", @" .. " ]) {
    NSError *error = nil;
    XCTAssertNil(ALNSearchEnginePathComponent(value, &error), @"%@", value);
    XCTAssertEqualObjects(ALNSearchModuleErrorDomain, error.domain, @"%@", value);
    XCTAssertEqual((NSInteger)ALNSearchModuleErrorValidationFailed, error.code, @"%@", value);
  }
  NSError *error = nil;
  XCTAssertNil(ALNSearchEnginePathComponent(nil, &error));
  XCTAssertEqual((NSInteger)ALNSearchModuleErrorValidationFailed, error.code);
}

#if !defined(_WIN32)
- (SearchEnginePathFakeHTTPServer *)startedServer {
  SearchEnginePathFakeHTTPServer *server = [[SearchEnginePathFakeHTTPServer alloc] init];
  XCTAssertTrue([server start]);
  [self addTeardownBlock:^{
    [server stop];
  }];
  return server;
}

- (id)engineOfClass:(Class)engineClass configKey:(NSString *)configKey server:(SearchEnginePathFakeHTTPServer *)server {
  id<ALNSearchEngine> engine = [[engineClass alloc] init];
  NSError *error = nil;
  NSDictionary *moduleConfig = @{
    @"engine" : @{
      configKey : @{
        @"serviceURL" : [NSString stringWithFormat:@"http://127.0.0.1:%d", server.port],
        @"liveRequestsEnabled" : @YES,
        @"indexPrefix" : @"app",
      },
    },
  };
  // The live engines only use the runtime and application for fixture files.
  ALNSearchModuleRuntime *runtime = nil;
  ALNApplication *application = nil;
  XCTAssertTrue([engine searchModuleConfigureWithRuntime:runtime
                                             application:application
                                            moduleConfig:moduleConfig
                                                   error:&error]);
  XCTAssertNil(error);
  return engine;
}

- (void)assertDotSegmentRecordsAreRejectedByEngine:(id)engine server:(SearchEnginePathFakeHTTPServer *)server {
  NSDictionary *metadata = @{ @"identifier" : @"articles", @"identifierField" : @"slug" };
  for (NSString *slug in @[ @"..", @"." ]) {
    for (NSString *operation in @[ @"delete", @"upsert" ]) {
      NSError *error = nil;
      BOOL ok = [engine syncLiveOperation:operation
                                   record:@{ @"slug" : slug, @"title" : @"Title" }
                                 metadata:metadata
                                 snapshot:@{}
                                    error:&error];
      XCTAssertFalse(ok, @"%@ %@", operation, slug);
      XCTAssertEqual((NSInteger)ALNSearchModuleErrorValidationFailed, error.code, @"%@ %@", operation, slug);
    }
  }
  XCTAssertEqualObjects(@[], [server requestLines]);
}
#endif

- (void)testOpenSearchDotSegmentRecordIssuesNoRequestAndNormalIDIsEncoded {
#if defined(_WIN32)
  XCTSkip(@"fake HTTP server uses POSIX sockets");
#else
  SearchEnginePathFakeHTTPServer *server = [self startedServer];
  id engine = [self engineOfClass:NSClassFromString(@"ALNOpenSearchSearchEngine") configKey:@"opensearch" server:server];
  [self assertDotSegmentRecordsAreRejectedByEngine:engine server:server];

  NSError *error = nil;
  BOOL ok = [engine syncLiveOperation:@"delete"
                               record:@{ @"slug" : @"my post/1" }
                             metadata:@{ @"identifier" : @"articles", @"identifierField" : @"slug" }
                             snapshot:@{}
                                error:&error];
  XCTAssertTrue(ok, @"%@", error);
  XCTAssertEqualObjects(@[ @"DELETE /app_articles/_doc/my%20post%2F1?refresh=true" ], [server requestLines]);
#endif
}

- (void)testMeilisearchDotSegmentRecordIssuesNoRequestAndNormalIDIsEncoded {
#if defined(_WIN32)
  XCTSkip(@"fake HTTP server uses POSIX sockets");
#else
  SearchEnginePathFakeHTTPServer *server = [self startedServer];
  id engine = [self engineOfClass:NSClassFromString(@"ALNMeilisearchSearchEngine") configKey:@"meilisearch" server:server];
  [self assertDotSegmentRecordsAreRejectedByEngine:engine server:server];

  NSError *error = nil;
  BOOL ok = [engine syncLiveOperation:@"delete"
                               record:@{ @"slug" : @"my post/1" }
                             metadata:@{ @"identifier" : @"articles", @"identifierField" : @"slug" }
                             snapshot:@{}
                                error:&error];
  XCTAssertTrue(ok, @"%@", error);
  XCTAssertEqualObjects(@[ @"DELETE /indexes/app_articles/documents/my%20post%2F1" ], [server requestLines]);
#endif
}

@end
