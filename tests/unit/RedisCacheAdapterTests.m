#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNServices.h"
#import "../shared/ALNTestWait.h"

#if !defined(_WIN32)
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

// In-process stand-in for a Redis server: listens on 127.0.0.1 (ephemeral
// port), serves each accepted connection on its own thread, keeps string
// values in memory, and counts accepts and SELECT commands. When `cannedGETReply`
// is set, every GET is answered with those raw bytes instead.
@interface ALNFakeRedisServer : NSObject

@property(nonatomic, assign, readonly) int port;
@property(atomic, copy) NSData *cannedGETReply;

- (BOOL)start;
- (void)stop;
- (void)dropClientConnections;
- (NSUInteger)openClientCount;
- (NSUInteger)acceptCount;
- (NSUInteger)selectCount;

@end

@implementation ALNFakeRedisServer {
  int _listenFD;
  NSLock *_lock;
  NSUInteger _acceptCount;
  NSUInteger _selectCount;
  NSMutableDictionary *_values;
  NSMutableArray *_clientFDs;
  volatile BOOL _stopping;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _listenFD = -1;
    _lock = [[NSLock alloc] init];
    _values = [NSMutableDictionary dictionary];
    _clientFDs = [NSMutableArray array];
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
  if (bind(_listenFD, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(_listenFD, 16) != 0) {
    close(_listenFD);
    _listenFD = -1;
    return NO;
  }
  socklen_t length = sizeof(address);
  if (getsockname(_listenFD, (struct sockaddr *)&address, &length) != 0) {
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
  [self dropClientConnections];
}

- (void)dropClientConnections {
  [_lock lock];
  for (NSNumber *descriptor in _clientFDs) {
    (void)shutdown([descriptor intValue], SHUT_RDWR);
  }
  [_lock unlock];
}

- (NSUInteger)openClientCount {
  [_lock lock];
  NSUInteger count = [_clientFDs count];
  [_lock unlock];
  return count;
}

- (NSUInteger)acceptCount {
  [_lock lock];
  NSUInteger count = _acceptCount;
  [_lock unlock];
  return count;
}

- (NSUInteger)selectCount {
  [_lock lock];
  NSUInteger count = _selectCount;
  [_lock unlock];
  return count;
}

- (void)acceptLoop {
  @autoreleasepool {
    int listenFD = _listenFD;
    while (!_stopping) {
      struct pollfd descriptor = { listenFD, POLLIN, 0 };
      int ready = poll(&descriptor, 1, 50);
      if (ready <= 0) {
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
      [_lock lock];
      _acceptCount += 1;
      [_clientFDs addObject:@(clientFD)];
      [_lock unlock];
      [NSThread detachNewThreadSelector:@selector(serveClient:) toTarget:self withObject:@(clientFD)];
    }
    close(listenFD);
  }
}

static BOOL ALNFakeRedisReadExact(int fd, uint8_t *buffer, size_t length) {
  size_t done = 0;
  while (done < length) {
    ssize_t count = recv(fd, buffer + done, length - done, 0);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return NO;
    }
    done += (size_t)count;
  }
  return YES;
}

static NSString *ALNFakeRedisReadLine(int fd) {
  NSMutableData *line = [NSMutableData data];
  while (YES) {
    uint8_t byte = 0;
    if (!ALNFakeRedisReadExact(fd, &byte, 1)) {
      return nil;
    }
    if (byte == '\n') {
      break;
    }
    if (byte != '\r') {
      [line appendBytes:&byte length:1];
    }
  }
  return [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
}

static NSArray *ALNFakeRedisReadCommand(int fd) {
  NSString *header = ALNFakeRedisReadLine(fd);
  if (![header hasPrefix:@"*"]) {
    return nil;
  }
  NSInteger count = [[header substringFromIndex:1] integerValue];
  NSMutableArray *parts = [NSMutableArray array];
  for (NSInteger index = 0; index < count; index++) {
    NSString *bulkHeader = ALNFakeRedisReadLine(fd);
    if (![bulkHeader hasPrefix:@"$"]) {
      return nil;
    }
    NSInteger length = [[bulkHeader substringFromIndex:1] integerValue];
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)length + 2];
    if (!ALNFakeRedisReadExact(fd, [bytes mutableBytes], (size_t)length + 2)) {
      return nil;
    }
    [bytes setLength:(NSUInteger)length];
    [parts addObject:bytes];
  }
  return parts;
}

static BOOL ALNFakeRedisSend(int fd, NSData *data) {
  const uint8_t *bytes = [data bytes];
  size_t sent = 0;
  while (sent < [data length]) {
#if defined(MSG_NOSIGNAL)
    ssize_t count = send(fd, bytes + sent, [data length] - sent, MSG_NOSIGNAL);
#else
    ssize_t count = send(fd, bytes + sent, [data length] - sent, 0);
#endif
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return NO;
    }
    sent += (size_t)count;
  }
  return YES;
}

static NSData *ALNFakeRedisASCII(NSString *text) {
  return [text dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)serveClient:(NSNumber *)descriptor {
  int fd = [descriptor intValue];
  while (!_stopping) {
    @autoreleasepool {
      NSArray *parts = ALNFakeRedisReadCommand(fd);
      if ([parts count] == 0) {
        break;
      }
      NSString *command =
          [[[NSString alloc] initWithData:parts[0] encoding:NSUTF8StringEncoding] uppercaseString];
      NSData *reply = nil;
      if ([command isEqualToString:@"GET"] && [parts count] == 2) {
        NSData *canned = self.cannedGETReply;
        if (canned != nil) {
          reply = canned;
        } else {
          [_lock lock];
          NSData *value = _values[parts[1]];
          [_lock unlock];
          if (value == nil) {
            reply = ALNFakeRedisASCII(@"$-1\r\n");
          } else {
            NSMutableData *bulk = [NSMutableData
                dataWithData:ALNFakeRedisASCII([NSString stringWithFormat:@"$%lu\r\n",
                                                                          (unsigned long)[value length]])];
            [bulk appendData:value];
            [bulk appendData:ALNFakeRedisASCII(@"\r\n")];
            reply = bulk;
          }
        }
      } else if ([command isEqualToString:@"SET"] && [parts count] >= 3) {
        [_lock lock];
        _values[parts[1]] = parts[2];
        [_lock unlock];
        reply = ALNFakeRedisASCII(@"+OK\r\n");
      } else if ([command isEqualToString:@"SELECT"] || [command isEqualToString:@"AUTH"]) {
        if ([command isEqualToString:@"SELECT"]) {
          [_lock lock];
          _selectCount += 1;
          [_lock unlock];
        }
        reply = ALNFakeRedisASCII(@"+OK\r\n");
      } else if ([command isEqualToString:@"DEL"] && [parts count] >= 2) {
        [_lock lock];
        [_values removeObjectForKey:parts[1]];
        [_lock unlock];
        reply = ALNFakeRedisASCII(@":1\r\n");
      } else {
        reply = ALNFakeRedisASCII(@":1\r\n");
      }
      if (!ALNFakeRedisSend(fd, reply)) {
        break;
      }
    }
  }
  [_lock lock];
  [_clientFDs removeObject:descriptor];
  [_lock unlock];
  close(fd);
}

@end
#endif

@interface RedisCacheAdapterTests : XCTestCase
#if !defined(_WIN32)
@property(nonatomic, strong) ALNFakeRedisServer *server;
@property(nonatomic, strong) NSLock *resultLock;
@property(nonatomic, assign) NSUInteger finishedThreads;
@property(nonatomic, assign) NSUInteger threadFailures;
#endif
@end

@implementation RedisCacheAdapterTests

#if !defined(_WIN32)
- (void)tearDown {
  [self.server stop];
  self.server = nil;
  [super tearDown];
}

- (ALNFakeRedisServer *)startedServer {
  ALNFakeRedisServer *server = [[ALNFakeRedisServer alloc] init];
  XCTAssertTrue([server start]);
  self.server = server;
  return server;
}

- (void)runCacheWorker:(NSDictionary *)arguments {
  @autoreleasepool {
    ALNRedisCacheAdapter *adapter = arguments[@"adapter"];
    NSString *key = arguments[@"key"];
    NSUInteger iterations = [arguments[@"iterations"] unsignedIntegerValue];
    NSUInteger localFailures = 0;
    for (NSUInteger iteration = 0; iteration < iterations; iteration++) {
      @autoreleasepool {
        NSError *error = nil;
        NSNumber *expected = @(iteration);
        if (![adapter setObject:expected forKey:key ttlSeconds:0 error:&error]) {
          localFailures += 1;
          continue;
        }
        id value = [adapter objectForKey:key atTime:[NSDate date] error:&error];
        if (![value isEqual:expected]) {
          localFailures += 1;
        }
      }
    }
    [self.resultLock lock];
    self.threadFailures += localFailures;
    self.finishedThreads += 1;
    [self.resultLock unlock];
  }
}

- (ALNRedisCacheAdapter *)adapterForServer:(ALNFakeRedisServer *)server database:(NSInteger)database {
  NSString *url = [NSString stringWithFormat:@"redis://127.0.0.1:%d/%ld", server.port, (long)database];
  NSError *error = nil;
  ALNRedisCacheAdapter *adapter = [[ALNRedisCacheAdapter alloc] initWithURLString:url
                                                                        namespace:@"redis_fake"
                                                                      adapterName:@"redis_fake"
                                                                            error:&error];
  XCTAssertNotNil(adapter);
  XCTAssertNil(error);
  return adapter;
}

- (NSError *)errorForCannedGETReply:(NSData *)reply server:(ALNFakeRedisServer *)server {
  server.cannedGETReply = reply;
  ALNRedisCacheAdapter *adapter = [self adapterForServer:server database:0];
  NSError *error = nil;
  id value = [adapter objectForKey:@"key" atTime:[NSDate date] error:&error];
  XCTAssertNil(value);
  XCTAssertEqualObjects(ALNServiceErrorDomain, error.domain);
  return error;
}
#endif

- (void)testRedisReplyParserRejectsDeepNestingAndOversizedSizes {
#if defined(_WIN32)
  XCTSkip(@"fake Redis server uses POSIX sockets");
#else
  ALNFakeRedisServer *server = [self startedServer];

  NSMutableData *deep = [NSMutableData data];
  for (NSUInteger level = 0; level < 100000; level++) {
    [deep appendBytes:"*1\r\n" length:4];
  }
  [deep appendBytes:":1\r\n" length:4];
  XCTAssertEqual((NSInteger)2231, [self errorForCannedGETReply:deep server:server].code);

  NSData *oversizedBulk = [@"$9000000000000\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqual((NSInteger)2232, [self errorForCannedGETReply:oversizedBulk server:server].code);

  NSData *negativeBulk = [@"$-5\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqual((NSInteger)2208, [self errorForCannedGETReply:negativeBulk server:server].code);

  NSData *oversizedArray = [@"*9000000000000\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqual((NSInteger)2233, [self errorForCannedGETReply:oversizedArray server:server].code);

  // Eight nested levels are still accepted (and are simply not cache data).
  NSMutableData *allowed = [NSMutableData data];
  for (NSUInteger level = 0; level < 8; level++) {
    [allowed appendBytes:"*1\r\n" length:4];
  }
  [allowed appendBytes:":1\r\n" length:4];
  NSError *allowedError = [self errorForCannedGETReply:allowed server:server];
  XCTAssertEqual((NSInteger)2225, allowedError.code);
#endif
}

- (void)testRedisCacheAdapterReusesOneConnectionAcrossCommands {
#if defined(_WIN32)
  XCTSkip(@"fake Redis server uses POSIX sockets");
#else
  ALNFakeRedisServer *server = [self startedServer];
  ALNRedisCacheAdapter *adapter = [self adapterForServer:server database:3];

  NSError *error = nil;
  XCTAssertTrue([adapter setObject:@"value" forKey:@"key" ttlSeconds:0 error:&error]);
  XCTAssertNil(error);
  for (NSUInteger index = 0; index < 50; index++) {
    error = nil;
    XCTAssertEqualObjects(@"value", [adapter objectForKey:@"key" atTime:[NSDate date] error:&error]);
    XCTAssertNil(error);
  }
  XCTAssertTrue([adapter removeObjectForKey:@"key" error:&error]);
  XCTAssertNil([adapter objectForKey:@"key" atTime:[NSDate date] error:&error]);

  XCTAssertEqual((NSUInteger)1, [server acceptCount]);
  XCTAssertEqual((NSUInteger)1, [server selectCount]);
#endif
}

- (void)testRedisCacheAdapterReconnectsAfterServerDropsPooledConnection {
#if defined(_WIN32)
  XCTSkip(@"fake Redis server uses POSIX sockets");
#else
  ALNFakeRedisServer *server = [self startedServer];
  ALNRedisCacheAdapter *adapter = [self adapterForServer:server database:0];

  NSError *error = nil;
  XCTAssertTrue([adapter setObject:@"value" forKey:@"key" ttlSeconds:0 error:&error]);
  XCTAssertEqual((NSUInteger)1, [server acceptCount]);

  // The server closes the idle pooled connection; the next command must not
  // fail because of it.
  [server dropClientConnections];
  XCTAssertTrue(ALNTestWaitUntil(5.0, ALNTestWaitDefaultInterval, ^BOOL {
    return [server openClientCount] == 0;
  }));

  error = nil;
  XCTAssertEqualObjects(@"value", [adapter objectForKey:@"key" atTime:[NSDate date] error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [server acceptCount]);
#endif
}

- (void)testRedisCacheAdapterSharesPoolAcrossThreads {
#if defined(_WIN32)
  XCTSkip(@"fake Redis server uses POSIX sockets");
#else
  ALNFakeRedisServer *server = [self startedServer];
  ALNRedisCacheAdapter *adapter = [self adapterForServer:server database:0];

  // No more threads than the adapter keeps idle connections, so every
  // connection opened can be returned to the pool.
  const NSUInteger threadCount = 4;
  self.resultLock = [[NSLock alloc] init];
  self.finishedThreads = 0;
  self.threadFailures = 0;
  for (NSUInteger threadIndex = 0; threadIndex < threadCount; threadIndex++) {
    NSDictionary *arguments = @{
      @"adapter" : adapter,
      @"key" : [NSString stringWithFormat:@"thread-%lu", (unsigned long)threadIndex],
      @"iterations" : @25,
    };
    [NSThread detachNewThreadSelector:@selector(runCacheWorker:) toTarget:self withObject:arguments];
  }

  XCTAssertTrue(ALNTestWaitUntil(30.0, ALNTestWaitDefaultInterval, ^BOOL {
    [self.resultLock lock];
    BOOL done = (self.finishedThreads == threadCount);
    [self.resultLock unlock];
    return done;
  }));
  [self.resultLock lock];
  XCTAssertEqual((NSUInteger)0, self.threadFailures);
  [self.resultLock unlock];
  XCTAssertLessThanOrEqual([server acceptCount], threadCount);
#endif
}

@end
